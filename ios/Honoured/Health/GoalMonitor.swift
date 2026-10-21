import Foundation
import UIKit

/// Compares today's on-device totals with the goals the web app sent through
/// `SET_GOALS` and announces each goal at most once per activity per health
/// day. Runs after every collection pass, so a goal crossed while the app is
/// in the background is noticed on the same wake that read the data. It never
/// derives totals from raw samples; it uses the same source-deduplicated
/// statistics queries as `health_daily`, or Core Motion when the person chose
/// it. The marker ignores the source, so switching sources never announces a
/// goal twice.
actor GoalMonitor {
    static let shared = GoalMonitor()

    private let defaults = UserDefaults.standard
    private let markersKey = "goals.reached-markers"

    /// One check at a time. Reads suspend the actor, so two checks at once —
    /// a sync pass and the live Core Motion count, say — could both find a
    /// goal unmarked and announce it twice.
    private var isEvaluating = false
    private var needsAnotherPass = false
    private var nextTrigger: String?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private init() {}

    // MARK: - Evaluation

    /// Returns once a check that started after this call has finished. A call
    /// that arrives during a check runs one more pass afterwards, with fresh
    /// reads, so no request is lost and none overlaps another.
    ///
    /// - Parameters:
    ///   - prefetched: totals the Live Activity refresh just read for today's
    ///     window. They are reused only for the same health-day start, so a read
    ///     that straddled the reset never counts toward the new day.
    ///   - trigger: what asked for this check (`sync_pass`, `motion_live`,
    ///     `live_start`, ...), for the diagnostics.
    func evaluate(prefetched: HealthPrefetch? = nil, trigger: String = "sync_pass") async {
        if isEvaluating {
            needsAnotherPass = true
            nextTrigger = trigger
            await withCheckedContinuation { waiters.append($0) }
            return
        }
        isEvaluating = true
        var prefetched = prefetched
        var trigger = trigger
        repeat {
            needsAnotherPass = false
            await evaluatePass(prefetched: prefetched, trigger: trigger)
            prefetched = nil
            trigger = nextTrigger ?? trigger
            nextTrigger = nil
        } while needsAnotherPass
        isEvaluating = false
        let resumed = waiters
        waiters.removeAll()
        for waiter in resumed { waiter.resume() }
    }

    private func evaluatePass(prefetched: HealthPrefetch?, trigger: String) async {
        let goals = await HealthSyncSettings.shared.currentGoals()
        guard !goals.isEmpty, HealthKitService.shared.isAvailable else { return }

        let now = Date()
        let dayStart = await HealthSyncSettings.shared.healthDayStart(containing: now)
        let day = HealthSyncSettings.dayString(dayStart)
        let markedAtStart = prunedMarkers(keeping: day)
        let reusable = prefetched?.dayStart == dayStart ? prefetched?.totals ?? [:] : [:]
        let account = GoalDiagnostics.account()

        for goal in goals where !markedAtStart.contains(Self.marker(goal.activityId, day)) {
            let read: HealthTotalRead
            let source: HealthReadingSource
            if let prefetchedRead = reusable[goal.metric] {
                read = prefetchedRead
                source = await HealthKitService.shared.readingSource(for: goal.metric)
            } else {
                (read, source) = await HealthKitService.shared.readTotalAndSource(for: goal.metric, from: dayStart, to: now)
            }
            await GoalDiagnostics.shared.reading(
                activityId: goal.activityId, metric: goal.metric, day: day, target: goal.target,
                read: read, source: source, trigger: trigger, at: now, account: account
            )
            guard let value = read.numericValue, value >= goal.target else { continue }

            // Read the markers again and mark with no suspension in between:
            // ACTIVITY_COMPLETED may have marked the goal during the reads.
            // The marker is saved before announcing so a crash in between can
            // only lose an event, never repeat a notification.
            var markers = prunedMarkers(keeping: day)
            guard markers.insert(Self.marker(goal.activityId, day)).inserted else { continue }
            save(markers)

            let identifier = "goal-\(goal.activityId)-\(day)"
            let isActive = await MainActor.run { UIApplication.shared.applicationState == .active }
            var notified = false
            var notification = isActive ? "app_active" : "not_authorized"
            if !isActive, await NotificationCoordinator.shared.isAuthorized() {
                notified = (try? await NotificationCoordinator.shared.schedule(
                    identifier: identifier,
                    kind: .goal,
                    activityId: goal.activityId,
                    title: "Goal reached",
                    body: "\(goal.activityName) — \(Self.format(value, goal.metric)) of \(Self.format(goal.target, goal.metric)).",
                    at: now,
                    sound: NotificationSound.current
                )) != nil
                notification = notified ? "scheduled" : "failed"
            }

            NativeBridgeEvents.postDurable(type: "GOAL_REACHED", payload: [
                "activityId": goal.activityId,
                "metric": goal.metric.rawValue,
                "value": value,
                "target": goal.target,
                "reachedAt": TestamentTimer.iso8601.string(from: now),
                "notified": notified,
                "source": source.rawValue
            ])
            MotionProbe.noteAppGoal(
                metric: goal.metric.rawValue, value: value, target: goal.target,
                notified: notified, source: source.rawValue
            )
            // Not awaited: estimating the crossing reads history and must not
            // hold the next goal's announcement.
            let metric = goal.metric, activityId = goal.activityId, target = goal.target
            Task {
                await GoalDiagnostics.shared.goalDetected(
                    activityId: activityId, metric: metric, day: day, dayStart: dayStart, target: target,
                    value: value, source: source, trigger: trigger, notification: notification,
                    identifier: identifier, at: now, account: account
                )
            }
        }
    }

    // MARK: - Markers

    /// The web app marked the contract honoured itself (timer, manual, or its own
    /// HealthKit read), so native must not notify for it again today. Timer and
    /// manual completions name the contract id while goals are addressed per
    /// slot (`<id>:primary`), so every current goal under that contract is
    /// marked as well.
    ///
    /// - Parameter day: the health day the completion belongs to, when the web
    ///   app names it. A completion that arrives after the reset then marks
    ///   its own day and cannot silence today's goal. Nil means today.
    func markCelebrated(activityId: String, day: String? = nil) async {
        let dayStart = await HealthSyncSettings.shared.healthDayStart(containing: Date())
        let goals = await HealthSyncSettings.shared.currentGoals()
        let today = HealthSyncSettings.dayString(dayStart)
        let markerDay = day ?? today
        // Read and saved with no suspension in between, so a mark a running
        // check makes meanwhile is never overwritten.
        var markers = prunedMarkers(keeping: today)
        markers.insert(Self.marker(activityId, markerDay))
        let slotPrefix = activityId + ":"
        for goal in goals where goal.activityId.hasPrefix(slotPrefix) {
            markers.insert(Self.marker(goal.activityId, markerDay))
        }
        save(markers)
    }

    /// A different reset hour redraws the day boundaries, so markers keyed by
    /// the old days no longer mean anything. The evaluation that follows runs
    /// while the app is active, so a goal still met under the new boundaries is
    /// re-announced in-app without a notification.
    func clear() {
        defaults.removeObject(forKey: markersKey)
    }

    private static func marker(_ activityId: String, _ day: String) -> String {
        "\(activityId)|\(day)"
    }

    /// Keeps only today's markers plus the previous day's, which still matter
    /// for late samples attributed to yesterday and for the hours right after
    /// the reset boundary.
    private func prunedMarkers(keeping day: String) -> Set<String> {
        let stored = Set(defaults.stringArray(forKey: markersKey) ?? [])
        let previousDay: String = {
            guard let start = Self.parseDay(day),
                  let previous = Calendar.current.date(byAdding: .day, value: -1, to: start) else { return "" }
            return HealthSyncSettings.dayString(previous)
        }()
        let kept = stored.filter { $0.hasSuffix("|\(day)") || (!previousDay.isEmpty && $0.hasSuffix("|\(previousDay)")) }
        if kept.count != stored.count {
            save(kept)
        }
        return kept
    }

    private func save(_ markers: Set<String>) {
        defaults.set(Array(markers).sorted(), forKey: markersKey)
    }

    private static func parseDay(_ day: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day)
    }

    // MARK: - Copy

    private static func format(_ value: Double, _ metric: HealthMetric) -> String {
        switch metric {
        case .steps:
            return "\(Int(value.rounded())) steps"
        case .distanceWalkingRunning, .distanceCycling, .distanceSwimming:
            return value >= 1000 ? String(format: "%.1f km", value / 1000) : "\(Int(value.rounded())) m"
        case .activeEnergy, .basalEnergy:
            return "\(Int(value.rounded())) kcal"
        case .heartRate:
            return "\(Int(value.rounded())) bpm"
        case .exerciseMinutes, .sleep:
            return "\(Int(value.rounded())) min"
        }
    }
}
