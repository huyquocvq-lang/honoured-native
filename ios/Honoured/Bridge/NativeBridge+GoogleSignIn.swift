import Foundation
import WebKit

/// The single system sign-in lock shared by Apple and Google.
@MainActor
enum SignInPresentation {
    static let gate = ProviderPresentationGate()
}

/// Google Sign-In over the bridge (`docs/bridge.md`, "Google Sign-In"). The
/// messages are accepted only from the main frame of the configured web app
/// origin, and every reply goes only to the same page that asked. Credentials
/// never enter the broadcast queue, the durable event store or a log.
extension NativeBridge {
    static let googleMessageTypes: Set<String> = [
        "SYNC_AUTH_CONTEXT", "SIGN_IN_WITH_GOOGLE", "CANCEL_GOOGLE_SIGN_IN", "CLEAR_GOOGLE_SIGN_IN"
    ]

    /// How long the web app may wait for Google's UI before the attempt is
    /// abandoned. A sheet still on screen keeps the presentation lock.
    static let googleSignInTimeout: TimeInterval = 120

    /// Capability advertised in `NATIVE_READY` / `PLATFORM_INFO`.
    @MainActor
    func googleSignInCapability() -> [String: Any] {
        [
            "protocolVersion": 1,
            "supported": trustedWebOrigin != nil,
            "configured": GoogleSignInCoordinator.shared.isConfigured,
            "transport": "trusted-auth-v1",
            "intents": ["sign_in", "link"]
        ]
    }

    /// Main frame, exact configured origin, and the page currently loaded in
    /// this bridge's WebView. Anything else is dropped without a reply.
    func isTrustedAuthMessage(_ message: WKScriptMessage) -> Bool {
        guard let origin = trustedWebOrigin, message.frameInfo.isMainFrame,
              let webView, message.webView === webView else { return false }
        let securityOrigin = message.frameInfo.securityOrigin
        guard origin.matches(scheme: securityOrigin.protocol, host: securityOrigin.host, port: securityOrigin.port) else {
            return false
        }
        return origin.matches(url: webView.url)
    }

    @MainActor
    func handleGoogle(type: String, payload: [String: Any], requestId: String?) {
        let generation = googleAuth.documentGeneration
        let reply: (String, [String: Any]) -> Void = { [weak self] replyType, body in
            self?.sendAuthReply(type: replyType, payload: body, requestId: requestId, generation: generation)
        }
        switch type {
        case "SYNC_AUTH_CONTEXT":
            let rawUser = payload["userId"]
            guard rawUser is NSNull || rawUser is String else {
                reply("ERROR", ["message": "userId must be a string or null", "code": "invalid_payload"])
                return
            }
            let context = googleAuth.sync(userId: rawUser as? String)
            reply("AUTH_CONTEXT_SYNCED", [
                "authContextId": context.id,
                "userId": context.userId ?? NSNull()
            ])
        case "SIGN_IN_WITH_GOOGLE":
            startGoogleSignIn(payload: payload, requestId: requestId, reply: reply)
        case "CANCEL_GOOGLE_SIGN_IN":
            let target = payload["targetRequestId"] as? String
            if let cancelled = googleAuth.cancel(contextId: payload["authContextId"] as? String, targetRequestId: target) {
                cancelGoogleTimeout(cancelled.requestId)
                sendAuthReply(
                    type: "GOOGLE_SIGN_IN_FAILED",
                    payload: failurePayload(.cancelled, contextId: cancelled.contextId),
                    requestId: cancelled.requestId,
                    generation: cancelled.documentGeneration
                )
                reply("GOOGLE_SIGN_IN_CANCEL_ACCEPTED", ["targetRequestId": target ?? NSNull(), "cancelled": true])
            } else {
                reply("GOOGLE_SIGN_IN_CANCEL_ACCEPTED", ["targetRequestId": target ?? NSNull(), "cancelled": false])
            }
        case "CLEAR_GOOGLE_SIGN_IN":
            if let attempt = googleAuth.attempt { cancelGoogleTimeout(attempt.requestId) }
            // Invalidation first, synchronously; the SDK cleanup follows.
            let context = googleAuth.clear()
            GoogleSignInCoordinator.shared.signOut()
            // A presentation still on screen would repopulate the SDK cache
            // when it ends; clear it again then.
            if SignInPresentation.gate.holder == .google { signOutGoogleAfterPresentation = true }
            reply("GOOGLE_SIGN_IN_CLEARED", ["authContextId": context.id, "providerCleared": true])
        default:
            break
        }
    }

