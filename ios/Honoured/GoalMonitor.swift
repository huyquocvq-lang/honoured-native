import Foundation
import UIKit

/// Compares today's on-device totals with the goals the web app sent through
/// `SET_GOALS` and announces each goal at most once per activity per health
/// day. Runs after every collection pass that queued new samples, so a goal
/// crossed while the app is in the background is noticed on the same wake that
/// read the data. It never derives totals from raw samples; it uses the same
/// source-deduplicated statistics queries as `health_daily`.
actor GoalMonitor {
    static let shared = GoalMonitor()

    private let defaults = UserDefaults.standard
    private let markersKey = "goals.reached-markers"

    private init() {}

    // MARK: - Evaluation

    func evaluate() async {
        let goals = await HealthSyncSettings.shared.currentGoals()
        guard !goals.isEmpty, HealthKitService.shared.isAvailable else { return }

        let now = Date()
        let dayStart = await HealthSyncSettings.shared.healthDayStart(containing: now)
        let day = HealthSyncSettings.dayString(dayStart)
        var markers = prunedMarkers(keeping: day)

        for goal in goals where !markers.contains(Self.marker(goal.activityId, day)) {
            guard let value = await HealthKitService.shared.total(for: goal.metric, from: dayStart, to: now),
                  value >= goal.target else { continue }

            // Persist the marker before announcing so a crash in between can only
            // lose an event, never repeat a notification.
            markers.insert(Self.marker(goal.activityId, day))
            save(markers)

            let isActive = await MainActor.run { UIApplication.shared.applicationState == .active }
            var notified = false
            if !isActive, await NotificationCoordinator.shared.isAuthorized() {
                notified = (try? await NotificationCoordinator.shared.schedule(
                    identifier: "goal-\(goal.activityId)-\(day)",
                    kind: .goal,
                    activityId: goal.activityId,
                    title: "Goal reached",
                    body: "\(goal.activityName) — \(Self.format(value, goal.metric)) of \(Self.format(goal.target, goal.metric)).",
                    at: now,
                    sound: NotificationSound.current
                )) != nil
            }

            NativeBridgeEvents.postDurable(type: "GOAL_REACHED", payload: [
                "activityId": goal.activityId,
                "metric": goal.metric.rawValue,
                "value": value,
                "target": goal.target,
                "reachedAt": TestamentTimer.iso8601.string(from: now),
                "notified": notified
            ])
        }
    }

    // MARK: - Markers

    /// The web app marked the contract honoured itself (timer, manual, or its own
    /// HealthKit read), so native must not notify for it again today.
    func markCelebrated(activityId: String) async {
        let dayStart = await HealthSyncSettings.shared.healthDayStart(containing: Date())
        let day = HealthSyncSettings.dayString(dayStart)
        var markers = prunedMarkers(keeping: day)
        markers.insert(Self.marker(activityId, day))
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
