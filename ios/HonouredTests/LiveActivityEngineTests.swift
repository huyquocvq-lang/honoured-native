import XCTest

/// Holds async work open until the test lets it go.
actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var arrivals = 0

    func wait() async {
        arrivals += 1
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func waitForArrival() async {
        while arrivals == 0 {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

final class LiveActivityEngineTests: XCTestCase {
    private func start(_ h: EngineHarness, _ definition: ContractDefinition, seconds: Double = 600) async -> LiveActivityEngine.TimerStartResult? {
        let outcome = await h.engine.perform(.startTimer(LiveActivityEngine.TimerStart(
            activityId: definition.timerActivityId ?? definition.contractId,
            activityName: definition.contractName,
            durationSeconds: seconds,
            account: "user-a",
            definition: .success(definition)
        )))
        guard case .timerStarted(let result) = outcome else {
            XCTFail("expected timerStarted, got \(outcome)")
            return nil
        }
        return result
    }

    private func score(_ h: EngineHarness, _ contractId: String) -> Double? {
        h.driver.liveCard(contractId)?.content.relevanceScore
    }

    // MARK: - Identity

    func testTwoSlotsMakeOneCardAndTwoContractsMakeTwo() async {
        let h = await EngineHarness.make()
        let two = h.healthContract("two", slots: [(.primary, .steps, 8000), (.secondary, .activeEnergy, 400)])
        let other = h.healthContract("other")
        h.setGoals(for: [two, other])
        _ = await h.track(two)
        _ = await h.track(two)
        _ = await h.track(other)
        await h.settle()
        XCTAssertEqual(h.driver.live.count, 2)
        XCTAssertEqual(h.driver.requestCount, 2)
        XCTAssertEqual(h.driver.liveCard("two")?.content.state.health.count, 2)
    }

    func testTheSameContractOnANewHealthDayIsANewOccurrence() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk", expiresIn: 48 * 3600)
        h.setGoals(for: [walk])
        _ = await h.track(walk)
        h.environment.clock = h.environment.clock.addingTimeInterval(24 * 3600)
        let nextDay = h.healthContract("walk", expiresIn: 24 * 3600)
        XCTAssertNotEqual(nextDay.healthDay, walk.healthDay)
        _ = await h.engine.perform(.dayMayHaveChanged)
        _ = await h.track(nextDay)
        await h.settle()
        let state = await h.state()
        XCTAssertEqual(state.tracked.map(\.key), [nextDay.key], "yesterday's finished occurrence is forgotten")
        XCTAssertEqual(h.driver.live.count, 1)
        XCTAssertEqual(h.driver.live.first?.attributes.healthDay, nextDay.healthDay)
    }

    // MARK: - Ordering and focus

    func testMostRecentSelectionLeadsAndEveryOtherCardStays() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk")
        let exercise = h.healthContract("exercise", slots: [(.primary, .exerciseMinutes, 30)])
        let meditation = h.timerContract("meditation")
        h.setGoals(for: [walk, exercise])

        let observed1 = trackReply(await h.track(walk))?.status
        XCTAssertEqual(observed1, .active)
        let exerciseReply = trackReply(await h.track(exercise))
        XCTAssertEqual(exerciseReply?.focused, true)
        let started = await start(h, meditation)
        XCTAssertEqual(started?.liveActivityStatus, "active")
        await h.settle()
        XCTAssertEqual(h.driver.live.count, 3)
        XCTAssertEqual(score(h, "meditation"), 100)
        XCTAssertEqual(score(h, "exercise"), 99)
        XCTAssertEqual(score(h, "walk"), 98)

        let observed2 = trackReply(await h.track(walk))?.focused
        XCTAssertEqual(observed2, true)
        await h.settle()
        XCTAssertEqual(score(h, "walk"), 100)
        XCTAssertEqual(score(h, "meditation"), 99)
        XCTAssertEqual(score(h, "exercise"), 98)
        XCTAssertEqual(h.driver.live.count, 3, "moving focus ends nothing")
        XCTAssertEqual(h.environment.timer?.activityId, "meditation", "and cancels no timer")
        XCTAssertEqual(h.driver.requestCount, 3, "and recreates nothing")
    }

    func testALateHealthResultForAnEarlierOpenDoesNotTakeFocusBack() async {
        let h = await EngineHarness.make()
        let a = h.healthContract("a")
        let b = h.healthContract("b", slots: [(.primary, .activeEnergy, 300)])
        h.setGoals(for: [a, b])
        _ = await h.track(a)
        let gate = AsyncGate()
        h.environment.readGate = { await gate.wait() }
        h.environment.health = [.steps: .value(1200)]
        let refresh = Task { await h.engine.refreshHealth() }
        await gate.waitForArrival()
        _ = await h.track(b)
        await gate.open()
        _ = await refresh.value
        await h.settle()
        let observed3 = await h.state().focused?.contractId
        XCTAssertEqual(observed3, "b")
        XCTAssertEqual(score(h, "b"), 100)
        XCTAssertEqual(h.driver.liveCard("a")?.content.state.health.first?.value, 1200)
    }

    func testFocusFollowsNativeOrderNotTheClock() async {
        let h = await EngineHarness.make()
        let a = h.healthContract("a")
        let b = h.healthContract("b", slots: [(.primary, .activeEnergy, 300)])
        h.setGoals(for: [a, b])
        _ = await h.track(a)
        h.environment.clock = h.environment.clock.addingTimeInterval(-3600)
        _ = await h.track(b)
        let observed4 = await h.state().focused?.contractId
        XCTAssertEqual(observed4, "b")
    }

    func testHealthUpdatesAndSyncNeverMoveFocus() async {
        let h = await EngineHarness.make()
        let a = h.healthContract("a")
        let b = h.healthContract("b", slots: [(.primary, .activeEnergy, 300)])
        h.setGoals(for: [a, b])
        _ = await h.track(b)
        _ = await h.track(a)
        h.environment.health = [.steps: .value(10), .activeEnergy: .value(20)]
        await h.engine.refreshHealth()
        _ = await h.engine.perform(.sync([.valid(b), .valid(a)], account: "user-a"))
        await h.settle()
        let observed5 = await h.state().focused?.contractId
        XCTAssertEqual(observed5, "a")
        XCTAssertEqual(score(h, "a"), 100)
    }

    func testFocusFallsBackWhenTheFocusedCardIsRemoved() async {
        let h = await EngineHarness.make()
        let a = h.healthContract("a")
        let b = h.healthContract("b", slots: [(.primary, .activeEnergy, 300)])
        h.setGoals(for: [a, b])
        _ = await h.track(a)
        _ = await h.track(b)
        await h.settle()
        h.driver.dismissByUser(h.driver.liveCard("b")!.id)
        await h.settle()
        let observed6 = await h.entry("b")?.status
        XCTAssertEqual(observed6, .dismissed)
        let observed7 = await h.state().focused?.contractId
        XCTAssertEqual(observed7, "a")
        XCTAssertEqual(score(h, "a"), 100)
    }

    func testSyncForgetsUnlistedOccurrencesAndNeverCreatesCards() async {
        let h = await EngineHarness.make()
        let a = h.healthContract("a")
        let b = h.healthContract("b", slots: [(.primary, .activeEnergy, 300)])
        let c = h.healthContract("c", slots: [(.primary, .exerciseMinutes, 20)])
        h.setGoals(for: [a, b, c])
        _ = await h.track(a)
        _ = await h.track(b)
        guard case .synced(let entries) = await h.engine.perform(.sync([.valid(a), .valid(c)], account: "user-a")) else {
            return XCTFail("sync")
        }
        await h.settle()
        XCTAssertNil(entries.first { $0.key.contractId == "b" })
        XCTAssertNil(h.driver.liveCard("b"))
        let pending = entries.first { $0.key.contractId == "c" }
        XCTAssertEqual(pending?.status, .pending)
        XCTAssertEqual(pending?.reason, "awaiting_open")
        XCTAssertNil(h.driver.liveCard("c"), "a sync is not an open")
        let observed8 = await h.state().focused?.contractId
        XCTAssertEqual(observed8, "a")
    }

    func testSyncReportsRejectedEntriesAndKeepsTheirRecords() async {
        let h = await EngineHarness.make()
        let a = h.healthContract("a")
        h.setGoals(for: [a])
        _ = await h.track(a)
        var changed = a
        changed.activities[0].target = 9000
        guard case .synced(let entries) = await h.engine.perform(.sync([.valid(changed)], account: "user-a")) else {
            return XCTFail("sync")
        }
        XCTAssertTrue(entries.contains { $0.key == a.key && $0.status == .failed && $0.reason == "goal_definition_mismatch" })
        XCTAssertNotNil(h.driver.liveCard("a"), "a rejected entry is still listed, so its card stays")
    }

    // MARK: - Async lifecycle

    func testSignOutWhileAHealthReadIsOutDropsTheResult() async {
        let h = await EngineHarness.make()
        let a = h.healthContract("a")
        h.setGoals(for: [a])
        _ = await h.track(a)
        let gate = AsyncGate()
        h.environment.readGate = { await gate.wait() }
        h.environment.health = [.steps: .value(99)]
        let refresh = Task { await h.engine.refreshHealth() }
        await gate.waitForArrival()
        _ = await h.engine.perform(.accountChanged(nil))
        await gate.open()
        _ = await refresh.value
        await h.settle()
        let observed9 = await h.state().tracked.isEmpty
        XCTAssertTrue(observed9)
        XCTAssertTrue(h.driver.live.isEmpty)
        XCTAssertEqual(h.driver.requestCount, 1)
    }

    func testStopWhileAHealthReadIsOutDoesNotReviveTheCard() async {
        let h = await EngineHarness.make()
        let a = h.healthContract("a")
        h.setGoals(for: [a])
        _ = await h.track(a)
        let gate = AsyncGate()
        h.environment.readGate = { await gate.wait() }
        let refresh = Task { await h.engine.refreshHealth() }
        await gate.waitForArrival()
        _ = await h.engine.perform(.stop(a.key, account: "user-a"))
        await gate.open()
        _ = await refresh.value
        await h.settle()
        let observed10 = await h.entry("a")
        XCTAssertNil(observed10)
        XCTAssertTrue(h.driver.live.isEmpty)
    }

    func testADefinitionChangedDuringAReadDiscardsTheOldResult() async {
        let h = await EngineHarness.make()
        let a = h.healthContract("a")
        h.setGoals(for: [a])
        _ = await h.track(a)
        let gate = AsyncGate()
        h.environment.readGate = { await gate.wait() }
        h.environment.health = [.steps: .value(5000)]
        let refresh = Task { await h.engine.refreshHealth() }
        await gate.waitForArrival()
        var energy = a
        energy.activities[0].metric = .activeEnergy
        energy.activities[0].target = 300
        h.setGoals(for: [energy])
        _ = await h.track(energy)
        await gate.open()
        _ = await refresh.value
        await h.settle()
        let part = h.driver.liveCard("a")?.content.state.health.first
        XCTAssertEqual(part?.metric, "active_energy")
        XCTAssertNil(part?.value, "a steps total must not land on the energy slot")
        XCTAssertEqual(part?.dataStatus, .waiting)
    }

    func testAnUpdateInFlightThenAStopLeavesTheCardEnded() async {
        let h = await EngineHarness.make()
        let a = h.healthContract("a")
        h.setGoals(for: [a])
        _ = await h.track(a)
        h.driver.updateDelayNanoseconds = 150_000_000
        h.environment.health = [.steps: .value(1000)]
        await h.engine.refreshHealth()
        _ = await h.engine.perform(.stop(a.key, account: "user-a"))
        try? await Task.sleep(nanoseconds: 300_000_000)
        await h.settle()
        XCTAssertEqual(h.driver.anyCard("a")?.state, .dismissed)
        XCTAssertTrue(h.driver.live.isEmpty)
    }

    func testAnOldRunFinishingAfterAResumeIsIgnored() async {
        let h = await EngineHarness.make()
        let meditation = h.timerContract("meditation")
        _ = await start(h, meditation)
        let firstRun = h.environment.timer!
        h.environment.timer = nil
        _ = await h.engine.perform(.timerDiscarded(firstRun))
        let resumed = await start(h, meditation, seconds: 300)
        _ = await h.engine.perform(.timerCompleted(firstRun))
        await h.settle()
        let observed11 = await h.entry("meditation")?.status
        XCTAssertEqual(observed11, .active)
        XCTAssertEqual(h.driver.liveCard("meditation")?.content.state.timer?.endsAt, resumed?.started.endsAt)
        XCTAssertEqual(h.driver.liveCard("meditation")?.content.state.timer?.finished, false)
    }

    func testAReadStartedBeforeAStopNeverLandsOnTheContractTrackedAgain() async {
        let h = await EngineHarness.make()
        let a = h.healthContract("a", policy: "web_authoritative")
        h.setGoals(for: [a])
        _ = await h.track(a)
        let gate = AsyncGate()
        h.environment.readGate = { await gate.wait() }
        h.environment.health = [.steps: .value(5000)]
        let refresh = Task { await h.engine.refreshHealth() }
        await gate.waitForArrival()
        _ = await h.engine.perform(.stop(a.key, account: "user-a"))
        var energy = a
        energy.activities[0].metric = .activeEnergy
        energy.activities[0].target = 300
        h.setGoals(for: [energy])
        _ = await h.track(energy)
        await gate.open()
        _ = await refresh.value
        await h.settle()
        let part = h.driver.liveCard("a")?.content.state.health.first
        XCTAssertEqual(part?.metric, "active_energy")
        XCTAssertNil(part?.value, "the old steps read belongs to the stopped record")
        XCTAssertEqual(part?.reached, false)
    }

    // MARK: - Timer

    func testAReopenThatLeavesOutTheTimerKeepsTheRunningTimer() async {
        let h = await EngineHarness.make()
        var journal = ContractDefinition(
            contractId: "journal", contractName: "Journal", healthDay: h.today,
            expiresAt: h.environment.clock.addingTimeInterval(6 * 3600), completionPolicy: .webAuthoritative,
            activities: [TrackedActivity(activityId: "journal:primary", slot: .primary, name: "Write", mode: .manual)],
            timerActivityId: nil
        )
        var started = journal
        started.timerActivityId = "journal" // what START_TIMER fills in
        _ = await start(h, started)
        XCTAssertNotNil(h.driver.liveCard("journal")?.content.state.timer)
        journal.contractName = "Journal (reopened)"
        let reopened = trackReply(await h.track(journal))
        await h.settle()
        XCTAssertEqual(reopened?.status, .active)
        XCTAssertNotNil(h.driver.liveCard("journal")?.content.state.timer, "a reload mid-countdown keeps the timer on its card")
        XCTAssertEqual(h.driver.liveCard("journal")?.content.state.contractName, "Journal (reopened)")
    }

    func testRestartingTheSameContractsTimerKeepsItsCard() async {
        let h = await EngineHarness.make()
        let meditation = h.timerContract("meditation")
        _ = await start(h, meditation, seconds: 600)
        let card = h.driver.liveCard("meditation")
        let restarted = await start(h, meditation, seconds: 300)
        await h.settle()
        XCTAssertEqual(h.driver.requestCount, 1, "no end-and-recreate flicker")
        XCTAssertEqual(h.driver.liveCard("meditation")?.id, card?.id)
        XCTAssertEqual(h.driver.liveCard("meditation")?.content.state.timer?.endsAt, restarted?.started.endsAt)
    }

    func testATimerOnlyContractShowsNoCardUntilItsTimerRuns() async {
        let h = await EngineHarness.make()
        let meditation = h.timerContract("meditation")
        let observed12 = trackReply(await h.track(meditation))?.status
        XCTAssertEqual(observed12, .awaitingTimer)
        XCTAssertTrue(h.driver.live.isEmpty)
        let started = await start(h, meditation)
        XCTAssertEqual(started?.liveActivityStatus, "active")
        XCTAssertNotNil(h.driver.liveCard("meditation")?.content.state.timer)
    }

    func testPauseEndsATimerOnlyCardAndResumeBringsItBack() async {
        let h = await EngineHarness.make()
        let meditation = h.timerContract("meditation")
        _ = await start(h, meditation)
        let run = h.environment.timer!
        h.environment.timer = nil
        _ = await h.engine.perform(.timerDiscarded(run))
        await h.settle()
        let observed13 = await h.entry("meditation")?.status
        XCTAssertEqual(observed13, .awaitingTimer)
        XCTAssertTrue(h.driver.live.isEmpty)
        let resumed = await start(h, meditation, seconds: 200)
        XCTAssertEqual(resumed?.liveActivityStatus, "active")
        XCTAssertEqual(h.driver.live.count, 1)
    }

    func testStartingAnotherTimerKeepsTheReplacedContractsHealthCard() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk")
        h.setGoals(for: [walk])
        h.environment.health = [.steps: .value(3000)]
        _ = await start(h, walk)
        await h.engine.refreshHealth()
        let second = await start(h, h.timerContract("breathe"))
        XCTAssertEqual(second?.replaced?.activityId, "walk")
        await h.settle()
        let walkCard = h.driver.liveCard("walk")
        XCTAssertNotNil(walkCard)
        XCTAssertNil(walkCard?.content.state.timer)
        XCTAssertEqual(walkCard?.content.state.health.first?.value, 3000)
        XCTAssertEqual(score(h, "breathe"), 100)
        XCTAssertEqual(score(h, "walk"), 99)
    }

    func testALiveActivityRefusalNeverFailsTheTimer() async {
        let h = await EngineHarness.make()
        h.driver.requestError = .limitReached
        let started = await start(h, h.timerContract("meditation"))
        XCTAssertEqual(started?.liveActivityStatus, "limit_reached")
        XCTAssertEqual(h.environment.timer?.activityId, "meditation")
        _ = await h.engine.perform(.appBecameActive)
        _ = await h.engine.perform(.sync([.valid(h.timerContract("meditation"))], account: "user-a"))
        XCTAssertEqual(h.driver.requestCount, 0, "limit_reached is not retried in a loop")
        let observed14 = await h.entry("meditation")?.status
        XCTAssertEqual(observed14, .limitReached)
    }

    func testAnInvalidTrackingContextStillStartsTheTimer() async {
        let h = await EngineHarness.make()
        let outcome = await h.engine.perform(.startTimer(LiveActivityEngine.TimerStart(
            activityId: "x", activityName: "X", durationSeconds: 60, account: "user-a",
            definition: .failure(.invalidContract("bad"))
        )))
        guard case .timerStarted(let result) = outcome else { return XCTFail("timer") }
        XCTAssertEqual(result.liveActivityStatus, "rejected")
        XCTAssertEqual(result.reason, "invalid_contract")
        XCTAssertEqual(h.environment.timer?.activityId, "x")
    }

    func testANaturalFinishCompletesOnlyUnderATimerPolicy() async {
        let h = await EngineHarness.make()
        let meditation = h.timerContract("meditation")
        let walk = h.healthContract("walk")
        h.setGoals(for: [walk])
        _ = await start(h, meditation)
        let run = h.environment.timer!
        h.environment.timer = nil
        _ = await h.engine.perform(.timerCompleted(run))
        await h.settle()
        let finished = await h.entry("meditation")
        XCTAssertEqual(finished?.status, .ended)
        XCTAssertEqual(finished?.reason, "completed")
        let card = h.driver.anyCard("meditation")
        XCTAssertEqual(card?.content.state.status, .completed)
        XCTAssertEqual(card?.content.state.timer?.finished, true)
        XCTAssertEqual(card?.content.state.completedAt, run.endsAt)

        _ = await start(h, walk)
        let walkRun = h.environment.timer!
        h.environment.timer = nil
        _ = await h.engine.perform(.timerCompleted(walkRun))
        await h.settle()
        let observed15 = await h.entry("walk")?.status
        XCTAssertEqual(observed15, .active, "all_health_slots does not end on a timer")
        XCTAssertNil(h.driver.liveCard("walk")?.content.state.timer)
    }

    func testAWebAuthoritativeTimerCardWaitsForTheWebAfterTheFinish() async {
        let h = await EngineHarness.make()
        let meditation = h.timerContract("meditation", policy: .webAuthoritative)
        _ = await start(h, meditation)
        let run = h.environment.timer!
        h.environment.timer = nil
        _ = await h.engine.perform(.timerCompleted(run))
        await h.settle()
        let observed16 = await h.entry("meditation")?.status
        XCTAssertEqual(observed16, .active)
        XCTAssertEqual(h.driver.liveCard("meditation")?.content.state.timer?.finished, true)
        let scope = LiveActivityProtocol.CompletionScope(key: meditation.key, isContract: true, completedAt: run.endsAt)
        _ = await h.engine.perform(.completion(.init(scope: scope, activityId: "meditation", account: "user-a")))
        await h.settle()
        let observed17 = await h.entry("meditation")?.reason
        XCTAssertEqual(observed17, "completed")
    }

    func testALegacyTimerStartAttachesWithoutMovingFocus() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk")
        let other = h.healthContract("other", slots: [(.primary, .activeEnergy, 300)])
        h.setGoals(for: [walk, other])
        _ = await h.track(walk)
        _ = await h.track(other)
        let run = TimerRunSnapshot(runId: "legacy", activityId: "walk", activityName: "Walk", startedAt: h.environment.clock, endsAt: h.environment.clock.addingTimeInterval(600))
        h.environment.timer = run
        _ = await h.engine.perform(.timerStarted(run, replaced: nil))
        await h.settle()
        XCTAssertEqual(h.driver.liveCard("walk")?.content.state.timer?.activityId, "walk")
        let observed18 = await h.state().focused?.contractId
        XCTAssertEqual(observed18, "other")
    }

    // MARK: - Health

    func testEachMetricIsReadOnceForAllCards() async {
        let h = await EngineHarness.make()
        let a = h.healthContract("a", slots: [(.primary, .steps, 5000)])
        let b = h.healthContract("b", slots: [(.primary, .steps, 8000), (.secondary, .activeEnergy, 300)])
        h.setGoals(for: [a, b])
        _ = await h.track(a)
        _ = await h.track(b)
        h.environment.health = [.steps: .value(6000), .activeEnergy: .value(10)]
        let prefetch = await h.engine.refreshHealth()
        XCTAssertEqual(h.environment.reads.filter { $0.metric == .steps }.count, 1)
        XCTAssertEqual(h.environment.reads.filter { $0.metric == .activeEnergy }.count, 1)
        XCTAssertEqual(prefetch?.totals[.steps], .value(6000), "goal detection can reuse today's reads")
        await h.settle()
        XCTAssertEqual(h.driver.anyCard("a")?.content.state.status, .completed)
        XCTAssertEqual(h.driver.liveCard("b")?.content.state.health.first?.value, 6000)
    }

    func testUnknownIsNeverZeroAndAFailedReadKeepsTheLastReading() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk", policy: "web_authoritative")
        h.setGoals(for: [walk])
        _ = await h.track(walk)
        func part() async -> HonouredLiveActivityState.HealthPart? {
            await h.settle()
            return h.driver.liveCard("walk")?.content.state.health.first
        }
        let observed19 = await part()?.dataStatus
        XCTAssertEqual(observed19, .waiting)

        h.environment.health = [.steps: .noData]
        await h.engine.refreshHealth()
        var current = await part()
        XCTAssertNil(current?.value)
        XCTAssertEqual(current?.dataStatus, .noData)

        h.environment.health = [.steps: .value(2000)]
        await h.engine.refreshHealth()
        let observed20 = await part()?.value
        XCTAssertEqual(observed20, 2000)

        for failure in [HealthTotalRead.protectedDataUnavailable, .failed] {
            h.environment.health = [.steps: failure]
            await h.engine.refreshHealth()
            current = await part()
            XCTAssertEqual(current?.value, 2000)
            XCTAssertEqual(current?.dataStatus, .unavailable)
        }

        h.environment.health = [.steps: .noData]
        await h.engine.refreshHealth()
        current = await part()
        XCTAssertNil(current?.value, "a successful read with no data does not keep the old number")
        XCTAssertEqual(current?.dataStatus, .noData)
    }

    func testTotalsMayGoDownButAReachedSlotStaysReached() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk", policy: "web_authoritative")
        h.setGoals(for: [walk])
        _ = await h.track(walk)
        h.environment.health = [.steps: .value(9000)]
        await h.engine.refreshHealth()
        h.environment.health = [.steps: .value(1500)]
        await h.engine.refreshHealth()
        await h.settle()
        let part = h.driver.liveCard("walk")?.content.state.health.first
        XCTAssertEqual(part?.value, 1500)
        XCTAssertEqual(part?.reached, true)
    }

    func testAHealthCardGoesStaleAfterAnHourWithoutAReading() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk", policy: "web_authoritative")
        h.setGoals(for: [walk])
        _ = await h.track(walk)
        h.environment.health = [.steps: .value(100)]
        await h.engine.refreshHealth()
        let observed21 = await h.entry("walk")?.status
        XCTAssertEqual(observed21, .active)
        h.environment.clock = h.environment.clock.addingTimeInterval(61 * 60)
        let observed22 = await h.entry("walk")?.status
        XCTAssertEqual(observed22, .stale)
    }

    // MARK: - Completion

    func testOneReachedSlotIsProgressAndEverySlotHonoursTheContract() async {
        let h = await EngineHarness.make()
        let two = h.healthContract("two", slots: [(.primary, .steps, 8000), (.secondary, .activeEnergy, 400)])
        h.setGoals(for: [two])
        _ = await h.track(two)
        h.environment.health = [.steps: .value(9000), .activeEnergy: .value(320)]
        await h.engine.refreshHealth()
        await h.settle()
        let observed23 = await h.entry("two")?.status
        XCTAssertEqual(observed23, .active)
        XCTAssertEqual(h.driver.liveCard("two")?.content.state.health.map(\.reached), [true, false])
        XCTAssertEqual(h.driver.liveCard("two")?.content.state.status, .active)

        h.environment.health = [.steps: .value(9000), .activeEnergy: .value(420)]
        await h.engine.refreshHealth()
        await h.settle()
        let entry = await h.entry("two")
        XCTAssertEqual(entry?.status, .ended)
        XCTAssertEqual(entry?.reason, "completed")
        let card = h.driver.anyCard("two")
        XCTAssertEqual(card?.state, .ended)
        XCTAssertEqual(card?.content.state.status, .completed)
        XCTAssertEqual(card?.dismissal, .after(h.environment.clock.addingTimeInterval(LiveActivityConfig.completedDismissalDelay)))
    }

    func testWebAuthoritativeEndsOnlyOnAContractConfirmation() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk", policy: "web_authoritative")
        h.setGoals(for: [walk])
        _ = await h.track(walk)
        h.environment.health = [.steps: .value(9000)]
        await h.engine.refreshHealth()
        let slot = LiveActivityProtocol.CompletionScope(key: walk.key, isContract: false, completedAt: nil)
        _ = await h.engine.perform(.completion(.init(scope: slot, activityId: "walk:primary", account: "user-a")))
        let observed24 = await h.entry("walk")?.status
        XCTAssertEqual(observed24, .active)
        let contract = LiveActivityProtocol.CompletionScope(key: walk.key, isContract: true, completedAt: nil)
        guard case .completion(let tracked, let status) = await h.engine.perform(.completion(.init(scope: contract, activityId: "walk", account: "user-a"))) else {
            return XCTFail("completion")
        }
        XCTAssertTrue(tracked)
        XCTAssertEqual(status, .ended)
    }

    func testASlotCompletionForAnotherContractsActivityIsRefused() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk")
        h.setGoals(for: [walk])
        _ = await h.track(walk)
        let slot = LiveActivityProtocol.CompletionScope(key: walk.key, isContract: false, completedAt: nil)
        let observed25 = rejection(await h.engine.perform(.completion(.init(scope: slot, activityId: "other:primary", account: "user-a"))))
        XCTAssertEqual(observed25, "invalid_activity_completion")
        let unknown = LiveActivityProtocol.CompletionScope(key: OccurrenceKey(contractId: "nope", healthDay: h.today), isContract: true, completedAt: nil)
        guard case .completion(let tracked, _) = await h.engine.perform(.completion(.init(scope: unknown, activityId: "nope", account: "user-a"))) else {
            return XCTFail("completion")
        }
        XCTAssertFalse(tracked)
    }

    func testAFinishedOccurrenceIsNotRecreatedByAnotherOpen() async {
        let h = await EngineHarness.make()
        let meditation = h.timerContract("meditation")
        _ = await start(h, meditation)
        let run = h.environment.timer!
        h.environment.timer = nil
        _ = await h.engine.perform(.timerCompleted(run))
        let requests = h.driver.requestCount
        let observed26 = trackReply(await h.track(meditation))?.status
        XCTAssertEqual(observed26, .ended)
        XCTAssertEqual(h.driver.requestCount, requests)
    }

    // MARK: - Validity

    func testTheResetHourDecidesTheHealthDay() async {
        let environment = FakeEnvironment(now: EngineHarness.morning.addingTimeInterval(-7 * 3600)) // 03:00
        environment.resetHour = 4
        let h = await EngineHarness.make(environment: environment)
        XCTAssertEqual(h.today, "2026-09-22")
        let walk = h.healthContract("walk", day: "2026-09-23")
        h.setGoals(for: [walk])
        guard case .rejected(let error) = await h.track(walk) else { return XCTFail("expected rejection") }
        XCTAssertEqual(error.code, "health_day_mismatch")
        XCTAssertEqual(error.details["expectedHealthDay"], "2026-09-22")
    }

    func testTrackRejectsExpiredMismatchedAndForeignAccounts() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk")
        h.setGoals(for: [walk])
        let late = h.healthContract("late", expiresIn: -60)
        h.setGoals(for: [walk, late])
        let observed27 = rejection(await h.track(late))
        XCTAssertEqual(observed27, "occurrence_expired")
        let observed28 = rejection(await h.track(h.healthContract("unknown")))
        XCTAssertEqual(observed28, "goal_definition_mismatch", "no goal from SET_GOALS")
        var other = walk
        other.activities[0].target = 7000
        let observed29 = rejection(await h.track(other))
        XCTAssertEqual(observed29, "goal_definition_mismatch", "a second target for the same activity")
        let observed30 = rejection(await h.track(walk, account: "user-b"))
        XCTAssertEqual(observed30, "account_mismatch")
        let observed31 = rejection(await h.track(walk, account: nil))
        XCTAssertEqual(observed31, "auth_session_required")
        let observed32 = await h.state().tracked.isEmpty
        XCTAssertTrue(observed32)
    }

    func testDayRolloverEndsHealthCardsButKeepsARunningTimer() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk", expiresIn: 30 * 3600)
        let mixed = h.healthContract("mixed", slots: [(.primary, .activeEnergy, 300)], expiresIn: 30 * 3600)
        h.setGoals(for: [walk, mixed])
        _ = await h.track(walk)
        _ = await start(h, mixed, seconds: 16 * 3600)
        h.environment.clock = h.environment.clock.addingTimeInterval(14.5 * 3600) // 00:30 next day
        _ = await h.engine.perform(.dayMayHaveChanged)
        await h.settle()
        XCTAssertEqual(h.driver.anyCard("walk")?.state, .dismissed)
        let kept = h.driver.liveCard("mixed")
        XCTAssertNotNil(kept, "the running timer keeps its original occurrence")
        XCTAssertTrue(kept?.content.state.health.isEmpty ?? false, "yesterday's Health is not shown on the new day")
        XCTAssertNotNil(kept?.content.state.timer)
    }

    func testExpiryEndsTheCardButNotTheTimer() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk", expiresIn: 3600)
        h.setGoals(for: [walk])
        _ = await start(h, walk, seconds: 2 * 3600)
        h.environment.clock = h.environment.clock.addingTimeInterval(3700)
        _ = await h.engine.perform(.dayMayHaveChanged)
        await h.settle()
        let observed33 = await h.entry("walk")?.reason
        XCTAssertEqual(observed33, "expired")
        XCTAssertTrue(h.driver.live.isEmpty)
        XCTAssertEqual(h.environment.timer?.activityId, "walk", "the business timer keeps running")
    }

    // MARK: - Limits and restore

    func testDisabledAndBackgroundAreStatusesRetriedOnlyOnForeground() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk")
        h.setGoals(for: [walk])
        h.driver.enabled = false
        let observed34 = trackReply(await h.track(walk))?.status
        XCTAssertEqual(observed34, .disabled)
        h.driver.enabled = true
        h.environment.foreground = false
        _ = await h.engine.perform(.appBecameActive)
        let observed35 = await h.entry("walk")?.status
        XCTAssertEqual(observed35, .needsForeground)
        h.environment.foreground = true
        _ = await h.engine.perform(.appBecameActive)
        let observed36 = await h.entry("walk")?.status
        XCTAssertEqual(observed36, .active)
        XCTAssertEqual(h.driver.requestCount, 1)
    }

    func testAnOversizedCardIsRefusedAsFailed() async {
        let h = await EngineHarness.make()
        var walk = h.healthContract("walk")
        walk.contractName = String(repeating: "x", count: 5000)
        h.setGoals(for: [walk])
        let reply = trackReply(await h.track(walk))
        XCTAssertEqual(reply?.status, .failed)
        XCTAssertEqual(reply?.reason, "payload_too_large")
        XCTAssertEqual(h.driver.requestCount, 0)
    }

    func testRestoreAdoptsKnownCardsAndEndsOrphansAndDuplicates() async {
        let persistence = InMemoryTrackedContractsPersistence()
        let driver = FakeDriver()
        let first = await EngineHarness.make(persistence: persistence, driver: driver)
        let walk = first.healthContract("walk")
        let exercise = first.healthContract("exercise", slots: [(.primary, .exerciseMinutes, 30)])
        first.setGoals(for: [walk, exercise])
        _ = await first.track(walk)
        _ = await first.track(exercise)
        await first.settle()

        // A crash between creating the exercise card and saving its ID.
        var file = persistence.stored!
        let index = file.records.firstIndex { $0.key.contractId == "exercise" }!
        file.records[index].activityKitId = nil
        persistence.stored = file
        let walkCard = driver.liveCard("walk")!
        let duplicate = driver.seed(attributes: walkCard.attributes, content: walkCard.content)
        let foreign = driver.seed(
            attributes: DriverAttributes(contractId: "foreign", healthDay: first.today, occurrenceToken: UUID().uuidString),
            content: walkCard.content
        )

        let second = await EngineHarness.make(persistence: persistence, driver: driver, environment: first.environment, signIn: nil)
        await second.settle()
        XCTAssertEqual(driver.all.first { $0.id == duplicate }?.state, .dismissed)
        XCTAssertEqual(driver.all.first { $0.id == foreign }?.state, .dismissed)
        XCTAssertEqual(driver.live.map(\.attributes.contractId).sorted(), ["exercise", "walk"])
        XCTAssertEqual(driver.liveCard("walk")?.id, walkCard.id)
        let observed37 = await second.entry("exercise")?.status
        XCTAssertEqual(observed37, .active)
        XCTAssertEqual(driver.requestCount, 2, "restore never creates a card")
    }

    func testACardGoneWhileTheAppWasNotRunningIsNotBroughtBack() async {
        let persistence = InMemoryTrackedContractsPersistence()
        let first = await EngineHarness.make(persistence: persistence)
        let walk = first.healthContract("walk")
        first.setGoals(for: [walk])
        _ = await first.track(walk)
        await first.settle()

        let second = await EngineHarness.make(persistence: persistence, driver: FakeDriver(), environment: first.environment, signIn: nil)
        let entry = await second.entry("walk")
        XCTAssertEqual(entry?.status, .dismissed)
        XCTAssertEqual(entry?.reason, "not_found_on_restore")
        _ = await second.engine.perform(.sync([.valid(walk)], account: "user-a"))
        await second.engine.refreshHealth()
        XCTAssertEqual(second.driver.requestCount, 0)
        let observed38 = trackReply(await second.track(walk))?.status
        XCTAssertEqual(observed38, .active, "an explicit open may bring it back")
    }

    func testRestoreWithALockedKeychainTouchesNothing() async {
        let persistence = InMemoryTrackedContractsPersistence()
        let driver = FakeDriver()
        let first = await EngineHarness.make(persistence: persistence, driver: driver)
        let walk = first.healthContract("walk")
        first.setGoals(for: [walk])
        _ = await first.track(walk)
        await first.settle()
        first.environment.accountState = .unavailable
        _ = await EngineHarness.make(persistence: persistence, driver: driver, environment: first.environment, signIn: nil)
        XCTAssertEqual(driver.live.count, 1)
    }

    func testAStoreThatCannotBeReadYetIsNotOverwritten() async {
        let persistence = InMemoryTrackedContractsPersistence()
        let first = await EngineHarness.make(persistence: persistence)
        let walk = first.healthContract("walk")
        first.setGoals(for: [walk])
        _ = await first.track(walk)
        let saved = persistence.stored
        persistence.isAvailable = false
        let second = await EngineHarness.make(persistence: persistence, driver: first.driver, environment: first.environment, signIn: nil)
        let observed39 = rejection(await second.track(walk))
        XCTAssertEqual(observed39, "store_unavailable")
        persistence.isAvailable = true
        XCTAssertEqual(persistence.stored, saved)
    }

    func testTheUsersDismissalIsNotUndoneByHealthOrSync() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk")
        h.setGoals(for: [walk])
        _ = await h.track(walk)
        await h.settle()
        h.driver.dismissByUser(h.driver.liveCard("walk")!.id)
        await h.settle()
        let observed40 = await h.entry("walk")?.status
        XCTAssertEqual(observed40, .dismissed)
        h.environment.health = [.steps: .value(100)]
        await h.engine.refreshHealth()
        _ = await h.engine.perform(.sync([.valid(walk)], account: "user-a"))
        _ = await h.engine.perform(.appBecameActive)
        XCTAssertEqual(h.driver.requestCount, 1)
        let observed41 = trackReply(await h.track(walk))?.status
        XCTAssertEqual(observed41, .active)
        XCTAssertEqual(h.driver.requestCount, 2)
    }

    // MARK: - Account

    func testSwitchingAccountRemovesEveryCardIncludingFinishedOnes() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk")
        h.setGoals(for: [walk])
        _ = await h.track(walk)
        _ = await start(h, h.timerContract("meditation"))
        let run = h.environment.timer!
        h.environment.timer = nil
        _ = await h.engine.perform(.timerCompleted(run))
        await h.settle()
        XCTAssertEqual(h.driver.anyCard("meditation")?.state, .ended, "the result is on show")

        _ = await h.engine.perform(.accountChanged("user-b"))
        await h.settle()
        XCTAssertTrue(h.driver.all.allSatisfy { $0.state == .dismissed })
        let observed42 = await h.state().tracked.isEmpty
        XCTAssertTrue(observed42)
        let observed43 = rejection(await h.track(walk, account: "user-a"))
        XCTAssertEqual(observed43, "account_mismatch")
    }

    func testASameUserRefreshKeepsEverything() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk")
        h.setGoals(for: [walk])
        _ = await h.track(walk)
        _ = await h.engine.perform(.accountChanged("user-a"))
        await h.settle()
        XCTAssertEqual(h.driver.live.count, 1)
        let observed44 = await h.entry("walk")?.status
        XCTAssertEqual(observed44, .active)
    }

    func testARestoreDuringASignInDoesNotSwitchTheAccountBack() async {
        let h = await EngineHarness.make()
        // The bridge switched to user-b; the Keychain still says user-a until
        // the session is saved, and the phone is unlocked meanwhile.
        _ = await h.engine.perform(.accountChanged("user-b"))
        _ = await h.engine.perform(.restore)
        let walk = h.healthContract("walk")
        h.setGoals(for: [walk])
        let observedReply = trackReply(await h.track(walk, account: "user-b"))
        XCTAssertEqual(observedReply?.status, .active)
    }

    func testAScopedCompletionFromAnotherAccountIsRefused() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk")
        h.setGoals(for: [walk])
        _ = await h.track(walk)
        let scope = LiveActivityProtocol.CompletionScope(key: walk.key, isContract: true, completedAt: nil)
        let observedCode = rejection(await h.engine.perform(.completion(.init(scope: scope, activityId: "walk", account: "user-b"))))
        XCTAssertEqual(observedCode, "account_mismatch")
        let observedStatus = await h.entry("walk")?.status
        XCTAssertEqual(observedStatus, .active)
    }

    func testRestoreUnderAnotherAccountEndsEverything() async {
        let persistence = InMemoryTrackedContractsPersistence()
        let driver = FakeDriver()
        let first = await EngineHarness.make(persistence: persistence, driver: driver)
        let walk = first.healthContract("walk")
        first.setGoals(for: [walk])
        _ = await first.track(walk)
        first.environment.accountState = .signedIn("user-b")
        let second = await EngineHarness.make(persistence: persistence, driver: driver, environment: first.environment, signIn: nil)
        await second.settle()
        XCTAssertTrue(driver.live.isEmpty)
        let observed45 = await second.state().tracked.isEmpty
        XCTAssertTrue(observed45)
    }

    // MARK: - Deep links and broadcasts

    func testOnlyTheAccountsOwnCardLinkNavigates() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk")
        h.setGoals(for: [walk])
        _ = await h.track(walk)
        let token = h.driver.liveCard("walk")!.attributes.occurrenceToken
        let target = ContractDeepLink.Target(contractId: "walk", healthDay: h.today, occurrenceToken: token)
        _ = await h.engine.perform(.deepLink(target))
        _ = await h.engine.perform(.deepLink(ContractDeepLink.Target(contractId: "walk", healthDay: h.today, occurrenceToken: UUID().uuidString)))
        _ = await h.engine.perform(.deepLink(ContractDeepLink.Target(contractId: "other", healthDay: h.today, occurrenceToken: token)))
        XCTAssertEqual(h.environment.opened, [walk.key])
        _ = await h.engine.perform(.accountChanged("user-b"))
        _ = await h.engine.perform(.deepLink(target))
        XCTAssertEqual(h.environment.opened, [walk.key])
    }

    func testStateChangesAreBroadcastWhenStatusOrFocusMoves() async {
        let h = await EngineHarness.make()
        let walk = h.healthContract("walk")
        h.setGoals(for: [walk])
        _ = await h.track(walk)
        let afterTrack = h.environment.changes.count
        XCTAssertGreaterThan(afterTrack, 0)
        _ = await h.engine.perform(.getState)
        h.environment.health = [.steps: .value(10)]
        await h.engine.refreshHealth()
        XCTAssertEqual(h.environment.changes.count, afterTrack, "a new reading is not a state change")
        await h.settle()
        h.driver.dismissByUser(h.driver.liveCard("walk")!.id)
        await h.settle()
        XCTAssertEqual(h.environment.changes.last?.tracked.first?.status, .dismissed)
    }
}
