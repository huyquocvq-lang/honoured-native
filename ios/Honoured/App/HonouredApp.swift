import SwiftUI

@main
struct HonouredApp: App {
    @UIApplicationDelegateAdaptor(HonouredAppDelegate.self) private var appDelegate

    init() {
        SubscriptionService.shared.configureIfPossible()
        HealthNetworkMonitor.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
