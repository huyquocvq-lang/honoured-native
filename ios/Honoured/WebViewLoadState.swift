import Foundation
import WebKit

/// Tracks whether the hosted web app has rendered, so the shell can show a
/// loading indicator and a retry-able error instead of a bare black screen.
@MainActor
final class WebViewLoadState: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// `WKWebView` ignores `URLRequest.timeoutInterval`, and a connection to a
    /// host that accepts but never answers produces no delegate callback at
    /// all. Without this watchdog the shell spins indefinitely.
    private static let loadTimeout: Duration = .seconds(30)

    @Published private(set) var phase: Phase = .loading

    let url: URL
    private weak var webView: WKWebView?
    private var timeoutTask: Task<Void, Never>?

    init(url: URL) {
        self.url = url
    }

    var request: URLRequest {
        URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    /// Starts a navigation. Safe to call from `makeUIView`: the phase is only
    /// published when it actually changes, so it never mutates state during a
    /// SwiftUI view update.
    func load() {
        if phase != .loading {
            phase = .loading
        }
        webView?.load(request)
        startTimeout()
    }

    func retry() {
        load()
    }

    func markLoaded() {
        timeoutTask?.cancel()
        timeoutTask = nil
        phase = .loaded
    }

    func markFailed(_ message: String) {
        timeoutTask?.cancel()
        timeoutTask = nil
        phase = .failed(message)
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.loadTimeout)
            guard !Task.isCancelled, let self, self.phase == .loading else { return }
            self.webView?.stopLoading()
            self.markFailed("The connection timed out.")
        }
    }
}
