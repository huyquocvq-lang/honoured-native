import XCTest

final class IconCardPlanTests: XCTestCase {
    // Tue 6 Oct 2026 in UTC: morning 07:00, evening 20:00, cut-off at midnight.
    private let morning = Date(timeIntervalSince1970: 1_791_270_000)        // 07:00
    private var evening: Date { morning.addingTimeInterval(13 * 3600) }     // 20:00
    private var cutoff: Date { morning.addingTimeInterval(17 * 3600) }      // 00:00 next day

    private func day(
        contract: String = "c1", iconDay: String = "2026-10-06", status: IconCardDay.Status = .pending,
        morningAt: Date?? = nil, eveningAt: Date?? = nil, reading: Double? = nil, reported: Double? = nil
    ) -> IconCardDay {
        let facts = IconCardFacts(
            contractId: contract, iconDay: iconDay, weekday: "TUE", sessionNumber: 5, totalSessions: 17,
            targetValue: "10,000", targetUnit: "STEPS", activityName: "Walking", because: "Spring", deadline: cutoff
        )
        return IconCardDay(
            facts: facts,
            morningAt: morningAt ?? morning,
            eveningAt: eveningAt ?? evening,
            deadlineAt: cutoff, status: status, reading: reading, reportedValue: reported
        )
    }

    private func card(_ id: String, contract: String = "c1", iconDay: String = "2026-10-06",
                      state: IconLiveActivityState, stale: Date? = nil, isActive: Bool = true) -> RunningIconCard {
        RunningIconCard(id: id, contractId: contract, iconDay: iconDay, state: state, staleDate: stale, isActive: isActive)
    }

    func testNoCardBeforeTheFirstReminder() {
        let actions = IconCardPlan.actions(days: [day()], running: [], started: [], now: morning.addingTimeInterval(-60), canStart: true)
        XCTAssertEqual(actions, [])
    }

