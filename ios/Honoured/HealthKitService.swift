import Foundation
import HealthKit

@MainActor
final class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

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
}
