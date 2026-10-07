import Foundation

/// An email and password to keep in the person's Passwords (iCloud Keychain)
/// after they signed in, signed up or changed their password on the web app
/// (`docs/phase1/bridge.md`, "Passwords (iOS)"). Validation only;
/// `WebCredentialSaver` hands it to iOS, which asks the person first.
struct WebCredential: Equatable {
    let email: String
    let password: String

    static let maxEmailLength = 320
    static let maxPasswordLength = 1024

    /// Reads `SAVE_WEB_CREDENTIAL`: a non-empty email, trimmed, and a
    /// non-empty password kept exactly as typed. Anything else is refused,
    /// never coerced.
    static func parse(_ payload: [String: Any]) -> WebCredential? {
        guard let rawEmail = payload["email"] as? String,
              let password = payload["password"] as? String else { return nil }
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, email.count <= maxEmailLength, email.contains("@"),
              !password.isEmpty, password.count <= maxPasswordLength else { return nil }
        return WebCredential(email: email, password: password)
    }

    /// iOS keeps a password only for a domain the app is associated with
    /// (`webcredentials:` entitlement and the site's apple-app-site-association
    /// file), so saving is offered only when the build's associated domain is
    /// the HTTPS host the web app loads from.
    static func isSupported(associatedHost: String, webAppURL: URL?) -> Bool {
        let host = associatedHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !host.isEmpty, !host.contains("$("),
              let webAppURL, webAppURL.scheme?.lowercased() == "https",
              let webHost = webAppURL.host?.lowercased() else { return false }
        return host == webHost
    }
}
