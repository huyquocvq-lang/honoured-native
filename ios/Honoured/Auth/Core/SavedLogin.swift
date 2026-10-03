import Foundation

/// The email and password the person chose to keep on this device with "Save
/// password" on the sign-in form (`docs/phase1/bridge.md`, "Saved login").
/// Validation only; `SavedLoginStore` keeps it in the Keychain.
struct SavedLogin: Codable, Equatable {
    let email: String
    let password: String

    static let maxEmailLength = 320
    static let maxPasswordLength = 1024

    /// Reads `SAVE_LOGIN`: a non-empty email, trimmed, and a non-empty password
    /// kept exactly as typed. Anything else is refused, never coerced.
    static func parse(_ payload: [String: Any]) -> SavedLogin? {
        guard let rawEmail = payload["email"] as? String,
              let password = payload["password"] as? String else { return nil }
        let email = rawEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, email.count <= maxEmailLength, email.contains("@"),
              !password.isEmpty, password.count <= maxPasswordLength else { return nil }
        return SavedLogin(email: email, password: password)
    }

    /// `SAVED_LOGIN` body for a stored login, or for none.
    static func replyPayload(_ login: SavedLogin?) -> [String: Any] {
        guard let login else { return ["found": false] }
        return ["found": true, "email": login.email, "password": login.password]
    }
}
