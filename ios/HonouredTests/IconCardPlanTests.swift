import XCTest

final class IconCardPlanTests: XCTestCase {
    // Tue 6 Oct 2026 in UTC: morning 07:00, evening 20:00, cut-off at midnight.
    private let morning = Date(timeIntervalSince1970: 1_791_270_000)        // 07:00
    private var evening: Date { morning.addingTimeInterval(13 * 3600) }     // 20:00
    private var cutoff: Date { morning.addingTimeInterval(17 * 3600) }      // 00:00 next day

    private func day(
        contract: String = "c1", iconDay: String = "2026-10-06", status: IconCardDay.Status = .pending,
        morningAt: Date?? = nil, eveningAt: Date?? = nil
    ) -> IconCardDay {
        let facts = IconCardFacts(
            contractId: contract, iconDay: iconDay, weekday: "TUE", sessionNumber: 5, totalSessions: 17,
            targetValue: "10,000", targetUnit: "STEPS", activityName: "Walking", because: "Spring", deadline: cutoff
        )
        return IconCardDay(
            facts: facts,
            morningAt: morningAt ?? morning,
            eveningAt: eveningAt ?? evening,
            deadlineAt: cutoff, status: status
        )
    }

    private func card(_ id: String, contract: String = "c1", iconDay: String = "2026-10-06",
                      state: IconLiveActivityState, stale: Date? = nil) -> RunningIconCard {
        RunningIconCard(id: id, contractId: contract, iconDay: iconDay, state: state, staleDate: stale)
    }

    func testNoCardBeforeTheFirstReminder() {
        let actions = IconCardPlan.actions(days: [day()], running: [], started: [], now: morning.addingTimeInterval(-60), canStart: true)
        XCTAssertEqual(actions, [])
    }

    func testMorningCardOpensWithTheAffirmationAndGoesStaleAtTheEveningReminder() {
        let now = morning.addingTimeInterval(600)
        let actions = IconCardPlan.actions(days: [day()], running: [], started: [], now: now, canStart: true)
        guard case let .start(facts, state, stale)? = actions.first, actions.count == 1 else {
            return XCTFail("expected one start, got \(actions)")
        }
        XCTAssertEqual(facts.iconDay, "2026-10-06")
        XCTAssertEqual(state.phase, .morning)
        XCTAssertEqual(state.line, IconCopy.affirmation(sessionNumber: 5))
        XCTAssertEqual(stale, evening)
        XCTAssertEqual(state.displayLine(isStale: true), IconCopy.eveningLine, "the widget switches lines on its own")
    }

    func testOnlyTheForegroundAppStartsCards() {
        let now = morning.addingTimeInterval(600)
        XCTAssertEqual(IconCardPlan.actions(days: [day()], running: [], started: [], now: now, canStart: false), [])
    }

    func testAStartedCardIsNeverStartedAgain() {
        let key = IconCardPlan.key(contractId: "c1", iconDay: "2026-10-06")
        let now = morning.addingTimeInterval(600)
        XCTAssertEqual(IconCardPlan.actions(days: [day()], running: [], started: [key], now: now, canStart: true), [],
                       "a card the person swiped away stays away")
    }

    func testAfterTheEveningReminderTheCardShowsTheEveningLine() {
        let now = evening.addingTimeInterval(60)
        let running = card("a", state: .morning(sessionNumber: 5, at: morning), stale: evening)
        let actions = IconCardPlan.actions(days: [day()], running: [running], started: ["x"], now: now, canStart: false)
        guard case let .update(id, state, stale)? = actions.first, actions.count == 1 else {
            return XCTFail("expected one update, got \(actions)")
        }
        XCTAssertEqual(id, "a")
        XCTAssertEqual(state.phase, .evening)
        XCTAssertNil(stale)
    }

    func testAnUnchangedCardIsLeftAlone() {
        let now = morning.addingTimeInterval(1200)
        let current = IconLiveActivityState.morning(sessionNumber: 5, at: morning)
        let running = card("a", state: current, stale: evening)
        XCTAssertEqual(IconCardPlan.actions(days: [day()], running: [running], started: [], now: now, canStart: true), [])
    }

    func testHonouredShowsTheResultUntilTheCutOff() {
        let now = morning.addingTimeInterval(4 * 3600)
        let running = card("a", state: .morning(sessionNumber: 5, at: morning), stale: evening)
        let actions = IconCardPlan.actions(days: [day(status: .honoured)], running: [running], started: [], now: now, canStart: true)
        guard case let .update(_, state, stale)? = actions.first, actions.count == 1 else {
            return XCTFail("expected one update, got \(actions)")
        }
        XCTAssertEqual(state.result, .honoured)
        XCTAssertEqual(state.line, "HONOURED")
        XCTAssertNil(stale)
    }

