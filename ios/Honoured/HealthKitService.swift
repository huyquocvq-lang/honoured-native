import Foundation
import HealthKit

struct HealthSample {
    let metric: HealthMetric
    let uuid: UUID
    /// In the metric's canonical unit (see `HealthMetric.unitName`).
    let value: Double
    let startDate: Date
    let endDate: Date
    let sourceName: String
}

struct HealthReadResult {
    let metric: HealthMetric
    let added: [HealthSample]
    let deletedUUIDs: [UUID]
    /// Pass to `commitAnchor` only once `added` and `deletedUUIDs` have been
    /// uploaded or durably queued. Committing earlier loses samples on failure.
    let newAnchor: HKQueryAnchor?
}

actor HealthKitService {
    static let shared = HealthKitService()

    /// How far back the very first sync reaches. Every later read is incremental
    /// from the stored anchor, so this bounds the one-time cost of a fresh install.
    static let initialHistoryDays = 30

    private let store = HKHealthStore()
    private let defaults = UserDefaults.standard
    private let syncFloorKey = "healthkit.sync.floor"

    nonisolated var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    // MARK: - Permission

    /// Shows the system permission sheet for any of the given metrics the user has
    /// not decided on yet. Returns immediately when there is nothing left to ask.
    func requestAuthorization(for metrics: [HealthMetric]) async throws {
        try await store.requestAuthorization(toShare: [], read: Set(metrics.map(\.objectType)))
    }

    /// Read permission is deliberately unknowable on iOS: once the user has
    /// decided, a declined type looks identical to one with no data. The only
    /// signal available is whether the sheet still needs to be shown.
    func permissionStatusPayload(for metrics: [HealthMetric]) async -> [String: Any] {
        guard isAvailable else {
            return ["available": false, "perMetric": [String: String]()]
        }

        var perMetric: [String: String] = [:]
        for metric in metrics {
            let status = try? await store.statusForAuthorizationRequest(toShare: [], read: [metric.objectType])
            switch status {
            case .shouldRequest?: perMetric[metric.rawValue] = "notDetermined"
            case .unnecessary?: perMetric[metric.rawValue] = "determined"
            default: perMetric[metric.rawValue] = "unknown"
            }
        }
        return ["available": true, "perMetric": perMetric]
    }

    // MARK: - Totals over a range

    /// Source-deduplicated total (or average, for heart rate) over the range, the
    /// way the Health app reports it. Raw samples from an iPhone and a Watch
    /// overlap, so summing them by hand would double count.
    func total(for metric: HealthMetric, from: Date, to: Date) async -> Double? {
        guard let unit = metric.quantityUnit, let type = metric.objectType as? HKQuantityType else {
            return await sleepMinutes(from: from, to: to)
        }

        let range = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        let options: HKStatisticsOptions = metric.aggregation == .average ? .discreteAverage : .cumulativeSum
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: range),
            options: options
        )
        guard let statistics = try? await descriptor.result(for: store) else { return nil }
        let quantity = metric.aggregation == .average ? statistics.averageQuantity() : statistics.sumQuantity()
        return quantity?.doubleValue(for: unit)
    }

    /// Minutes asleep for sleep segments ending in the range. Overlapping segments
    /// are merged so multiple sources and sleep-stage records cannot double count a
    /// minute. A night is credited to the day it ended on when the range is a day.
    private func sleepMinutes(from: Date, to: Date) async -> Double? {
        let range = HKQuery.predicateForSamples(withStart: from, end: to)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: range)],
            sortDescriptors: []
        )
        guard let samples = try? await descriptor.result(for: store) else { return nil }

        let intervals = samples
            .filter { Self.isAsleep($0) && $0.endDate > from && $0.endDate <= to }
            .map { ($0.startDate, $0.endDate) }
            .sorted { $0.0 < $1.0 }
        guard var current = intervals.first else { return nil }

        var seconds: TimeInterval = 0
        for interval in intervals.dropFirst() {
            if interval.0 <= current.1 {
                current.1 = max(current.1, interval.1)
            } else {
                seconds += current.1.timeIntervalSince(current.0)
                current = interval
            }
        }
        seconds += current.1.timeIntervalSince(current.0)
        return seconds / 60
    }

    private static func isAsleep(_ sample: HKCategorySample) -> Bool {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return false }
        return HKCategoryValueSleepAnalysis.allAsleepValues.contains(value)
    }

    // MARK: - Incremental reads

    /// Returns only samples added or deleted since the last committed anchor.
    func readNewSamples(for metric: HealthMetric) async throws -> HealthReadResult {
        let anchor = storedAnchor(for: metric)
        let sinceFloor = HKQuery.predicateForSamples(withStart: syncFloor(), end: nil)

        guard let unit = metric.quantityUnit, let type = metric.objectType as? HKQuantityType else {
            return try await readNewSleepSamples(anchor: anchor, predicate: sinceFloor)
        }

        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: sinceFloor)],
            anchor: anchor
        )
        let result = try await descriptor.result(for: store)
        let added = result.addedSamples.map { sample in
            HealthSample(
                metric: metric,
                uuid: sample.uuid,
                value: sample.quantity.doubleValue(for: unit),
                startDate: sample.startDate,
                endDate: sample.endDate,
                sourceName: sample.sourceRevision.source.name
            )
        }
        return HealthReadResult(
            metric: metric,
            added: added,
            deletedUUIDs: result.deletedObjects.map(\.uuid),
            newAnchor: result.newAnchor
        )
    }

    private func readNewSleepSamples(anchor: HKQueryAnchor?, predicate: NSPredicate) async throws -> HealthReadResult {
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            anchor: anchor
        )
        let result = try await descriptor.result(for: store)
        // In-bed and awake segments never reach the server, so a later deletion
        // of one of them is a harmless no-op upstream.
        let added = result.addedSamples.filter(Self.isAsleep).map { sample in
            HealthSample(
                metric: .sleep,
                uuid: sample.uuid,
                value: sample.endDate.timeIntervalSince(sample.startDate) / 60,
                startDate: sample.startDate,
                endDate: sample.endDate,
                sourceName: sample.sourceRevision.source.name
            )
        }
        return HealthReadResult(
            metric: .sleep,
            added: added,
            deletedUUIDs: result.deletedObjects.map(\.uuid),
            newAnchor: result.newAnchor
        )
    }

    // MARK: - Anchors

    func commitAnchor(_ anchor: HKQueryAnchor?, for metric: HealthMetric) {
        guard let anchor,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) else { return }
        defaults.set(data, forKey: anchorKey(for: metric))
    }

    /// Forgets every anchor and the history floor. Used when the signed-in user
    /// changes, so the next user's sync starts from a clean read.
    func resetSyncState() {
        for metric in HealthMetric.allCases {
            defaults.removeObject(forKey: anchorKey(for: metric))
        }
        defaults.removeObject(forKey: syncFloorKey)
    }

    private func storedAnchor(for metric: HealthMetric) -> HKQueryAnchor? {
        guard let data = defaults.data(forKey: anchorKey(for: metric)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func anchorKey(for metric: HealthMetric) -> String {
        "healthkit.anchor.\(metric.rawValue)"
    }

    /// Fixed on first use so every anchored query runs with the same predicate.
    private func syncFloor() -> Date {
        if let floor = defaults.object(forKey: syncFloorKey) as? Date { return floor }
        let floor = Calendar.current.date(byAdding: .day, value: -Self.initialHistoryDays, to: Date()) ?? Date()
        defaults.set(floor, forKey: syncFloorKey)
        return floor
    }
}
