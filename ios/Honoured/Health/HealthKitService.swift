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
    private let sourcePreferenceModeKey = "healthkit.source.preference.mode"
    private let sourcePreferenceIdKey = "healthkit.source.preference.id"
    private let dailyBasisKey = "healthkit.daily.basis"

    /// The metrics the source preference applies to; every other metric reads
    /// the combined total.
    static let sourceSelectableMetrics: Set<HealthMetric> = [
        .steps, .distanceWalkingRunning
    ]

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
    /// signal available is whether the sheet still needs to be shown. The
    /// Motion & Fitness permission, which can be read back, rides along as
    /// `motion`.
    func permissionStatusPayload(for metrics: [HealthMetric]) async -> [String: Any] {
        let motion = MotionService.availability().payload
        guard isAvailable else {
            return ["available": false, "perMetric": [String: String](), "motion": motion]
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
        return ["available": true, "perMetric": perMetric, "motion": motion]
    }

    // MARK: - Data source preference

    func setSourcePreference(_ preference: HealthSourcePreference) {
        let payload = preference.payload
        defaults.set(payload["mode"], forKey: sourcePreferenceModeKey)
        if let id = payload["sourceId"] {
            defaults.set(id, forKey: sourcePreferenceIdKey)
        } else {
            defaults.removeObject(forKey: sourcePreferenceIdKey)
        }
    }

    /// The HealthKit sources, with Core Motion first on an iPhone that counts
    /// steps. `effectiveSource*` and `fallback` say what is read now, which
    /// for Core Motion depends on its permission (`motion`).
    func sourceSettingsPayload() async -> [String: Any] {
        let preference = sourcePreference()
        let motion = MotionService.availability()
        guard isAvailable else {
            return ["available": false, "sources": [], "preference": preference.payload, "motion": motion.payload]
        }
        let healthKitSources = await availableSources(for: Array(Self.sourceSelectableMetrics))
        let resolution = HealthSourceSelector.resolve(
            preference: preference,
            available: healthKitSources,
            motionReadable: motion.canRead(.steps)
        )
        let sources = (motion.stepCounting ? [HealthSourceDescriptor.coreMotion] : []) + healthKitSources
        return [
            "available": true,
            "sources": sources.map(Self.sourcePayload),
            "preference": preference.payload,
            "effectiveSourceId": resolution.selected.map { $0.id as Any } ?? NSNull(),
            "effectiveSourceName": resolution.selected.map { $0.name as Any } ?? NSNull(),
            "fallback": resolution.requestedSourceMissing,
            "appliesTo": Self.sourceSelectableMetrics.map(\.rawValue).sorted(),
            "motion": motion.payload
        ]
    }

    /// The person chose Core Motion, whether or not it can be read.
    func prefersCoreMotion() -> Bool {
        sourcePreference() == .coreMotion
    }

    /// Core Motion is chosen and readable, so steps come from the iPhone's
    /// pedometer rather than HealthKit.
    func readsCoreMotion() -> Bool {
        prefersCoreMotion() && MotionService.availability().canRead(.steps)
    }

    /// Where `metric`'s totals come from right now: the same answer as the
    /// source resolution `readTotal` uses, without querying HealthKit.
    func readingSource(for metric: HealthMetric) -> HealthReadingSource {
        guard Self.sourceSelectableMetrics.contains(metric), prefersCoreMotion(),
              MotionService.availability().canRead(metric) else { return .healthKit }
        return .coreMotion
    }

    /// Core Motion's walking and running energy estimate over the range, only
    /// while Core Motion is the source being read. Calorie goals keep using
    /// Active Energy.
    func motionEnergyEstimate(from: Date, to: Date) async -> MotionEnergyEstimate? {
        guard readsCoreMotion() else { return nil }
        return await MotionService.estimatedEnergy(from: from, to: to)
    }

    func sourceMetadata(for metric: HealthMetric) async -> [String: Any] {
        guard Self.sourceSelectableMetrics.contains(metric) else {
            return [
                "mode": "aggregate",
                "effectiveSourceId": NSNull(),
                "effectiveSourceName": "Apple Health",
                "fallback": false
            ]
        }
        let resolution = await sourceResolution(for: metric)
        guard let selected = resolution.selected else {
            return [
                "mode": "aggregate",
                "effectiveSourceId": NSNull(),
                "effectiveSourceName": "Apple Health",
                "fallback": resolution.requestedSourceMissing
            ]
        }
        return [
            "mode": "source",
            "effectiveSourceId": selected.id,
            "effectiveSourceName": selected.name,
            "kind": selected.kind.rawValue,
            "fallback": resolution.requestedSourceMissing
        ]
    }

    // MARK: - Totals over a range

    /// Source-deduplicated total (or average, for heart rate) over the range, the
    /// way the Health app reports it. Raw samples from an iPhone and a Watch
    /// overlap, so summing them by hand would double count. Nil when there is
    /// no data or the read failed; `readTotal` tells those apart.
    func total(for metric: HealthMetric, from: Date, to: Date) async -> Double? {
        await readTotal(for: metric, from: from, to: to).numericValue
    }

    /// Same numbers as `total`, keeping "nothing recorded" apart from "could not
    /// read" (a locked device before the data is decrypted, a failed query), so
    /// a Live Activity can keep its last reading instead of showing zero. A
    /// declined read permission looks exactly like no data, as iOS intends.
    ///
    /// Every reader of steps and walking distance comes through here — goals,
    /// Live Activities, Icon readings, `QUERY_HEALTH_METRICS` and
    /// `health_daily` — so with Core Motion chosen they all read the
    /// pedometer, never the pedometer plus HealthKit.
    func readTotal(for metric: HealthMetric, from: Date, to: Date) async -> HealthTotalRead {
        await readTotalAndSource(for: metric, from: from, to: to).read
    }

    /// `readTotal` and the source it read, from one source resolution, so a
    /// reading is never labelled with a source chosen a moment later.
    func readTotalAndSource(for metric: HealthMetric, from: Date, to: Date) async -> (read: HealthTotalRead, source: HealthReadingSource) {
        #if DEBUG
        if let fake = BridgeStub.fakeHealthRead(for: metric) { return (fake, readingSource(for: metric)) }
        #endif
        guard let unit = metric.quantityUnit, let type = metric.objectType as? HKQuantityType else {
            return (await sleepMinutes(from: from, to: to), .healthKit)
        }

        let resolution = await sourceResolution(for: metric)
        if resolution.readingSource == .coreMotion {
            return (await MotionService.readTotal(for: metric, from: from, to: to), .coreMotion)
        }
        return (await healthKitTotal(metric: metric, unit: unit, type: type, resolution: resolution, from: from, to: to), .healthKit)
    }

    private func healthKitTotal(
        metric: HealthMetric, unit: HKUnit, type: HKQuantityType, resolution: HealthSourceResolution, from: Date, to: Date
    ) async -> HealthTotalRead {
        let range = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        let predicate: NSPredicate
        if let selected = resolution.selected,
           let source = await healthKitSource(for: selected, metric: metric) {
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                range, HKQuery.predicateForObjects(from: source)
            ])
        } else {
            predicate = range
        }
        let options: HKStatisticsOptions = metric.aggregation == .average ? .discreteAverage : .cumulativeSum
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: options
        )
        do {
            guard let statistics = try await descriptor.result(for: store) else { return .noData }
            let quantity = metric.aggregation == .average ? statistics.averageQuantity() : statistics.sumQuantity()
            guard let quantity else { return .noData }
            return .value(quantity.doubleValue(for: unit))
        } catch {
            return Self.readFailure(error)
        }
    }

    private static func readFailure(_ error: Error) -> HealthTotalRead {
        let nsError = error as NSError
        guard nsError.domain == HKErrorDomain else { return .failed }
        switch HKError.Code(rawValue: nsError.code) {
        case .errorNoData?, .errorAuthorizationDenied?, .errorAuthorizationNotDetermined?:
            return .noData
        case .errorDatabaseInaccessible?:
            return .protectedDataUnavailable
        default:
            return .failed
        }
    }

    /// Minutes asleep for sleep segments ending in the range. Overlapping segments
    /// are merged so multiple sources and sleep-stage records cannot double count a
    /// minute. A night is credited to the day it ended on when the range is a day.
    private func sleepMinutes(from: Date, to: Date) async -> HealthTotalRead {
        let range = HKQuery.predicateForSamples(withStart: from, end: to)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: range)],
            sortDescriptors: []
        )
        let samples: [HKCategorySample]
        do {
            samples = try await descriptor.result(for: store)
        } catch {
            return Self.readFailure(error)
        }

        let intervals = samples
            .filter { Self.isAsleep($0) && $0.endDate > from && $0.endDate <= to }
            .map { ($0.startDate, $0.endDate) }
            .sorted { $0.0 < $1.0 }
        guard var current = intervals.first else { return .noData }

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
        return .value(seconds / 60)
    }

    private static func isAsleep(_ sample: HKCategorySample) -> Bool {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return false }
        return HKCategoryValueSleepAnalysis.allAsleepValues.contains(value)
    }

    private func sourcePreference() -> HealthSourcePreference {
        HealthSourcePreference.parse(
            mode: defaults.string(forKey: sourcePreferenceModeKey),
            sourceId: defaults.string(forKey: sourcePreferenceIdKey)
        ) ?? .automatic
    }

    private func sourceResolution(for metric: HealthMetric) async -> HealthSourceResolution {
        let preference = sourcePreference()
        // Automatic never narrows a read, so it needs no source query.
        guard Self.sourceSelectableMetrics.contains(metric), preference != .automatic else {
            return HealthSourceResolution(selected: nil, requestedSourceMissing: false)
        }
        if preference == .coreMotion {
            return HealthSourceSelector.resolve(
                preference: preference,
                available: [],
                motionReadable: MotionService.availability().canRead(metric)
            )
        }
        return HealthSourceSelector.resolve(
            preference: preference,
            available: await availableSources(for: [metric])
        )
    }

    private func availableSources(for metrics: [HealthMetric]) async -> [HealthSourceDescriptor] {
        var byId: [String: HealthSourceDescriptor] = [:]
        for metric in metrics {
            for source in await sources(for: metric.objectType) {
                let descriptor = HealthSourceDescriptor.make(
                    name: source.name,
                    bundleIdentifier: source.bundleIdentifier
                )
                byId[descriptor.id] = descriptor
            }
        }
        return Array(byId.values).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func healthKitSource(for descriptor: HealthSourceDescriptor, metric: HealthMetric) async -> HKSource? {
        await sources(for: metric.objectType).first {
            HealthSourceDescriptor.make(name: $0.name, bundleIdentifier: $0.bundleIdentifier).id == descriptor.id
        }
    }

    private func sources(for type: HKObjectType) async -> [HKSource] {
        guard let sampleType = type as? HKSampleType else { return [] }
        return await withCheckedContinuation { continuation in
            let query = HKSourceQuery(sampleType: sampleType, samplePredicate: nil) { _, sources, _ in
                continuation.resume(returning: Array(sources ?? []))
            }
            store.execute(query)
        }
    }

    private static func sourcePayload(_ source: HealthSourceDescriptor) -> [String: String] {
        [
            "id": source.id,
            "name": source.name,
            "bundleIdentifier": source.bundleIdentifier,
            "kind": source.kind.rawValue
        ]
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

    /// Forgets every anchor, the history floor and the daily basis. Used when
    /// the signed-in user changes, so the next user's sync starts from a clean
    /// read.
    func resetSyncState() {
        for metric in HealthMetric.allCases {
            defaults.removeObject(forKey: anchorKey(for: metric))
        }
        defaults.removeObject(forKey: syncFloorKey)
        defaults.removeObject(forKey: dailyBasisKey)
    }

    // MARK: - Daily totals basis

    /// How totals of `sourceSelectableMetrics` are read now. `health_daily`
    /// rows written under another basis are stale: another source choice, or
    /// a build whose `automatic` read one device instead of the combined
    /// total (such a build never stored a basis). Core Motion counts as its
    /// own basis only while it can be read.
    func dailyBasis() -> String {
        sourcePreference().dailyBasis(motionReadable: MotionService.availability().canRead(.steps))
    }

    /// The basis of the totals already queued for upload; nil before the first.
    func committedDailyBasis() -> String? {
        defaults.string(forKey: dailyBasisKey)
    }

    func commitDailyBasis(_ basis: String) {
        defaults.set(basis, forKey: dailyBasisKey)
    }

    /// The oldest moment the uploaded history covers.
    func historyStart() -> Date {
        syncFloor()
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
