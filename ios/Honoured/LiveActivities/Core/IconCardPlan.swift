import Foundation

// Which Icon cards should exist right now (V1.2 M2-09, local lifecycle).
// Pure: the coordinator feeds it the server's Icon days and the running cards
// and applies the result through ActivityKit. The icon-push job (M2-07) opens
// the same cards from the server; this keeps them right whenever the app runs.
//
// A day's card appears twice, as the scope describes: at the morning reminder
// and again at the evening one. iOS ends a Live Activity 8 hours after it
// starts, so the morning card cannot be trusted to reach the cut-off; the
// evening gets a fresh card (the evening reminder is set within 8 hours of
// the cut-off). Without one, a card that would run out first is renewed: by
// the app whenever it is open, unseen, and otherwise by the server's push
// (icon_push_v5.sql) shortly before the 8 hours (client, Oct 6).

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
    /// Canonical Health metric of a measured Icon (`steps`, …); nil when self-reported.
    var metric: String? = nil
    /// Start of the Icon day in the Icon's time zone, where its Health total begins.
    var startsAt: Date? = nil
    /// The day's Health total read on this device just now; nil when the read
    /// failed (a locked device) or found nothing.
    var reading: Double? = nil
    /// The last total this account reported (`icon_days.measured_value`). The
    /// server stops taking reports once the day is stamped, so it can be
    /// behind a card the app kept updating.
    var reportedValue: Double? = nil

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
    /// False once iOS ended it at its 8 hours: it lingers on the Lock Screen
    /// but can no longer change. A card that was removed is not listed.
    var isActive: Bool = true

    var key: String { IconCardPlan.key(contractId: contractId, iconDay: iconDay) }
}

/// The two appearances of a day's card.
enum IconCardSlot: String, Equatable {
    case morning, evening
}

enum IconCardAction: Equatable {
    case start(IconCardFacts, IconLiveActivityState, staleDate: Date?, slot: IconCardSlot)
    case update(id: String, IconLiveActivityState, staleDate: Date?)
    case end(id: String)
}

enum IconCardPlan {
    static func key(contractId: String, iconDay: String) -> String { contractId + "\u{1F}" + iconDay }

    /// Remembers one appearance of a card as started.
    static func startedKey(_ key: String, slot: IconCardSlot) -> String { key + "\u{1F}" + slot.rawValue }

    /// The server push-starts the evening card within a minute of the
    /// reminder; the app opens it itself only after this, so the two never
    /// both open one.
    static let eveningGrace: TimeInterval = 3 * 60

    /// iOS ends a Live Activity 8 hours after it starts.
    static let cardLifetime: TimeInterval = 8 * 3600

    /// In the foreground a card at least this old is swapped for a fresh one
    /// if it would run out before the cut-off.
    static let renewAfter: TimeInterval = 3600

    /// - Parameters:
    ///   - started: `startedKey`s of the appearances already started. A card
    ///     the person swiped away, or one that closed, is not started again
    ///     for that appearance.
    ///   - canStart: ActivityKit only starts a card while the app is in the foreground.
    static func actions(
        days: [IconCardDay], running: [RunningIconCard], started: Set<String>, now: Date, canStart: Bool
    ) -> [IconCardAction] {
        var actions: [IconCardAction] = []
        var wanted: [String: IconCardDay] = [:]
        for day in days where isShowable(day, now: now) {
            wanted[day.key] = day
        }

        // Evening and result cards come first, so beside one of them it is the
        // morning card that closes; otherwise the newer card stays.
        let ordered = running.filter(\.isActive).enumerated().sorted { a, b in
            let ra = a.element.state.phase == .morning ? 1 : 0
            let rb = b.element.state.phase == .morning ? 1 : 0
            if ra != rb { return ra < rb }
            if a.element.state.updatedAt != b.element.state.updatedAt {
                return a.element.state.updatedAt > b.element.state.updatedAt
            }
            return a.offset < b.offset
        }.map(\.element)

        var kept = Set<String>()
        for card in ordered {
            guard let day = wanted[card.key], !kept.contains(card.key) else {
                // Day over, stamped BROKEN or amended, Icon gone, or a duplicate.
                actions.append(.end(id: card.id))
                continue
            }
            if day.status == .pending, card.state.phase == .morning,
               let evening = day.eveningAt, now >= evening {
                // The evening needs a fresh card. Until the grace period is
                // over the server's push is on its way, and while the app
                // cannot open one the morning card stays: its stale date
                // already shows the evening line.
                let eveningShown = started.contains(startedKey(day.key, slot: .evening))
                if now >= evening.addingTimeInterval(eveningGrace) && (canStart || eveningShown) {
                    actions.append(.end(id: card.id))
                } else {
                    kept.insert(card.key)
                }
                continue
            }
            kept.insert(card.key)
            var (state, stale) = desired(for: day, now: now, keeping: card.state)
            if canStart && needsRenewal(card.state, day: day, now: now) {
                // A fresh card, unseen: the island hides the app's own card
                // while the app is open.
                state.updatedAt = now
                actions.append(.start(day.facts, state, staleDate: stale, slot: slot(of: state)))
                actions.append(.end(id: card.id))
                continue
            }
            if state.phase != card.state.phase || state.result != card.state.result
                || state.line != card.state.line || state.value != card.state.value || stale != card.staleDate {
                actions.append(.update(id: card.id, state, staleDate: stale))
            }
        }

        if canStart {
            for day in wanted.values.sorted(by: { $0.deadlineAt < $1.deadlineAt }) where !kept.contains(day.key) {
                let due = Self.slot(of: day, at: now)
                if due == .evening, let evening = day.eveningAt, now < evening.addingTimeInterval(eveningGrace) {
                    continue
                }
                if started.contains(startedKey(day.key, slot: due)) {
                    // Shown already. A card iOS ended at its 8 hours comes back;
                    // one the person removed stays away.
                    guard let lapsed = running.first(where: { !$0.isActive && $0.key == day.key }) else { continue }
                    var (state, stale) = desired(for: day, now: now, keeping: lapsed.state)
                    state.updatedAt = now
                    actions.append(.start(day.facts, state, staleDate: stale, slot: due))
                    continue
                }
                let (state, stale) = desired(for: day, now: now, keeping: nil)
                actions.append(.start(day.facts, state, staleDate: stale, slot: due))
            }
        }
        return actions
    }

