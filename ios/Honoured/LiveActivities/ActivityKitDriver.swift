import ActivityKit
import Foundation
import UIKit

/// The real ActivityKit calls. Only `LiveActivityEngine` uses it, and only on
/// iOS 16.2+, where `ActivityContent` carries the relevance score that decides
/// which Honoured card leads in the Dynamic Island.
@available(iOS 16.2, *)
final class ActivityKitDriver: LiveActivityDriving {
    private let lock = NSLock()
    private var observers: [String: Task<Void, Never>] = [:]

    var isSupported: Bool { true }

    func activitiesEnabled() -> Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func runningActivities() -> [DriverActivityInfo] {
        Activity<HonouredActivityAttributes>.activities.map { activity in
            DriverActivityInfo(
                id: activity.id,
                attributes: DriverAttributes(
                    contractId: activity.attributes.contractId,
                    healthDay: activity.attributes.healthDay,
                    occurrenceToken: activity.attributes.occurrenceToken
                ),
                state: Self.state(activity.activityState)
            )
        }
    }

    func request(attributes: DriverAttributes, content: DriverContent) throws -> String {
        do {
            let activity = try Activity.request(
                attributes: HonouredActivityAttributes(
                    contractId: attributes.contractId,
                    healthDay: attributes.healthDay,
                    occurrenceToken: attributes.occurrenceToken
                ),
                content: Self.content(content),
                pushType: nil
            )
            return activity.id
        } catch let error as ActivityAuthorizationError {
            throw Self.requestError(error)
        } catch {
            throw DriverRequestError.failed(String(describing: error))
        }
    }

    func update(activityId: String, content: DriverContent) async {
        guard let activity = find(activityId) else { return }
        await activity.update(Self.content(content))
    }

    func end(activityId: String, content: DriverContent?, dismissal: DriverDismissal) async {
        guard let activity = find(activityId) else { return }
        if let completed = content, completed.state.status == .completed, await !Self.appIsActive() {
            // The island is on screen: the active -> completed update runs the
            // widget's pulse, and the card stays there until the person opens
            // the app (`endPresentedCompletions`). A delayed end would not run
            // reliably once iOS suspends the app again. The alert makes iOS
            // expand the island and light a locked screen for the moment.
            await activity.update(Self.content(completed), alertConfiguration: Self.completionAlert(completed.state))
            return
        }
        // In the app the island is hidden, so there is nothing to present:
        // end now, and nothing is left on the island when the person leaves.
        await activity.end(content.map(Self.content), dismissalPolicy: Self.policy(dismissal))
    }

    /// Ends every completion still presented on the island. Runs when the app
    /// becomes active, including after a relaunch, so it reads the cards from
    /// ActivityKit rather than from memory.
    func endPresentedCompletions() async {
        for activity in Activity<HonouredActivityAttributes>.activities
        where activity.activityState == .active || activity.activityState == .stale {
            guard activity.content.state.status == .completed else { continue }
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }
    }

    /// Silent on purpose: the timer and goal notifications already carry the
    /// completion sound when the person enabled it, and the alert must not
    /// play a second one or interrupt music. A missing named sound would fall
    /// back to the default one, so the silent file is bundled.
    static func completionAlert(_ state: HonouredLiveActivityState) -> AlertConfiguration {
        AlertConfiguration(
            title: "Honoured",
            body: "\(state.contractName) is honoured.",
            sound: .named("live-activity-silent.caf")
        )
    }

    @MainActor
    private static func appIsActive() -> Bool {
        UIApplication.shared.applicationState == .active
    }

    func observe(activityId: String, onChange: @escaping @Sendable (DriverActivityState) -> Void) {
        guard let activity = find(activityId) else { return }
        let task = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                onChange(Self.state(state))
                if state == .dismissed { break }
            }
            self?.forgetObserver(activityId)
        }
        lock.lock()
        observers[activityId]?.cancel()
        observers[activityId] = task
        lock.unlock()
    }

    private func forgetObserver(_ activityId: String) {
        lock.lock()
        observers[activityId] = nil
        lock.unlock()
    }

    private func find(_ id: String) -> Activity<HonouredActivityAttributes>? {
        Activity<HonouredActivityAttributes>.activities.first { $0.id == id }
    }

    private static func content(_ content: DriverContent) -> ActivityContent<HonouredLiveActivityState> {
        ActivityContent(state: content.state, staleDate: content.staleDate, relevanceScore: content.relevanceScore)
    }

    private static func policy(_ dismissal: DriverDismissal) -> ActivityUIDismissalPolicy {
        switch dismissal {
        case .immediate: return .immediate
        case .after(let date): return .after(date)
        }
    }

    private static func state(_ state: ActivityState) -> DriverActivityState {
        switch state {
        case .active: return .active
        case .stale: return .stale
        case .ended: return .ended
        case .dismissed: return .dismissed
        default: return .other
        }
    }

    private static func requestError(_ error: ActivityAuthorizationError) -> DriverRequestError {
        switch error {
        case .denied: return .disabled
        case .globalMaximumExceeded, .targetMaximumExceeded: return .limitReached
        case .visibility: return .needsForeground
        case .attributesTooLarge: return .payloadTooLarge
        case .unsupported, .unsupportedTarget: return .unsupported
        default: return .failed(String(describing: error))
        }
    }
}
