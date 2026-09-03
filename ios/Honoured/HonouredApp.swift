import SwiftUI

@main
struct HonouredApp: App {
    init() {
        SubscriptionService.shared.configureIfPossible()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
