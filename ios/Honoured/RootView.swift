import SwiftUI

struct RootView: View {
    var body: some View {
        HonouredWebView(url: AppConfig.webAppURL)
            .ignoresSafeArea()
    }
}
