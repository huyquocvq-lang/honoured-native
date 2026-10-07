import Foundation

/// Passwords (`docs/phase1/bridge.md`, "Passwords (iOS)"): after a successful
/// sign-in, sign-up or password change the page asks native to offer saving
/// the email and password in the person's Passwords (iCloud Keychain), which a
/// web view never offers on its own. Same trust rules as Google Sign-In:
/// accepted only from the main frame of the configured web app origin, replies
/// go only to the page that asked, and the password never enters the broadcast
/// queue, the durable event store or a log.
extension NativeBridge {
    static let webCredentialMessageTypes: Set<String> = ["SAVE_WEB_CREDENTIAL"]

    /// One prompt at a time, in arrival order.
    static let webCredentialOperations = SerialAsyncQueue()

    /// Capability advertised in `NATIVE_READY` / `PLATFORM_INFO`.
    func webCredentialsCapability() -> [String: Any] {
        let supported = trustedWebOrigin != nil
            && WebCredential.isSupported(associatedHost: AppConfig.webCredentialsHost, webAppURL: AppConfig.webAppURL)
        return ["protocolVersion": 1, "supported": supported]
    }

    @MainActor
    func handleWebCredentials(type: String, payload: [String: Any], requestId: String?) {
        guard type == "SAVE_WEB_CREDENTIAL" else { return }
        let generation = googleAuth.documentGeneration
        let reply: (String, [String: Any]) -> Void = { [weak self] replyType, body in
            DispatchQueue.main.async {
                self?.sendAuthReply(type: replyType, payload: body, requestId: requestId, generation: generation)
            }
        }
        guard webCredentialsCapability()["supported"] as? Bool == true,
              let host = AppConfig.webAppURL.host else {
            reply("ERROR", ["message": "Saving passwords is not available in this build", "code": "web_credentials_unavailable"])
            return
        }
        guard let credential = WebCredential.parse(payload) else {
            reply("ERROR", [
                "message": "email and password must be non-empty strings",
                "code": "invalid_web_credential"
            ])
            return
        }
        let window = webView?.window
        Self.webCredentialOperations.enqueue {
            do {
                try await WebCredentialSaver.save(credential, host: host, anchor: window)
                reply("WEB_CREDENTIAL_SAVED", [:])
            } catch {
                // Declining the prompt lands here too; nothing about the
                // credential is put in the message.
                reply("ERROR", ["message": "The password was not saved", "code": "web_credential_not_saved"])
            }
        }
    }
}
