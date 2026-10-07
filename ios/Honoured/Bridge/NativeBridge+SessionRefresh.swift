import Foundation

/// Session refresh handed over by the page (`docs/phase1/bridge.md`, "Session
/// refresh"). Native refreshes in the background, so the page's stored refresh
/// token may already have been used; refreshing it would revoke the session
/// and sign the person out. The page asks native instead, which refreshes its
/// own, newest copy once and hands Supabase's response back.
///
/// Same trust rules as Google Sign-In: accepted only from the main frame of
/// the configured web app origin, and the reply, which carries tokens, goes
/// only to the page that asked, never to the broadcast queue, the durable
/// event store or a log.
extension NativeBridge {
    static let sessionRefreshMessageTypes: Set<String> = ["REFRESH_AUTH_SESSION"]

    /// Capability advertised in `NATIVE_READY` / `PLATFORM_INFO`.
    func sessionRefreshCapability() -> [String: Any] {
        ["protocolVersion": 1, "supported": trustedWebOrigin != nil]
    }

    @MainActor
    func handleSessionRefresh(type: String, payload: [String: Any], requestId: String?) {
        guard type == "REFRESH_AUTH_SESSION" else { return }
        let generation = googleAuth.documentGeneration
        let reply: (String, [String: Any]) -> Void = { [weak self] replyType, body in
            DispatchQueue.main.async {
                self?.sendAuthReply(type: replyType, payload: body, requestId: requestId, generation: generation)
            }
        }
        guard let userId = payload["userId"] as? String, !userId.isEmpty else {
            reply("ERROR", ["message": "userId must be a non-empty string", "code": "invalid_refresh_request"])
            return
        }
        // Not behind `authMutations`: a refresh must not wait for a health
        // upload, and the store refuses to save over a session that changed.
        Task {
            switch await AuthSessionStore.shared.refreshForWeb(userId: userId) {
            case .refreshed(let response):
                guard let session = try? JSONSerialization.jsonObject(with: response) as? [String: Any] else {
                    reply("ERROR", ["message": "Supabase returned an invalid auth response", "code": "auth_refresh_failed"])
                    return
                }
                reply("AUTH_SESSION_REFRESHED", ["session": session])
            case .declined(let reason):
                reply("AUTH_REFRESH_DECLINED", ["reason": reason])
            case .failed:
                reply("ERROR", ["message": "The session could not be refreshed right now", "code": "auth_refresh_failed"])
            }
        }
    }
}
