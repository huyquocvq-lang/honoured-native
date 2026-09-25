import XCTest

final class LiveActivityPresenterTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }()
    private let now = EngineHarness.morning

    private func record(health: [(String, HealthMetric, Double)] = [("w:primary", .steps, 8000)], day: String = "2026-09-23") -> TrackedRecord {
        let activities = health.enumerated().map { index, item in
            TrackedActivity(activityId: item.0, slot: index == 0 ? .primary : .secondary, name: item.0, mode: .health, metric: item.1, target: item.2)
        }
        let definition = ContractDefinition(
            contractId: "w", contractName: "Walk", healthDay: day, expiresAt: now.addingTimeInterval(6 * 3600),
            completionPolicy: .allHealthSlots(requiredActivityIds: activities.map(\.activityId)),
            activities: activities, timerActivityId: "w"
        )
        return TrackedRecord(
            definition: definition, occurrenceToken: UUID().uuidString, definitionGeneration: 1, createdSequence: 1,
            focusSequence: 1, presentation: .active, presentationReason: nil, activityKitId: "card", suppressed: false,
            terminal: nil, completedAt: nil, slots: [:], slotCompletions: [], lastAppliedReadSequence: 0,
            timerRunId: nil, finishedTimer: nil, trackedAt: now, lastUpdatedAt: nil
        )
    }

    private var today: HealthDayInfo { HealthDayMath.info(containing: now, resetHour: 0, calendar: calendar) }

    func testStaleDateIsTheEarliestOfReadingAgeTimerEndAndExpiry() {
        var walk = record()
        walk.slots["w:primary"] = SlotProgress(metric: .steps, value: 100, dataStatus: .fresh, measuredAt: now.addingTimeInterval(-600))
        var content = LiveActivityPresenter.content(for: walk, timer: nil, today: today, now: now, relevanceScore: 100, previous: nil)
        XCTAssertEqual(content.staleDate, now.addingTimeInterval(-600 + LiveActivityConfig.healthStaleInterval))

        let run = TimerRunSnapshot(runId: "r", activityId: "w", activityName: "Walk", startedAt: now, endsAt: now.addingTimeInterval(300))
        walk.timerRunId = "r"
        content = LiveActivityPresenter.content(for: walk, timer: run, today: today, now: now, relevanceScore: 100, previous: nil)
        XCTAssertEqual(content.staleDate, run.endsAt, "the countdown reaching zero makes the card stale, it does not end it")
        XCTAssertEqual(content.state.timer?.finished, false)

        let other = TimerRunSnapshot(runId: "other", activityId: "w", activityName: "Walk", startedAt: now, endsAt: now.addingTimeInterval(60))
        XCTAssertNil(LiveActivityPresenter.content(for: walk, timer: other, today: today, now: now, relevanceScore: 1, previous: nil).state.timer,
                     "a different run of the same activity is not this card's timer")
    }

    func testUnchangedDisplayKeepsItsTimestampSoNoUpdateIsSent() {
        let walk = record()
        let first = LiveActivityPresenter.content(for: walk, timer: nil, today: today, now: now, relevanceScore: 100, previous: nil)
        let later = LiveActivityPresenter.content(for: walk, timer: nil, today: today, now: now.addingTimeInterval(30), relevanceScore: 100, previous: first.state)
        XCTAssertEqual(first, later)
        let rescored = LiveActivityPresenter.content(for: walk, timer: nil, today: today, now: now.addingTimeInterval(30), relevanceScore: 99, previous: first.state)
        XCTAssertNotEqual(first, rescored, "relevance is content too")
    }

    func testCompactLeadsWithTheFirstUnreachedSlotAndPastDaysShowNoHealth() {
        var two = record(health: [("w:primary", .steps, 8000), ("w:secondary", .activeEnergy, 300)])
        two.slots["w:primary"] = SlotProgress(metric: .steps, value: 9000, dataStatus: .fresh, measuredAt: now, reachedAt: now)
        let content = LiveActivityPresenter.content(for: two, timer: nil, today: today, now: now, relevanceScore: 100, previous: nil)
        XCTAssertEqual(content.state.displaySlot, "w:secondary")
        XCTAssertEqual(content.state.health.map(\.reached), [true, false])

        let yesterday = record(day: "2026-09-22")
        XCTAssertTrue(LiveActivityPresenter.content(for: yesterday, timer: nil, today: today, now: now, relevanceScore: 1, previous: nil).state.health.isEmpty)
    }

    func testFinalContentAndSize() {
        var done = record()
        done.terminal = .completed
        done.completedAt = now
        let final = LiveActivityPresenter.finalContent(for: done, now: now)
        XCTAssertEqual(final.state.status, .completed)
        XCTAssertNil(final.staleDate)
        done.terminal = .expired
        XCTAssertEqual(LiveActivityPresenter.finalContent(for: done, now: now).state.status, .ended)

        let size = LiveActivityPresenter.encodedSize(attributes: LiveActivityPresenter.attributes(for: done), state: final.state)
        XCTAssertLessThan(size, 1500, "two slots with bounded names stay far below 4 KB")
    }
}

