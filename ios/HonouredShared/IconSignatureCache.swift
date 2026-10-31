import CryptoKit
import Foundation

/// Signature images for Icon cards, shared with the widget extension through
/// the App Group container (V1.2 M2-08). A push-started card carries only the
/// contract id and its Icon day; the widget finds the person's signature here.
///
/// An Icon whose target was revised (Phase 4 M2) has one signature per
/// revision: the signing is revision 0, and each revision holds from its
/// effective day on. Beside the images the cache keeps each Icon's revisions
/// (`<stem>.revisions.json`), so the widget picks the signature of the card's
/// own day. A revision's image is named after its signature's path on the
/// server, so another signature is never taken for it.
///
/// The group comes from `HonouredAppGroup` in Info.plist. Until both targets
/// carry the matching App Group entitlement there is no container: storing is
/// a no-op and cards render without a signature.
enum IconSignatureCache {
    /// Large enough for a cropped signature PNG, small enough for the widget's
    /// memory budget.
    static let maxBytes = 64 * 1024

    /// A revision, the first Icon day it holds for (`yyyy-MM-dd`) and where
    /// its signature is on the server. Lists written by 1.0.9 (2) have no
    /// path: their revisions show no signature until the next sync.
    struct Revision: Codable, Equatable {
        var revision: Int
        var effectiveDay: String
        var signaturePath: String?
    }

    /// Tests point the cache at a folder of their own; the app and the widget
    /// never set it.
    static var directoryOverride: URL?

    static var groupIdentifier: String? {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "HonouredAppGroup") as? String,
              identifier.hasPrefix("group."), identifier.count > "group.".count,
              !identifier.contains("$(") else { return nil }
        return identifier
    }

    /// Contract ids are opaque web strings; hashing keeps the file name short
    /// and free of path characters. The signing keeps the name earlier builds
    /// gave the only signature, so their cache stays valid.
    static func fileName(for contractId: String) -> String {
        stem(for: contractId) + ".png"
    }

    /// A revision's image: the Icon's stem, then its signature path, hashed.
    static func fileName(for contractId: String, signaturePath: String) -> String {
        stem(for: contractId) + "-" + String(hex(signaturePath).prefix(32)) + ".png"
    }

    /// The revision a card of `iconDay` shows: the latest one in effect by
    /// then, else the signing. Days compare as `yyyy-MM-dd` text.
    static func revision(on iconDay: String, among revisions: [Revision]) -> Int {
        revisions.filter { $0.effectiveDay <= iconDay }.map(\.revision).max() ?? 0
    }

    /// False when there is no shared container or the image is too large.
    @discardableResult
    static func store(_ png: Data, for contractId: String) throws -> Bool {
        try store(png, named: fileName(for: contractId))
    }

    @discardableResult
    static func store(_ png: Data, for contractId: String, signaturePath: String) throws -> Bool {
        try store(png, named: fileName(for: contractId, signaturePath: signaturePath))
    }

    /// The signing's image.
    static func load(for contractId: String) -> Data? {
        load(named: fileName(for: contractId))
    }

    static func load(for contractId: String, signaturePath: String) -> Data? {
        load(named: fileName(for: contractId, signaturePath: signaturePath))
    }

    /// The signature of the card for `iconDay`: that of `targetRevision` when
    /// the card knows it, else of the revision the list puts in force that day.
    /// Nil while that image is not here, or when the list cannot be read: a
    /// card shows no signature rather than another revision's.
    static func load(for contractId: String, iconDay: String, targetRevision: Int? = nil) -> Data? {
        if targetRevision == 0 { return load(for: contractId) }
        guard let revisions = revisions(for: contractId) else { return nil }
        let revision = targetRevision ?? self.revision(on: iconDay, among: revisions)
        if revision == 0 { return load(for: contractId) }
        guard let path = revisions.first(where: { $0.revision == revision })?.signaturePath else { return nil }
        return load(for: contractId, signaturePath: path)
    }

    /// Records an Icon's revisions; an empty list means it was never revised.
    @discardableResult
    static func storeRevisions(_ revisions: [Revision], for contractId: String) throws -> Bool {
        guard let url = revisionsURL(for: contractId) else { return false }
        guard !revisions.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return true
        }
        try write(try JSONEncoder().encode(revisions), to: url)
        return true
    }

    /// An Icon's revisions: empty when it was never revised (or there is no
    /// container), nil when the list is there but cannot be read.
    static func revisions(for contractId: String) -> [Revision]? {
        guard let url = revisionsURL(for: contractId),
              let data = try? Data(contentsOf: url) else { return [] }
        return try? JSONDecoder().decode([Revision].self, from: data)
    }

    /// Drops the images of an Icon's revisions that are not in `revisions`
    /// (left by a rollback, or by 1.0.9 (2)'s naming).
    static func prune(_ contractId: String, keeping revisions: [Revision]) {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let keep = Set([fileName(for: contractId), stem(for: contractId) + ".revisions.json"]
                       + revisions.compactMap { $0.signaturePath.map { fileName(for: contractId, signaturePath: $0) } })
        for file in files where file.hasPrefix(stem(for: contractId)) && !keep.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    /// Drops the signatures and revisions of Icons that are no longer active.
    static func retainOnly(contractIds: Set<String>) {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let keep = Set(contractIds.map(stem(for:)))
        for file in files where !keep.contains(String(file.prefix(64))) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    /// Signing out or switching account must not leave a signature behind.
    static func removeAll() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    private static var directory: URL? {
        if let directoryOverride { return directoryOverride }
        guard let group = groupIdentifier,
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return root.appendingPathComponent("IconSignatures", isDirectory: true)
    }

    private static func revisionsURL(for contractId: String) -> URL? {
        directory?.appendingPathComponent(stem(for: contractId) + ".revisions.json")
    }

    private static func store(_ png: Data, named name: String) throws -> Bool {
        guard !png.isEmpty, png.count <= maxBytes, let url = directory?.appendingPathComponent(name) else { return false }
        try write(png, to: url)
        return true
    }

    private static func load(named name: String) -> Data? {
        guard let url = directory?.appendingPathComponent(name) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// 64 hex characters, the start of every file of one Icon.
    private static func stem(for contractId: String) -> String {
        hex(contractId)
    }

    private static func hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
