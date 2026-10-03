import Foundation

// Which Icon cards should exist right now (V1.2 M2-09, local lifecycle).
// Pure: the coordinator feeds it the server's Icon days and the running cards
// and applies the result through ActivityKit. Push-to-start (M2-07) will open
// the same cards from the server; this keeps them right whenever the app runs.

/// One Icon day as the server schedules it, with what its card shows.
struct IconCardDay: Equatable {
    enum Status: String, Equatable {
        case pending, honoured, broken, amended
    }

    var facts: IconCardFacts
    var morningAt: Date?
    var eveningAt: Date?
    var deadlineAt: Date
    var status: Status

    /// Cards are identified by contract and Icon day.
    var key: String { IconCardPlan.key(contractId: facts.contractId, iconDay: facts.iconDay) }

    /// The first reminder of the day; with both reminders off there is no card.
    var opensAt: Date? { [morningAt, eveningAt].compactMap { $0 }.min() }
}

/// A card ActivityKit is showing.
struct RunningIconCard: Equatable {
    var id: String
    var contractId: String
    var iconDay: String
    var state: IconLiveActivityState
    var staleDate: Date?

    var key: String { IconCardPlan.key(contractId: contractId, iconDay: iconDay) }
}

enum IconCardAction: Equatable {
    case start(IconCardFacts, IconLiveActivityState, staleDate: Date?)
    case update(id: String, IconLiveActivityState, staleDate: Date?)
    case end(id: String)
}

enum IconCardPlan {
    static func key(contractId: String, iconDay: String) -> String { contractId + "\u{1F}" + iconDay }

    /// - Parameters:
    ///   - started: keys of cards already started once. A card the person
    ///     swiped away, or one that closed, is never started again.
    ///   - canStart: ActivityKit only starts a card while the app is in the foreground.
    static func actions(
        days: [IconCardDay], running: [RunningIconCard], started: Set<String>, now: Date, canStart: Bool
    ) -> [IconCardAction] {
        var actions: [IconCardAction] = []
        var wanted: [String: IconCardDay] = [:]
        for day in days where isShowable(day, now: now) {
            wanted[day.key] = day
        }

        var kept = Set<String>()
        for card in running {
            guard let day = wanted[card.key], !kept.contains(card.key) else {
                // Day over, stamped BROKEN or amended, Icon gone, or a duplicate.
                actions.append(.end(id: card.id))
                continue
            }
            kept.insert(card.key)
            let (state, stale) = desired(for: day, now: now, keeping: card.state)
            if state.phase != card.state.phase || state.result != card.state.result
                || state.line != card.state.line || stale != card.staleDate {
                actions.append(.update(id: card.id, state, staleDate: stale))
            }
        }

        if canStart {
            for day in wanted.values.sorted(by: { $0.deadlineAt < $1.deadlineAt })
            where !kept.contains(day.key) && !started.contains(day.key) {
                let (state, stale) = desired(for: day, now: now, keeping: nil)
                actions.append(.start(day.facts, state, staleDate: stale))
            }
        }
        return actions
    }

    /// From the first reminder until the cut-off, unless the day ended otherwise.
    static func isShowable(_ day: IconCardDay, now: Date) -> Bool {
        guard day.status == .pending || day.status == .honoured,
              let opensAt = day.opensAt else { return false }
        return now >= opensAt && now < day.deadlineAt
    }

    /// The morning card goes stale at the evening reminder; the widget then
    /// shows the evening line without the app having to run.
    static func desired(
        for day: IconCardDay, now: Date, keeping current: IconLiveActivityState?
    ) -> (IconLiveActivityState, Date?) {
        if day.status == .honoured {
            if let current, current.result == .honoured { return (current, nil) }
            return (.result(.honoured, at: now), nil)
        }
        if let evening = day.eveningAt, now >= evening {
            if let current, current.phase == .evening { return (current, nil) }
            return (.evening(at: now), nil)
        }
        if let current, current.phase == .morning {
            return (current, day.eveningAt)
        }
        return (.morning(sessionNumber: day.facts.sessionNumber, at: now), day.eveningAt)
    }
}

// MARK: - Server rows

/// `icon_days` rows with their contract, as PostgREST returns them.
enum IconCardRows {
    struct Row: Decodable {
        struct Contract: Decodable {
            let client_id: String
            let primary_activity: String
            let primary_target: String?
            let because: String
        }

        let contract_id: String
        let day: String
        let session_number: Int
        let deadline_at: String
        let morning_at: String?
        let evening_at: String?
        let status: String
        let contracts: Contract
    }

    /// `totals` maps `contract_id` to its number of Icon days.
    static func days(from data: Data, totals: [String: Int]) throws -> [IconCardDay] {
        try JSONDecoder().decode([Row].self, from: data).compactMap { row in
            guard let deadline = IconTimestamp.parse(row.deadline_at),
                  let status = IconCardDay.Status(rawValue: row.status) else { return nil }
            let target = IconTargetText.split(row.contracts.primary_target ?? "")
            let facts = IconCardFacts(
                contractId: row.contracts.client_id, iconDay: row.day,
                weekday: IconTargetText.weekday(of: row.day) ?? "",
                sessionNumber: row.session_number,
                totalSessions: totals[row.contract_id] ?? row.session_number,
                targetValue: target.value, targetUnit: target.unit,
                activityName: row.contracts.primary_activity, because: row.contracts.because,
                deadline: deadline
            )
            return IconCardDay(
                facts: facts,
                morningAt: row.morning_at.flatMap(IconTimestamp.parse),
                eveningAt: row.evening_at.flatMap(IconTimestamp.parse),
                deadlineAt: deadline, status: status
            )
        }
    }
}

/// Splits the target the person wrote for the card's layout.
enum IconTargetText {
    /// `10000 steps` → (`10,000`, `STEPS`); `2.5 km` → (`2.5`, `KM`); text with
    /// no leading number stays whole.
    static func split(_ target: String) -> (value: String, unit: String) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.range(of: #"^\d+(?:[.,]\d+)?"#, options: .regularExpression) else {
            return (trimmed, "")
        }
        let number = String(trimmed[match])
        let unit = trimmed[match.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !number.contains(","), !number.contains("."), let whole = Int(number) else {
            return (number, unit.uppercased())
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .decimal
        return (formatter.string(from: NSNumber(value: whole)) ?? number, unit.uppercased())
    }

    /// `2026-10-06` → `TUE`; the weekday of a calendar date is the same in every zone.
    static func weekday(of day: String) -> String? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: day) else { return nil }
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }
}
