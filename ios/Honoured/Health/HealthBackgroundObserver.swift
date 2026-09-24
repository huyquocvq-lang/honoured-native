import Foundation
import HealthKit

enum HealthBackgroundPendingState {
    private static let key = "healthkit.background-collection-pending"

    static var isPending: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markPending() {
        UserDefaults.standard.set(true, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Makes the HealthKit callback safe to retain across async actor work and
/// guarantees the system-provided completion block is invoked at most once.
final class HealthObserverCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (() -> Void)?

    init(_ callback: @escaping () -> Void) {
        self.callback = callback
    }

    func call() {
        lock.lock()
        let callback = callback
        self.callback = nil
        lock.unlock()
        callback?()
    }
}

/// Owns the long-running observer queries. Registration is synchronous so the
/// queries exist before HealthKit delivers a launch-time background update.
final class HealthBackgroundObserver: @unchecked Sendable {
    static let shared = HealthBackgroundObserver()

    private let store = HKHealthStore()
    private let lock = NSLock()
    private var queries: [HKObserverQuery] = []
    private var enabledMetricNames: Set<String> = []
    private var enablingMetricNames: Set<String> = []
    private var started = false

    private init() {}

    func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true

        queries = HealthMetric.allCases.compactMap { metric in
            guard let sampleType = metric.objectType as? HKSampleType else { return nil }
            return HKObserverQuery(sampleType: sampleType, predicate: nil) {
                _, completionHandler, _ in
                // Persist the signal before crossing into async work. If the process
                // is suspended, launch/foreground recovery will perform the read.
                HealthBackgroundPendingState.markPending()
                let completion = HealthObserverCompletion(completionHandler)
                Task {
                    await HealthBackgroundDeliveryCoordinator.shared.receive(completion)
                }
            }
        }
        for query in queries {
            store.execute(query)
        }
    }

    /// Idempotently enables hourly delivery for every supported sample type.
    /// `.hourly` is a maximum wake frequency, not a scheduling guarantee.
    func enableBackgroundDelivery() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        start()

        for metric in HealthMetric.allCases where shouldEnable(metric) {
            store.enableBackgroundDelivery(for: metric.objectType, frequency: .hourly) {
                [weak self] success, _ in
                self?.finishEnabling(metric, success: success)
            }
        }
    }

    func disableBackgroundDelivery() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        store.disableAllBackgroundDelivery { [weak self] success, _ in
            guard success else { return }
            self?.lock.lock()
            self?.enabledMetricNames.removeAll()
            self?.enablingMetricNames.removeAll()
            self?.lock.unlock()
        }
    }

    private func shouldEnable(_ metric: HealthMetric) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !enabledMetricNames.contains(metric.rawValue),
              !enablingMetricNames.contains(metric.rawValue) else { return false }
        enablingMetricNames.insert(metric.rawValue)
        return true
    }

    private func finishEnabling(_ metric: HealthMetric, success: Bool) {
        lock.lock()
        enablingMetricNames.remove(metric.rawValue)
        if success {
            enabledMetricNames.insert(metric.rawValue)
        }
        lock.unlock()
    }
}

/// Coalesces the callbacks from all metric observers. A callback that arrives
/// during an anchored-read pass forces another pass, so no signal is dropped just
/// because the first pass had already read that metric.
actor HealthBackgroundDeliveryCoordinator {
    static let shared = HealthBackgroundDeliveryCoordinator()

    private var completions: [HealthObserverCompletion] = []
    private var isProcessing = false
    private var needsAnotherPass = false

    func receive(_ completion: HealthObserverCompletion) {
        completions.append(completion)
        needsAnotherPass = true
        startWorkerIfNeeded()
    }

    func retryPendingCollection() {
        guard HealthBackgroundPendingState.isPending else { return }
        needsAnotherPass = true
        startWorkerIfNeeded()
    }

    private func startWorkerIfNeeded() {
        guard !isProcessing else { return }
        isProcessing = true
        Task { await processPendingDeliveries() }
    }

    private func processPendingDeliveries() async {
        var outcome: HealthCollectionOutcome = .failed
        repeat {
            needsAnotherPass = false
            outcome = await HealthSyncCoordinator.shared.collectAndEnqueue()
        } while needsAnotherPass

        let pendingCompletions = completions
        completions.removeAll()
        isProcessing = false

        // Acknowledge HealthKit after local processing. Upload retries are never
        // allowed to hold these completion handlers.
        for completion in pendingCompletions {
            completion.call()
        }

        if outcome.completedLocalProcessing {
            await HealthSyncCoordinator.shared.drainOnce()
        }
    }
}
