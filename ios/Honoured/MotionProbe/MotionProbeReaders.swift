import CoreMotion
import Foundation
import HealthKit

/// What one read returned, keeping "no permission", "locked" and "failed" apart
/// from a number, because whether a locked iPhone can be read at all is the
/// main question of the probe.
enum MotionProbeRead: Sendable {
    case value(steps: Double, distanceMeters: Double?, activeSeconds: Double?)
    case noData
    case failed(domain: String, code: Int)
    case unavailable(String)

    var steps: Double? {
        if case .value(let steps, _, _) = self { return steps }
        return nil
    }

    /// Fields for the log line.
    var logNumbers: [String: Double] {
        guard case .value(let steps, let distance, let active) = self else { return [:] }
        var numbers = ["steps": steps]
        if let distance { numbers["distance_m"] = distance }
        if let active { numbers["active_s"] = active }
        return numbers
    }

    var logNotes: [String: String] {
        switch self {
        case .value: return ["result": "value"]
        case .noData: return ["result": "no_data"]
        case .failed(let domain, let code):
            var notes = ["result": "error", "domain": domain, "code": String(code)]
            notes["meaning"] = Self.meaning(domain: domain, code: code)
            return notes
        case .unavailable(let why): return ["result": "unavailable", "why": why]
        }
    }

    /// Identifies a result for de-duplicating screen polls: the count, or the
    /// kind of failure.
    var signature: String {
        if let steps { return "value:\(steps)" }
        return logNotes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }

    /// The errors the probe expects to meet, named so the log reads without a
    /// code table. Unknown codes stay as domain and code only.
    static func meaning(domain: String, code: Int) -> String? {
        switch (domain, code) {
        case (HKErrorDomain, HKError.Code.errorAuthorizationDenied.rawValue): return "health_denied"
        case (HKErrorDomain, HKError.Code.errorAuthorizationNotDetermined.rawValue): return "health_not_asked"
        case (HKErrorDomain, HKError.Code.errorDatabaseInaccessible.rawValue): return "health_locked"
        case (CMErrorDomain, Int(CMErrorMotionActivityNotAvailable.rawValue)): return "motion_unavailable"
        case (CMErrorDomain, Int(CMErrorMotionActivityNotAuthorized.rawValue)): return "motion_not_authorized"
        case (CMErrorDomain, Int(CMErrorMotionActivityNotEntitled.rawValue)): return "motion_not_entitled"
        default: return nil
        }
    }
}

/// Core Motion pedometer. Each call is independent; the live updates belong to
/// `MotionProbe`.
enum MotionProbePedometer {
    static var authorization: String {
        switch CMPedometer.authorizationStatus() {
        case .notDetermined: return "not_determined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "unknown"
        }
    }

    static var isAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    /// The first call shows the Motion & Fitness prompt.
    static func read(from start: Date, to end: Date) async -> MotionProbeRead {
        guard isAvailable else { return .unavailable("step_counting_unavailable") }
        let pedometer = CMPedometer()
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: start, to: end) { data, error in
                continuation.resume(returning: Self.result(data, error))
            }
        }
    }

    /// Per-window counts for the crossing reconstruction, one query per window,
    /// in order. A window that fails is left out and counted.
    static func intervals(_ windows: [DateInterval]) async -> (intervals: [MotionProbeInterval], failures: Int) {
        guard isAvailable else { return ([], windows.count) }
        let pedometer = CMPedometer()
        var intervals: [MotionProbeInterval] = []
        var failures = 0
        for window in windows {
            let read: MotionProbeRead = await withCheckedContinuation { continuation in
                pedometer.queryPedometerData(from: window.start, to: window.end) { data, error in
                    continuation.resume(returning: Self.result(data, error))
                }
            }
            switch read {
            case .value(let steps, _, _):
                intervals.append(MotionProbeInterval(start: window.start, end: window.end, value: steps))
            case .noData:
                intervals.append(MotionProbeInterval(start: window.start, end: window.end, value: 0))
            case .failed, .unavailable:
                failures += 1
            }
        }
        return (intervals, failures)
    }

    static func result(_ data: CMPedometerData?, _ error: Error?) -> MotionProbeRead {
        if let error {
            let nsError = error as NSError
            return .failed(domain: nsError.domain, code: nsError.code)
        }
        guard let data else { return .noData }
        let active: Double? = {
            guard let pace = data.averageActivePace?.doubleValue, let distance = data.distance?.doubleValue else { return nil }
            return pace * distance
        }()
        return .value(steps: data.numberOfSteps.doubleValue, distanceMeters: data.distance?.doubleValue, activeSeconds: active)
    }
}

