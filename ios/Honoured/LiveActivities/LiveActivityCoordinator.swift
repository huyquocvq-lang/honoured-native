import Foundation
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// App-side entry point for contract Live Activities. Owns the engine on
/// iOS 16.2+ and is an inert no-op below that, where the timer, Health sync and
/// notifications keep working exactly as before and the bridge reports the
/// feature as unsupported.
final class LiveActivityCoordinator {
    static let shared = LiveActivityCoordinator()

    private let engine: LiveActivityEngine?

    private init() {
        if #available(iOS 16.2, *) {
            let engine = LiveActivityEngine(
                driver: ActivityKitDriver(),
                environment: AppLiveActivityEnvironment(),
                persistence: FileTrackedContractsPersistence(url: FileTrackedContractsPersistence.defaultURL)
            )
            engine.start()
            self.engine = engine
        } else {
            engine = nil
        }
    }

    var isSupported: Bool { engine != nil }

    /// Synchronous, for `NATIVE_READY` and `PLATFORM_INFO`. `enabled` is the
    /// Live Activities switch at this moment, not notification or Health access.
    func capabilities() -> [String: Any] {
        var enabled = false
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        }
        #endif
        return LiveActivityProtocol.capabilities(supported: isSupported, enabled: enabled)
    }

    /// Queues a command in call order. Without an engine the reply never comes,
    /// so callers check `isSupported` first.
    func submit(_ command: LiveActivityEngine.Command, reply: ((LiveActivityEngine.Outcome) -> Void)? = nil) {
        engine?.submit(command, reply: reply)
    }

    // MARK: - Lifecycle

    /// Also runs on background launches: restore only ends or adopts cards.
    func applicationDidFinishLaunching() {
        submit(.restore)
    }

    func applicationDidBecomeActive() {
        submit(.appBecameActive)
        refreshHealthSoon()
    }

    /// Before the first unlock neither the store nor the Keychain can be read,
    /// so restore is repeated once they can.
    func protectedDataDidBecomeAvailable() {
        submit(.restore)
        refreshHealthSoon()
    }

    /// Reset hour, time zone, midnight or a clock change.
    func dayMayHaveChanged() {
        submit(.dayMayHaveChanged)
        refreshHealthSoon()
    }

    /// `SET_AUTH_SESSION` (user ID) or `CLEAR_AUTH_SESSION` (nil), queued the
    /// moment the message arrives so no later mutation can overtake it.
    func accountChanged(_ userId: String?) {
        submit(.accountChanged(userId))
    }

    // MARK: - Testament Timer

    func timerStarted(_ timer: ActiveTimer, replaced: ActiveTimer?) {
        submit(.timerStarted(timer.runSnapshot, replaced: replaced?.runSnapshot))
    }

    func timerDiscarded(_ timer: ActiveTimer) {
        submit(.timerDiscarded(timer.runSnapshot))
    }

    func timerCompleted(_ timer: ActiveTimer) {
        submit(.timerCompleted(timer.runSnapshot))
    }

    // MARK: - Health

    /// Reads Health for every card that shows it. The returned totals let goal
    /// detection reuse the same reads.
    func refreshHealthProgress() async -> HealthPrefetch? {
        await engine?.refreshHealth()
    }

    func refreshHealthSoon() {
        guard isSupported else { return }
        Task { _ = await refreshHealthProgress() }
    }

    // MARK: - Deep links

    /// Handles `honoured://contract/...`. Anything else, or a link to an
    /// occurrence the signed-in account does not track, only opens the app.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let target = ContractDeepLink.parse(url) else { return false }
        submit(.deepLink(target))
        return true
    }
}

/// The real services behind `LiveActivityEnvironment`.
private final class AppLiveActivityEnvironment: LiveActivityEnvironment {
    func now() -> Date { Date() }

    var calendar: Calendar { Calendar.current }

    func dayResetHour() async -> Int {
        await HealthSyncSettings.shared.dayResetHour()
    }

    func goals() async -> [GoalSnapshot] {
        await HealthSyncSettings.shared.currentGoals().map {
            GoalSnapshot(activityId: $0.activityId, metric: $0.metric, target: $0.target)
        }
    }

    func account() async -> NativeAccountState {
        await AuthSessionStore.shared.accountState()
    }

    func currentTimer() async -> TimerRunSnapshot? {
        await TestamentTimer.shared.current()?.runSnapshot
    }

    func startTimer(activityId: String, activityName: String, durationSeconds: Double) async -> (started: TimerRunSnapshot, replaced: TimerRunSnapshot?) {
        let result = await TestamentTimer.shared.start(
            activityId: activityId, activityName: activityName, durationSeconds: durationSeconds
        )
        return (result.timer.runSnapshot, result.replaced?.runSnapshot)
    }

    func isAppInForeground() async -> Bool {
        await MainActor.run { UIApplication.shared.applicationState != .background }
    }

    func readHealth(metric: HealthMetric, from: Date, to: Date) async -> HealthTotalRead {
        await HealthKitService.shared.readTotal(for: metric, from: from, to: to)
    }

    func stateChanged(_ snapshot: LiveActivityStateSnapshot) {
        NativeBridgeEvents.post(type: "LIVE_ACTIVITY_STATE_CHANGED", payload: snapshot.payload)
    }

    func contractOpened(eventId: String, key: OccurrenceKey) {
        NativeBridgeEvents.postDurable(type: "LIVE_ACTIVITY_OPENED", payload: [
            "eventId": eventId,
            "contractId": key.contractId,
            "healthDay": key.healthDay
        ])
    }
}
