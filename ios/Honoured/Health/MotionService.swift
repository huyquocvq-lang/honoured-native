import CoreMotion
import Foundation

/// The iPhone's own pedometer as a source for steps and walking distance
/// (Phase 3 M2, docs/phase3/core-motion-plan.vi.md). It counts only what the
/// iPhone itself carried, and it cannot wake the app: Core Motion has no
/// background trigger, so these reads happen whenever iOS already runs
/// Honoured (opening it, a HealthKit delivery, a background refresh).
enum MotionService {
    static func availability() -> MotionAvailability {
        MotionAvailability(
            stepCounting: CMPedometer.isStepCountingAvailable(),
            distance: CMPedometer.isDistanceAvailable(),
            authorization: authorization()
        )
    }

    static func authorization() -> MotionAuthorization {
        switch CMPedometer.authorizationStatus() {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorized: return .authorized
        @unknown default: return .denied
        }
    }

    /// Shows the Motion & Fitness prompt if the person has never been asked.
    /// Core Motion has no request call of its own; its first query asks, and
    /// answers once the person has decided. Call it only while the app is on
    /// screen, from something the person did.
    static func requestAuthorization() async -> MotionAuthorization {
        guard CMPedometer.isStepCountingAvailable(), authorization() == .notDetermined else {
            return authorization()
        }
        let now = Date()
        _ = await query(from: now.addingTimeInterval(-60), to: now)
        return authorization()
    }

    // MARK: - Reads

    struct Reading: Sendable {
        let steps: Double
        /// Nil when Core Motion reported no distance.
        let distanceMeters: Double?
        /// Time spent moving, from the average active pace; nil without one.
        let activeSeconds: Double?
    }

    enum ReadResult: Sendable {
        case value(Reading)
        case noData
        case failed(domain: String, code: Int)
    }

    /// The same contract as `HealthKitService.readTotal`: "could not read"
    /// stays apart from a number. A range Core Motion no longer fully holds,
    /// or one that has not started, reads as no data and is never a short
    /// total. A zero is a real zero only if the pedometer counted something
    /// earlier in its history; otherwise the iPhone has no history for the
    /// range (new, restored, or not counting) and it reads as no data, so it
    /// never overwrites another source's total with a zero.
    static func readTotal(for metric: HealthMetric, from: Date, to: Date, now: Date = Date()) async -> HealthTotalRead {
        guard metric == .steps || metric == .distanceWalkingRunning else { return .noData }
        let end = min(to, now)
        guard end > from, MotionHistory.canRead(from: from, now: now) else { return .noData }
        switch await query(from: from, to: end) {
        case .value(let reading):
            let value = metric == .steps ? reading.steps : reading.distanceMeters
            guard let value else { return .noData }
            if value <= 0, reading.steps <= 0 {
                guard case .value(let history) = await query(from: MotionHistory.earliestReadable(now: now), to: end) else {
                    return .failed
                }
                if MotionHistory.zeroMeansNoHistory(stepsSinceHistoryStart: history.steps) { return .noData }
            }
            return .value(value)
        case .noData:
            return .noData
        case .failed:
            return .failed
        }
    }

    /// The walking and running energy estimate over a range Core Motion still
    /// holds; nil without a distance.
    static func estimatedEnergy(from: Date, to: Date, now: Date = Date()) async -> MotionEnergyEstimate? {
        let end = min(to, now)
        guard end > from, MotionHistory.canRead(from: from, now: now),
              case .value(let reading) = await query(from: from, to: end),
              let distance = reading.distanceMeters else { return nil }
        return MotionEnergyEstimate(distanceMeters: distance, activeSeconds: reading.activeSeconds)
    }

    static func query(from: Date, to: Date) async -> ReadResult {
        guard CMPedometer.isStepCountingAvailable() else {
            return .failed(domain: CMErrorDomain, code: Int(CMErrorMotionActivityNotAvailable.rawValue))
        }
        // Kept alive by this frame until the handler has answered.
        let pedometer = CMPedometer()
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: from, to: to) { data, error in
                continuation.resume(returning: result(data, error))
            }
        }
    }

    static func result(_ data: CMPedometerData?, _ error: Error?) -> ReadResult {
        if let error {
            let nsError = error as NSError
            return .failed(domain: nsError.domain, code: nsError.code)
        }
        guard let data else { return .noData }
        let distance = data.distance?.doubleValue
        var active: Double?
        if let pace = data.averageActivePace?.doubleValue, let distance {
            active = pace * distance
        }
        return .value(Reading(steps: data.numberOfSteps.doubleValue, distanceMeters: distance, activeSeconds: active))
    }
}
