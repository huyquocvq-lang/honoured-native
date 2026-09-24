import Foundation
import Security

struct NativeAuthSession: Codable {
    let userId: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: TimeInterval
}

actor AuthSessionStore {
    static let shared = AuthSessionStore()

    private let service = (Bundle.main.bundleIdentifier ?? "com.honoured.app") + ".supabase-auth"
    private let account = "current-session"

    func save(_ session: NativeAuthSession) throws {
        let data = try JSONEncoder().encode(session)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    func load() -> NativeAuthSession? {
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
        return try? JSONDecoder().decode(NativeAuthSession.self, from: data)
    }

    /// Who native is signed in as, telling "no session" apart from "cannot read
    /// the Keychain yet" (before the first unlock), which `load()` does not.
    /// Live Activity restore must not treat a locked Keychain as a sign-out.
    func accountState() -> NativeAccountState {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data,
                  let session = try? JSONDecoder().decode(NativeAuthSession.self, from: data) else { return .signedOut }
            return .signedIn(session.userId)
        case errSecItemNotFound:
            return .signedOut
        default:
            return .unavailable
        }
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

    func refreshedSessionIfNeeded(force: Bool = false) async throws -> NativeAuthSession? {
        guard let current = load() else { return nil }
        guard force || current.expiresAt <= Date().timeIntervalSince1970 + 60 else { return current }
        guard let baseURL = AppConfig.supabaseURL, !AppConfig.supabaseAnonKey.isEmpty else {
            throw SessionRefreshError.notConfigured
        }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("auth/v1/token"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        guard let url = components?.url else { throw SessionRefreshError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(RefreshRequest(refreshToken: current.refreshToken))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SessionRefreshError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 400 || http.statusCode == 401 { throw SessionRefreshError.invalidSession }
            throw SessionRefreshError.http(http.statusCode)
        }

        let refreshed = try JSONDecoder().decode(RefreshResponse.self, from: data)
        guard refreshed.user.id == current.userId else {
            throw SessionRefreshError.invalidSession
        }
        let expiresAt = refreshed.expiresAt ?? Date().timeIntervalSince1970 + refreshed.expiresIn
        guard expiresAt.isFinite, expiresAt > 0 else {
            throw SessionRefreshError.invalidResponse
        }
        let session = NativeAuthSession(
            userId: refreshed.user.id,
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            expiresAt: expiresAt
        )
        // The network call suspended this actor: the web app may have signed
        // out, switched account or saved a newer session meanwhile. Only the
        // session this refresh started from may be replaced.
        guard let stored = load(), stored.userId == current.userId, stored.refreshToken == current.refreshToken else {
            throw SessionRefreshError.superseded
        }
        try save(session)
        return session
    }

    private struct RefreshRequest: Codable {
        let refreshToken: String
        enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
    }

    private struct RefreshResponse: Codable {
        struct User: Codable { let id: String }
        let accessToken: String
        let refreshToken: String
        let expiresIn: TimeInterval
        let expiresAt: TimeInterval?
        let user: User

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case expiresAt = "expires_at"
            case user
        }
    }

    enum SessionRefreshError: LocalizedError {
        case notConfigured, invalidResponse, invalidSession, superseded, http(Int)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Supabase native sync is not configured"
            case .invalidResponse: return "Supabase returned an invalid auth response"
            case .invalidSession: return "The Supabase session is no longer valid"
            case .superseded: return "The Supabase session changed while it was being refreshed"
            case .http(let code): return "Supabase auth refresh failed with HTTP \(code)"
            }
        }
    }

    private enum KeychainError: LocalizedError {
        case status(OSStatus)

        var errorDescription: String? {
            switch self {
            case .status(let status): return "Could not update the secure session (Keychain status \(status))"
            }
        }
    }
}
