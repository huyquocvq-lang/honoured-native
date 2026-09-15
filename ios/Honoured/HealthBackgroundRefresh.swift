import BackgroundTasks
import Foundation

/// `BGAppRefreshTask` fallback for the times HealthKit background delivery does
/// not wake the app. Delivery is best-effort and iOS may stop it after missed
/// completions or a reboot; a scheduled refresh keeps the offline queue moving
/// through the same collect-then-drain pipeline the observer path uses.
final class HealthBackgroundRefresh: @unchecked Sendable {
    static let shared = HealthBackgroundRefresh()

    /// Must match the entry in `BGTaskSchedulerPermittedIdentifiers`, which is
    /// `$(PRODUCT_BUNDLE_IDENTIFIER).healthsync` in `Info.plist`.
    let taskIdentifier: String = {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.honoured.app"
        return "\(bundleID).healthsync"
    }()

    /// Lower bound only. iOS decides when, if ever, the refresh actually runs.
    private let minimumInterval: TimeInterval = 60 * 60

    private let lock = NSLock()
    private var registered = false

    private init() {}

    /// Registers the launch handler. This must run before
    /// `application(_:didFinishLaunchingWithOptions:)` returns or iOS will not
    /// deliver the task to the process.
    func register() {
        lock.lock()
        defer { lock.unlock() }
        guard !registered else { return }
        registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self, let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            self.handle(refreshTask)
        }
    }

    /// Requests a refresh no sooner than `minimumInterval` from now. Submitting
    /// again with the same identifier replaces the pending request, so callers
    /// do not need to dedupe.
    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        // Failures here are platform or configuration limits (not permitted,
        // unavailable on this device); there is nothing to recover at runtime.
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Keeps a pending request only while native has a user to sync for.
    func scheduleIfSessionExists() {
        Task {
            if await AuthSessionStore.shared.load() != nil {
                schedule()
            } else {
                cancel()
            }
        }
    }

    func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    private func handle(_ task: BGAppRefreshTask) {
        // Schedule the next run before doing any work so the chain survives an
        // expired or failed pass.
        schedule()

        let completion = BackgroundTaskCompletion(task)
        let work = Task { [weak self] in
            let outcome = await HealthSyncCoordinator.shared.collectAndEnqueue()
            if outcome.completedLocalProcessing, !Task.isCancelled {
                await HealthSyncCoordinator.shared.drainOnce()
            }
            if case .deferred(let reason) = outcome, reason != .protectedDataUnavailable {
                // No session or no HealthKit on this device: nothing to refresh
                // until the bridge hands over a session again.
                self?.cancel()
            }
            completion.finish(success: outcome.completedLocalProcessing)
        }
        task.expirationHandler = {
            work.cancel()
            completion.finish(success: false)
        }
    }
}

/// Guarantees `setTaskCompleted` is called exactly once even when expiration
/// and normal completion race. Calling it twice is a programmer error in
/// BackgroundTasks; never calling it gets the app throttled.
private final class BackgroundTaskCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var task: BGTask?

    init(_ task: BGTask) {
        self.task = task
    }

    func finish(success: Bool) {
        lock.lock()
        let task = task
        self.task = nil
        lock.unlock()
        task?.setTaskCompleted(success: success)
    }
}
