import Foundation

/// "Save password" on the sign-in form (`docs/phase1/bridge.md`, "Saved
/// login"). Same trust rules as Google Sign-In: accepted only from the main
/// frame of the configured web app origin, replies go only to the page that
/// asked, and the password never enters the broadcast queue, the durable
/// event store or a log.
extension NativeBridge {
    static let savedLoginMessageTypes: Set<String> = [
        "GET_SAVED_LOGIN", "SAVE_LOGIN", "CLEAR_SAVED_LOGIN"
    ]

    /// Keychain reads and writes run strictly in arrival order, so a
    /// `CLEAR_SAVED_LOGIN` sent after a `SAVE_LOGIN` always wins and a read
    /// sees every write sent before it.
    static let savedLoginOperations = SerialAsyncQueue()

    /// Capability advertised in `NATIVE_READY` / `PLATFORM_INFO`.
    func savedLoginCapability() -> [String: Any] {
        ["protocolVersion": 1, "supported": trustedWebOrigin != nil]
    }

    @MainActor
    func handleSavedLogin(type: String, payload: [String: Any], requestId: String?) {
        let generation = googleAuth.documentGeneration
        let reply: (String, [String: Any]) -> Void = { [weak self] replyType, body in
            DispatchQueue.main.async {
                self?.sendAuthReply(type: replyType, payload: body, requestId: requestId, generation: generation)
            }
        }
        let store = SavedLoginStore.shared
        switch type {
        case "GET_SAVED_LOGIN":
            Self.savedLoginOperations.enqueue {
                reply("SAVED_LOGIN", SavedLogin.replyPayload(await store.load()))
            }
        case "SAVE_LOGIN":
            guard let login = SavedLogin.parse(payload) else {
                reply("ERROR", [
                    "message": "email and password must be non-empty strings",
                    "code": "invalid_saved_login"
                ])
                return
            }
            Self.savedLoginOperations.enqueue {
                do {
                    try await store.save(login)
                    reply("LOGIN_SAVED", [:])
                } catch {
                    reply("ERROR", ["message": error.localizedDescription, "code": "saved_login_store_failed"])
                }
            }
        case "CLEAR_SAVED_LOGIN":
            Self.savedLoginOperations.enqueue {
                do {
                    try await store.clear()
                    reply("SAVED_LOGIN_CLEARED", [:])
                } catch {
                    reply("ERROR", ["message": error.localizedDescription, "code": "saved_login_clear_failed"])
                }
            }
        default:
            break
        }
    }
}
