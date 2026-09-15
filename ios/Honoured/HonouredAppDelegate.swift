import UIKit

@MainActor
final class HonouredAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        HealthBackgroundObserver.shared.start()
        Task {
            if await AuthSessionStore.shared.load() != nil {
                HealthBackgroundObserver.shared.enableBackgroundDelivery()
            }
            await HealthBackgroundDeliveryCoordinator.shared.retryPendingCollection()
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Task {
            await HealthBackgroundDeliveryCoordinator.shared.retryPendingCollection()
        }
    }

    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        Task {
            await HealthBackgroundDeliveryCoordinator.shared.retryPendingCollection()
        }
    }
}
