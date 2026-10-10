import Foundation
import Security

struct StoredWordSource: Codable, Equatable {
    let sourceId: String
    let userId: String
    let contractId: String
    let kind: WordSourceKind
    let bookmark: Data
}

/// Device-only security-scoped bookmarks. The service name deliberately says
/// nothing about the selected file, and neither file names nor paths are kept.
enum WordSourceBookmarkStore {
    private static let service = "com.honoured.word-source.v1"

    /// Stores the one source of this user's contract, replacing any earlier
    /// one. `sourceId` is kept when reconnecting a signed Icon's source, whose
    /// id the server has locked; otherwise a new random id is made.
    static func save(
        url: URL, userId: String, contractId: String, kind: WordSourceKind, sourceId: String? = nil
    ) throws -> StoredWordSource {
        let source = StoredWordSource(
            sourceId: sourceId ?? UUID().uuidString.lowercased(), userId: userId,
            contractId: contractId, kind: kind, bookmark: try bookmark(for: url)
        )
        try put(source)
        return source
    }

    /// Re-creates a stale bookmark (the file moved or was renamed) from the
    /// URL it still resolves to. Call while that URL's access is open. A
    /// source replaced or removed while it was being read is left alone.
    static func refresh(_ source: StoredWordSource, url: URL) throws {
        guard try load(userId: source.userId, contractId: source.contractId) == source else { return }
        try put(StoredWordSource(
            sourceId: source.sourceId, userId: source.userId,
            contractId: source.contractId, kind: source.kind, bookmark: try bookmark(for: url)
        ))
    }

    private static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            // iOS document-picker URLs already carry a security-scoped grant.
            // The macOS-only withSecurityScope bookmark option is unavailable.
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func load(userId: String, contractId: String) throws -> StoredWordSource? {
        guard let data = copy(account: account(userId: userId, contractId: contractId)) else { return nil }
        let source = try JSONDecoder().decode(StoredWordSource.self, from: data)
        guard source.userId == userId, source.contractId == contractId else {
            throw WordSourceError.permissionDenied
        }
        return source
    }

    /// A stale bookmark still resolves to the file's new location; the caller
    /// refreshes it with `refresh(_:url:)` once it has access.
    static func resolve(_ source: StoredWordSource) throws -> (url: URL, isStale: Bool) {
        var stale = false
        do {
            let url = try URL(
                resolvingBookmarkData: source.bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            return (url, stale)
        } catch {
            throw WordSourceError.missing
        }
    }

    static func remove(userId: String, contractId: String) {
        SecItemDelete(query(account: account(userId: userId, contractId: contractId)) as CFDictionary)
    }

    static func removeAll(for userId: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        guard let raw = copyMatching(query) as? [[String: Any]] else { return }
        for item in raw where (item[kSecAttrAccount as String] as? String)?.hasPrefix(userId + "|") == true {
            if let account = item[kSecAttrAccount as String] as? String {
                SecItemDelete(self.query(account: account) as CFDictionary)
            }
        }
    }

    private static func put(_ source: StoredWordSource) throws {
        let data = try JSONEncoder().encode(source)
        let account = account(userId: source.userId, contractId: source.contractId)
        SecItemDelete(query(account: account) as CFDictionary)
        var item = query(account: account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw WordSourceError.permissionDenied
        }
    }

    private static func copy(account: String) -> Data? {
        var item = query(account: account)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        return copyMatching(item) as? Data
    }

    private static func copyMatching(_ query: [String: Any]) -> CFTypeRef? {
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result
    }

    private static func account(userId: String, contractId: String) -> String { userId + "|" + contractId }
    private static func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }
}
