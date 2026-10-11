import XCTest

final class HealthDailyLedgerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    private func row(_ metric: String, _ total: Double, day: String = "2026-10-11") -> HealthDailyPayload {
        HealthDailyPayload(day: day, metric: metric, total: total, unit: "count")
    }

    private func ledger(uploading rows: [HealthDailyPayload], for userId: String = "user-a") -> HealthDailyLedger {
        var ledger = HealthDailyLedger()
        ledger.recordUpload(rows, userId: userId, at: start)
        return ledger
    }

    func testANewProcessSendsEveryTotal() {
        let daily = [row("steps", 1_200), row("active_energy", 80)]
        XCTAssertEqual(HealthDailyLedger().totalsToUpload(daily, userId: "user-a", queued: [], now: start), daily)
    }

    func testOnlyChangedTotalsAreSentWithinTheHour() {
        let ledger = ledger(uploading: [row("steps", 1_200), row("active_energy", 80), row("steps", 9_000, day: "2026-10-10")])
        let daily = [row("steps", 1_350), row("active_energy", 80), row("steps", 9_000, day: "2026-10-10"), row("sleep", 420)]
        XCTAssertEqual(
            ledger.totalsToUpload(daily, userId: "user-a", queued: [], now: start.addingTimeInterval(600)),
            [row("steps", 1_350), row("sleep", 420)]
        )
        XCTAssertEqual(
            ledger.totalsToUpload([row("steps", 1_200)], userId: "user-a", queued: [], now: start.addingTimeInterval(3_599)),
            []
        )
    }

    /// Home's "Updated" time comes from the newest uploaded total, so unchanged
    /// totals go up again once an hour has passed without one.
    func testUnchangedTotalsAreSentAgainAfterTheRefreshInterval() {
        let daily = [row("steps", 1_200), row("active_energy", 80)]
        let ledger = ledger(uploading: daily)
        XCTAssertEqual(
            ledger.totalsToUpload(daily, userId: "user-a", queued: [], now: start.addingTimeInterval(HealthDailyLedger.defaultRefreshInterval)),
            daily
        )
    }

    func testTheRefreshIntervalCanBeShortened() {
        let daily = [row("steps", 1_200)]
        var ledger = HealthDailyLedger(refreshInterval: 60)
        ledger.recordUpload(daily, userId: "user-a", at: start)
        XCTAssertEqual(ledger.totalsToUpload(daily, userId: "user-a", queued: [], now: start.addingTimeInterval(59)), [])
        XCTAssertEqual(ledger.totalsToUpload(daily, userId: "user-a", queued: [], now: start.addingTimeInterval(60)), daily)
        ledger.reset()
        XCTAssertEqual(ledger.refreshInterval, 60)
    }

    /// Queued totals will refresh the server when they upload, so they hold
    /// back the hourly refresh, and the newest queued value is the one compared.
    func testQueuedTotalsCountAsKnownAndTheNewestWins() {
        let ledger = ledger(uploading: [row("steps", 1_000)])
        let queued = [row("steps", 1_100), row("active_energy", 80), row("steps", 1_200)]
        let later = start.addingTimeInterval(HealthDailyLedger.defaultRefreshInterval * 3)
        XCTAssertEqual(ledger.totalsToUpload([row("steps", 1_200), row("active_energy", 80)], userId: "user-a", queued: queued, now: later), [])
        XCTAssertEqual(ledger.totalsToUpload([row("steps", 1_100)], userId: "user-a", queued: queued, now: later), [row("steps", 1_100)])
        XCTAssertEqual(HealthDailyLedger().totalsToUpload([row("steps", 1_200)], userId: "user-a", queued: queued, now: later), [])
    }

    /// A total that went back to the uploaded value while a different one is
    /// still queued must be sent, or the queued value would win on the server.
    func testATotalThatReturnsToTheUploadedValueIsSentWhileANewerOneIsQueued() {
        let ledger = ledger(uploading: [row("steps", 1_000)])
        XCTAssertEqual(
            ledger.totalsToUpload([row("steps", 1_000)], userId: "user-a", queued: [row("steps", 1_500)], now: start),
            [row("steps", 1_000)]
        )
    }

    func testAnotherAccountStartsFromNothing() {
        let daily = [row("steps", 1_200)]
        var ledger = ledger(uploading: daily)
        XCTAssertEqual(ledger.totalsToUpload(daily, userId: "user-b", queued: [], now: start), daily)

        ledger.recordUpload([row("active_energy", 80)], userId: "user-b", at: start)
        XCTAssertEqual(ledger.totalsToUpload(daily, userId: "user-b", queued: [], now: start), daily)
        XCTAssertEqual(ledger.totalsToUpload(daily, userId: "user-a", queued: [], now: start), daily)
    }

    func testResetForgetsEverything() {
        let daily = [row("steps", 1_200)]
        var ledger = ledger(uploading: daily)
        ledger.reset()
        XCTAssertEqual(ledger.totalsToUpload(daily, userId: "user-a", queued: [], now: start), daily)
    }

    /// A batch of samples alone leaves `health_daily.updated_at` as it was, so
    /// it does not postpone the hourly refresh.
    func testABatchWithoutTotalsIsNotARefresh() {
        let daily = [row("steps", 1_200)]
        var ledger = ledger(uploading: daily)
        ledger.recordUpload([], userId: "user-a", at: start.addingTimeInterval(3_000))
        XCTAssertEqual(
            ledger.totalsToUpload(daily, userId: "user-a", queued: [], now: start.addingTimeInterval(HealthDailyLedger.defaultRefreshInterval)),
            daily
        )
    }
}
