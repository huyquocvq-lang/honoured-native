import Foundation
import UIKit
import UserNotifications

/// Goal-latency diagnostics (Phase 3 M2-B, docs/phase3/core-motion-plan.vi.md):
/// what Honoured could know about when a step or distance goal was crossed,
/// noticed, announced and seen, kept on the device and uploaded to
/// `goal_diagnostics` (docs/db/goal_diagnostics_v1.sql) so the delays between
/// those moments can be measured, and how much a change improves them. It
/// holds counts, times and identifiers only — no token, email or content —
/// and is cleared when the account changes.
///
/// Recording runs in development, Ad Hoc and TestFlight builds. An App Store
/// build records nothing until the client decides, because the App Store
/// privacy details would have to declare it.
actor GoalDiagnostics {
    static let shared = GoalDiagnostics()

    nonisolated static let isEnabled: Bool = {
        #if DEBUG
        return true
        #else
        // Development and Ad Hoc installs carry their provisioning profile and
        // TestFlight installs a sandbox receipt; neither needs the network.
        if MotionProbeAccess.hasEmbeddedProfile { return true }
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }()

    /// Lines kept for upload. Past this the oldest are dropped down to
    /// `trimmedStored`, so one rewrite of the file covers many new lines.
    private static let maxStored = 5_000
    private static let trimmedStored = 4_500
    /// Small enough that the server's per-row checks stay cheap.
    private static let uploadBatch = 50
    /// Readings this close before the detection bound the crossing on their
    /// own; the pedometer's live count arrives every few seconds.
    private static let liveWindow: TimeInterval = 30
    /// How long a resolved account is reused before the Keychain is read again.
    private static let accountCacheLife: TimeInterval = 60
    /// How often the bookkeeping is written while only readings move it.
    private static let stateSaveInterval: TimeInterval = 30
    /// Bookkeeping older than this is dropped.
    private static let stateLife: TimeInterval = 2 * 24 * 60 * 60

    private struct State: Codable {
        var pendingNotifications: [GoalNotificationRequest] = []
        /// Per goal (`activityId|day`): when a reading last found it below target.
        var lastBelow: [String: Date] = [:]
        var lastReading: [String: GoalReadingLog.Last] = [:]
        /// Per card part: when an update was last written, and what it showed.
        var lastCard: [String: GoalReadingLog.Last] = [:]
        var uploadFailures = 0
        var nextUploadAfter: Date?
    }

    private let directory: URL
    private var events: [GoalDiagnosticsEvent] = []
    private var state = State()
    private var loaded = false
    private var isUploading = false
    private var cachedUser: (token: Int, userId: String?, at: Date)?
    private var lastStateSave = Date.distantPast

    private init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = root.appendingPathComponent("Honoured/GoalDiagnostics", isDirectory: true)
    }

    private var eventsURL: URL { directory.appendingPathComponent("events.jsonl") }
    private var stateURL: URL { directory.appendingPathComponent("state.json") }

    // MARK: - Account

    private static let tokenLock = NSLock()
    private static var currentToken = 0

    /// "The account as it is now", taken when something is observed. Signing
    /// out or switching accounts moves it, so a line observed before the
    /// change is never written after it, under either account.
    nonisolated static func account() -> Int {
        tokenLock.withLock { currentToken }
    }

    private static func moveAccountToken() {
        tokenLock.withLock { currentToken += 1 }
    }

    // MARK: - Hooks (no-ops when disabled)

    /// A lifecycle moment UIKit reports as it happens.
    nonisolated static func lifecycle(_ reason: String) {
        guard isEnabled else { return }
        let at = Date(), token = account()
        Task { await shared.write(token: token, { .recorded("app_lifecycle", at: at, userId: $0) }) { $0.reason = reason } }
    }

    /// iOS let the app run: why, and whether the device was locked. Also
    /// the moment to look for delivered goal notifications.
    nonisolated static func ran(_ reason: String, details: [String: String] = [:]) {
        guard isEnabled else { return }
        let at = Date(), token = account()
        Task {
            let device = await MainActor.run { deviceState() }
            await shared.write(token: token, { .recorded("app_ran", at: at, userId: $0) }) {
                $0.reason = reason
                $0.details = device.merging(details) { _, new in new }
            }
            await shared.checkDeliveries(token: token)
        }
    }

    /// A goal notification iOS handed to the app while it was on screen.
    nonisolated static func notificationPresented(identifier: String, activityId: String, deliveredAt: Date) {
        guard isEnabled else { return }
        let token = account()
        Task { await shared.delivered(identifier: identifier, activityId: activityId, at: deliveredAt, seenIn: "app_on_screen", token: token) }
    }

    /// The person tapped a goal notification. Tapping takes it out of
    /// Notification Center, so this is also the evidence of its delivery.
    nonisolated static func notificationOpened(identifier: String, activityId: String, deliveredAt: Date) {
        guard isEnabled else { return }
        let at = Date(), token = account()
        Task {
            await shared.delivered(identifier: identifier, activityId: activityId, at: deliveredAt, seenIn: "opened", token: token)
            await shared.write(token: token, { .recorded("notification_opened", at: at, userId: $0) }) {
                $0.activityId = activityId
                $0.details = ["identifier": identifier]
            }
        }
    }

    /// The app asked ActivityKit to update a contract card; when the card
    /// changes on the Lock Screen iOS does not say. One line per step or
    /// distance goal on it, when that goal's state moves and otherwise at
    /// most once a minute.
    nonisolated static func contractCardUpdated(_ state: HonouredLiveActivityState) {
        guard isEnabled else { return }
        let followed = [HealthMetric.steps.rawValue, HealthMetric.distanceWalkingRunning.rawValue]
        let parts = state.health.filter { followed.contains($0.metric) }
        guard !parts.isEmpty else { return }
        let at = Date(), token = account()
        Task {
            for part in parts {
                await shared.cardUpdated(key: "contract|\(part.activityId)", shown: "\(state.status.rawValue)|\(part.reached)", at: at, token: token) {
                    $0.activityId = part.activityId
                    $0.metric = part.metric
                    $0.value = part.value
                    $0.target = part.target
                    $0.details = ["kind": "contract", "status": state.status.rawValue, "reached": String(part.reached)]
                }
            }
        }
    }

    nonisolated static func iconCardUpdated(contractId: String, iconDay: String, state: IconLiveActivityState) {
        guard isEnabled else { return }
        let at = Date(), token = account()
        Task {
            await shared.cardUpdated(key: "icon|\(contractId)|\(iconDay)", shown: "\(state.phase.rawValue)|\(state.result?.rawValue ?? "")", at: at, token: token) {
                $0.activityId = contractId
                $0.day = iconDay
                $0.value = state.value
                $0.details = ["kind": "icon", "phase": state.phase.rawValue]
            }
        }
    }

    // MARK: - Goals (from GoalMonitor)

    /// One reading of a goal not yet reached today. Remembers the last one
    /// below the target, which bounds when the goal was crossed.
    func reading(
        activityId: String, metric: HealthMetric, day: String, target: Double,
        read: HealthTotalRead, source: HealthReadingSource, trigger: String, at: Date, account token: Int
    ) async {
        guard Self.isEnabled, let userId = await currentUser(token: token) else { return }
        let key = Self.goalKey(activityId, day)
        let result: String
        switch read {
        case .value(let value):
            result = "value"
            if value < target { state.lastBelow[key] = at }
        case .noData: result = "no_data"
        case .protectedDataUnavailable: result = "locked"
        case .failed: result = "failed"
        }
        if GoalReadingLog.shouldWrite(result: result, at: at, last: state.lastReading[key]) {
            var event = GoalDiagnosticsEvent.recorded("reading", at: at, userId: userId)
            event.reason = result
            event.source = source.rawValue
            event.metric = metric.rawValue
            event.activityId = activityId
            event.day = day
            event.value = read.numericValue
            event.target = target
            event.details = ["trigger": trigger]
            append(event)
            state.lastReading[key] = GoalReadingLog.Last(result: result, at: at)
        }
        saveState(force: false)
    }

    /// The app saw the goal met, and what it did about the notification:
    /// `scheduled`, or why not (`app_active`, `not_authorized`, `failed`).
    /// The crossing is then estimated from the history that is still there.
    func goalDetected(
        activityId: String, metric: HealthMetric, day: String, dayStart: Date, target: Double, value: Double,
        source: HealthReadingSource, trigger: String, notification: String, identifier: String, at: Date,
        account token: Int
    ) async {
        guard Self.isEnabled, let userId = await currentUser(token: token) else { return }
        var detected = GoalDiagnosticsEvent.recorded("goal_detected", at: at, userId: userId)
        detected.source = source.rawValue
        detected.metric = metric.rawValue
        detected.activityId = activityId
        detected.day = day
        detected.value = value
        detected.target = target
        detected.details = ["trigger": trigger]
        append(detected)

        var requested = GoalDiagnosticsEvent.recorded("notification_requested", at: at, userId: userId)
        requested.reason = notification
        requested.activityId = activityId
        requested.day = day
        requested.details = ["identifier": identifier]
        append(requested)
        if notification == "scheduled" {
            state.pendingNotifications.append(GoalNotificationRequest(
                userId: userId, identifier: identifier, activityId: activityId, day: day, requestedAt: at
            ))
        }

        let key = Self.goalKey(activityId, day)
        let lastBelow = state.lastBelow.removeValue(forKey: key)
        state.lastReading.removeValue(forKey: key)
        let since = lastBelow ?? dayStart
        // When the data that met the goal became readable is not observable:
        // only that it came after the last read below the target.
        if var available = GoalDiagnosticsEvent.estimated(
            "data_available", from: since, to: at, method: "between_reads", userId: userId
        ) {
            available.source = source.rawValue
            available.metric = metric.rawValue
            available.activityId = activityId
            available.day = day
            available.details = ["bounded_by_reading": String(lastBelow != nil)]
            append(available)
        }
        saveState(force: true)

        let liveBound = trigger == "motion_live" && lastBelow.map { at.timeIntervalSince($0) <= Self.liveWindow } == true
        let crossing = await Self.estimateCrossing(
            metric: metric, source: source, target: target, dayStart: dayStart,
            since: since, until: at, liveBound: liveBound
        )
        guard token == Self.account(),
              var crossed = GoalDiagnosticsEvent.estimated(
                "goal_crossed", from: crossing.window.start, to: crossing.window.end, method: crossing.method, userId: userId
              ) else { return }
        crossed.source = source.rawValue
        crossed.metric = metric.rawValue
        crossed.activityId = activityId
        crossed.day = day
        crossed.target = target
        append(crossed)
    }

    // MARK: - Notifications

    /// Settles requested goal notifications against Notification Center. A
    /// notification the person cleared before the app ran again leaves no
    /// trace, so after a day it is written as unknown.
    func checkDeliveries(token: Int) async {
        guard Self.isEnabled, loadIfNeeded(), !state.pendingNotifications.isEmpty,
              let userId = await currentUser(token: token) else { return }
        // Requests of another account are not this account's to settle.
        state.pendingNotifications.removeAll { $0.userId != userId }
        let shown = await UNUserNotificationCenter.current().deliveredNotifications()
        guard token == Self.account() else { return }
        var delivered: [String: Date] = [:]
        for notification in shown { delivered[notification.request.identifier] = notification.date }
        let outcome = GoalNotificationDeliveries.settle(state.pendingNotifications, delivered: delivered, now: Date())
        for item in outcome.delivered {
            var event = GoalDiagnosticsEvent.recorded("notification_delivered", at: item.at, userId: userId)
            event.activityId = item.request.activityId
            event.day = item.request.day
            event.details = ["identifier": item.request.identifier, "seen_in": "notification_center"]
            append(event)
        }
        for request in outcome.unknown {
            var event = GoalDiagnosticsEvent.unknown("notification_delivered", userId: userId)
            event.reason = "not_in_notification_center"
            event.activityId = request.activityId
            event.day = request.day
            event.details = ["identifier": request.identifier]
            append(event)
        }
        state.pendingNotifications = outcome.stillPending
        saveState(force: true)
    }

    /// iOS's own delivery time, seen on screen or through a tap.
    private func delivered(identifier: String, activityId: String, at: Date, seenIn: String, token: Int) async {
        guard let userId = await currentUser(token: token) else { return }
        let request = state.pendingNotifications.first { $0.identifier == identifier && $0.userId == userId }
        state.pendingNotifications.removeAll { $0.identifier == identifier }
        var event = GoalDiagnosticsEvent.recorded("notification_delivered", at: at, userId: userId)
        event.activityId = activityId
        event.day = request?.day
        event.details = ["identifier": identifier, "seen_in": seenIn]
        append(event)
        saveState(force: true)
    }

    // MARK: - Live Activities

    private func cardUpdated(key: String, shown: String, at: Date, token: Int, fill: (inout GoalDiagnosticsEvent) -> Void) async {
        // The throttle first: it needs no Keychain read.
        guard loadIfNeeded(), GoalReadingLog.shouldWrite(result: shown, at: at, last: state.lastCard[key]),
              let userId = await currentUser(token: token) else { return }
        var event = GoalDiagnosticsEvent.recorded("live_activity_update", at: at, userId: userId)
        fill(&event)
        if let metric = event.metric.flatMap(HealthMetric.init(rawValue:)) {
            event.source = await HealthKitService.shared.readingSource(for: metric).rawValue
        }
        guard token == Self.account() else { return }
        append(event)
        state.lastCard[key] = GoalReadingLog.Last(result: shown, at: at)
        saveState(force: false)
    }

    // MARK: - Upload

    /// Sends the signed-in account's lines in small batches and keeps what
    /// fails for later, waiting longer after each failure. Lines of another
    /// account are never sent; signing out or switching clears them.
    func upload() async {
        guard Self.isEnabled, !isUploading, loadIfNeeded(), !events.isEmpty else { return }
        if let next = state.nextUploadAfter, next > Date() { return }
        isUploading = true
        defer { isUploading = false }
        let token = Self.account()
        guard let session = try? await AuthSessionStore.shared.refreshedSessionIfNeeded(),
              token == Self.account() else { return }
        while true {
            let batch = Array(events.lazy.filter { $0.userId == session.userId }.prefix(Self.uploadBatch))
            guard !batch.isEmpty else { break }
            let sentAt = Date()
            do {
                try await SupabaseHealthClient.shared.recordGoalDiagnostics(batch.map { $0.row(sentAt: sentAt) }, session: session)
            } catch {
                var status: Int?
                if case SupabaseHealthClient.SyncError.http(let code) = error { status = code }
                state.uploadFailures += 1
                state.nextUploadAfter = Date().addingTimeInterval(
                    GoalDiagnosticsUploadBackoff.delay(failures: state.uploadFailures, status: status)
                )
                saveState(force: true)
                return
            }
            // The account may have changed during the upload; clear() has
            // then already removed these lines.
            guard token == Self.account() else { return }
            let sent = Set(batch.map(\.id))
            events.removeAll { sent.contains($0.id) }
            rewriteEvents()
        }
        if state.uploadFailures != 0 || state.nextUploadAfter != nil {
            state.uploadFailures = 0
            state.nextUploadAfter = nil
            saveState(force: true)
        }
    }

    /// A session was stored: the account read a moment ago may be stale.
    func sessionStored() {
        cachedUser = nil
    }

    #if DEBUG
    /// What is stored, for the bridge stub's checks.
    func storedEvents() -> [GoalDiagnosticsEvent] {
        _ = loadIfNeeded()
        return events
    }
    #endif

    /// Signing out or switching accounts: nothing of the previous account
    /// stays on the device, and nothing it observed is written afterwards.
    func clear() {
        Self.moveAccountToken()
        events.removeAll()
        state = State()
        cachedUser = nil
        try? FileManager.default.removeItem(at: eventsURL)
        try? FileManager.default.removeItem(at: stateURL)
        loaded = (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil
    }

    // MARK: - Storage

    private func write(token: Int, _ make: (String) -> GoalDiagnosticsEvent, fill: (inout GoalDiagnosticsEvent) -> Void = { _ in }) async {
        guard let userId = await currentUser(token: token) else { return }
        var event = make(userId)
        fill(&event)
        append(event)
    }

    /// The signed-in account, if it is still the one `token` was taken
    /// under. Nil before the first unlock (the Keychain is closed, and so are
    /// the files) and while signed out: such lines belong to no account.
    private func currentUser(token: Int) async -> String? {
        guard loadIfNeeded(), token == Self.account() else { return nil }
        let now = Date()
        if let cached = cachedUser, cached.token == token, now.timeIntervalSince(cached.at) < Self.accountCacheLife {
            return cached.userId
        }
        let userId = await AuthSessionStore.shared.load()?.userId
        guard token == Self.account() else { return nil }
        cachedUser = (token, userId, now)
        return userId
    }

    private func append(_ event: GoalDiagnosticsEvent) {
        events.append(event)
        if events.count > Self.maxStored {
            events.removeFirst(events.count - Self.trimmedStored)
            rewriteEvents()
            return
        }
        guard let line = try? Self.encoder.encode(event) else { return }
        if FileManager.default.fileExists(atPath: eventsURL.path) {
            do {
                let handle = try FileHandle(forWritingTo: eventsURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line + Data([0x0A]))
            } catch {
                // Never truncate what is there: write the whole log anew.
                rewriteEvents()
            }
        } else {
            try? (line + Data([0x0A])).write(to: eventsURL, options: .atomic)
        }
    }

    private func rewriteEvents() {
        let data = events.compactMap { try? Self.encoder.encode($0) }.reduce(into: Data()) {
            $0.append($1)
            $0.append(0x0A)
        }
        try? data.write(to: eventsURL, options: .atomic)
    }

    /// Readings move the bookkeeping every few seconds while the app follows
    /// the pedometer, so those writes are spaced out; losing one only widens
    /// a crossing window.
    private func saveState(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastStateSave) >= Self.stateSaveInterval else { return }
        let horizon = now.addingTimeInterval(-Self.stateLife)
        state.lastBelow = state.lastBelow.filter { $0.value > horizon }
        state.lastReading = state.lastReading.filter { $0.value.at > horizon }
        state.lastCard = state.lastCard.filter { $0.value.at > horizon }
        guard let data = try? Self.encoder.encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
        lastStateSave = now
    }

    /// Reads what an earlier run stored. False while the files cannot be
    /// read (before the first unlock), so nothing is overwritten then.
    private func loadIfNeeded() -> Bool {
        if loaded { return true }
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            if manager.fileExists(atPath: eventsURL.path) {
                let data = try Data(contentsOf: eventsURL)
                events = data.split(separator: 0x0A).compactMap { try? Self.decoder.decode(GoalDiagnosticsEvent.self, from: Data($0)) }
                // A line cut short by a crash would swallow the next append.
                if let last = data.last, last != 0x0A { rewriteEvents() }
            }
            if manager.fileExists(atPath: stateURL.path) {
                state = (try? Self.decoder.decode(State.self, from: Data(contentsOf: stateURL))) ?? State()
            }
        } catch {
            return false
        }
        loaded = true
        return true
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()

    private static func goalKey(_ activityId: String, _ day: String) -> String {
        "\(activityId)|\(day)"
    }

    @MainActor
    private static func deviceState() -> [String: String] {
        let application = UIApplication.shared
        let appState: String
        switch application.applicationState {
        case .active: appState = "active"
        case .inactive: appState = "inactive"
        case .background: appState = "background"
        @unknown default: appState = "unknown"
        }
        return [
            "protected_data": application.isProtectedDataAvailable ? "available" : "locked",
            "app_state": appState,
            "low_power": String(ProcessInfo.processInfo.isLowPowerModeEnabled)
        ]
    }

    // MARK: - Crossing

    /// When the goal was crossed, from the history still on the device: the
    /// pedometer's running total for Core Motion, narrowed to the minute in a
    /// dozen reads; HealthKit's per-minute statistics otherwise. Without
    /// them, the window between the last reading below the target and the
    /// detection.
    private static func estimateCrossing(
        metric: HealthMetric, source: HealthReadingSource, target: Double, dayStart: Date,
        since: Date, until: Date, liveBound: Bool
    ) async -> (window: DateInterval, method: String) {
        let coarse = DateInterval(start: min(since, until), end: until)
        if liveBound { return (coarse, "motion_live") }

        if source == .coreMotion {
            let narrowed = await GoalCrossingEstimate.narrow(
                target: target, below: coarse.start, reached: coarse.end, resolution: 60
            ) { moment in
                guard moment > dayStart else { return 0 }
                guard case .value(let reading) = await MotionService.query(from: dayStart, to: moment) else { return nil }
                return metric == .steps ? reading.steps : reading.distanceMeters
            }
            guard let narrowed else { return (coarse, "between_reads") }
            return (narrowed, "motion_query")
        }

        var before = 0.0
        if since > dayStart {
            guard case .value(let total) = await HealthKitService.shared.readTotal(for: metric, from: dayStart, to: since) else {
                return (coarse, "between_reads")
            }
            before = total
        }
        guard before < target,
              let minutes = await HealthKitService.shared.minuteTotals(for: metric, from: since, to: until),
              let window = GoalCrossingEstimate.window(target: target, before: before, intervals: minutes) else {
            return (coarse, "between_reads")
        }
        return (GoalCrossingEstimate.bounded(window, notBefore: since, notAfter: until), "healthkit_minutes")
    }
}
