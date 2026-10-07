import Foundation
import Security

/// Builds up to 1.0.6 (3) kept the email and password of "Save password" in a
/// device-only Keychain item. The person's Passwords (iCloud Keychain) replaced
/// it (`WebCredentialSaver`), so the old item is deleted on launch rather than
/// left behind unused.
enum LegacySavedLogin {
    static func remove() {
        let service = (Bundle.main.bundleIdentifier ?? "com.honoured.app") + ".saved-login"
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "email-password",
        ] as CFDictionary)
    }
}
