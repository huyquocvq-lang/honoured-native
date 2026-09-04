import SwiftUI
import WebKit

struct HonouredWebView: UIViewRepresentable {
    @ObservedObject var state: WebViewLoadState

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator.bridge, name: "honouredNative")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black

        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        context.coordinator.bridge.webView = webView
        state.attach(webView)
        state.load()
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "honouredNative")
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let bridge = NativeBridge()
        private let state: WebViewLoadState

        init(state: WebViewLoadState) {
            self.state = state
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in state.markLoaded() }
            bridge.send(type: "NATIVE_READY", payload: [
                "platform": "ios",
                "bridgeVersion": AppConfig.bridgeVersion
            ])
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            guard navigationResponse.isForMainFrame,
                  let response = navigationResponse.response as? HTTPURLResponse,
                  response.statusCode >= 400 else {
                decisionHandler(.allow)
                return
            }

            Task { @MainActor in state.markFailed("HTTP \(response.statusCode)") }
            decisionHandler(.cancel)
        }

        /// Ignores the cancellation that WebKit reports when a navigation is
        /// superseded, which is not a user-visible failure.
        private func report(_ error: Error) {
            let nsError = error as NSError
            guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
            Task { @MainActor in state.markFailed(nsError.localizedDescription) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let destination = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if destination.host == AppConfig.webAppURL.host || destination.scheme == "about" {
                decisionHandler(.allow)
                return
            }

            if navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(destination)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
