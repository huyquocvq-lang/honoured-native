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
                // Google's sign-in callback goes to the Google SDK; taps on a
                // contract Live Activity keep their route, and the web app
                // gets LIVE_ACTIVITY_OPENED once it is ready, never before.
                .onOpenURL { AppURLRouter.handle($0) }
        }
    }
}
