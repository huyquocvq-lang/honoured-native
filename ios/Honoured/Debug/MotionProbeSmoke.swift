#if DEBUG
import Foundation
import ZIPFoundation

/// Debug-only end-to-end check of the motion probe without tapping:
/// `-HonouredMotionProbeSmoke <targetSteps>` switches the probe on, opens its
/// screen, runs one session, rebuilds the report and exports the log, printing
/// each step (read it with `xcrun simctl launch --console-pty`). The simulator
/// has no pedometer, so Core Motion reads as unavailable there.
enum MotionProbeSmoke {
    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-HonouredMotionProbeSmoke") else { return }
        let target = arguments.indices.contains(index + 1) ? Double(arguments[index + 1]) ?? 200 : 200
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            let probe = MotionProbe.shared
            await probe.setEnabled(true)
            MotionProbePresenter.shared.open()
            await probe.startSession(targetSteps: target)
            await probe.recordRun(reason: .probeScreen)
            let report = await probe.rebuildReport()
            print("MOTION PROBE SMOKE report\n\(report)")
            do {
                let url = try await probe.exportArchive()
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                let entries = (try? Archive(url: url, accessMode: .read)).map { Array($0).map(\.path) } ?? []
                print("MOTION PROBE SMOKE export \(url.lastPathComponent) \(size) bytes: \(entries.joined(separator: ", "))")
            } catch {
                print("MOTION PROBE SMOKE export failed: \(error)")
            }
            let snapshot = await probe.snapshot()
            for event in snapshot.recent.reversed() {
                print("MOTION PROBE SMOKE event \((try? event.jsonLine()) ?? event.event)")
            }
            print("MOTION PROBE SMOKE DONE")
        }
    }
}
#endif
