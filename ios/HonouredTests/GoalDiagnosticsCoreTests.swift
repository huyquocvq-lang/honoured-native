import XCTest

final class GoalDiagnosticsCoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_792_000_000)

    private func json(_ row: GoalDiagnosticsRow) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any])
    }

    func testRecordedMomentHasATimeAndNoWindow() throws {
        var event = GoalDiagnosticsEvent.recorded("goal_detected", at: t0, userId: "u1", now: t0.addingTimeInterval(1))
        event.source = "core_motion"
        event.value = 10_050
        let row = try json(event.row(sentAt: t0.addingTimeInterval(60)))
        XCTAssertEqual(row["certainty"] as? String, "recorded")
        XCTAssertEqual(row["event"] as? String, "goal_detected")
        XCTAssertEqual(row["source"] as? String, "core_motion")
        XCTAssertEqual(row["value"] as? Double, 10_050)
        XCTAssertNotNil(row["occurredAt"] as? String)
        XCTAssertNil(row["windowStart"] as? String)
        XCTAssertNil(row["method"] as? String)
        XCTAssertNotNil(row["deviceTime"] as? String)
        XCTAssertNotNil(row["sentAt"] as? String)
        XCTAssertNil(row["userId"], "the server takes the account from the session, never from the row")
    }

    func testEstimateAlwaysCarriesItsWindowAndMethod() throws {
        let event = try XCTUnwrap(GoalDiagnosticsEvent.estimated(
            "goal_crossed", from: t0, to: t0.addingTimeInterval(60), method: "motion_query", userId: "u1"
        ))
        XCTAssertNil(event.occurredAt)
        let row = try json(event.row(sentAt: t0))
        XCTAssertEqual(row["certainty"] as? String, "estimated")
        XCTAssertEqual(row["method"] as? String, "motion_query")
        XCTAssertNotNil(row["windowStart"] as? String)
        XCTAssertNotNil(row["windowEnd"] as? String)
        XCTAssertNil(row["occurredAt"] as? String)
    }

    func testABackwardWindowIsNoEstimateAtAll() {
        XCTAssertNil(GoalDiagnosticsEvent.estimated("goal_crossed", from: t0, to: t0.addingTimeInterval(-1), method: "x", userId: "u1"))
    }

    func testUnknownHasNoTimeToBorrow() throws {
        let event = GoalDiagnosticsEvent.unknown("notification_delivered", userId: "u1")
        XCTAssertNil(event.occurredAt)
        XCTAssertNil(event.windowStart)
        XCTAssertNil(event.windowEnd)
        let row = try json(event.row(sentAt: t0))
        XCTAssertEqual(row["certainty"] as? String, "unknown")
    }

    func testEventsSurviveTheLocalFile() throws {
        var event = GoalDiagnosticsEvent.recorded("reading", at: t0, userId: "u1")
        event.details = ["trigger": "motion_live"]
        let data = try JSONEncoder().encode(event)
        XCTAssertEqual(try JSONDecoder().decode(GoalDiagnosticsEvent.self, from: data), event)
    }

    func testDeliveryCountsOnlyWhatNotificationCenterShows() {
        let shown = GoalNotificationRequest(userId: "u1", identifier: "goal-a-2026-10-21", activityId: "a", day: "2026-10-21", requestedAt: t0)
        let waiting = GoalNotificationRequest(userId: "u1", identifier: "goal-b-2026-10-21", activityId: "b", day: "2026-10-21", requestedAt: t0)
        let lost = GoalNotificationRequest(userId: "u1", identifier: "goal-c-2026-10-20", activityId: "c", day: "2026-10-20", requestedAt: t0.addingTimeInterval(-25 * 3600))
        let deliveredAt = t0.addingTimeInterval(1)
        let outcome = GoalNotificationDeliveries.settle(
            [shown, waiting, lost],
            delivered: [shown.identifier: deliveredAt, "goal-other": t0],
            now: t0.addingTimeInterval(120)
        )
        XCTAssertEqual(outcome.delivered, [GoalNotificationDeliveries.Delivered(request: shown, at: deliveredAt)])
        XCTAssertEqual(outcome.stillPending, [waiting])
        XCTAssertEqual(outcome.unknown, [lost], "after a day without a trace the delivery is unknown, never the request time")
    }

    func testReadingsAreWrittenOnChangeOrOnceAMinute() {
        XCTAssertTrue(GoalReadingLog.shouldWrite(result: "value", at: t0, last: nil))
        let last = GoalReadingLog.Last(result: "value", at: t0)
        XCTAssertFalse(GoalReadingLog.shouldWrite(result: "value", at: t0.addingTimeInterval(3), last: last))
        XCTAssertTrue(GoalReadingLog.shouldWrite(result: "failed", at: t0.addingTimeInterval(3), last: last))
        XCTAssertTrue(GoalReadingLog.shouldWrite(result: "value", at: t0.addingTimeInterval(60), last: last))
    }

    func testCrossingIsTheIntervalThatReachedTheTarget() throws {
        let minutes = (0..<5).map { i in
            (start: t0.addingTimeInterval(Double(i) * 60), end: t0.addingTimeInterval(Double(i + 1) * 60), value: 40.0)
        }
        // 9,900 before the window: the target falls in the third minute.
        let window = try XCTUnwrap(GoalCrossingEstimate.window(target: 10_000, before: 9_900, intervals: minutes))
        XCTAssertEqual(window.start, t0.addingTimeInterval(120))
        XCTAssertEqual(window.end, t0.addingTimeInterval(180))
        XCTAssertNil(GoalCrossingEstimate.window(target: 10_000, before: 9_000, intervals: minutes), "never reached in the window")
        XCTAssertNil(GoalCrossingEstimate.window(target: 10_000, before: 10_000, intervals: minutes), "already met before it")
    }

    func testCrossingNeverClaimsMoreThanTheReadingsProve() {
        let window = DateInterval(start: t0, end: t0.addingTimeInterval(60))
        let bounded = GoalCrossingEstimate.bounded(window, notBefore: t0.addingTimeInterval(20), notAfter: t0.addingTimeInterval(50))
        XCTAssertEqual(bounded, DateInterval(start: t0.addingTimeInterval(20), end: t0.addingTimeInterval(50)))
        let outside = GoalCrossingEstimate.bounded(window, notBefore: t0.addingTimeInterval(90), notAfter: t0.addingTimeInterval(120))
        XCTAssertEqual(outside, window, "contradicting bounds leave the window as found")
    }

    func testNarrowingFindsTheMinuteFromTheRunningTotal() async throws {
        // 100 steps a minute from t0: 10,000 is reached at minute 37 of a
        // day that started with 6,300 already counted.
        let total: (Date) async -> Double? = { moment in
            6_300 + max(0, moment.timeIntervalSince(self.t0) / 60) * 100
        }
        var reads = 0
        let found = await GoalCrossingEstimate.narrow(
            target: 10_000, below: t0, reached: t0.addingTimeInterval(24 * 3600), resolution: 60
        ) { moment in
            reads += 1
            return await total(moment)
        }
        let window = try XCTUnwrap(found)
        XCTAssertLessThanOrEqual(window.duration, 60)
        XCTAssertLessThanOrEqual(window.start, t0.addingTimeInterval(37 * 60))
        XCTAssertGreaterThanOrEqual(window.end, t0.addingTimeInterval(37 * 60))
        XCTAssertLessThanOrEqual(reads, 11, "a whole day narrows to the minute in about a dozen reads")
    }

    func testNarrowingGivesUpWhenAReadFails() async {
        let window = await GoalCrossingEstimate.narrow(target: 10, below: t0, reached: t0.addingTimeInterval(600), resolution: 60) { _ in nil }
        XCTAssertNil(window)
    }

    func testUploadsWaitLongerAfterEachFailure() {
        XCTAssertEqual(GoalDiagnosticsUploadBackoff.delay(failures: 1, status: 500), 15 * 60)
        XCTAssertEqual(GoalDiagnosticsUploadBackoff.delay(failures: 2, status: nil), 30 * 60)
        XCTAssertEqual(GoalDiagnosticsUploadBackoff.delay(failures: 3, status: 503), 60 * 60)
        XCTAssertEqual(GoalDiagnosticsUploadBackoff.delay(failures: 30, status: nil), 6 * 60 * 60, "never more than six hours")
        XCTAssertEqual(GoalDiagnosticsUploadBackoff.delay(failures: 1, status: 404), 24 * 60 * 60, "no server function yet: a day")
    }

    func testChunksCoverTheWindowExactly() {
        let chunks = GoalCrossingEstimate.chunks(from: t0, to: t0.addingTimeInterval(150), step: 60)
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks.first?.start, t0)
        XCTAssertEqual(chunks.last?.end, t0.addingTimeInterval(150))
        XCTAssertTrue(GoalCrossingEstimate.chunks(from: t0, to: t0, step: 60).isEmpty)
    }
}
