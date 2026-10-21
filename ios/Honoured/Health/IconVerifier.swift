import Foundation

/// Measures the signed-in person's Icon days and reports the readings; the
/// server stamps HONOURED or BROKEN from them (V1.2 M2-05,
/// docs/db/icon_scoring_v1.sql). A stamped day stays on the list for 30 days
/// after its cut-off so it shows the whole day's total, and a late total can
/// still turn BROKEN into HONOURED (docs/db/icon_scoring_v2.sql). Runs after
/// each health upload and when the app becomes active. A day the device cannot
/// read is simply not reported: the server's 24-hour rule settles it, so
/// nothing here ever stamps a day itself.
actor IconVerifier {
    static let shared = IconVerifier()

    private var isRunning = false

    func run() async {
        guard !isRunning, HealthKitService.shared.isAvailable else { return }
        isRunning = true
        defer { isRunning = false }

        do {
            guard let session = try await AuthSessionStore.shared.refreshedSessionIfNeeded() else { return }
            let days = try await SupabaseHealthClient.shared.iconDaysToMeasure(session: session)
            guard !days.isEmpty else { return }

            let now = Date()
            var readings: [IconMeasurementPayload] = []
            for day in days {
                guard let metric = HealthMetric(rawValue: day.metric),
                      let window = day.window(now: now) else { continue }
                // "Nothing recorded" and "could not read" both wait. A declined
                // Health permission looks like no data, so it is never read as
                // zero and stamped BROKEN early.
                guard case .value(let total) = await HealthKitService.shared.readTotal(
                    for: metric, from: window.start, to: window.end
                ) else { continue }
                readings.append(IconMeasurementPayload(day: day, value: total, measuredThrough: window.end))
            }
            guard !readings.isEmpty else { return }

            // The account may have changed while HealthKit was read.
            guard await AuthSessionStore.shared.load()?.userId == session.userId else { return }
            let summary = try await SupabaseHealthClient.shared.recordIconMeasurements(readings, session: session)
            if summary.changedAny {
                NativeBridgeEvents.post(type: "ICON_DAYS_UPDATED", payload: [
                    "honoured": summary.honoured,
                    "broken": summary.broken,
                    "updated": summary.updated
                ])
            }
        } catch {
            // Offline, signed out or a rejected session: the next upload or
            // foreground pass tries again, inside the 24-hour window.
        }
    }
}
