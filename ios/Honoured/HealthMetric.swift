import Foundation
import HealthKit

/// Canonical metric identifiers. The raw values are the strings used in bridge
/// payloads and in the `metric` column of `health_samples` / `health_daily`,
/// so renaming a case is a contract change on both sides.
enum HealthMetric: String, CaseIterable {
    case steps
    case distanceWalkingRunning = "distance_walking_running"
    case distanceCycling = "distance_cycling"
    case distanceSwimming = "distance_swimming"
    case activeEnergy = "active_energy"
    case basalEnergy = "basal_energy"
    case heartRate = "heart_rate"
    case exerciseMinutes = "exercise_minutes"
    case sleep

    enum Aggregation {
        case sum
        case average
    }

    var objectType: HKObjectType {
        switch self {
        case .steps: return HKQuantityType(.stepCount)
        case .distanceWalkingRunning: return HKQuantityType(.distanceWalkingRunning)
        case .distanceCycling: return HKQuantityType(.distanceCycling)
        case .distanceSwimming: return HKQuantityType(.distanceSwimming)
        case .activeEnergy: return HKQuantityType(.activeEnergyBurned)
        case .basalEnergy: return HKQuantityType(.basalEnergyBurned)
        case .heartRate: return HKQuantityType(.heartRate)
        case .exerciseMinutes: return HKQuantityType(.appleExerciseTime)
        case .sleep: return HKCategoryType(.sleepAnalysis)
        }
    }

    /// Nil for sleep, which is a category type whose "minutes" come from sample
    /// duration rather than a quantity.
    var quantityUnit: HKUnit? {
        switch self {
        case .steps: return .count()
        case .distanceWalkingRunning, .distanceCycling, .distanceSwimming: return .meter()
        case .activeEnergy, .basalEnergy: return .kilocalorie()
        case .heartRate: return HKUnit.count().unitDivided(by: .minute())
        case .exerciseMinutes: return .minute()
        case .sleep: return nil
        }
    }

    var unitName: String {
        switch self {
        case .steps: return "count"
        case .distanceWalkingRunning, .distanceCycling, .distanceSwimming: return "meters"
        case .activeEnergy, .basalEnergy: return "kcal"
        case .heartRate: return "bpm"
        case .exerciseMinutes, .sleep: return "minutes"
        }
    }

    var aggregation: Aggregation {
        self == .heartRate ? .average : .sum
    }

    /// Parses a bridge `metrics` array. A missing array means every metric.
    static func parse(_ raw: Any?) -> (metrics: [HealthMetric], unknown: [String]) {
        guard let names = raw as? [String] else { return (allCases, []) }
        var metrics: [HealthMetric] = []
        var unknown: [String] = []
        for name in names {
            if let metric = HealthMetric(rawValue: name) {
                metrics.append(metric)
            } else {
                unknown.append(name)
            }
        }
        return (metrics, unknown)
    }
}
