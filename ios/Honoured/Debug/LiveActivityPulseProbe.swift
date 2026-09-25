#if DEBUG
import ActivityKit
import UIKit

/// Debug-only check of the completion pulse on a real Dynamic Island.
/// `-HonouredPulseProbe <delay>` starts one timer card, then, holding a
/// background task, switches it to completed `<delay>` seconds later so the
/// app can be sent to the background first and the island recorded.
enum LiveActivityPulseProbe {
    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-HonouredPulseProbe"),
              #available(iOS 16.2, *) else { return }
        let delay = arguments.indices.contains(index + 1) ? Double(arguments[index + 1]) ?? 10 : 10
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let now = Date()
            var state = HonouredLiveActivityState(
                contractName: "Pulse probe",
                status: .active,
                timer: .init(activityId: "probe", name: "Pulse probe", startedAt: now,
                             endsAt: now.addingTimeInterval(delay + 2), finished: false),
                timerCompletesContract: true,
                health: [],
                updatedAt: now,
                validUntil: now.addingTimeInterval(3600)
            )
            let activity: Activity<HonouredActivityAttributes>
            do {
                activity = try Activity.request(
                    attributes: HonouredActivityAttributes(contractId: "probe", healthDay: "2026-01-01", occurrenceToken: UUID().uuidString),
                    content: ActivityContent(state: state, staleDate: nil, relevanceScore: 1000),
                    pushType: nil
                )
            } catch {
                print("[pulse-probe] request failed: \(error)")
                return
            }
            print("[pulse-probe] started \(activity.id); background the app now")
            let task = UIApplication.shared.beginBackgroundTask(withName: "pulse-probe")
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            state.status = .completed
            state.completedAt = Date()
            state.timer?.finished = true
            state.updatedAt = Date()
            await activity.update(
                ActivityContent(state: state, staleDate: nil, relevanceScore: 1000),
                alertConfiguration: ActivityKitDriver.completionAlert(state)
            )
            print("[pulse-probe] completed update sent at \(Date().timeIntervalSince1970)")
            UIApplication.shared.endBackgroundTask(task)
        }
    }
}
#endif
