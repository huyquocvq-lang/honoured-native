import Foundation

/// What the probe log shows about Honoured itself during a session: the locks
/// it saw, whether iOS ran it while locked or in the background, and the
/// stretches in which it could not have seen a lock. A lock is only visible
/// when it starts while Honoured is on screen or running; a suspended or
/// swiped-away app receives nothing, so "no lock seen" never means "not
/// locked".
struct MotionProbeTimeline {
    struct Period: Equatable, Sendable {
        let start: Date
        let end: Date
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    enum Place: String, Sendable {
        case foreground, background
    }

    /// From "protected data will become unavailable" to the first sign of an
    /// unlock.
    private(set) var locks: [Period] = []
    /// Runs that found Health data still protected. HealthKit callbacks that
    /// iOS holds back and hands over at the unlock do not count.
    private(set) var runsWhileLocked = 0
    /// Runs iOS started while Honoured was in the background, by reason.
    private(set) var backgroundRuns: [String: Int] = [:]
    /// Background stretches of at least `minimumGap` in which no lock was seen.
    private(set) var unseen: [Period] = []
    /// When a new Honoured process started: the previous one had ended.
    private(set) var relaunches: [Date] = []

    private let events: [MotionProbeEvent]

    init(events: [MotionProbeEvent], from start: Date, to end: Date, minimumGap: TimeInterval = 30) {
        self.events = events.filter { $0.at >= start && $0.at <= end }.sorted { $0.at < $1.at }
        var lockedSince: Date?
        var backgroundSince: Date?
        var lockSeen = false
        for event in self.events {
            let lifecycle = event.event == "lifecycle" ? event.reason : nil
            let run = event.event == "app_ran"
            let state = run ? event.notes?["app_state"] : nil
            let protected = run ? event.notes?["protected_data"] : nil

            if lifecycle == "protected_data_will_become_unavailable" {
                lockedSince = lockedSince ?? event.at
                if backgroundSince != nil { lockSeen = true }
            } else if lifecycle == "did_enter_background", backgroundSince == nil {
                backgroundSince = event.at
                lockSeen = lockedSince != nil
            } else if lifecycle == "launched" {
                relaunches.append(event.at)
            }
            if run {
                if protected == "locked" { runsWhileLocked += 1 }
                if state == "background" { backgroundRuns[event.reason ?? "unknown", default: 0] += 1 }
            }

            if lifecycle == "will_enter_foreground" || protected == "available", let since = lockedSince {
                locks.append(Period(start: since, end: event.at))
                lockedSince = nil
            }
            if lifecycle == "will_enter_foreground" || state == "active" || state == "inactive",
               let since = backgroundSince {
                if !lockSeen, event.at.timeIntervalSince(since) >= minimumGap {
                    unseen.append(Period(start: since, end: event.at))
                }
                backgroundSince = nil
                lockSeen = false
            }
        }
        if let since = lockedSince { locks.append(Period(start: since, end: end)) }
        if let since = backgroundSince, !lockSeen, end.timeIntervalSince(since) >= minimumGap {
            unseen.append(Period(start: since, end: end))
        }
    }

    /// Whether Honoured was in the foreground or the background at `date`,
    /// from the last run or lifecycle change up to it; nil when the log says
    /// nothing.
    func place(at date: Date) -> Place? {
        var place: Place?
        for event in events where event.at <= date {
            if event.event == "lifecycle" {
                if event.reason == "did_enter_background" { place = .background }
                if event.reason == "will_enter_foreground" { place = .foreground }
            } else if event.event == "app_ran", let state = event.notes?["app_state"] {
                place = state == "background" ? .background : .foreground
            }
        }
        return place
    }

    /// The last read of `source` over the session (not the day), if any.
    func lastSessionRead(of source: String) -> MotionProbeEvent? {
        events.last { $0.event == "reading" && $0.source == source && $0.notes?["scope"] == "session" }
    }

    func summaryLines(clock: (Date) -> String) -> [String] {
        var lines: [String] = []
        if locks.isEmpty {
            lines.append("Locks seen by the probe: none")
        } else {
            let lengths = locks.map { "\(Int($0.duration.rounded())) s" }.joined(separator: ", ")
            lines.append("Locks seen by the probe: \(locks.count) (\(lengths))")
        }
        lines.append("App runs while locked: \(runsWhileLocked)")
        let woken = backgroundRuns.values.reduce(0, +)
        let reasons = backgroundRuns.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        lines.append("Background runs started by iOS: \(woken)\(woken > 0 ? " (\(reasons))" : "")")
        for period in unseen {
            lines.append("In the background with no lock seen: \(clock(period.start))–\(clock(period.end)) (\(Int(period.duration.rounded())) s). The probe cannot see a lock that starts while Honoured is suspended or closed.")
        }
        for moment in relaunches {
            lines.append("Honoured restarted at \(clock(moment)): the earlier process had ended (swiped away, closed by iOS or crashed)")
        }
        return lines
    }
}
