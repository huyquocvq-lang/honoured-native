import ActivityKit
import Foundation

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
        let policy: ActivityUIDismissalPolicy
        switch dismissal {
        case .immediate: policy = .immediate
        case .after(let date): policy = .after(date)
        }
        await activity.end(content.map(Self.content), dismissalPolicy: policy)
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