    func testTheCardClosesAtTheCutOffOrWhenTheDayEndsAnotherWay() {
        let running = card("a", state: .evening(at: evening))
        XCTAssertEqual(IconCardPlan.actions(days: [day()], running: [running], started: [], now: cutoff, canStart: true), [.end(id: "a")])
        let mid = morning.addingTimeInterval(3600)
        XCTAssertEqual(IconCardPlan.actions(days: [day(status: .broken)], running: [running], started: [], now: mid, canStart: true), [.end(id: "a")])
        XCTAssertEqual(IconCardPlan.actions(days: [day(status: .amended)], running: [running], started: [], now: mid, canStart: true), [.end(id: "a")])
        XCTAssertEqual(IconCardPlan.actions(days: [], running: [running], started: [], now: mid, canStart: true), [.end(id: "a")],
                       "an Icon that ended or belongs to another account")
    }

    func testADuplicateCardIsClosed() {
        let now = morning.addingTimeInterval(600)
        let state = IconLiveActivityState.morning(sessionNumber: 5, at: morning)
        let actions = IconCardPlan.actions(
            days: [day()], running: [card("a", state: state, stale: evening), card("b", state: state, stale: evening)],
            started: [], now: now, canStart: true
        )
        XCTAssertEqual(actions, [.end(id: "b")])
    }

    func testRemindersOffMeansNoCard() {
        let off = day(morningAt: .some(nil), eveningAt: .some(nil))
        XCTAssertEqual(IconCardPlan.actions(days: [off], running: [], started: [], now: morning.addingTimeInterval(600), canStart: true), [])
    }

    func testEveningOnlyOpensAtTheEveningReminderWithoutAStaleDate() {
        let eveningOnly = day(morningAt: .some(nil))
        XCTAssertEqual(IconCardPlan.actions(days: [eveningOnly], running: [], started: [], now: morning.addingTimeInterval(600), canStart: true), [])
        let actions = IconCardPlan.actions(days: [eveningOnly], running: [], started: [], now: evening.addingTimeInterval(60), canStart: true)
        guard case let .start(_, state, stale)? = actions.first else { return XCTFail("expected a start") }
        XCTAssertEqual(state.phase, .evening)
        XCTAssertNil(stale)
    }

    // MARK: - Server rows and text

    func testDecodesIconDaysWithTheirContract() throws {
        let json = Data("""
        [{"contract_id":"uuid-1","day":"2026-10-06","session_number":5,
          "deadline_at":"2026-10-06T14:00:00+00:00","morning_at":"2026-10-05T20:00:00+00:00","evening_at":null,
          "status":"pending",
          "contracts":{"client_id":"local-1","primary_activity":"Walking","primary_target":"10000 steps","because":"Spring","status":"active"}}]
        """.utf8)
        let days = try IconCardRows.days(from: json, totals: ["uuid-1": 92])
        XCTAssertEqual(days.count, 1)
        let first = try XCTUnwrap(days.first)
        XCTAssertEqual(first.facts.contractId, "local-1")
        XCTAssertEqual(first.facts.sessionLabel, "TUE · 5 OF 92")
        XCTAssertEqual(first.facts.targetValue, "10,000")
        XCTAssertEqual(first.facts.targetUnit, "STEPS")
        XCTAssertEqual(first.deadlineAt, IconTimestamp.parse("2026-10-06T14:00:00Z"))
        XCTAssertNil(first.eveningAt)
        XCTAssertEqual(first.status, .pending)
    }

    func testTargetTextSplitsNumberAndUnit() {
        XCTAssertEqual(IconTargetText.split("10000 steps").value, "10,000")
        XCTAssertEqual(IconTargetText.split("10000 steps").unit, "STEPS")
        XCTAssertEqual(IconTargetText.split("33 min").value, "33")
        XCTAssertEqual(IconTargetText.split("2.5 km").value, "2.5")
        XCTAssertEqual(IconTargetText.split("2.5 km").unit, "KM")
        XCTAssertEqual(IconTargetText.split("Read daily").value, "Read daily")
        XCTAssertEqual(IconTargetText.split("Read daily").unit, "")
        XCTAssertEqual(IconTargetText.weekday(of: "2026-10-06"), "TUE")
        XCTAssertEqual(IconTargetText.weekday(of: "2027-01-01"), "FRI")
        XCTAssertNil(IconTargetText.weekday(of: "not a day"))
    }
}
