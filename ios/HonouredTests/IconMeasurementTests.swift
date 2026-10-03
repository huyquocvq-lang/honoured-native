import XCTest

final class IconMeasurementTests: XCTestCase {
    // The shape `icon_days_to_measure()` returns through PostgREST.
    private let response = Data("""
    [
      {"contract_id": "0b7c1e7a-9d3c-4f55-8a52-2d6f0b0c1a11", "day": "2026-10-06",
       "starts_at": "2026-10-05T13:00:00+00:00", "deadline_at": "2026-10-06T12:59:00+00:00",
       "metric": "steps", "target": 8000, "unit": "count"},
      {"contract_id": "5d1f0c2e-1111-4a3b-9c7d-000000000002", "day": "2026-10-07",
       "starts_at": "2026-10-06T13:00:00.25+00:00", "deadline_at": "2026-10-07T12:59:00.5+00:00",
       "metric": "exercise_minutes", "target": 33, "unit": "minutes"}
    ]
    """.utf8)

    private func date(_ raw: String) -> Date { IconTimestamp.parse(raw)! }

    func testDecodesPostgrestRowsWithAndWithoutFractionalSeconds() throws {
        let days = try IconDayToMeasure.decodeList(from: response)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].contractId, "0b7c1e7a-9d3c-4f55-8a52-2d6f0b0c1a11")
        XCTAssertEqual(days[0].day, "2026-10-06")
        XCTAssertEqual(days[0].startsAt, date("2026-10-05T13:00:00Z"))
        XCTAssertEqual(days[0].deadlineAt, date("2026-10-06T12:59:00Z"))
        XCTAssertEqual(days[0].metric, "steps")
        XCTAssertEqual(days[0].target, 8000)
        XCTAssertEqual(days[1].deadlineAt.timeIntervalSince(date("2026-10-07T12:59:00Z")), 0.5, accuracy: 0.001)
    }

    func testEveryMetricTheServerCanVerifyIsAHealthMetric() {
        for metric in ["steps", "distance_walking_running", "distance_cycling",
                       "distance_swimming", "active_energy", "exercise_minutes"] {
            XCTAssertNotNil(HealthMetric(rawValue: metric), metric)
        }
    }

    func testUnreadableTimestampFailsTheWholeList() {
        let bad = Data(#"[{"contract_id":"x","day":"2026-10-06","starts_at":"yesterday","deadline_at":"2026-10-06T12:59:00Z","metric":"steps","target":1,"unit":"count"}]"#.utf8)
        XCTAssertThrowsError(try IconDayToMeasure.decodeList(from: bad))
    }

    func testWindowRunsToNowWhileTheDayIsOpen() throws {
        let day = try IconDayToMeasure.decodeList(from: response)[0]
        let now = date("2026-10-06T08:00:00Z")
        XCTAssertEqual(day.window(now: now), DateInterval(start: day.startsAt, end: now))
    }

    func testWindowStopsAtTheCutOff() throws {
        let day = try IconDayToMeasure.decodeList(from: response)[0]
        let window = day.window(now: date("2026-10-06T20:00:00Z"))
        XCTAssertEqual(window?.end, day.deadlineAt)
    }

    func testNoWindowBeforeTheDayStarts() throws {
        let day = try IconDayToMeasure.decodeList(from: response)[0]
        XCTAssertNil(day.window(now: date("2026-10-05T12:00:00Z")))
        XCTAssertNil(day.window(now: day.startsAt))
    }

    func testPayloadSendsTheDayBackUnchangedAndAnISOInstant() throws {
        let day = try IconDayToMeasure.decodeList(from: response)[0]
        let payload = IconMeasurementPayload(day: day, value: 6240, measuredThrough: date("2026-10-06T09:30:00Z"))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        XCTAssertEqual(json?["contractId"] as? String, day.contractId)
        XCTAssertEqual(json?["day"] as? String, "2026-10-06")
        XCTAssertEqual(json?["value"] as? Double, 6240)
        let sent = try XCTUnwrap(json?["measuredThrough"] as? String)
        XCTAssertEqual(IconTimestamp.parse(sent), date("2026-10-06T09:30:00Z"))
    }

    func testSummaryReportsWhetherAnyDayWasStamped() throws {
        let pendingOnly = try JSONDecoder().decode(
            IconMeasurementSummary.self,
            from: Data(#"{"honoured":0,"broken":0,"pending":2,"skipped":1}"#.utf8)
        )
        XCTAssertFalse(pendingOnly.stampedAny)
        let stamped = try JSONDecoder().decode(
            IconMeasurementSummary.self,
            from: Data(#"{"honoured":0,"broken":1,"pending":0,"skipped":0}"#.utf8)
        )
        XCTAssertTrue(stamped.stampedAny)
    }
}
