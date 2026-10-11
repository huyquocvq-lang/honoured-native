import Foundation
import Network

actor OfflineHealthQueue {
    static let shared = OfflineHealthQueue()

    private let fileURL: URL
    private var batches: [PendingHealthBatch]

    init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Honoured", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileURL = root.appendingPathComponent("health-sync-queue.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([PendingHealthBatch].self, from: data) {
            // A batch queued before uploads were split may be too large to
            // ever reach the server; split it now so the queue moves again.
            batches = decoded.flatMap { $0.splitForUpload() }
            if batches.count != decoded.count { try? persist() }
        } else {
            batches = []
        }
    }

    /// Queues the batch in upload-sized parts.
    func append(_ batch: PendingHealthBatch) throws {
        let parts = batch.splitForUpload()
        batches.append(contentsOf: parts)
        do {
            try persist()
        } catch {
            batches.removeLast(parts.count)
            throw error
        }
    }

    func first() -> PendingHealthBatch? { batches.first }

    /// The daily totals still waiting to upload for `userId`, oldest first.
    func queuedDaily(userId: String) -> [HealthDailyPayload] {
        batches.filter { $0.userId == userId }.flatMap(\.daily)
    }

    func removeFirst(id: UUID) throws {
        guard batches.first?.id == id else { return }
        let removed = batches.removeFirst()
        do {
            try persist()
        } catch {
            batches.insert(removed, at: 0)
            throw error
        }
    }

    /// Replaces the first batch with `parts`, in order; an empty list drops it.
    func replaceFirst(id: UUID, with parts: [PendingHealthBatch]) throws {
        guard batches.first?.id == id else { return }
        let removed = batches.removeFirst()
        batches.insert(contentsOf: parts, at: 0)
        do {
            try persist()
        } catch {
            batches.removeFirst(parts.count)
            batches.insert(removed, at: 0)
            throw error
        }
    }

    func recordFailure(id: UUID) throws -> Int {
        guard batches.first?.id == id else { return 0 }
        batches[0].attempts += 1
        do {
            try persist()
        } catch {
            batches[0].attempts -= 1
            throw error
        }
        return batches[0].attempts
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        batches.removeAll()
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(batches)
        try data.write(to: fileURL, options: .atomic)
    }
}

final class HealthNetworkMonitor {
    static let shared = HealthNetworkMonitor()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.honoured.health-network")
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { await HealthSyncCoordinator.shared.syncNow() }
        }
        monitor.start(queue: queue)
    }
}
