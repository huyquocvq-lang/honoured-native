import Foundation

/// How a probe timestamp was obtained (Phase 3 M1, docs/phase3/core-motion-plan.vi.md).
/// An estimate is never written as `recorded`, and a missing fact stays
/// `unknown` instead of borrowing another timestamp.
enum MotionProbeCertainty: String, Codable, Sendable {
    /// The app or iOS noted the moment as it happened.
    case recorded
    /// Inferred afterwards; the event carries the window and the method.
    case estimated
    /// No evidence either way.
    case unknown
}

/// One line of the probe log. Foundation only: also compiled into the
/// host-less test target.
struct MotionProbeEvent: Codable, Equatable, Sendable {
    var at: Date
    var event: String
    var certainty: MotionProbeCertainty
    var reason: String?
    var source: String?
    var numbers: [String: Double]?
    var notes: [String: String]?

    init(
        at: Date,
        event: String,
        certainty: MotionProbeCertainty = .recorded,
        reason: String? = nil,
        source: String? = nil,
        numbers: [String: Double]? = nil,
        notes: [String: String]? = nil
    ) {
        self.at = at
        self.event = event
        self.certainty = certainty
        self.reason = reason
        self.source = source
        self.numbers = numbers
        self.notes = notes
    }

    /// One JSON object per line, dates as ISO 8601 with milliseconds.
    func jsonLine() throws -> String {
        String(decoding: try MotionProbeCoding.encoder.encode(self), as: UTF8.self)
    }

    static func parse(line: String) -> MotionProbeEvent? {
        try? MotionProbeCoding.decoder.decode(MotionProbeEvent.self, from: Data(line.utf8))
    }
}

enum MotionProbeCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timestamp(date))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = date(raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unreadable date \(raw)")
            }
            return date
        }
        return decoder
    }()

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}

/// One minute of a session as the export lists it, so a long run with several
/// test cases can be cut into its parts afterwards. `nil` = that source could
/// not be read for the minute, never zero.
struct MotionProbeMinute: Equatable, Sendable {
    let start: Date
    let coreMotion: Double?
    let healthKit: Double?
    let healthKitBySource: [String: Double]
}

enum MotionProbeCSV {
    /// One row per minute: UTC instant, local clock, Core Motion, the combined
    /// HealthKit total, then one column per HealthKit source.
    static func minutes(_ rows: [MotionProbeMinute], calendar: Calendar) -> String {
        let sources = Set(rows.flatMap { $0.healthKitBySource.keys }).sorted()
        let clock = DateFormatter()
        clock.calendar = calendar
        clock.timeZone = calendar.timeZone
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "HH:mm"
        let header = ["minute_start", "local_time", "core_motion", "healthkit_combined"] + sources.map { "healthkit:\($0)" }
        var lines = [header.map(field).joined(separator: ",")]
        for row in rows {
            var cells = [MotionProbeCoding.timestamp(row.start), clock.string(from: row.start),
                         number(row.coreMotion), number(row.healthKit)]
            cells += sources.map { number(row.healthKitBySource[$0]) }
            lines.append(cells.map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func number(_ value: Double?) -> String {
        value.map { String(Int($0.rounded())) } ?? ""
    }

    private static func field(_ text: String) -> String {
        guard text.contains(",") || text.contains("\"") else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// A count over one interval, as Core Motion or a HealthKit statistics
/// collection reports it.
struct MotionProbeInterval: Equatable, Sendable {
    let start: Date
    let end: Date
    let value: Double
}

/// Where a running total first reached a target: somewhere inside
/// `[windowStart, windowEnd]`. No API says which step was the Nth, so this is
/// always an estimate.
struct MotionProbeCrossing: Codable, Equatable, Sendable {
    let windowStart: Date
    let windowEnd: Date
    let totalBefore: Double
    let totalAfter: Double
}

enum MotionProbeMath {
    /// The interval in which the running total of `intervals` (oldest first)
    /// reached `target`; nil when it never does.
    static func crossing(of target: Double, in intervals: [MotionProbeInterval]) -> MotionProbeCrossing? {
        guard target > 0 else { return nil }
        var total = 0.0
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            let before = total
            total += max(interval.value, 0)
            if before < target, total >= target {
                return MotionProbeCrossing(
                    windowStart: interval.start,
                    windowEnd: interval.end,
                    totalBefore: before,
                    totalAfter: total
                )
            }
        }
        return nil
    }

    /// `crossing` limited to `[notBefore, notAfter]`, the bounds that reads
    /// taken during the session prove. Bounds that would leave nothing, or
    /// that fall outside the window, are ignored, so the result is never
    /// narrower than the evidence.
    static func narrowed(_ crossing: MotionProbeCrossing, notBefore: Date?, notAfter: Date?) -> MotionProbeCrossing {
        var start = crossing.windowStart
        var end = crossing.windowEnd
        if let notBefore, notBefore > start, notBefore < end { start = notBefore }
        if let notAfter, notAfter < end, notAfter > start { end = notAfter }
        return MotionProbeCrossing(windowStart: start, windowEnd: end,
                                   totalBefore: crossing.totalBefore, totalAfter: crossing.totalAfter)
    }

    /// Seconds from a crossing to a recorded moment, as the range the crossing
    /// window allows: the earliest crossing gives the longest delay.
    static func delayRange(from crossing: MotionProbeCrossing, to recorded: Date) -> ClosedRange<TimeInterval> {
        let shortest = recorded.timeIntervalSince(crossing.windowEnd)
        let longest = recorded.timeIntervalSince(crossing.windowStart)
        return min(shortest, longest)...max(shortest, longest)
    }

    /// "3–7 min", or "45 s" when the range is under a minute wide and short.
    static func delayText(_ range: ClosedRange<TimeInterval>) -> String {
        if range.upperBound < 90 {
            return "\(Int(range.lowerBound.rounded()))–\(Int(range.upperBound.rounded())) s"
        }
        let low = Int((range.lowerBound / 60).rounded(.down))
        let high = Int((range.upperBound / 60).rounded(.up))
        return low == high ? "\(low) min" : "\(low)–\(high) min"
    }

    /// Consecutive windows of `step` seconds covering `[start, end)`, at most
    /// `limit` of them (the most recent are kept).
    static func windows(from start: Date, to end: Date, step: TimeInterval = 60, limit: Int = 1_440) -> [DateInterval] {
        guard end > start, step > 0, limit > 0 else { return [] }
        var windows: [DateInterval] = []
        var cursor = start
        while cursor < end {
            let next = min(cursor.addingTimeInterval(step), end)
            windows.append(DateInterval(start: cursor, end: next))
            cursor = next
        }
        return Array(windows.suffix(limit))
    }

    enum Gait: String, Codable, Sendable {
        case walking, running
    }

    /// Honoured's own estimate (`MotionEnergyEstimate`), so the probe's report
    /// and the number the app shows never disagree.
    static func estimatedActiveKilocalories(
        distanceMeters: Double,
        activeSeconds: Double?,
        weightKg: Double = MotionEnergyEstimate.assumedWeightKg
    ) -> (kilocalories: Double, gait: Gait) {
        let estimate = MotionEnergyEstimate(distanceMeters: distanceMeters, activeSeconds: activeSeconds, weightKg: weightKg)
        return (estimate.kilocalories, estimate.gait == .running ? .running : .walking)
    }
}
