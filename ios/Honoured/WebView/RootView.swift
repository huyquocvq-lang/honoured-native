import SwiftUI

struct RootView: View {
    @StateObject private var state = WebViewLoadState(url: AppConfig.webAppURL)

    private static let foreground = Color(red: 0.929, green: 0.906, blue: 0.867)
    private static let muted = Color(white: 0.54)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // The web view keeps full opacity for its whole life. An opacity
            // modifier would force it into an offscreen compositing pass, which
            // costs a blend on every scrolled frame; an opaque cover on top of
            // it hides the unpainted page just as well.
            HonouredWebView(state: state)
                .ignoresSafeArea()

            switch state.phase {
            case .loading:
                Color.black.ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Self.foreground)
                    .scaleEffect(1.4)
            case .failed(let detail):
                errorView(detail)
            case .loaded:
                EmptyView()
            }
        }
    }

    private func errorView(_ detail: String) -> some View {
        VStack(spacing: 12) {
            Text("Can’t reach Honoured")
                .font(.title3)
                .foregroundStyle(Self.foreground)

            Text("Check your connection and try again.")
                .font(.subheadline)
                .foregroundStyle(Self.muted)

            Text(detail)
                .font(.footnote)
                .foregroundStyle(Self.muted)
                .multilineTextAlignment(.center)

            Button("Try again") { state.retry() }
                .buttonStyle(.bordered)
                .tint(Self.foreground)
                .padding(.top, 16)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
