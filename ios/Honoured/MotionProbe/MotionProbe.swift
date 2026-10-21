import CoreMotion
import Foundation
import UIKit
import UserNotifications
import ZIPFoundation

/// Phase 3 M1 feasibility probe (docs/phase3/core-motion-plan.vi.md): records,
/// every time iOS lets Honoured run, what Core Motion and HealthKit report and
/// when a test target is noticed and announced. It adds no way of running in
/// the background; measuring the existing ones is the point. Off unless turned
/// on from the hidden probe screen, which only Debug and TestFlight builds open
/// (`MotionProbeAccess`). The log stays on the device until the tester exports
/// it, and holds counts, timestamps and Health source names only.
actor MotionProbe {
    static let shared = MotionProbe()

    enum RunReason: String, Sendable {
        case launch
        case appActive = "app_active"
        case healthKitDelivery = "healthkit_delivery"
        case backgroundRefresh = "bg_app_refresh"
        case protectedDataAvailable = "protected_data_available"
        case probeScreen = "probe_screen"
    }

    /// One walk to a target, counted from `startedAt` so Core Motion and
    /// HealthKit start from the same zero.
    struct Session: Codable, Equatable, Sendable {
        let id: String
        let startedAt: Date
        let targetSteps: Double
        var stoppedAt: Date?
        /// Per source: when the app first saw the target met (recorded).
        var detected: [String: Date] = [:]
        /// Per source: when the notification request was accepted (recorded).
        var requested: [String: Date] = [:]
        /// Per source: `UNNotification.date` once iOS shows it delivered.
        var delivered: [String: Date] = [:]
        /// Per source: the last read still below the target, the start of the
        /// window in which the data became available.
        var lastBelow: [String: Date] = [:]

        var isRunning: Bool { stoppedAt == nil }
        var notificationPrefix: String { "motion-probe-\(id)-" }
    }

    struct Snapshot: Sendable {
        var enabled: Bool
        var session: Session?
        var liveSteps: Double?
        var healthSteps: Double?
        var recent: [MotionProbeEvent]
        var lastReport: String?
    }

    static let coreMotion = "core_motion"
    static let healthKit = "healthkit"

    private static let enabledKey = "motionProbe.enabled"
    private static let sessionKey = "motionProbe.session"

    nonisolated static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    private let directory: URL
    private var recent: [MotionProbeEvent] = []
    private var recentLoaded = false
    private var session: Session?
    private var livePedometer: CMPedometer?
    private var liveSteps: Double?
    private var healthSteps: Double?
    private var lastLogged: [String: (signature: String, at: Date)] = [:]
    private var lastReport: String?

    private init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = root.appendingPathComponent("Honoured/MotionProbe", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = UserDefaults.standard.data(forKey: Self.sessionKey) {
            session = try? MotionProbeCoding.decoder.decode(Session.self, from: data)
        }
    }

    private var logURL: URL { directory.appendingPathComponent("events.jsonl") }
    var metricKitDirectory: URL { directory.appendingPathComponent("metrickit", isDirectory: true) }
    private var reportsDirectory: URL { directory.appendingPathComponent("reports", isDirectory: true) }

    // MARK: - Hooks (cheap no-ops while the probe is off)

    nonisolated static func note(_ event: String, reason: String? = nil, notes: [String: String]? = nil) {
        guard isEnabled else { return }
        let at = Date()
        Task { await shared.append(MotionProbeEvent(at: at, event: event, reason: reason, notes: notes)) }
    }

    nonisolated static func noteLiveActivityUpdate(kind: String) {
        note("live_activity_update", reason: kind)
    }

    nonisolated static func noteHealthKitCallback(metric: String) {
        note("healthkit_callback", reason: metric)
    }

    /// The production goal path (`GoalMonitor`), to compare with the probe's.
    nonisolated static func noteAppGoal(metric: String, value: Double, target: Double, notified: Bool) {
        guard isEnabled else { return }
        let at = Date()
        Task {
            await shared.append(MotionProbeEvent(
                at: at, event: "app_goal_reached", source: healthKit,
                numbers: ["value": value, "target": target],
                notes: ["metric": metric, "notification_scheduled": String(notified)]
            ))
        }
    }

    nonisolated static func isProbeNotification(_ notification: UNNotification) -> Bool {
        notification.request.identifier.hasPrefix("motion-probe-")
    }

    /// iOS hands a notification to the app instead of showing it when the app
    /// is in front. `notification.date` is still iOS's own delivery time, so
    /// it counts as recorded delivery.
    nonisolated static func notificationWillPresent(_ notification: UNNotification) {
        guard isEnabled, isProbeNotification(notification) else { return }
        let at = Date()
        let identifier = notification.request.identifier
        let delivered = notification.date
        Task { await shared.presentedInForeground(identifier: identifier, delivered: delivered, at: at) }
    }

    private func presentedInForeground(identifier: String, delivered: Date, at: Date) {
        append(MotionProbeEvent(
            at: at, event: "notification_presented_foreground",
            notes: ["identifier": identifier, "ios_date": MotionProbeCoding.timestamp(delivered)]
        ))
        guard var current = session, identifier.hasPrefix(current.notificationPrefix) else { return }
        let source = String(identifier.dropFirst(current.notificationPrefix.count))
        guard current.delivered[source] == nil else { return }
        current.delivered[source] = delivered
        session = current
        saveSession()
        append(MotionProbeEvent(at: delivered, event: "notification_delivered", source: source,
                                notes: ["observed_at": MotionProbeCoding.timestamp(at), "app_state": "active"]))
    }

    nonisolated static func notificationOpened(_ response: UNNotificationResponse) {
        guard isEnabled, response.notification.request.identifier.hasPrefix("motion-probe-") else { return }
        let at = Date()
        Task {
            await shared.append(MotionProbeEvent(
                at: at, event: "notification_opened",
                notes: ["identifier": response.notification.request.identifier]
            ))
        }
    }

    // MARK: - Switching on and off

    func setEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        let build = await MotionProbeAccess.buildKind()
        append(MotionProbeEvent(at: Date(), event: enabled ? "probe_enabled" : "probe_disabled", notes: ["build": build]))
        if enabled {
            await MainActor.run { UIDevice.current.isBatteryMonitoringEnabled = true }
            MotionProbeMetricKit.shared.start()
        } else {
            stopLiveUpdates()
        }
    }

    // MARK: - Sessions

    func startSession(targetSteps: Double) async {
        let now = Date()
        if var previous = session, previous.isRunning {
            previous.stoppedAt = now
            session = previous
        }
        session = Session(id: Self.sessionId(now), startedAt: now, targetSteps: targetSteps)
        lastLogged = [:]
        liveSteps = 0
        healthSteps = nil
        saveSession()
        append(MotionProbeEvent(at: now, event: "session_started", numbers: ["target_steps": targetSteps]))
        await recordRun(reason: .probeScreen)
    }

    func stopSession() {
        guard var current = session, current.isRunning else { return }
        let now = Date()
        current.stoppedAt = now
        session = current
        saveSession()
        stopLiveUpdates()
        append(MotionProbeEvent(at: now, event: "session_stopped"))
    }

    // MARK: - Runs

    /// One observation of everything the probe measures. Called from every
    /// path on which iOS runs the app; logs even unchanged values, because the
    /// run itself is the data point.
    func recordRun(reason: RunReason) async {
        guard Self.isEnabled else { return }
        let now = Date()
        let device = await Self.deviceState()
        append(MotionProbeEvent(at: now, event: "app_ran", reason: reason.rawValue,
                                numbers: device.numbers, notes: device.notes))

        let dayStart = await HealthSyncSettings.shared.healthDayStart(containing: now)
        let motionDay = await MotionProbePedometer.read(from: dayStart, to: now)
        logRead(motionDay, source: Self.coreMotion, scope: "day", at: Date(), force: true)
        let healthDay = await MotionProbeHealth.steps(from: dayStart, to: now)
        logRead(healthDay.read, source: Self.healthKit, scope: "day", at: Date(), force: true,
                bySource: healthDay.bySource)

        if let current = session, current.isRunning {
            await readSession(current, force: true)
        }
        await checkDelivered()
    }

    /// The probe screen's periodic read: logs only values that changed, or once
    /// a minute, so a screen left open does not flood the log.
    func pollFromScreen() async {
        guard Self.isEnabled, let current = session, current.isRunning else { return }
        await readSession(current, force: false)
        await checkDelivered()
    }

    private func readSession(_ current: Session, force: Bool) async {
        let motion = await MotionProbePedometer.read(from: current.startedAt, to: Date())
        let motionAt = Date()
        logRead(motion, source: Self.coreMotion, scope: "session", at: motionAt, force: force)
        if let steps = motion.steps {
            liveSteps = max(liveSteps ?? 0, steps)
            await check(source: Self.coreMotion, steps: steps, at: motionAt, method: "motion_query")
        }
        let health = await MotionProbeHealth.sessionSteps(from: current.startedAt, to: Date())
        let healthAt = Date()
        logRead(health.read, source: Self.healthKit, scope: "session", at: healthAt, force: force,
                bySource: health.bySource)
        if let steps = health.read.steps {
            healthSteps = steps
            await check(source: Self.healthKit, steps: steps, at: healthAt, method: "healthkit_statistics")
        }
    }

    private func logRead(
        _ read: MotionProbeRead,
        source: String,
        scope: String,
        at: Date,
        force: Bool,
        bySource: [String: Double] = [:]
    ) {
        let key = "\(source)|\(scope)"
        let signature = read.signature
        if !force, let last = lastLogged[key], last.signature == signature, at.timeIntervalSince(last.at) < 60 {
            return
        }
        lastLogged[key] = (signature, at)
        var notes = read.logNotes
        notes["scope"] = scope
        for (name, steps) in bySource {
            notes["source:\(name)"] = String(Int(steps.rounded()))
        }
        append(MotionProbeEvent(at: at, event: "reading", source: source, numbers: read.logNumbers, notes: notes))
    }

    // MARK: - Live Core Motion (only while the probe screen is open)

    func startLiveUpdates() {
        guard Self.isEnabled, livePedometer == nil, let current = session, current.isRunning,
              MotionProbePedometer.isAvailable else { return }
        let pedometer = CMPedometer()
        livePedometer = pedometer
        pedometer.startUpdates(from: current.startedAt) { data, error in
            let at = Date()
            let read = MotionProbePedometer.result(data, error)
            Task { await MotionProbe.shared.liveUpdate(read, at: at) }
        }
        append(MotionProbeEvent(at: Date(), event: "live_updates_started", source: Self.coreMotion))
    }

    func stopLiveUpdates() {
        guard let pedometer = livePedometer else { return }
        pedometer.stopUpdates()
        livePedometer = nil
        append(MotionProbeEvent(at: Date(), event: "live_updates_stopped", source: Self.coreMotion))
    }

    private func liveUpdate(_ read: MotionProbeRead, at: Date) async {
        guard let current = session, current.isRunning else { return }
        logRead(read, source: Self.coreMotion, scope: "live", at: at, force: false)
        if let steps = read.steps {
            // After a restart of the updates iOS can deliver one older count
            // late; the screen keeps the highest.
            liveSteps = max(liveSteps ?? 0, steps)
            await check(source: Self.coreMotion, steps: steps, at: at, method: "motion_live")
        }
    }

    // MARK: - Target, notification, delivery

    private func check(source: String, steps: Double, at: Date, method: String) async {
        guard var current = session, current.isRunning, current.detected[source] == nil else { return }
        guard steps >= current.targetSteps else {
            current.lastBelow[source] = at
            session = current
            saveSession()
            return
        }
        current.detected[source] = at
        session = current
        saveSession()

        // When the data arrived is not observable: only that it came after the
        // last read below the target and by this read.
        var window = ["window_end": MotionProbeCoding.timestamp(at), "method": method]
        if let below = current.lastBelow[source] {
            window["window_start"] = MotionProbeCoding.timestamp(below)
        }
        append(MotionProbeEvent(at: at, event: "data_available", certainty: .estimated,
                                source: source, notes: window))
        append(MotionProbeEvent(at: at, event: "goal_detected", source: source,
                                numbers: ["steps": steps, "target_steps": current.targetSteps],
                                notes: ["method": method]))
        await requestNotification(for: source, steps: steps, session: current)
    }

    private func requestNotification(for source: String, steps: Double, session current: Session) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            append(MotionProbeEvent(at: Date(), event: "notification_not_requested", source: source,
                                    notes: ["why": "not_authorized"]))
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Probe target reached"
        content.body = "\(source == Self.coreMotion ? "Core Motion" : "HealthKit"): \(Int(steps)) of \(Int(current.targetSteps)) steps since the session started."
        content.sound = .default
        let request = UNNotificationRequest(identifier: current.notificationPrefix + source, content: content, trigger: nil)
        do {
            try await center.add(request)
            let at = Date()
            let appState = await MainActor.run { UIApplication.shared.applicationState == .active ? "active" : "not_active" }
            if var updated = session, updated.id == current.id {
                updated.requested[source] = at
                session = updated
                saveSession()
            }
            append(MotionProbeEvent(at: at, event: "notification_requested", source: source,
                                    notes: ["app_state": appState]))
        } catch {
            let nsError = error as NSError
            append(MotionProbeEvent(at: Date(), event: "notification_not_requested", source: source,
                                    notes: ["why": "error", "domain": nsError.domain, "code": String(nsError.code)]))
        }
    }

    /// Delivery is `recorded` only from iOS's own date on a notification still
    /// in Notification Center; one removed by the person or held back by Focus
    /// is never logged as delivered.
    private func checkDelivered() async {
        guard var current = session else { return }
        let pending = current.requested.keys.filter { current.delivered[$0] == nil }
        guard !pending.isEmpty else { return }
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        let observed = Date()
        var changed = false
        for notification in delivered where notification.request.identifier.hasPrefix(current.notificationPrefix) {
            let source = String(notification.request.identifier.dropFirst(current.notificationPrefix.count))
            guard pending.contains(source) else { continue }
            current.delivered[source] = notification.date
            changed = true
            append(MotionProbeEvent(at: notification.date, event: "notification_delivered", source: source,
                                    notes: ["observed_at": MotionProbeCoding.timestamp(observed)]))
        }
        if changed {
            session = current
            saveSession()
        }
    }

    // MARK: - Crossing reconstruction and report

    /// Re-reads the session minute by minute (Core Motion keeps about seven
    /// days) and HealthKit's combined per-minute totals to estimate when each
    /// source crossed the target, then writes a report next to the log.
    func rebuildReport() async -> String {
        guard let current = session else { return "No session yet." }
        return await rebuildReport(for: current)
    }

    /// Rebuilds every session the log still holds from the last seven days,
    /// which is as far back as Core Motion keeps its history. The probe keeps
    /// only the latest session's state; the log keeps them all.
    func rebuildAllSessions() async -> String {
        let horizon = Date().addingTimeInterval(-7 * 24 * 3600)
        let sessions = sessionsFromLog().filter { $0.startedAt > horizon }
        guard !sessions.isEmpty else { return "No session in the log." }
        var texts: [String] = []
        for item in sessions {
            texts.append(await rebuildReport(for: item))
        }
        let text = texts.joined(separator: "\n\n---\n\n")
        lastReport = text
        return text
    }

    /// Sessions as the log recorded them: start, target and stop, the first
    /// detection, request and delivery per source, and the last Core Motion
    /// or HealthKit session read still below the target.
    private func sessionsFromLog() -> [Session] {
        let events = logEvents()
        var sessions: [Session] = []
        var open: Session?
        for event in events {
            switch event.event {
            case "session_started":
                if var previous = open {
                    previous.stoppedAt = previous.stoppedAt ?? event.at
                    sessions.append(previous)
                }
                open = Session(id: Self.sessionId(event.at), startedAt: event.at,
                               targetSteps: event.numbers?["target_steps"] ?? 100)
            case "session_stopped":
                if var finished = open {
                    finished.stoppedAt = event.at
                    sessions.append(finished)
                    open = nil
                }
            case "goal_detected", "notification_requested", "notification_delivered":
                guard var current = open, let source = event.source else { break }
                switch event.event {
                case "goal_detected": current.detected[source] = current.detected[source] ?? event.at
                case "notification_requested": current.requested[source] = current.requested[source] ?? event.at
                default: current.delivered[source] = current.delivered[source] ?? event.at
                }
                open = current
            case "reading":
                guard var current = open, let source = event.source,
                      event.notes?["scope"] != "day", current.detected[source] == nil,
                      let steps = event.numbers?["steps"], steps < current.targetSteps else { break }
                current.lastBelow[source] = event.at
                open = current
            default:
                break
            }
        }
        if let current = open { sessions.append(current) }
        return sessions
    }

    /// The whole log, oldest first.
    private func logEvents() -> [MotionProbeEvent] {
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
        return text.split(separator: "\n")
            .compactMap { MotionProbeEvent.parse(line: String($0)) }
            .sorted { $0.at < $1.at }
    }

    private func rebuildReport(for current: Session) async -> String {
        let end = current.stoppedAt ?? Date()
        let windows = MotionProbeMath.windows(from: current.startedAt, to: end)
        let motion = await MotionProbePedometer.intervals(windows)
        let healthMinutes = await MotionProbeHealth.stepMinutes(from: current.startedAt, to: end)
        let health = (healthMinutes ?? []).map { MotionProbeInterval(start: $0.start, end: $0.end, value: $0.total) }
        // The minute re-read is narrowed by what the session saw as it
        // happened: a read at the target proves the crossing came before it,
        // and for Core Motion, which counts in real time, a read still below
        // the target proves it came after. HealthKit can receive older samples
        // late, so a low HealthKit read proves nothing.
        var crossings: [String: MotionProbeCrossing] = [:]
        var methods: [String: String] = [:]
        let reread: [String: MotionProbeCrossing?] = [
            Self.coreMotion: MotionProbeMath.crossing(of: current.targetSteps, in: motion.intervals),
            Self.healthKit: MotionProbeMath.crossing(of: current.targetSteps, in: health)
        ]
        for (source, found) in reread {
            guard let found else { continue }
            let notBefore = source == Self.coreMotion ? current.lastBelow[source] : nil
            let narrowed = MotionProbeMath.narrowed(found, notBefore: notBefore, notAfter: current.detected[source])
            crossings[source] = narrowed
            let base = source == Self.coreMotion ? "motion_query_1min" : "healthkit_statistics_1min"
            methods[source] = narrowed == found ? base : base + "+session_reads"
        }

        let events = logEvents()
        // A rebuild that finds the same window again adds nothing to the log.
        let logged = Set(events.filter { $0.event == "goal_crossed" }.map {
            "\($0.source ?? "")|\($0.notes?["window_start"] ?? "")|\($0.notes?["window_end"] ?? "")"
        })
        for (source, crossing) in crossings {
            let key = "\(source)|\(MotionProbeCoding.timestamp(crossing.windowStart))|\(MotionProbeCoding.timestamp(crossing.windowEnd))"
            guard !logged.contains(key) else { continue }
            append(MotionProbeEvent(
                at: crossing.windowEnd, event: "goal_crossed", certainty: .estimated, source: source,
                numbers: ["total_before": crossing.totalBefore, "total_after": crossing.totalAfter],
                notes: ["window_start": MotionProbeCoding.timestamp(crossing.windowStart),
                        "window_end": MotionProbeCoding.timestamp(crossing.windowEnd),
                        "method": methods[source] ?? ""]
            ))
        }

        let sessionMotion = await MotionProbePedometer.read(from: current.startedAt, to: end)
        let activeEnergy = await MotionProbeHealth.activeEnergy(from: current.startedAt, to: end)
        var bySource: [String: Double] = [:]
        for minute in healthMinutes ?? [] {
            for (name, steps) in minute.bySource { bySource[name, default: 0] += steps }
        }
        let text = Self.reportText(
            current, end: end, crossings: crossings, motionFailures: motion.failures,
            motionWindows: windows.count, sessionMotion: sessionMotion, activeEnergy: activeEnergy,
            windowTotals: [Self.coreMotion: motion.intervals.reduce(0) { $0 + $1.value },
                           Self.healthKit: health.reduce(0) { $0 + $1.value }],
            healthBySource: bySource,
            timeline: MotionProbeTimeline(events: events, from: current.startedAt, to: end)
        )
        try? FileManager.default.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        try? text.write(to: reportsDirectory.appendingPathComponent("session-\(current.id).txt"), atomically: true, encoding: .utf8)
        let csv = MotionProbeCSV.minutes(
            Self.minuteRows(start: current.startedAt, motion: motion.intervals, health: healthMinutes),
            calendar: .current
        )
        try? csv.write(to: reportsDirectory.appendingPathComponent("session-\(current.id)-minutes.csv"), atomically: true, encoding: .utf8)
        lastReport = text
        return text
    }

    /// Core Motion's and HealthKit's minutes side by side. Both are cut from
    /// the session start in whole minutes, so they pair by minute index.
    private static func minuteRows(
        start: Date,
        motion: [MotionProbeInterval],
        health: [MotionProbeHealth.MinuteSteps]?
    ) -> [MotionProbeMinute] {
        let index = { (date: Date) in Int((date.timeIntervalSince(start) / 60).rounded()) }
        var motionByMinute: [Int: Double] = [:]
        for interval in motion { motionByMinute[index(interval.start)] = interval.value }
        var healthByMinute: [Int: MotionProbeHealth.MinuteSteps] = [:]
        for minute in health ?? [] { healthByMinute[index(minute.start)] = minute }
        let minutes = Set(motionByMinute.keys).union(healthByMinute.keys).sorted()
        return minutes.map { i in
            MotionProbeMinute(
                start: start.addingTimeInterval(Double(i) * 60),
                coreMotion: motionByMinute[i],
                healthKit: health == nil ? nil : (healthByMinute[i]?.total ?? 0),
                healthKitBySource: healthByMinute[i]?.bySource ?? [:]
            )
        }
    }

    private static func reportText(
        _ session: Session,
        end: Date,
        crossings: [String: MotionProbeCrossing],
        motionFailures: Int,
        motionWindows: Int,
        sessionMotion: MotionProbeRead,
        activeEnergy: Double?,
        windowTotals: [String: Double],
        healthBySource: [String: Double],
        timeline: MotionProbeTimeline
    ) -> String {
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm:ss"
        func time(_ date: Date) -> String { clock.string(from: date) }

        var lines = [
            "Honoured motion probe, session \(session.id)",
            "Target: \(Int(session.targetSteps)) steps from \(time(session.startedAt)) to \(time(end))",
            "Core Motion minute windows read: \(motionWindows - motionFailures) of \(motionWindows)"
        ] + timeline.summaryLines(clock: time) + [""]
        for source in [coreMotion, healthKit] {
            let name = source == coreMotion ? "Core Motion" : "HealthKit (combined)"
            lines.append("\(name): \(Int(windowTotals[source] ?? 0)) steps in the session")
            if source == healthKit, !healthBySource.isEmpty {
                let shares = healthBySource.sorted { $0.key < $1.key }
                    .map { "\($0.key) \(Int($0.value.rounded()))" }
                    .joined(separator: ", ")
                lines.append("  by source: \(shares)")
            }
            let crossing = crossings[source]
            if let crossing {
                lines.append("  target crossed (estimated): \(time(crossing.windowStart))–\(time(crossing.windowEnd))")
            } else {
                lines.append("  target not crossed in the re-read data")
            }
            func moment(_ date: Date) -> String {
                guard let crossing else { return time(date) }
                return "\(time(date)), \(MotionProbeMath.delayText(MotionProbeMath.delayRange(from: crossing, to: date))) after crossing"
            }
            guard let noticed = session.detected[source] else {
                lines.append("  app noticed: not during the session\(lastRead(timeline.lastSessionRead(of: source), time: time))")
                lines.append("")
                continue
            }
            let place = timeline.place(at: noticed).map { ", Honoured in the \($0.rawValue)" } ?? ""
            lines.append("  app noticed (recorded): \(moment(noticed))\(place)")
            guard let requested = session.requested[source] else {
                lines.append("  notification requested: none")
                lines.append("")
                continue
            }
            lines.append("  notification requested (recorded): \(moment(requested))")
            lines.append("  notification delivered (recorded by iOS): \(session.delivered[source].map(moment) ?? "unknown, not found in Notification Center")")
            lines.append("")
        }
        lines.append("Crossing times are when the steps were taken, not when a source had them. HealthKit spreads each sample evenly over its time span, so its minutes are approximate.")
        lines.append("")
        if case .value(_, let distance, let active) = sessionMotion, let distance {
            let estimate = MotionProbeMath.estimatedActiveKilocalories(distanceMeters: distance, activeSeconds: active)
            lines.append("Calories (estimate, 70 kg assumed, \(estimate.gait.rawValue)): \(Int(estimate.kilocalories.rounded())) kcal")
        } else {
            lines.append("Calories (estimate): no Core Motion distance")
        }
        lines.append("Apple Health Active Energy: \(activeEnergy.map { "\(Int($0.rounded())) kcal" } ?? "no data yet")")
        return lines.joined(separator: "\n")
    }

    /// " (last read 16:30:20: no data)", or nothing when the session has no read.
    private static func lastRead(_ event: MotionProbeEvent?, time: (Date) -> String) -> String {
        guard let event else { return "" }
        let value: String
        switch event.notes?["result"] {
        case "value": value = "\(Int((event.numbers?["steps"] ?? 0).rounded())) steps"
        case "no_data": value = "no data"
        case let result?: value = event.notes?["meaning"] ?? result
        case nil: value = "unknown"
        }
        return " (last read \(time(event.at)): \(value))"
    }

    // MARK: - Log and export

    func snapshot() -> Snapshot {
        loadRecentIfNeeded()
        return Snapshot(enabled: Self.isEnabled, session: session, liveSteps: liveSteps,
                        healthSteps: healthSteps, recent: Array(recent.suffix(60).reversed()), lastReport: lastReport)
    }

    /// A zip of the whole probe folder: the event log, reports and MetricKit
    /// payloads.
    func exportArchive() throws -> URL {
        let stamp = Self.sessionId(Date())
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("honoured-motion-probe-\(stamp).zip")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.zipItem(at: directory, to: destination)
        append(MotionProbeEvent(at: Date(), event: "log_exported"))
        return destination
    }

    func clearLog() {
        try? FileManager.default.removeItem(at: logURL)
        try? FileManager.default.removeItem(at: reportsDirectory)
        try? FileManager.default.removeItem(at: metricKitDirectory)
        recent = []
        lastReport = nil
        session = nil
        saveSession()
        append(MotionProbeEvent(at: Date(), event: "log_cleared"))
    }

    func append(_ event: MotionProbeEvent) {
        loadRecentIfNeeded()
        recent.append(event)
        if recent.count > 300 { recent.removeFirst(recent.count - 300) }
        guard let line = try? event.jsonLine() else { return }
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }

    private func loadRecentIfNeeded() {
        guard !recentLoaded else { return }
        recentLoaded = true
        guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return }
        let lines = text.split(separator: "\n").suffix(300)
        recent = lines.compactMap { MotionProbeEvent.parse(line: String($0)) } + recent
    }

    private func saveSession() {
        if let session, let data = try? MotionProbeCoding.encoder.encode(session) {
            UserDefaults.standard.set(data, forKey: Self.sessionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.sessionKey)
        }
    }

    private static func sessionId(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    // MARK: - Device state

    private static func deviceState() async -> (numbers: [String: Double], notes: [String: String]) {
        await MainActor.run {
            let device = UIDevice.current
            let application = UIApplication.shared
            var numbers: [String: Double] = [:]
            if device.isBatteryMonitoringEnabled, device.batteryLevel >= 0 {
                numbers["battery_level"] = Double(device.batteryLevel)
            }
            let state: String
            switch application.applicationState {
            case .active: state = "active"
            case .inactive: state = "inactive"
            case .background: state = "background"
            @unknown default: state = "unknown"
            }
            let battery: String
            switch device.batteryState {
            case .charging: battery = "charging"
            case .full: battery = "full"
            case .unplugged: battery = "unplugged"
            case .unknown: battery = "unknown"
            @unknown default: battery = "unknown"
            }
            let thermal: String
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: thermal = "nominal"
            case .fair: thermal = "fair"
            case .serious: thermal = "serious"
            case .critical: thermal = "critical"
            @unknown default: thermal = "unknown"
            }
            return (numbers, [
                "app_state": state,
                "protected_data": application.isProtectedDataAvailable ? "available" : "locked",
                "low_power": String(ProcessInfo.processInfo.isLowPowerModeEnabled),
                "battery_state": battery,
                "thermal": thermal
            ])
        }
    }
}