    /// Whether the app should swap this card for a fresh one: it is an hour
    /// old or more and would run out before the cut-off, with no evening card
    /// coming first. `updatedAt` is when the card's line began, never before
    /// the card started, so a card is never renewed early; when it is late,
    /// the server's renewal covers it.
    static func needsRenewal(_ state: IconLiveActivityState, day: IconCardDay, now: Date) -> Bool {
        let runsOut = state.updatedAt.addingTimeInterval(cardLifetime)
        guard now.timeIntervalSince(state.updatedAt) >= renewAfter, runsOut < day.deadlineAt else { return false }
        if day.status == .pending, let evening = day.eveningAt, evening > now, evening <= runsOut { return false }
        return true
    }

    /// A morning card is the morning appearance; any other is the evening one.
    static func slot(of state: IconLiveActivityState) -> IconCardSlot {
        state.phase == .morning ? .morning : .evening
    }

    /// The appearance due now: the evening one from the evening reminder on.
    static func slot(of day: IconCardDay, at now: Date) -> IconCardSlot {
        if let evening = day.eveningAt, now >= evening { return .evening }
        return .morning
    }

    /// From the first reminder until the cut-off, unless the day ended otherwise.
    static func isShowable(_ day: IconCardDay, now: Date) -> Bool {
        guard day.status == .pending || day.status == .honoured,
              let opensAt = day.opensAt else { return false }
        return now >= opensAt && now < day.deadlineAt
    }

    /// The morning card goes stale at the evening reminder; the widget then
    /// shows the evening line without the app having to run. The Health total
    /// rides along in every phase, HONOURED included; without a new reading
    /// the card keeps the one it shows, and a new card starts from the last
    /// reported one.
    static func desired(
        for day: IconCardDay, now: Date, keeping current: IconLiveActivityState?
    ) -> (IconLiveActivityState, Date?) {
        var (state, stale) = phaseState(for: day, now: now, keeping: current)
        state.value = day.reading ?? current?.value ?? day.reportedValue
        return (state, stale)
    }

    private static func phaseState(
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
            var icon_metric: String? = nil
            var icon_timezone: String? = nil
        }

        let contract_id: String
        let day: String
        let session_number: Int
        let deadline_at: String
        let morning_at: String?
        let evening_at: String?
        let status: String
        var measured_value: Double? = nil
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
                deadlineAt: deadline, status: status,
                metric: row.contracts.icon_metric,
                startsAt: row.contracts.icon_timezone.flatMap { startOfDay(row.day, timeZone: $0) },
                reportedValue: row.measured_value
            )
        }
    }

    /// Midnight that starts `day` (`yyyy-MM-dd`) in the Icon's time zone.
    static func startOfDay(_ day: String, timeZone identifier: String) -> Date? {
        guard let zone = TimeZone(identifier: identifier) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: day)
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