/// HealthKit reads made by the probe itself, independent of the person's
/// source preference: the combined total plus each source's share.
enum MotionProbeHealth {
    private static let store = HKHealthStore()

    struct Totals: Sendable {
        let read: MotionProbeRead
        /// Steps per HealthKit source name, as HealthKit attributes them.
        let bySource: [String: Double]
    }

    static func steps(from start: Date, to end: Date) async -> Totals {
        guard HKHealthStore.isHealthDataAvailable() else {
            return Totals(read: .unavailable("health_unavailable"), bySource: [:])
        }
        let type = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: [.cumulativeSum, .separateBySource]
        )
        do {
            guard let statistics = try await descriptor.result(for: store),
                  let sum = statistics.sumQuantity() else {
                return Totals(read: .noData, bySource: [:])
            }
            var bySource: [String: Double] = [:]
            for source in statistics.sources ?? [] {
                if let share = statistics.sumQuantity(for: source) {
                    bySource[source.name, default: 0] += share.doubleValue(for: .count())
                }
            }
            return Totals(read: .value(steps: sum.doubleValue(for: .count()), distanceMeters: nil, activeSeconds: nil), bySource: bySource)
        } catch {
            return Totals(read: Self.failure(error), bySource: [:])
        }
    }

    /// Active Energy in the session, including the share of samples that only
    /// overlap it, as `sessionSteps` does: a strict-start read showed no data
    /// for a two-minute walk. Nil when no sample touches the session.
    static func activeEnergy(from start: Date, to end: Date) async -> Double? {
        let type = HKQuantityType(.activeEnergyBurned)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(minute: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return nil }
        var total: Double?
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            if let sum = statistics.sumQuantity() {
                total = (total ?? 0) + sum.doubleValue(for: .kilocalorie())
            }
        }
        return total
    }

    /// Combined steps since a session started. The iPhone writes steps to
    /// HealthKit in chunks that often begin before the session, and a
    /// strict-start read left them out, so it showed no data for a whole walk.
    /// This sums the per-minute collection instead, which takes the share of
    /// each overlapping sample that falls inside the window.
    static func sessionSteps(from start: Date, to end: Date) async -> Totals {
        guard HKHealthStore.isHealthDataAvailable() else {
            return Totals(read: .unavailable("health_unavailable"), bySource: [:])
        }
        guard let intervals = await stepIntervals(from: start, to: end) else {
            return Totals(read: .failed(domain: HKErrorDomain, code: -1), bySource: [:])
        }
        let steps = intervals.reduce(0) { $0 + $1.value }
        guard steps > 0 else { return Totals(read: .noData, bySource: [:]) }
        return Totals(read: .value(steps: steps, distanceMeters: nil, activeSeconds: nil), bySource: [:])
    }

    /// Combined, source-deduplicated steps per minute from `start` to `end`,
    /// including samples that only overlap the window.
    static func stepIntervals(from start: Date, to end: Date) async -> [MotionProbeInterval]? {
        await stepMinutes(from: start, to: end)?.map {
            MotionProbeInterval(start: $0.start, end: $0.end, value: $0.total)
        }
    }

    struct MinuteSteps: Sendable {
        let start: Date
        let end: Date
        /// The combined total, overlaps between sources removed.
        let total: Double
        /// Each source's own count, as HealthKit attributes it.
        let bySource: [String: Double]
    }

    /// Steps per minute from `start` to `end`, the combined total and each
    /// source's share (an iPhone and a watch in the same walk, say).
    static func stepMinutes(from start: Date, to end: Date) async -> [MinuteSteps]? {
        let type = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: [.cumulativeSum, .separateBySource],
            anchorDate: start,
            intervalComponents: DateComponents(minute: 1)
        )
        guard let collection = try? await descriptor.result(for: store) else { return nil }
        var minutes: [MinuteSteps] = []
        collection.enumerateStatistics(from: start, to: end) { statistics, _ in
            var bySource: [String: Double] = [:]
            for source in statistics.sources ?? [] {
                if let share = statistics.sumQuantity(for: source) {
                    bySource[source.name, default: 0] += share.doubleValue(for: .count())
                }
            }
            minutes.append(MinuteSteps(
                start: statistics.startDate,
                end: statistics.endDate,
                total: statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0,
                bySource: bySource
            ))
        }
        return minutes
    }

    private static func failure(_ error: Error) -> MotionProbeRead {
        let nsError = error as NSError
        if nsError.domain == HKErrorDomain, nsError.code == HKError.Code.errorNoData.rawValue {
            return .noData
        }
        return .failed(domain: nsError.domain, code: nsError.code)
    }
}
