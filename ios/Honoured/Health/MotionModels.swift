import Foundation

/// The Motion & Fitness permission as the bridge reports it. Unlike HealthKit
/// read access it can be read back: a refusal shows as `denied`.
enum MotionAuthorization: String, Equatable, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized
}

/// What the iPhone's own pedometer (Core Motion) can give right now.
/// Foundation only: the source rules built on it are tested without
/// CoreMotion in the host-less test target.
struct MotionAvailability: Equatable, Sendable {
    /// `CMPedometer.isStepCountingAvailable()`.
    let stepCounting: Bool
    /// `CMPedometer.isDistanceAvailable()`.
    let distance: Bool
    let authorization: MotionAuthorization

    /// Whether Core Motion can stand in for `metric`. Only steps and walking
    /// distance have a Core Motion counterpart, and only with permission.
    func canRead(_ metric: HealthMetric) -> Bool {
        guard authorization == .authorized else { return false }
        switch metric {
        case .steps: return stepCounting
        case .distanceWalkingRunning: return distance
        default: return false
        }
    }

    /// `motion` in `HEALTH_PERMISSION_STATUS` and `HEALTH_SOURCES`, and the
    /// whole `MOTION_PERMISSION_STATUS` payload.
    var payload: [String: Any] {
        ["available": stepCounting, "authorization": authorization.rawValue]
    }
}

/// Core Motion keeps about seven days of pedometer history. A range that
/// starts earlier comes back short without an error, so it is not read at
/// all, and such a day keeps the total another source gave it.
enum MotionHistory {
    static let retention: TimeInterval = 7 * 24 * 60 * 60
    /// Apple documents only "seven days". Stopping six hours early keeps a
    /// day that is being trimmed from overwriting the total it had while it
    /// was whole; that day's last full reading stays.
    static let margin: TimeInterval = 6 * 60 * 60

    static func canRead(from start: Date, now: Date) -> Bool {
        start >= now.addingTimeInterval(-retention + margin)
    }

    /// The earliest moment a read can start, for checking whether the
    /// pedometer has any history at all.
    static func earliestReadable(now: Date) -> Date {
        now.addingTimeInterval(-retention + margin)
    }

    /// A zero is a real zero only while the pedometer has counted something
    /// since its history begins. Zero all the way back means no history for
    /// that time: a new or restored iPhone, or one that was not counting.
    static func zeroMeansNoHistory(stepsSinceHistoryStart: Double) -> Bool {
        stepsSinceHistoryStart <= 0
    }
}

/// A rough walking and running energy estimate from Core Motion's distance
/// and pace. Core Motion has no calorie API, so this is only ever shown as an
/// estimate next to Apple Health's Active Energy and never scores a contract.
/// About 0.5 kcal per kg per km walking and 1.0 running, for an assumed
/// 70 kg: the same figures as the M1 probe's report.
struct MotionEnergyEstimate: Equatable, Sendable {
    enum Gait: String, Sendable {
        case walking, running
    }

    static let assumedWeightKg: Double = 70
    /// Below 0.42 s per metre (about 7 min per km) counts as running.
    static let runningPaceSecondsPerMeter = 0.42

    let kilocalories: Double
    let gait: Gait

    /// - Parameter activeSeconds: time spent moving, from Core Motion's
    ///   average active pace; nil when it reported none.
    init(distanceMeters: Double, activeSeconds: Double?, weightKg: Double = MotionEnergyEstimate.assumedWeightKg) {
        let meters = max(distanceMeters, 0)
        var gait = Gait.walking
        if let activeSeconds, activeSeconds > 0, meters > 0,
           activeSeconds / meters < Self.runningPaceSecondsPerMeter {
            gait = .running
        }
        let perKgKm = gait == .running ? 1.0 : 0.5
        kilocalories = meters / 1_000 * weightKg * perKgKm
        self.gait = gait
    }

    /// `estimates.walking_running_energy` in `HEALTH_METRICS`.
    var payload: [String: Any] {
        [
            "value": kilocalories,
            "unit": "kcal",
            "source": HealthReadingSource.coreMotion.rawValue,
            "method": "distance_pace",
            "gait": gait.rawValue,
            "assumedWeightKg": Self.assumedWeightKg
        ]
    }
}