    @MainActor
    private func startGoogleSignIn(
        payload: [String: Any],
        requestId: String?,
        reply: @escaping (String, [String: Any]) -> Void
    ) {
        let contextId = payload["authContextId"] as? String
        let coordinator = GoogleSignInCoordinator.shared
        guard trustedWebOrigin != nil else {
            reply("GOOGLE_SIGN_IN_FAILED", failurePayload(.unsupported, contextId: contextId))
            return
        }
        guard coordinator.isConfigured else {
            reply("GOOGLE_SIGN_IN_FAILED", failurePayload(.notConfigured, contextId: contextId))
            return
        }
        let nonce = AuthNonce.make()
        let attempt: GoogleAuthAttempt
        switch googleAuth.begin(
            requestId: requestId,
            intent: payload["intent"] as? String,
            contextId: contextId,
            rawNonce: nonce.raw
        ) {
        case .success(let started):
            attempt = started
        case .failure(let failure):
            reply("GOOGLE_SIGN_IN_FAILED", failurePayload(failure, contextId: contextId))
            return
        }
        guard let token = SignInPresentation.gate.acquire(.google) else {
            _ = googleAuth.finish(attempt)
            reply("GOOGLE_SIGN_IN_FAILED", failurePayload(.inProgress, contextId: contextId))
            return
        }

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.googleAuth.finish(attempt) != nil else { return }
            self.googleTimeouts[attempt.requestId] = nil
            self.sendAuthReply(
                type: "GOOGLE_SIGN_IN_FAILED",
                payload: self.failurePayload(.timeout, contextId: attempt.contextId),
                requestId: attempt.requestId,
                generation: attempt.documentGeneration
            )
        }
        googleTimeouts[attempt.requestId] = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.googleSignInTimeout, execute: timeout)

        Task { @MainActor [weak self] in
            let outcome = await coordinator.present(hashedNonce: nonce.hashed)
            SignInPresentation.gate.release(token)
            guard let self else { return }
            if self.signOutGoogleAfterPresentation {
                self.signOutGoogleAfterPresentation = false
                coordinator.signOut()
            }
            self.cancelGoogleTimeout(attempt.requestId)
            // Reloaded, re-owned, cancelled or timed out meanwhile: drop it.
            guard let current = self.googleAuth.finish(attempt) else { return }
            switch outcome {
            case .success(let idToken, let accessToken):
                var body: [String: Any] = [
                    "intent": current.intent.rawValue,
                    "authContextId": current.contextId,
                    "idToken": idToken,
                    "rawNonce": current.rawNonce
                ]
                if let accessToken { body["accessToken"] = accessToken }
                self.sendAuthReply(type: "GOOGLE_SIGN_IN_SUCCESS", payload: body, requestId: current.requestId, generation: current.documentGeneration)
            case .failure(let failure):
                self.sendAuthReply(
                    type: "GOOGLE_SIGN_IN_FAILED",
                    payload: self.failurePayload(failure, contextId: current.contextId),
                    requestId: current.requestId,
                    generation: current.documentGeneration
                )
            }
        }
    }

    private func failurePayload(_ failure: GoogleAuthFailure, contextId: String?) -> [String: Any] {
        ["code": failure.code, "message": failure.message, "authContextId": contextId ?? NSNull()]
    }

    private func cancelGoogleTimeout(_ requestId: String) {
        googleTimeouts.removeValue(forKey: requestId)?.cancel()
    }

    /// Direct reply to the page that asked. Dropped when that page is gone or
    /// the WebView no longer shows the trusted origin. Never queued.
    func sendAuthReply(type: String, payload: [String: Any], requestId: String?, generation: Int) {
        guard generation == googleAuth.documentGeneration,
              let origin = trustedWebOrigin,
              origin.matches(url: webView?.url) else { return }
        var body = payload
        if let requestId { body["requestId"] = requestId }
        dispatchNow(type: type, payload: body, generation: generation)
    }
}
