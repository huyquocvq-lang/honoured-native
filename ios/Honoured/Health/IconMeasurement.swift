import Foundation

/// One Icon day the server wants measured, as returned by
/// `icon_days_to_measure()`: pending, or stamped from Health readings and
/// still inside the 30-day window in which its total keeps growing
/// (docs/db/icon_scoring_v2.sql). Foundation only: it is also compiled into
/// the host-less test target.
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
/// `source` (`healthkit` or `core_motion`) lets icon_scoring_v3.sql tell a
/// source change from a lower reading of the same source; servers before it
/// ignore the key.
struct IconMeasurementPayload: Encodable, Equatable, Sendable {
    let contractId: String
    let day: String
    let value: Double
    let measuredThrough: String
    let source: String

    init(day: IconDayToMeasure, value: Double, measuredThrough: Date, source: HealthReadingSource) {
        contractId = day.contractId
        self.day = day.day
        self.value = value
        self.measuredThrough = IconTimestamp.format(measuredThrough)
        self.source = source.rawValue
    }
}

/// Counts from `record_icon_measurements`.
struct IconMeasurementSummary: Decodable, Equatable, Sendable {
    /// Days this report stamped HONOURED, including a BROKEN day a late
    /// reading took to the target.
    let honoured: Int
    let broken: Int
    let pending: Int
    let skipped: Int
    /// Stamped days whose total went up. A server still on
    /// icon_scoring_v1.sql has no such count, so it reads as zero.
    let updated: Int

    private enum CodingKeys: String, CodingKey {
        case honoured, broken, pending, skipped, updated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        honoured = try container.decode(Int.self, forKey: .honoured)
        broken = try container.decode(Int.self, forKey: .broken)
        pending = try container.decode(Int.self, forKey: .pending)
        skipped = try container.decode(Int.self, forKey: .skipped)
        updated = try container.decodeIfPresent(Int.self, forKey: .updated) ?? 0
    }

    /// True when a day was stamped or a stamped day's total rose, either of
    /// which the web app should show.
    var changedAny: Bool { honoured + broken + updated > 0 }
}
