import CryptoKit
import Foundation

/// Signature images for Icon cards, shared with the widget extension through
/// the App Group container (V1.2 M2-08). A push-started card carries only the
/// contract id; the widget finds the person's signature here.
///
/// The group comes from `HonouredAppGroup` in Info.plist. Until both targets
/// carry the matching App Group entitlement there is no container: storing is
/// a no-op and cards render without a signature.
enum IconSignatureCache {
    /// Large enough for a cropped signature PNG, small enough for the widget's
    /// memory budget.
    static let maxBytes = 64 * 1024

    static var groupIdentifier: String? {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "HonouredAppGroup") as? String,
              identifier.hasPrefix("group."), identifier.count > "group.".count,
              !identifier.contains("$(") else { return nil }
        return identifier
    }

    /// Contract ids are opaque web strings; hashing keeps the file name short
    /// and free of path characters.
    static func fileName(for contractId: String) -> String {
        SHA256.hash(data: Data(contractId.utf8)).map { String(format: "%02x", $0) }.joined() + ".png"
    }

    static func fileURL(for contractId: String) -> URL? {
        guard let group = groupIdentifier,
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return root.appendingPathComponent("IconSignatures", isDirectory: true)
            .appendingPathComponent(fileName(for: contractId))
    }

    /// False when there is no shared container or the image is too large.
    @discardableResult
    static func store(_ png: Data, for contractId: String) throws -> Bool {
        guard !png.isEmpty, png.count <= maxBytes, let url = fileURL(for: contractId) else { return false }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try png.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return true
    }

    static func load(for contractId: String) -> Data? {
        guard let url = fileURL(for: contractId) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Drops the signatures of Icons that are no longer active.
    static func retainOnly(contractIds: Set<String>) {
        guard let directory = fileURL(for: "")?.deletingLastPathComponent(),
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let keep = Set(contractIds.map(fileName(for:)))
        for file in files where !keep.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    /// Signing out or switching account must not leave a signature behind.
    static func removeAll() {
        guard let group = groupIdentifier,
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return }
        try? FileManager.default.removeItem(at: root.appendingPathComponent("IconSignatures", isDirectory: true))
    }
}
