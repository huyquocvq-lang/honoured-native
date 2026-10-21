import Foundation
import MetricKit

/// Keeps the MetricKit payloads iOS delivers (about once a day) while the
/// probe is on, for the battery part of the M1 report: CPU time, background
/// time and location activity measured by iOS rather than by the app.
final class MotionProbeMetricKit: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MotionProbeMetricKit()

    private let lock = NSLock()
    private var started = false

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        guard MotionProbe.isEnabled else { return }
        let items = payloads.map { (begin: $0.timeStampBegin, end: $0.timeStampEnd, json: $0.jsonRepresentation()) }
        Task { await MotionProbe.shared.storeMetricPayloads(items) }
    }
}

extension MotionProbe {
    func storeMetricPayloads(_ payloads: [(begin: Date, end: Date, json: Data)]) {
        try? FileManager.default.createDirectory(at: metricKitDirectory, withIntermediateDirectories: true)
        for payload in payloads {
            let name = "metrics-\(Int(payload.begin.timeIntervalSince1970))-\(Int(payload.end.timeIntervalSince1970)).json"
            try? payload.json.write(to: metricKitDirectory.appendingPathComponent(name), options: .atomic)
            append(MotionProbeEvent(
                at: Date(), event: "metrickit_payload",
                notes: ["begin": MotionProbeCoding.timestamp(payload.begin),
                        "end": MotionProbeCoding.timestamp(payload.end)]
            ))
        }
    }
}