final class HealthDayMathTests: XCTestCase {
    private func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    func testResetHourMovesTheBoundary() {
        let hcm = calendar("Asia/Ho_Chi_Minh")
        let threeAM = EngineHarness.morning.addingTimeInterval(-7 * 3600)
        XCTAssertEqual(HealthDayMath.info(containing: threeAM, resetHour: 0, calendar: hcm).day, "2026-09-23")
        let early = HealthDayMath.info(containing: threeAM, resetHour: 4, calendar: hcm)
        XCTAssertEqual(early.day, "2026-09-22")
        XCTAssertEqual(early.end, threeAM.addingTimeInterval(3600))
        XCTAssertEqual(HealthDayMath.window(forDay: "2026-09-22", resetHour: 4, calendar: hcm), early)
        XCTAssertNil(HealthDayMath.window(forDay: "2026-02-30", resetHour: 0, calendar: hcm))
    }

    func testDaylightSavingDaysAreShortAndLong() {
        let newYork = calendar("America/New_York")
        let spring = HealthDayMath.window(forDay: "2026-03-08", resetHour: 0, calendar: newYork)!
        XCTAssertEqual(spring.end.timeIntervalSince(spring.start), 23 * 3600)
        let autumn = HealthDayMath.window(forDay: "2026-11-01", resetHour: 0, calendar: newYork)!
        XCTAssertEqual(autumn.end.timeIntervalSince(autumn.start), 25 * 3600)
        let noon = spring.start.addingTimeInterval(12 * 3600)
        XCTAssertEqual(HealthDayMath.info(containing: noon, resetHour: 0, calendar: newYork), spring)
    }

    func testTheSameInstantIsADifferentDayInAnotherTimeZone() {
        let instant = ISO8601DateFormatter().date(from: "2026-09-23T20:00:00Z")!
        XCTAssertEqual(HealthDayMath.info(containing: instant, resetHour: 0, calendar: calendar("Asia/Ho_Chi_Minh")).day, "2026-09-24")
        XCTAssertEqual(HealthDayMath.info(containing: instant, resetHour: 0, calendar: calendar("America/Los_Angeles")).day, "2026-09-23")
    }
}

final class LiveActivityFormatTests: XCTestCase {
    private let us = Locale(identifier: "en_US")

    func testValuesStayCanonicalAndOnlyDisplayConverts() {
        XCTAssertEqual(HonouredLiveActivityFormat.valueText(6240, metric: "steps", displayUnit: nil, locale: us), "6,240")
        XCTAssertEqual(HonouredLiveActivityFormat.targetText(8000, metric: "steps", displayUnit: nil, locale: us), "8,000 steps")
        XCTAssertEqual(HonouredLiveActivityFormat.valueText(3200, metric: "distance_walking_running", displayUnit: "km", locale: us), "3.2 km")
        XCTAssertEqual(HonouredLiveActivityFormat.valueText(1609.344 * 3, metric: "distance_cycling", displayUnit: "mi", locale: us), "3 mi")
        XCTAssertEqual(HonouredLiveActivityFormat.valueText(3200, metric: "distance_swimming", displayUnit: "km", locale: Locale(identifier: "de_DE")), "3,2 km")
        XCTAssertEqual(HonouredLiveActivityFormat.valueText(320.4, metric: "active_energy", displayUnit: nil, locale: us), "320 kcal")
        XCTAssertEqual(HonouredLiveActivityFormat.valueText(425, metric: "sleep", displayUnit: nil, locale: us), "7 h 05 min")
        XCTAssertEqual(HonouredLiveActivityFormat.targetText(480, metric: "sleep", displayUnit: nil, locale: us), "8 h")
        XCTAssertEqual(HonouredLiveActivityFormat.valueText(18, metric: "exercise_minutes", displayUnit: nil, locale: us), "18 min")
    }

    func testShortValuesFitTheCompactSlot() {
        XCTAssertEqual(HonouredLiveActivityFormat.shortValueText(640, metric: "steps", displayUnit: nil, locale: us), "640")
        XCTAssertEqual(HonouredLiveActivityFormat.shortValueText(6249, metric: "steps", displayUnit: nil, locale: us), "6,249")
        XCTAssertEqual(HonouredLiveActivityFormat.shortValueText(12_345, metric: "steps", displayUnit: nil, locale: us), "12,345")
        XCTAssertEqual(HonouredLiveActivityFormat.shortValueText(18.4, metric: "exercise_minutes", displayUnit: nil, locale: us), "18m")
        XCTAssertEqual(HonouredLiveActivityFormat.shortValueText(425, metric: "sleep", displayUnit: nil, locale: us), "7h05")
    }

    func testProgressIsClampedAndUnknownStaysUnknown() {
        XCTAssertNil(HonouredLiveActivityFormat.progress(value: nil, target: 100))
        XCTAssertEqual(HonouredLiveActivityFormat.progress(value: 0, target: 100), 0)
        XCTAssertEqual(HonouredLiveActivityFormat.progress(value: 250, target: 100), 1)
        XCTAssertNil(HonouredLiveActivityFormat.progress(value: 5, target: 0))
    }
}
