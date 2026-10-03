import Foundation

/// One pending Icon day the server wants measured, as returned by
/// `icon_days_to_measure()` (docs/db/icon_scoring_v1.sql). Foundation only:
/// it is also compiled into the host-less test target.
struct IconDayToMeasure: Decodable, Equatable, Sendable {
    let contractId: String
    /// The Icon day as the server stores it, "YYYY-MM-DD". Sent back unchanged.
    let day: String
    let startsAt: Date
    let deadlineAt: Date
    /// Canonical metric name (`HealthMetric.rawValue`).
    let metric: String
    let target: Double
    let unit: String

    private enum CodingKeys: String, CodingKey {
        case contractId = "contract_id"
        case day
        case startsAt = "starts_at"
        case deadlineAt = "deadline_at"
        case metric, target, unit
    }

    /// The range to read: from the start of the Icon day to the cut-off, or to
    /// now while the day is still running. Nil before the day has started.
    func window(now: Date) -> DateInterval? {
        let end = min(now, deadlineAt)
        guard end > startsAt else { return nil }
        return DateInterval(start: startsAt, end: end)
    }

    /// PostgREST writes timestamptz with or without fractional seconds.
    static func decodeList(from data: Data) throws -> [IconDayToMeasure] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = IconTimestamp.parse(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unreadable timestamp \(raw)"
                )
            }
            return date
        }
        return try decoder.decode([IconDayToMeasure].self, from: data)
    }
}

/// A reading of one Icon day: the total from the start of the day to
/// `measuredThrough`. The server decides HONOURED / BROKEN / still pending.
struct IconMeasurementPayload: Encodable, Equatable, Sendable {
    let contractId: String
    let day: String
    let value: Double
    let measuredThrough: String

    init(day: IconDayToMeasure, value: Double, measuredThrough: Date) {
        contractId = day.contractId
        self.day = day.day
        self.value = value
        self.measuredThrough = IconTimestamp.format(measuredThrough)
    }
}

/// Counts from `record_icon_measurements`.
struct IconMeasurementSummary: Decodable, Equatable, Sendable {
    let honoured: Int
    let broken: Int
    let pending: Int
    let skipped: Int

    /// True when a day was stamped, which the web app should show.
    var stampedAny: Bool { honoured + broken > 0 }
}
