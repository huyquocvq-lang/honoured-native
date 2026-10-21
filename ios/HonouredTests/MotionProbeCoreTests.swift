import XCTest

final class MotionProbeCoreTests: XCTestCase {
    private let t0 = ISO8601DateFormatter().date(from: "2026-10-18T07:00:00Z")!

    private func minutes(_ counts: [Double]) -> [MotionProbeInterval] {
        counts.enumerated().map { index, value in
            MotionProbeInterval(
                start: t0.addingTimeInterval(Double(index) * 60),
                end: t0.addingTimeInterval(Double(index + 1) * 60),
                value: value
            )
        }
    }

    func testCrossingIsTheMinuteTheRunningTotalReachesTheTarget() {
        let crossing = MotionProbeMath.crossing(of: 1_000, in: minutes([300, 400, 250, 120, 500]))
        XCTAssertEqual(crossing?.windowStart, t0.addingTimeInterval(180))
        XCTAssertEqual(crossing?.windowEnd, t0.addingTimeInterval(240))
        XCTAssertEqual(crossing?.totalBefore, 950)
        XCTAssertEqual(crossing?.totalAfter, 1_070)
    }

    func testCrossingExactlyAtTheTargetCounts() {
        let crossing = MotionProbeMath.crossing(of: 700, in: minutes([300, 400, 10]))
        XCTAssertEqual(crossing?.windowEnd, t0.addingTimeInterval(120))
    }

    func testNoCrossingBelowTheTargetOrWithoutATarget() {
        XCTAssertNil(MotionProbeMath.crossing(of: 5_000, in: minutes([300, 400])))
        XCTAssertNil(MotionProbeMath.crossing(of: 0, in: minutes([300])))
        XCTAssertNil(MotionProbeMath.crossing(of: 100, in: []))
    }

    func testIntervalsAreSortedAndNegativeCountsIgnored() {
        let shuffled = Array(minutes([600, -50, 500]).reversed())
        XCTAssertEqual(MotionProbeMath.crossing(of: 1_000, in: shuffled)?.windowStart, t0.addingTimeInterval(120))
    }

    func testDelayIsARangeAcrossTheCrossingWindow() {
        let crossing = MotionProbeCrossing(
            windowStart: t0, windowEnd: t0.addingTimeInterval(60), totalBefore: 990, totalAfter: 1_020
        )
        let range = MotionProbeMath.delayRange(from: crossing, to: t0.addingTimeInterval(420))
        XCTAssertEqual(range, 360...420)
        XCTAssertEqual(MotionProbeMath.delayText(range), "6–7 min")
        XCTAssertEqual(MotionProbeMath.delayText(MotionProbeMath.delayRange(from: crossing, to: t0.addingTimeInterval(75))), "15–75 s")
    }

    func testSessionReadsNarrowTheMinuteWindow() {
        // The 19 Oct T1 run: re-read minute 07:25:27–07:26:27, live 98 steps
        // at 07:25:32.151 and 100 at 07:25:34.710.
        let minute = MotionProbeCrossing(
            windowStart: t0, windowEnd: t0.addingTimeInterval(60), totalBefore: 96, totalAfter: 124
        )
        let narrowed = MotionProbeMath.narrowed(
            minute, notBefore: t0.addingTimeInterval(4.939), notAfter: t0.addingTimeInterval(7.498)
        )
        XCTAssertEqual(narrowed.windowStart, t0.addingTimeInterval(4.939))
        XCTAssertEqual(narrowed.windowEnd, t0.addingTimeInterval(7.498))
        let noticed = MotionProbeMath.delayRange(from: narrowed, to: t0.addingTimeInterval(7.498))
        XCTAssertEqual(noticed.lowerBound, 0, accuracy: 0.001)
        XCTAssertEqual(MotionProbeMath.delayText(noticed), "0–3 s")
    }

