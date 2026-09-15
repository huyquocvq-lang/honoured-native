import Foundation
import UIKit

struct ActiveTimer: Codable, Equatable {
    let activityId: String
    let activityName: String
    let startedAt: Date
    let endsAt: Date

    var notificationIdentifier: String { "timer-\(activityId)" }
}

/// One Testament Timer at a time. The countdown is persisted so it survives a
/// WebView reload or an app relaunch, and a local notification carries it
/// through backgrounding. Three things can observe the deadline — the in-process
/// sleep, the notification delegate and the foreground reconcile — and all of
/// them funnel through `complete(_:notified:)`, which removes the stored timer
/// inside the actor so `TIMER_COMPLETED` is emitted exactly once.
actor TestamentTimer {
    static let shared = TestamentTimer()

    enum CancelResult {
        case cancelled
        case nothingRunning
        case differentTimerRunning(ActiveTimer)
    }

    private let defaults = UserDefaults.standard
    private let key = "timer.active"
    private var deadline: Task<Void, Never>?

    private init() {}

    func current() -> ActiveTimer? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ActiveTimer.self, from: data)
    }

    // MARK: - Bridge entry points

    /// Replaces any running timer. The previous one is returned so the bridge
    /// can announce its cancellation before `TIMER_STARTED`.
    func start(activityId: String, activityName: String, durationSeconds: Double) async -> (timer: ActiveTimer, replaced: ActiveTimer?) {
        let previous = current()
        if let previous {
            NotificationCoordinator.shared.cancel(identifiers: [previous.notificationIdentifier])
        }

        let now = Date()
        let timer = ActiveTimer(
            activityId: activityId,
            activityName: activityName,
            startedAt: now,
            endsAt: now.addingTimeInterval(durationSeconds)
        )
        store(timer)
        await scheduleNotification(for: timer)
        armDeadline(for: timer)
        return (timer, previous)
    }

    func cancel(activityId: String) -> CancelResult {
        guard let running = current() else { return .nothingRunning }
        guard running.activityId == activityId else { return .differentTimerRunning(running) }
        discard(running)
        return .cancelled
    }

    /// Run on launch, on becoming active, before answering `GET_TIMER_STATE` and
    /// after a timer notification is tapped. A timer whose deadline passed while
    /// the app was not running completes here; `notified` reflects whether the
    /// system could have shown its notification in the meantime.
    func reconcile() async {
        guard let timer = current() else { return }
        if timer.endsAt <= Date() {
            // Without permission no banner was ever shown, so the web app still
            // owes the user an in-app completion.
            let notified = await NotificationCoordinator.shared.isAuthorized()
            complete(timer, notified: notified)
        } else {
            armDeadline(for: timer)
        }
    }

    /// Re-adds the notification request after permission was just granted, in
    /// case the one added while undetermined is never delivered.
    func rescheduleNotificationIfRunning(activityId: String) async {
        guard let timer = current(), timer.activityId == activityId, timer.endsAt > Date() else { return }
        await scheduleNotification(for: timer)
    }

    /// Account switch or sign-out: the timer belonged to the previous user.
    func clear() {
        if let running = current() {
            discard(running)
        }
    }

    // MARK: - Notification delegate hooks

    /// The timer notification fired while the app was in the foreground. It is
    /// not shown; the web app celebrates in-app instead.
    func notificationPresentedInForeground(activityId: String) {
        guard let timer = current(), timer.activityId == activityId,
              timer.endsAt <= Date().addingTimeInterval(1) else { return }
        complete(timer, notified: false)
    }

    // MARK: - Completion

    private func armDeadline(for timer: ActiveTimer) {
        deadline?.cancel()
        deadline = Task {
            let interval = timer.endsAt.timeIntervalSinceNow
            if interval > 0 {
                try? await Task.sleep(for: .seconds(interval))
            }
            guard !Task.isCancelled else { return }
            await self.deadlineReached(timer)
        }
    }

    private func deadlineReached(_ timer: ActiveTimer) async {
        // A sleep that wakes late because the process was suspended must not
        // claim the user saw an in-app completion. Leave it to the notification
        // and to the next reconcile.
        let state = await MainActor.run { UIApplication.shared.applicationState }
        guard state == .active else { return }
        complete(timer, notified: false)
    }

    private func complete(_ timer: ActiveTimer, notified: Bool) {
        guard current() == timer else { return }
        discard(timer)
        NativeBridgeEvents.postDurable(type: "TIMER_COMPLETED", payload: [
            "activityId": timer.activityId,
            "completedAt": Self.iso8601.string(from: timer.endsAt),
            "notified": notified
        ])
    }

    private func discard(_ timer: ActiveTimer) {
        deadline?.cancel()
        deadline = nil
        defaults.removeObject(forKey: key)
        NotificationCoordinator.shared.cancel(identifiers: [timer.notificationIdentifier])
    }

    private func store(_ timer: ActiveTimer) {
        defaults.set(try? JSONEncoder().encode(timer), forKey: key)
    }

    private func scheduleNotification(for timer: ActiveTimer) async {
        // Sound is wired up with SET_SOUND_ENABLED (N-15); the setting defaults
        // to off, so until then the notification is silent by contract.
        try? await NotificationCoordinator.shared.schedule(
            identifier: timer.notificationIdentifier,
            kind: .timer,
            activityId: timer.activityId,
            title: "Time's up",
            body: "\(timer.activityName) — \(Self.durationText(timer)) done.",
            at: timer.endsAt,
            sound: nil
        )
    }

    private static func durationText(_ timer: ActiveTimer) -> String {
        let seconds = Int(timer.endsAt.timeIntervalSince(timer.startedAt).rounded())
        if seconds < 60 { return "\(seconds) sec" }
        let minutes = seconds / 60
        return "\(minutes) min"
    }

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
