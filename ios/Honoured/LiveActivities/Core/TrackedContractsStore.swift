import Foundation

/// Where the tracked-contract records live. The engine owns the in-memory copy
/// and writes through this after every change.
protocol TrackedContractsPersistence: AnyObject {
    /// Nil when nothing has been stored yet. Throws `.unavailable` when a file
    /// exists but cannot be read, which before the first unlock is expected:
    /// the caller must retry later rather than start from an empty store that
    /// would then overwrite the real one.
    func load() throws -> TrackedContractsFile?
    func save(_ file: TrackedContractsFile) throws
}

enum TrackedContractsPersistenceError: Error {
    case unavailable
}

/// `Application Support/Honoured/live-activities.json`, protected until first
/// unlock like the other native stores. Holds contract IDs, display names and
/// the last Health reading per slot — never tokens.
final class FileTrackedContractsPersistence: TrackedContractsPersistence {
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    static var defaultURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Honoured", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("live-activities.json")
    }

    func load() throws -> TrackedContractsFile? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TrackedContractsPersistenceError.unavailable
        }
        // An unknown schema or a damaged file starts clean. Cards it described
        // become orphans, and restore ends those.
        guard let file = try? JSONDecoder().decode(TrackedContractsFile.self, from: data),
              file.schemaVersion == TrackedContractsFile.currentSchemaVersion else {
            return TrackedContractsFile()
        }
        return file
    }

    func save(_ file: TrackedContractsFile) throws {
        let data = try JSONEncoder().encode(file)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// Test double; also handy to simulate a store that cannot be read yet.
final class InMemoryTrackedContractsPersistence: TrackedContractsPersistence {
    var stored: TrackedContractsFile?
    var isAvailable = true
    private(set) var saveCount = 0

    init(_ stored: TrackedContractsFile? = nil) {
        self.stored = stored
    }

    func load() throws -> TrackedContractsFile? {
        guard isAvailable else { throw TrackedContractsPersistenceError.unavailable }
        return stored
    }

    func save(_ file: TrackedContractsFile) throws {
        guard isAvailable else { throw TrackedContractsPersistenceError.unavailable }
        stored = file
        saveCount += 1
    }
}
