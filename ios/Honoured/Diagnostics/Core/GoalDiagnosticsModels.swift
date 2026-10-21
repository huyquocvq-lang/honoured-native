import Foundation

/// One line of the goal-latency diagnostics (Phase 3 M2-B,
/// docs/phase3/core-motion-plan.vi.md). Each moment says how it is known:
/// `recorded` when Honoured or iOS noted it as it happened, `estimated` when
/// it was inferred afterwards (always a window and a method), `unknown` when
/// there is no evidence. An estimate can never be stored as recorded: the
/// constructors are the only way to set the certainty and its times.
/// Foundation only, so it is also compiled into the host-less test target.
struct GoalDiagnosticsEvent: Codable, Equatable, Sendable {
    enum Certainty: String, Codable, Sendable {
        case recorded
        case estimated
        case unknown
    }

    let id: UUID
    /// The account the line belongs to; it is never uploaded for another.
    let userId: String
    let event: String
    let certainty: Certainty
    /// When it happened. Only for `recorded`.
    let occurredAt: Date?
    /// The window it happened in. Only for `estimated`, with `method`.
    let windowStart: Date?
    let windowEnd: Date?
    let method: String?
    /// The device clock when the line was written.
    let deviceTime: Date

    var reason: String?
    /// `core_motion` or `healthkit`.
    var source: String?
    var metric: String?
    var activityId: String?
    /// The health day, "yyyy-MM-dd".
    var day: String?
    var value: Double?
    var target: Double?
    var details: [String: String]?

    private init(
        userId: String, event: String, certainty: Certainty,
        occurredAt: Date?, windowStart: Date?, windowEnd: Date?, method: String?, deviceTime: Date
    ) {
        id = UUID()
        self.userId = userId
        self.event = event
        self.certainty = certainty
        self.occurredAt = occurredAt
        self.windowStart = windowStart
        self.windowEnd = windowEnd
        self.method = method
        self.deviceTime = deviceTime
    }

    static func recorded(_ event: String, at: Date, userId: String, now: Date = Date()) -> GoalDiagnosticsEvent {
        GoalDiagnosticsEvent(
            userId: userId, event: event, certainty: .recorded,
            occurredAt: at, windowStart: nil, windowEnd: nil, method: nil, deviceTime: now
        )
    }

    /// Nil when the window runs backwards: there is no estimate to keep.
    static func estimated(
        _ event: String, from start: Date, to end: Date, method: String, userId: String, now: Date = Date()
    ) -> GoalDiagnosticsEvent? {
        guard end >= start else { return nil }
        return GoalDiagnosticsEvent(
            userId: userId, event: event, certainty: .estimated,
            occurredAt: nil, windowStart: start, windowEnd: end, method: method, deviceTime: now
        )
    }

    static func unknown(_ event: String, userId: String, now: Date = Date()) -> GoalDiagnosticsEvent {
        GoalDiagnosticsEvent(
            userId: userId, event: event, certainty: .unknown,
            occurredAt: nil, windowStart: nil, windowEnd: nil, method: nil, deviceTime: now
        )
    }

    /// The row `record_goal_diagnostics` takes (docs/db/goal_diagnostics_v1.sql).
    /// `sentAt` is the device clock at upload: with the server's own receipt
    /// time it shows how far the device clock is off.
    func row(sentAt: Date) -> GoalDiagnosticsRow {
        GoalDiagnosticsRow(
            id: id.uuidString.lowercased(),
            event: event,
            certainty: certainty.rawValue,
            occurredAt: occurredAt.map(GoalDiagnosticsTime.format),
            windowStart: windowStart.map(GoalDiagnosticsTime.format),
            windowEnd: windowEnd.map(GoalDiagnosticsTime.format),
            method: method,
            reason: reason,
            source: source,
            metric: metric,
            activityId: activityId,
            day: day,
            value: value,
            target: target,
            details: details,
            deviceTime: GoalDiagnosticsTime.format(deviceTime),
            sentAt: GoalDiagnosticsTime.format(sentAt)
        )
    }
}

struct GoalDiagnosticsRow: Encodable, Equatable, Sendable {
    let id: String
    let event: String
    let certainty: String
    let occurredAt: String?
    let windowStart: String?
    let windowEnd: String?
    let method: String?
    let reason: String?
    let source: String?
    let metric: String?
    let activityId: String?
    let day: String?
    let value: Double?
    let target: Double?
    let details: [String: String]?
    let deviceTime: String
    let sentAt: String
}

enum GoalDiagnosticsTime {
    static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

/// A goal notification asked for and not yet seen delivered.
struct GoalNotificationRequest: Codable, Equatable, Sendable {
    /// The account that asked; only it settles the request.
    let userId: String
    let identifier: String
    let activityId: String
    let day: String
    let requestedAt: Date
}

/// Which requested goal notifications iOS shows as delivered. Only iOS's own
/// delivery time counts as recorded; a request that never shows up — cleared
/// by the person, held by a Focus, permission revoked — becomes unknown once
/// `giveUpAfter` has passed, never "delivered at the request time".
enum GoalNotificationDeliveries {
    static let giveUpAfter: TimeInterval = 24 * 60 * 60

