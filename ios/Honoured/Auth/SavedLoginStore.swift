import Foundation
import Security

/// One saved sign-in per device, kept only because the person ticked "Save
/// password". A device-only Keychain item readable while the phone is
/// unlocked: never synced, backed up to another device, logged or queued.
/// Signing out keeps it; `CLEAR_SAVED_LOGIN` removes it.
actor SavedLoginStore {
    static let shared = SavedLoginStore()

    private let service = (Bundle.main.bundleIdentifier ?? "com.honoured.app") + ".saved-login"
    private let account = "email-password"

    func save(_ login: SavedLogin) throws {
        let data = try JSONEncoder().encode(login)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func load() -> SavedLogin? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SavedLogin.self, from: data)
    }

    func clear() throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }

    private enum KeychainError: LocalizedError {
        case status(OSStatus)

        var errorDescription: String? {
            switch self {
            case .status(let status): return "Could not update the saved login (Keychain status \(status))"
            }
        }
    }
}