    func testMorningCardOpensWithTheAffirmationAndGoesStaleAtTheEveningReminder() {
        let now = morning.addingTimeInterval(600)
        let actions = IconCardPlan.actions(days: [day()], running: [], started: [], now: now, canStart: true)
        guard case let .start(facts, state, stale, slot)? = actions.first, actions.count == 1 else {
            return XCTFail("expected one start, got \(actions)")
        }
        XCTAssertEqual(slot, .morning)
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

    private var key: String { IconCardPlan.key(contractId: "c1", iconDay: "2026-10-06") }
    private var morningShown: String { IconCardPlan.startedKey(key, slot: .morning) }
    private var eveningShown: String { IconCardPlan.startedKey(key, slot: .evening) }
    private var afterGrace: Date { evening.addingTimeInterval(IconCardPlan.eveningGrace + 60) }

    func testAStartedAppearanceIsNeverStartedAgain() {
        let now = morning.addingTimeInterval(600)
        XCTAssertEqual(IconCardPlan.actions(days: [day()], running: [], started: [morningShown], now: now, canStart: true), [],
                       "a morning card the person swiped away stays away")
    }

    func testAtTheEveningReminderTheMorningCardWaitsForTheServersCard() {
        let running = card("a", state: .morning(sessionNumber: 5, at: morning), stale: evening)
        let now = evening.addingTimeInterval(60)
        XCTAssertEqual(IconCardPlan.actions(days: [day()], running: [running], started: [morningShown], now: now, canStart: true), [],
                       "the server push-starts the evening card within a minute; the stale date shows the evening line meanwhile")
    }

    func testAfterTheGraceTheMorningCardMakesWayForAFreshEveningCard() {
        // iOS ends a card 8 hours after it starts: a 07:00 card is gone before 20:00.
        let running = card("a", state: .morning(sessionNumber: 5, at: morning), stale: evening)
        let actions = IconCardPlan.actions(days: [day()], running: [running], started: [morningShown], now: afterGrace, canStart: true)
        guard actions.count == 2, actions[0] == .end(id: "a"),
              case let .start(_, state, stale, slot) = actions[1] else {
            return XCTFail("expected the morning card to end and an evening card to start, got \(actions)")
        }
        XCTAssertEqual(slot, .evening)
        XCTAssertEqual(state.phase, .evening)
        XCTAssertEqual(state.line, IconCopy.eveningLine)
        XCTAssertNil(stale)
    }

    func testInTheBackgroundTheMorningCardStaysThroughTheEvening() {
        let running = card("a", state: .morning(sessionNumber: 5, at: morning), stale: evening)
        XCTAssertEqual(IconCardPlan.actions(days: [day()], running: [running], started: [morningShown], now: afterGrace, canStart: false), [],
                       "closing it without opening another would leave nothing")
    }

    func testTheServersEveningCardIsKeptAndTheMorningCardClosed() {
        let morningCard = card("a", state: .morning(sessionNumber: 5, at: morning), stale: evening)
        let eveningCard = card("b", state: .evening(at: evening))
        let now = evening.addingTimeInterval(60)
        XCTAssertEqual(IconCardPlan.actions(days: [day()], running: [morningCard, eveningCard], started: [morningShown, eveningShown],
                                            now: now, canStart: true), [.end(id: "a")])
    }

    func testASwipedAwayMorningCardDoesNotStopTheEveningCard() {
        let actions = IconCardPlan.actions(days: [day()], running: [], started: [morningShown], now: afterGrace, canStart: true)
        guard case let .start(_, state, _, slot)? = actions.first, actions.count == 1 else {
            return XCTFail("expected the evening card, got \(actions)")
        }
        XCTAssertEqual(slot, .evening)
        XCTAssertEqual(state.phase, .evening)
        XCTAssertEqual(IconCardPlan.actions(days: [day()], running: [], started: [morningShown, eveningShown], now: afterGrace, canStart: true), [],
                       "a swiped-away evening card stays away")
    }

    func testAnHonouredDayKeepsItsCardThroughTheEvening() {
        // A card from 19:30: it reaches the cut-off, so it is not renewed.
        let running = card("a", state: .morning(sessionNumber: 5, at: evening.addingTimeInterval(-1800)), stale: evening)
        let actions = IconCardPlan.actions(days: [day(status: .honoured)], running: [running], started: [morningShown], now: afterGrace, canStart: true)
        guard case let .update(id, state, _)? = actions.first, actions.count == 1 else {
            return XCTFail("expected the card to show the result, got \(actions)")
        }
        XCTAssertEqual(id, "a")
        XCTAssertEqual(state.result, .honoured)
    }

    func testAnUnchangedCardIsLeftAlone() {
        let now = morning.addingTimeInterval(1200)
        let current = IconLiveActivityState.morning(sessionNumber: 5, at: morning)
        let running = card("a", state: current, stale: evening)
        XCTAssertEqual(IconCardPlan.actions(days: [day()], running: [running], started: [], now: now, canStart: true), [])
    }

    func testHonouredShowsTheResultUntilTheCutOff() {
        let now = morning.addingTimeInterval(1800)
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

    func testEveningOnlyOpensAfterTheEveningReminderWithoutAStaleDate() {
        let eveningOnly = day(morningAt: .some(nil))
        XCTAssertEqual(IconCardPlan.actions(days: [eveningOnly], running: [], started: [], now: morning.addingTimeInterval(600), canStart: true), [])
        XCTAssertEqual(IconCardPlan.actions(days: [eveningOnly], running: [], started: [], now: evening.addingTimeInterval(60), canStart: true), [],
                       "left to the server's push during the grace period")
        let actions = IconCardPlan.actions(days: [eveningOnly], running: [], started: [], now: afterGrace, canStart: true)
        guard case let .start(_, state, stale, slot)? = actions.first else { return XCTFail("expected a start") }
        XCTAssertEqual(slot, .evening)
        XCTAssertEqual(state.phase, .evening)
        XCTAssertNil(stale)
    }

    // MARK: - Health total in the Dynamic Island

    func testTheCardShowsTheDaysHealthTotalAndFollowsIt() {
        let now = morning.addingTimeInterval(1200)
        let running = card("a", state: .morning(sessionNumber: 5, at: morning), stale: evening)
        let actions = IconCardPlan.actions(days: [day(reading: 4_200)], running: [running], started: [], now: now, canStart: true)
        guard case let .update(id, state, stale)? = actions.first, actions.count == 1 else {
            return XCTFail("expected the reading to update the card, got \(actions)")
        }
        XCTAssertEqual(id, "a")
        XCTAssertEqual(state.value, 4_200)
        XCTAssertEqual(state.phase, .morning)
        XCTAssertEqual(stale, evening)
    }

    func testWithoutANewReadingTheCardKeepsItsTotal() {
        let now = morning.addingTimeInterval(1200)
        var current = IconLiveActivityState.morning(sessionNumber: 5, at: morning)
        current.value = 4_200
        let running = card("a", state: current, stale: evening)
        XCTAssertEqual(IconCardPlan.actions(days: [day()], running: [running], started: [], now: now, canStart: true), [],
                       "a failed read (locked device) changes nothing")
        XCTAssertEqual(IconCardPlan.actions(days: [day(reading: 4_200)], running: [running], started: [], now: now, canStart: true), [])
    }

    func testAfterHonouredTheCardStillFollowsTheTotal() {
        let now = morning.addingTimeInterval(6 * 3600)
        var current = IconLiveActivityState.result(.honoured, at: morning)
        current.value = 10_400
        let running = card("a", state: current)
        // In the background (a Health delivery): the open app would renew it instead.
        let actions = IconCardPlan.actions(days: [day(status: .honoured, reading: 12_382)], running: [running], started: [], now: now, canStart: false)
        guard case let .update(_, state, _)? = actions.first, actions.count == 1 else {
            return XCTFail("expected one update, got \(actions)")
        }
        XCTAssertEqual(state.result, .honoured)
        XCTAssertEqual(state.line, "HONOURED")
        XCTAssertEqual(state.value, 12_382)
    }

    func testANewCardStartsWithTheTotal() {
        let actions = IconCardPlan.actions(days: [day(reading: 2_000)], running: [], started: [], now: morning.addingTimeInterval(600), canStart: true)
        guard case let .start(_, state, _, _)? = actions.first else { return XCTFail("expected a start") }
        XCTAssertEqual(state.value, 2_000)
    }

    func testAfterHonouredAFailedReadKeepsTheCardsTotal() {
        // The server stops taking reports once the day is stamped, so its
        // total can be behind the card; a locked device must not roll it back.
        let now = morning.addingTimeInterval(6 * 3600)
        var current = IconLiveActivityState.result(.honoured, at: morning)
        current.value = 12_382
        let running = card("a", state: current)
        let days = [day(status: .honoured, reported: 10_050)]
        XCTAssertEqual(IconCardPlan.actions(days: days, running: [running], started: [], now: now, canStart: false), [])
    }

    func testWithoutAReadingANewCardStartsFromTheReportedTotal() {
        let days = [day(reported: 3_000)]
        let actions = IconCardPlan.actions(days: days, running: [], started: [], now: morning.addingTimeInterval(600), canStart: true)
        guard case let .start(_, state, _, _)? = actions.first else { return XCTFail("expected a start") }
        XCTAssertEqual(state.value, 3_000)
    }

    func testAReadingWinsOverTheReportedTotal() {
        let days = [day(reading: 3_400, reported: 3_000)]
        let actions = IconCardPlan.actions(days: days, running: [], started: [], now: morning.addingTimeInterval(600), canStart: true)
        guard case let .start(_, state, _, _)? = actions.first else { return XCTFail("expected a start") }
        XCTAssertEqual(state.value, 3_400)
    }

    // MARK: - Renewal before iOS ends a card at 8 hours (client, Oct 6)

    func testInTheForegroundAnOldCardIsSwappedForAFreshOne() {
        // 07:00 card, open at 09:00: it would run out at 15:00, before the
        // 20:00 evening card and the midnight cut-off.
        let now = morning.addingTimeInterval(2 * 3600)
        var current = IconLiveActivityState.morning(sessionNumber: 5, at: morning)
        current.value = 3_100
        let actions = IconCardPlan.actions(days: [day(reading: 3_400)], running: [card("a", state: current, stale: evening)],
                                           started: [morningShown], now: now, canStart: true)
        guard actions.count == 2, case let .start(_, state, stale, slot) = actions[0], actions[1] == .end(id: "a") else {
            return XCTFail("expected a fresh card, then the old one closed, got \(actions)")
        }
        XCTAssertEqual(slot, .morning)
        XCTAssertEqual(state.phase, .morning)
        XCTAssertEqual(state.line, IconCopy.affirmation(sessionNumber: 5))
        XCTAssertEqual(state.updatedAt, now, "the fresh card dates from now")
        XCTAssertEqual(state.value, 3_400)
        XCTAssertEqual(stale, evening)
    }

    func testAnHonouredCardIsRenewedWithItsResultAndTotal() {
        var current = IconLiveActivityState.result(.honoured, at: morning)
        current.value = 10_400
        let now = morning.addingTimeInterval(5 * 3600)
        let actions = IconCardPlan.actions(days: [day(status: .honoured, reading: 12_382)], running: [card("a", state: current)],
                                           started: [morningShown], now: now, canStart: true)
        guard actions.count == 2, case let .start(_, state, stale, _) = actions[0], actions[1] == .end(id: "a") else {
            return XCTFail("expected the card renewed, got \(actions)")
        }
        XCTAssertEqual(state.result, .honoured)
        XCTAssertEqual(state.line, "HONOURED")
        XCTAssertEqual(state.value, 12_382)
        XCTAssertNil(stale)
    }

    func testACardIsNotRenewedWhenItNeedNotBe() {
        let young = card("a", state: .morning(sessionNumber: 5, at: morning), stale: evening)
        XCTAssertEqual(IconCardPlan.actions(days: [day()], running: [young], started: [morningShown],
                                            now: morning.addingTimeInterval(50 * 60), canStart: true), [],
                       "under an hour old")
        XCTAssertEqual(IconCardPlan.actions(days: [day()], running: [young], started: [morningShown],
                                            now: morning.addingTimeInterval(2 * 3600), canStart: false), [],
                       "the app cannot start a card in the background")
        let afternoon = morning.addingTimeInterval(6 * 3600) // 13:00: runs out at 21:00, after the 20:00 evening card
        XCTAssertEqual(IconCardPlan.actions(days: [day()], running: [card("a", state: .morning(sessionNumber: 5, at: afternoon), stale: evening)],
                                            started: [morningShown], now: afternoon.addingTimeInterval(5400), canStart: true), [],
                       "the evening card comes first")
        let late = morning.addingTimeInterval(10 * 3600) // 17:00: runs out at 01:00, after the cut-off
        XCTAssertEqual(IconCardPlan.actions(days: [day(status: .honoured)], running: [card("a", state: .result(.honoured, at: late))],
                                            started: [morningShown], now: late.addingTimeInterval(5400), canStart: true), [],
                       "it reaches the cut-off")
    }

    func testACardIOSEndedAtEightHoursComesBackWhenTheAppOpens() {
        let lapsed = card("a", state: .morning(sessionNumber: 5, at: morning), stale: evening, isActive: false)
        let now = morning.addingTimeInterval(8.5 * 3600)
        let actions = IconCardPlan.actions(days: [day()], running: [lapsed], started: [morningShown], now: now, canStart: true)
        guard case let .start(_, state, stale, slot)? = actions.first, actions.count == 1 else {
            return XCTFail("expected the card back, got \(actions)")
        }
        XCTAssertEqual(slot, .morning)
        XCTAssertEqual(state.updatedAt, now)
        XCTAssertEqual(stale, evening)
        XCTAssertEqual(IconCardPlan.actions(days: [day()], running: [lapsed], started: [morningShown], now: now, canStart: false), [],
                       "nothing to update on an ended card")
        XCTAssertEqual(IconCardPlan.actions(days: [day()], running: [], started: [morningShown], now: now, canStart: true), [],
                       "a card the person removed stays away")
    }

    func testOfTwoCardsTheNewerStays() {
        let older = card("a", state: .morning(sessionNumber: 5, at: morning), stale: evening)
        let newer = card("b", state: .morning(sessionNumber: 5, at: morning.addingTimeInterval(5 * 3600)), stale: evening)
        let now = morning.addingTimeInterval(5 * 3600 + 600)
        XCTAssertEqual(IconCardPlan.actions(days: [day()], running: [older, newer], started: [morningShown], now: now, canStart: true),
                       [.end(id: "a")], "the server's renewal replaced it; the old one closes")
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
        XCTAssertNil(first.metric, "rows from before the reading was selected")
        XCTAssertNil(first.reportedValue)
        XCTAssertNil(first.reading)
    }

    func testDecodesTheMetricTheDayStartAndTheLastReading() throws {
        let json = Data("""
        [{"contract_id":"uuid-1","day":"2026-10-06","session_number":5,
          "deadline_at":"2026-10-06T13:00:00+00:00","morning_at":null,"evening_at":null,
          "status":"honoured","measured_value":12382,
          "contracts":{"client_id":"local-1","primary_activity":"Walking","primary_target":"10000 steps","because":"Spring",
                       "status":"active","icon_metric":"steps","icon_timezone":"Australia/Sydney"}}]
        """.utf8)
        let first = try XCTUnwrap(try IconCardRows.days(from: json, totals: [:]).first)
        XCTAssertEqual(first.metric, "steps")
        XCTAssertEqual(first.reportedValue, 12_382)
        XCTAssertNil(first.reading, "the server's report is not this device's reading")
        // Midnight in Sydney (UTC+11 since the 4 Oct clock change).
        XCTAssertEqual(first.startsAt, IconTimestamp.parse("2026-10-05T13:00:00Z"))
        XCTAssertEqual(first.status, .honoured)
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