    func testBoundsOutsideTheWindowAreIgnored() {
        let minute = MotionProbeCrossing(
            windowStart: t0, windowEnd: t0.addingTimeInterval(60), totalBefore: 96, totalAfter: 124
        )
        XCTAssertEqual(MotionProbeMath.narrowed(minute, notBefore: t0.addingTimeInterval(-30), notAfter: t0.addingTimeInterval(90)), minute)
        XCTAssertEqual(MotionProbeMath.narrowed(minute, notBefore: nil, notAfter: nil), minute)
        // A bound that would leave nothing is dropped rather than inverting the window.
        let inverted = MotionProbeMath.narrowed(minute, notBefore: t0.addingTimeInterval(50), notAfter: t0.addingTimeInterval(20))
        XCTAssertLessThanOrEqual(inverted.windowStart, inverted.windowEnd)
    }

    func testWindowsCoverTheSpanAndKeepTheMostRecent() {
        let windows = MotionProbeMath.windows(from: t0, to: t0.addingTimeInterval(150))
        XCTAssertEqual(windows.map(\.duration), [60, 60, 30])
        XCTAssertEqual(windows.last?.end, t0.addingTimeInterval(150))
        let capped = MotionProbeMath.windows(from: t0, to: t0.addingTimeInterval(600), limit: 3)
        XCTAssertEqual(capped.first?.start, t0.addingTimeInterval(420))
        XCTAssertTrue(MotionProbeMath.windows(from: t0, to: t0).isEmpty)
    }

    func testCalorieEstimateDependsOnGait() {
        let walk = MotionProbeMath.estimatedActiveKilocalories(distanceMeters: 2_000, activeSeconds: 1_500)
        XCTAssertEqual(walk.gait, .walking)
        XCTAssertEqual(walk.kilocalories, 70, accuracy: 0.001)
        let run = MotionProbeMath.estimatedActiveKilocalories(distanceMeters: 2_000, activeSeconds: 660)
        XCTAssertEqual(run.gait, .running)
        XCTAssertEqual(run.kilocalories, 140, accuracy: 0.001)
        XCTAssertEqual(MotionProbeMath.estimatedActiveKilocalories(distanceMeters: 0, activeSeconds: nil).kilocalories, 0)
    }

    func testMinuteCSVListsEverySourceAndKeepsUnreadMinutesEmpty() {
        var utc7 = Calendar(identifier: .gregorian)
        utc7.timeZone = TimeZone(secondsFromGMT: 7 * 3600)!
        let csv = MotionProbeCSV.minutes([
            MotionProbeMinute(start: t0, coreMotion: 96, healthKit: 90,
                              healthKitBySource: ["Watch, left": 90, "iPhone": 88]),
            MotionProbeMinute(start: t0.addingTimeInterval(60), coreMotion: nil, healthKit: 0,
                              healthKitBySource: [:])
        ], calendar: utc7)
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "minute_start,local_time,core_motion,healthkit_combined,\"healthkit:Watch, left\",healthkit:iPhone")
        XCTAssertEqual(lines.dropFirst().first, "2026-10-18T07:00:00.000Z,14:00,96,90,90,88")
        // A minute Core Motion could not read stays empty, never 0.
        XCTAssertEqual(lines.last, "2026-10-18T07:01:00.000Z,14:01,,0,,")
    }

    func testEventLinesRoundTripWithMilliseconds() throws {
        let event = MotionProbeEvent(
            at: t0.addingTimeInterval(0.25), event: "goal_crossed", certainty: .estimated,
            source: "core_motion", numbers: ["total_after": 1_020], notes: ["method": "motion_query_1min"]
        )
        let line = try event.jsonLine()
        XCTAssertFalse(line.contains("\n"))
        XCTAssertTrue(line.contains("\"certainty\":\"estimated\""))
        XCTAssertTrue(line.contains("2026-10-18T07:00:00.250Z"))
        XCTAssertEqual(MotionProbeEvent.parse(line: line), event)
        XCTAssertNil(MotionProbeEvent.parse(line: "not json"))
    }
}
