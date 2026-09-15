import Foundation

/// A broadcast that must reach the web app even if the process is relaunched
/// before a WebView exists: a notification tapped on cold start, a goal reached
/// or a timer completed while the app was not running.
struct NativeStoredEvent: Codable {
    let id: UUID
    let type: String
    /// JSON object bytes. Kept opaque so the store never has to know payload shapes.
    let payload: Data
    let createdAt: Date

    func payloadObject() -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: payload) as? [String: Any]) ?? [:]
    }
}

/// Durable, bounded, oldest-first event queue in Application Support. The
/// in-memory queue inside `NativeBridge` only survives a WebView reload; this
/// one survives a relaunch and a background launch that never creates a scene.
/// Never store tokens or other secrets here — the file is not in the Keychain.
actor NativeEventStore {
    static let shared = NativeEventStore()

    static let changed = Notification.Name("HonouredNativeEventStoreChanged")

    private let limit = 50
    private let fileURL: URL
    private var events: [NativeStoredEvent]

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Honoured", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileURL = root.appendingPathComponent("native-events.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([NativeStoredEvent].self, from: data) {
            events = decoded
        } else {
            events = []
        }
    }

    var isEmpty: Bool { events.isEmpty }

    /// Persists first, then tells any live bridge to drain. Drops the oldest
    /// entries past `limit` so a web app that never becomes ready cannot grow it.
    /// `createdAt` is stamped by the caller so two events posted back to back
    /// keep their order even if their appends are scheduled out of order.
    func append(type: String, payload: [String: Any], createdAt: Date) throws {
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw StoreError.invalidPayload
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        var next = events
        next.append(NativeStoredEvent(id: UUID(), type: type, payload: data, createdAt: createdAt))
        next.sort { $0.createdAt < $1.createdAt }
        if next.count > limit {
            next.removeFirst(next.count - limit)
        }
        try persist(next)
        events = next
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.changed, object: nil)
        }
    }

    /// Returns and removes everything, oldest first. If the emptied file cannot
    /// be written the events are still handed out — delivering twice after a
    /// relaunch is preferable to never delivering a tapped notification.
    func drain() -> [NativeStoredEvent] {
        let drained = events
        guard !drained.isEmpty else { return [] }
        events = []
        try? persist([])
        return drained
    }

    func clear() throws {
        events = []
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    private func persist(_ events: [NativeStoredEvent]) throws {
        let data = try JSONEncoder().encode(events)
        try data.write(to: fileURL, options: .atomic)
    }

    enum StoreError: Error {
        case invalidPayload
    }
}
