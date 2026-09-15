import UIKit

@MainActor
final class HonouredAppDelegate: NSObject, UIApplicationDelegate {
    private var lifecycleObservers: [NSObjectProtocol] = []

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // These registrations must happen synchronously here: HealthKit delivers
        // a launch-time observer update only to queries that already exist,
        // BGTaskScheduler refuses a launch handler registered after launch, and a
        // notification tap that launched the app is only delivered to a delegate
        // that is already set.
        HealthBackgroundObserver.shared.start()
        HealthBackgroundRefresh.shared.register()
        NotificationCoordinator.shared.install()
        observeLifecycle()

        Task {
            if await AuthSessionStore.shared.load() != nil {
                HealthBackgroundObserver.shared.enableBackgroundDelivery()
                HealthBackgroundRefresh.shared.schedule()
            }
            await HealthBackgroundDeliveryCoordinator.shared.retryPendingCollection()
        }
        return true
    }

    /// The SwiftUI App lifecycle is scene-based, so UIKit routes active/background
    /// transitions to the scene rather than to this delegate. The notifications
    /// fire in both lifecycles.
    private func observeLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { _ in
                Task { await HealthBackgroundDeliveryCoordinator.shared.retryPendingCollection() }
            },
            center.addObserver(
                forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main
            ) { _ in
                Task { await HealthBackgroundDeliveryCoordinator.shared.retryPendingCollection() }
            },
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
            ) { _ in
                // Refresh the pending request on every background transition so the
                // earliest-begin date is measured from the last time the user left.
                HealthBackgroundRefresh.shared.scheduleIfSessionExists()
            }
        ]
    }
}