    struct Delivered: Equatable {
        let request: GoalNotificationRequest
        /// `UNNotification.date`.
        let at: Date
    }

    struct Outcome: Equatable {
        var delivered: [Delivered]
        var unknown: [GoalNotificationRequest]
        var stillPending: [GoalNotificationRequest]
    }

    /// - Parameter delivered: identifier and `UNNotification.date` of each
    ///   notification in Notification Center now.
    static func settle(
        _ pending: [GoalNotificationRequest],
        delivered: [String: Date],
        now: Date
    ) -> Outcome {
        var outcome = Outcome(delivered: [], unknown: [], stillPending: [])
        for request in pending {
            if let at = delivered[request.identifier] {
                outcome.delivered.append(Delivered(request: request, at: at))
            } else if now.timeIntervalSince(request.requestedAt) >= giveUpAfter {
                outcome.unknown.append(request)
            } else {
                outcome.stillPending.append(request)
            }
        }
        return outcome
    }
}

/// Keeps readings of a goal from flooding the log while the app follows the
/// pedometer live: a reading is written when its kind of result changes or a
/// minute has passed since the last one written for that goal.
enum GoalReadingLog {
    static let interval: TimeInterval = 60

    struct Last: Codable, Equatable, Sendable {
        let result: String
        let at: Date
    }

    static func shouldWrite(result: String, at: Date, last: Last?) -> Bool {
        guard let last else { return true }
        return last.result != result || at.timeIntervalSince(last.at) >= interval
    }
}

/// Where a day's running total crossed a goal, from per-interval counts
/// between the last reading still below it and the first that met it.
enum GoalCrossingEstimate {
    /// - Parameters:
    ///   - before: the day's total at the start of the first interval.
    ///   - intervals: counts per interval, covering the window in order.
    /// - Returns: the interval in which `before` plus the running count
    ///   reached `target`, or nil when it never does in them.
    static func window(target: Double, before: Double, intervals: [(start: Date, end: Date, value: Double)]) -> DateInterval? {
        var total = before
        guard total < target else { return nil }
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            total += max(interval.value, 0)
            if total >= target, interval.end >= interval.start {
                return DateInterval(start: interval.start, end: interval.end)
            }
        }
        return nil
    }

    /// `window` held to what the readings prove: not before the last reading
    /// below the target, not after the first one that met it.
    static func bounded(_ window: DateInterval, notBefore: Date, notAfter: Date) -> DateInterval {
        let start = max(window.start, notBefore)
        let end = min(window.end, notAfter)
        return end >= start ? DateInterval(start: start, end: end) : window
    }

    /// Consecutive windows of `step` seconds covering `[start, end)`.
    static func chunks(from start: Date, to end: Date, step: TimeInterval) -> [DateInterval] {
        guard end > start, step > 0 else { return [] }
        var chunks: [DateInterval] = []
        var cursor = start
        while cursor < end {
            let next = min(cursor.addingTimeInterval(step), end)
            chunks.append(DateInterval(start: cursor, end: next))
            cursor = next
        }
        return chunks
    }

    /// Halves `[below, reached]` until it is at most `resolution` wide, with
    /// `total(t)` the day's running total at `t` (which only grows). About a
    /// dozen reads cover a whole day to the minute. Nil when a read fails.
    ///
    /// - Parameters:
    ///   - below: a moment the total was still under `target`.
    ///   - reached: a moment it had reached it.
    static func narrow(
        target: Double, below: Date, reached: Date, resolution: TimeInterval,
        total: (Date) async -> Double?
    ) async -> DateInterval? {
        guard reached >= below, resolution > 0 else { return nil }
        var low = below
        var high = reached
        while high.timeIntervalSince(low) > resolution {
            let middle = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
            guard let value = await total(middle) else { return nil }
            if value >= target { high = middle } else { low = middle }
        }
        return DateInterval(start: low, end: high)
    }
}

/// How long uploads wait after a failure: 15 minutes, doubling to six hours,
/// and a day when the server has no `record_goal_diagnostics` yet (the SQL
/// is applied separately), so an undeployed server is not asked every wake.
enum GoalDiagnosticsUploadBackoff {
    static let first: TimeInterval = 15 * 60
    static let longest: TimeInterval = 6 * 60 * 60
    static let serverNotReady: TimeInterval = 24 * 60 * 60

    /// - Parameters:
    ///   - failures: consecutive failures so far, this one included.
    ///   - status: the HTTP status, when the server answered.
    static func delay(failures: Int, status: Int?) -> TimeInterval {
        if status == 404 { return serverNotReady }
        let doublings = max(failures - 1, 0)
        return min(first * pow(2, Double(min(doublings, 16))), longest)
    }
}
