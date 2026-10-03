#if DEBUG
import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Starts, advances and ends a sample Icon card (`STUB_ICON_CARD`) so the
/// widget can be seen on a simulator or device before push-to-start exists.
/// Debug builds only; it touches no account data.
enum IconCardStub {
    static func apply(phase: String) async -> String {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return "unsupported" }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return "disabled" }
        let now = Date()
        switch phase {
        case "start":
            await endAll()
            let facts = IconCardFacts(
                contractId: "stub-icon", iconDay: "2026-10-06", weekday: "Tue", sessionNumber: 5, totalSessions: 17,
                targetValue: "10,000", targetUnit: "steps", activityName: "Walking",
                because: "Spring has begun, all life has sprung.",
                deadline: Calendar.current.startOfDay(for: now).addingTimeInterval(24 * 3600)
            )
            do {
                _ = try Activity.request(
                    attributes: IconActivityAttributes(facts: facts),
                    content: ActivityContent(state: .morning(sessionNumber: 5, at: now), staleDate: facts.deadline)
                )
                return "started"
            } catch {
                return "error: \(error.localizedDescription)"
            }
        case "evening":
            return await update(.evening(at: now))
        case "honoured":
            return await update(.result(.honoured, at: now))
        case "broken":
            return await update(.result(.broken, at: now))
        case "end":
            await endAll()
            return "ended"
        case "count":
            return String(Activity<IconActivityAttributes>.activities.count)
        default:
            return "unknown phase"
        }
        #else
        return "unsupported"
        #endif
    }

    #if canImport(ActivityKit)
    @available(iOS 16.2, *)
    private static func update(_ state: IconLiveActivityState) async -> String {
        let activities = Activity<IconActivityAttributes>.activities
        for activity in activities {
            await activity.update(ActivityContent(state: state, staleDate: activity.attributes.facts.deadline))
        }
        return "updated \(activities.count)"
    }

    @available(iOS 16.2, *)
    private static func endAll() async {
        for activity in Activity<IconActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
    #endif
}
#endif
