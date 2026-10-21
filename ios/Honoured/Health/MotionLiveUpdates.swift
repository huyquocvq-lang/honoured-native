import CoreMotion
import Foundation
import UIKit

/// While Honoured is on screen with Core Motion chosen, follows the
/// pedometer live, so a step or distance goal is noticed within seconds (the
/// M1 probe measured 0–3 s) and the Live Activity keeps up. iOS pauses these
/// updates with the app, so nothing here runs in the background; there the
/// regular passes read the pedometer whenever iOS runs Honoured.
@MainActor
final class MotionLiveUpdates {
    static let shared = MotionLiveUpdates()

    /// Pedometer updates come every few seconds while walking. Checking at
    /// most this often keeps a goal quick to notice without re-reading Health
    /// for every update.
    private static let minimumInterval: TimeInterval = 3
    /// Home shows the day's total from `health_daily`, so while the count
    /// moves the total is also uploaded, at most this often.
    private static let syncInterval: TimeInterval = 60

    private var pedometer: CMPedometer?
    private var countingFrom: Date?
    private var lastCheck = Date.distantPast
    private var pendingCheck: Task<Void, Never>?
    private var lastSync = Date.distantPast
    /// Bumped by every refresh and stop. A refresh that finds it moved while
    /// it was reading leaves the decision to the newer call.
    private var latestRequest = 0

    private init() {}

    /// Starts or stops the live count to match the moment: the app on screen,
    /// Core Motion chosen and readable, and a step or walking-distance goal
    /// today. Runs when the app becomes active and whenever the source, the
    /// goals, the reset hour or the day changes. Every start checks the goals
    /// at once, so opening Honoured brings them up to date.
    func refresh() async {
        latestRequest += 1
        let request = latestRequest
        let readsCoreMotion = await HealthKitService.shared.readsCoreMotion()
        let hasGoal = await Self.hasMotionGoal()
        let dayStart = await HealthSyncSettings.shared.healthDayStart(containing: Date())
        // A newer refresh, or a stop on the way to the background, came in
        // during the reads: that one decides.
        guard request == latestRequest else { return }
        guard UIApplication.shared.applicationState == .active, readsCoreMotion, hasGoal else {
            halt()
            return
        }
        if pedometer != nil, countingFrom == dayStart { return }
        halt()
        start(from: dayStart)
        scheduleCheck(trigger: "live_start")
        // Opening the app brings Home up to date too, not only the card.
        syncSoon(force: true)
    }

    func stop() {
        latestRequest += 1
        halt()
    }

    private func halt() {
        pedometer?.stopUpdates()
        pedometer = nil
        countingFrom = nil
        pendingCheck?.cancel()
        pendingCheck = nil
    }

    /// One check outside the live count, for a moment iOS runs the app anyway
    /// while it may be off screen, such as an unlock.
    func checkIfReadingCoreMotion(trigger: String) async {
        guard await HealthKitService.shared.readsCoreMotion(), await Self.hasMotionGoal() else { return }
        await checkGoals(trigger: trigger)
    }

    private func start(from dayStart: Date) {
        let pedometer = CMPedometer()
        self.pedometer = pedometer
        countingFrom = dayStart
        pedometer.startUpdates(from: dayStart) { [weak self] _, error in
            guard error == nil else { return }
            Task { @MainActor in self?.updateArrived(countingFrom: dayStart) }
        }
    }

    private func updateArrived(countingFrom dayStart: Date) {
        guard pedometer != nil, countingFrom == dayStart else { return }
        scheduleCheck(trigger: "motion_live")
        syncSoon(force: false)
    }

    /// A sync pass uploads the day's Core Motion total, and the
    /// `HEALTH_DATA_UPDATED` that follows makes Home read it again.
    private func syncSoon(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastSync) >= Self.syncInterval else { return }
        lastSync = now
        Task { await HealthSyncCoordinator.shared.syncNow() }
    }

    /// At most one check per `minimumInterval`; updates in between fold into
    /// the next one.
    private func scheduleCheck(trigger: String) {
        guard pendingCheck == nil else { return }
        let wait = max(0, Self.minimumInterval - Date().timeIntervalSince(lastCheck))
        pendingCheck = Task { @MainActor [weak self] in
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            guard let self, !Task.isCancelled else { return }
            self.pendingCheck = nil
            self.lastCheck = Date()
            // The reset hour can pass while the app stays open; the count
            // then starts again from the new day.
            if await HealthSyncSettings.shared.healthDayStart(containing: Date()) != self.countingFrom {
                await self.refresh()
                return
            }
            await self.checkGoals(trigger: trigger)
        }
    }

    /// The card and `GOAL_REACHED` from the same reads, as after a sync pass.
    private func checkGoals(trigger: String) async {
        let prefetched = await LiveActivityCoordinator.shared.refreshHealthProgress()
        await GoalMonitor.shared.evaluate(prefetched: prefetched, trigger: trigger)
    }

    private static func hasMotionGoal() async -> Bool {
        await HealthSyncSettings.shared.currentGoals().contains {
            HealthKitService.sourceSelectableMetrics.contains($0.metric)
        }
    }
}
