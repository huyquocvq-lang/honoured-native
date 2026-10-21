import XCTest

/// Event sequences from the 19 Oct device runs (UTC; the tester's clock is UTC+7).
final class MotionProbeTimelineTests: XCTestCase {
    private func date(_ time: String) -> Date {
        MotionProbeCoding.date("2026-10-19T\(time)Z")!
    }

    private func lifecycle(_ time: String, _ reason: String) -> MotionProbeEvent {
        MotionProbeEvent(at: date(time), event: "lifecycle", reason: reason)
    }

    private func run(_ time: String, _ reason: String, state: String, locked: Bool = false) -> MotionProbeEvent {
        MotionProbeEvent(at: date(time), event: "app_ran", reason: reason,
                         notes: ["app_state": state, "protected_data": locked ? "locked" : "available"])
    }

    private func clock(_ moment: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 7 * 3600)
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: moment)
    }

    func testLockWithHonouredOnScreenEndsAtTheUnlock() {
        let events = [
            run("09:21:20.705", "probe_screen", state: "active"),
            lifecycle("09:21:42.212", "did_enter_background"),
            lifecycle("09:21:42.384", "protected_data_will_become_unavailable"),
            lifecycle("09:29:23.941", "will_enter_foreground"),
            MotionProbeEvent(at: date("09:29:23.965"), event: "healthkit_callback", reason: "steps"),
            run("09:29:24.028", "protected_data_available", state: "inactive"),
            MotionProbeEvent(at: date("09:30:20.492"), event: "reading", source: "healthkit",
                             notes: ["result": "no_data", "scope": "session"]),
            MotionProbeEvent(at: date("09:30:20.485"), event: "reading", source: "healthkit",
                             notes: ["result": "value", "scope": "day"])
        ]
        let timeline = MotionProbeTimeline(events: events, from: date("09:21:20.702"), to: date("09:30:24.912"))
        XCTAssertEqual(timeline.locks.count, 1)
        XCTAssertEqual(timeline.locks.first?.duration ?? 0, 461.557, accuracy: 0.001)
        XCTAssertEqual(timeline.runsWhileLocked, 0)
        XCTAssertTrue(timeline.backgroundRuns.isEmpty)
        XCTAssertTrue(timeline.unseen.isEmpty)
        // Noticed 0.1 s after the unlock, but only because unlocking brought Honoured back on screen.
        XCTAssertEqual(timeline.place(at: date("09:29:24.038")), .foreground)
        XCTAssertEqual(timeline.place(at: date("09:25:00.000")), .background)
        XCTAssertEqual(timeline.lastSessionRead(of: "healthkit")?.at, date("09:30:20.492"))
        XCTAssertEqual(timeline.summaryLines(clock: clock), [
            "Locks seen by the probe: 1 (462 s)",
            "App runs while locked: 0",
            "Background runs started by iOS: 0"
        ])
    }

    func testSwipeAwayLeavesAnUnseenStretchAndARestart() {
        let events = [
            run("09:45:55.491", "probe_screen", state: "active"),
            lifecycle("09:46:00.852", "did_enter_background"),
            MotionProbeEvent(at: date("09:49:35.746"), event: "lifecycle", reason: "launched",
                             notes: ["state_at_launch": "background"]),
            lifecycle("09:49:35.764", "will_enter_foreground"),
            run("09:49:35.888", "launch", state: "active"),
            lifecycle("09:49:46.676", "did_enter_background"),
            lifecycle("09:49:53.804", "will_enter_foreground")
        ]
        let timeline = MotionProbeTimeline(events: events, from: date("09:45:55.486"), to: date("09:50:06.000"))
        XCTAssertTrue(timeline.locks.isEmpty)
        XCTAssertEqual(timeline.unseen, [.init(start: date("09:46:00.852"), end: date("09:49:35.764"))])
        XCTAssertEqual(timeline.relaunches, [date("09:49:35.746")])
        XCTAssertEqual(timeline.place(at: date("09:49:35.901")), .foreground)
        XCTAssertEqual(timeline.summaryLines(clock: clock), [
            "Locks seen by the probe: none",
            "App runs while locked: 0",
            "Background runs started by iOS: 0",
            "In the background with no lock seen: 16:46:00–16:49:35 (215 s). The probe cannot see a lock that starts while Honoured is suspended or closed.",
            "Honoured restarted at 16:49:35: the earlier process had ended (swiped away, closed by iOS or crashed)"
        ])
    }

    func testLockSeenJustBeforeTheBackgroundStillCounts() {
        let events = [
            lifecycle("09:37:50.186", "protected_data_will_become_unavailable"),
            lifecycle("09:37:50.191", "did_enter_background"),
            lifecycle("09:38:33.691", "will_enter_foreground")
        ]
        let timeline = MotionProbeTimeline(events: events, from: date("09:37:00.000"), to: date("09:39:00.000"))
        XCTAssertEqual(timeline.locks.first?.duration ?? 0, 43.505, accuracy: 0.001)
        XCTAssertTrue(timeline.unseen.isEmpty)
    }

    func testBackgroundRunsAreCountedAndShortStretchesIgnored() {
        let events = [
            run("10:00:00.000", "probe_screen", state: "active"),
            lifecycle("10:00:02.000", "did_enter_background"),
            lifecycle("10:00:04.000", "will_enter_foreground"),
            lifecycle("10:00:10.000", "did_enter_background"),
            run("10:10:00.000", "healthkit_delivery", state: "background", locked: true),
            run("10:15:00.000", "bg_app_refresh", state: "background"),
            lifecycle("10:16:40.000", "will_enter_foreground"),
            run("10:16:40.100", "app_active", state: "active")
        ]
        let timeline = MotionProbeTimeline(events: events, from: date("10:00:00.000"), to: date("10:20:00.000"))
        XCTAssertEqual(timeline.runsWhileLocked, 1)
        XCTAssertEqual(timeline.backgroundRuns, ["healthkit_delivery": 1, "bg_app_refresh": 1])
        XCTAssertEqual(timeline.unseen, [.init(start: date("10:00:10.000"), end: date("10:16:40.000"))])
        XCTAssertEqual(timeline.place(at: date("10:10:00.000")), .background)
        XCTAssertEqual(timeline.summaryLines(clock: clock)[2],
                       "Background runs started by iOS: 2 (bg_app_refresh 1, healthkit_delivery 1)")
    }

    func testAStretchStillOpenAtTheEndIsReported() {
        let events = [lifecycle("11:00:00.000", "did_enter_background")]
        let timeline = MotionProbeTimeline(events: events, from: date("10:59:00.000"), to: date("11:05:00.000"))
        XCTAssertEqual(timeline.unseen, [.init(start: date("11:00:00.000"), end: date("11:05:00.000"))])
        XCTAssertNil(timeline.place(at: date("10:59:30.000")))
    }
}
