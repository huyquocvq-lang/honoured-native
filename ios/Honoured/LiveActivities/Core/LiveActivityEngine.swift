import Foundation

/// A Health query shared by every occurrence that needs the same metric over
/// the same window, so each is read once per refresh and fanned out.
struct HealthQuery: Hashable {
    let metric: HealthMetric
    let start: Date
    let end: Date
}

struct HealthReadTarget {
    /// The record instance the read was planned for: a record stopped and
    /// tracked again gets a new token, so an old read can never land on it.
    let occurrenceToken: String
    let definitionGeneration: Int
    let queries: [String: HealthQuery]
}

/// Totals read for today's window (health-day start until the read), keyed by
/// metric. Goal detection only uses them for the same day start.
struct HealthPrefetch {
    let dayStart: Date
    let totals: [HealthMetric: HealthTotalRead]
}

/// Captured before HealthKit is read. Results are applied only if the account,
/// the definitions and the read order still match when they come back.
struct HealthReadPlan {
    let sequence: Int
    let accountGeneration: Int
    let readAt: Date
    let dayStart: Date
    let queries: [HealthQuery]
    let targets: [OccurrenceKey: HealthReadTarget]
}

/// The single owner of contract Live Activity state and the only caller of the
/// ActivityKit driver.
///
/// Every change goes through one ordered command queue: the bridge submits
/// commands synchronously on the main thread as messages arrive, so a later
/// open can never be applied before an earlier one, and focus order is native
/// order rather than wall-clock time. The loop does not pull the next command
/// until the current one is finished, even across suspension points, so no
/// command observes another's half-applied state. Slow work stays off the
/// loop: HealthKit is read between a plan and an apply command, and ActivityKit
/// updates run per card, one at a time, latest content wins.
actor LiveActivityEngine {
    enum SyncEntry {
        case valid(ContractDefinition)
        case invalid(OccurrenceKey, LiveActivityError)
    }

    struct TimerStart {
        let activityId: String
        let activityName: String
        let durationSeconds: Double
        let account: String?
        let definition: Result<ContractDefinition, LiveActivityError>
    }

    struct TimerStartResult {
        let started: TimerRunSnapshot
        let replaced: TimerRunSnapshot?
        let liveActivityStatus: String
        let reason: String?
    }

    struct Completion {
        let scope: LiveActivityProtocol.CompletionScope
        let activityId: String
        let account: String?
    }

    struct TrackReply: Equatable {
        let key: OccurrenceKey
        let focused: Bool
        let status: PresentationStatus
        let reason: String?
    }

    enum Command {
        case restore
        case accountChanged(String?)
        case track(ContractDefinition, account: String?)
        case sync([SyncEntry], account: String?)
        case stop(OccurrenceKey, account: String?)
        case getState
        case startTimer(TimerStart)
        case timerStarted(TimerRunSnapshot, replaced: TimerRunSnapshot?)
        case timerDiscarded(TimerRunSnapshot)
        case timerCompleted(TimerRunSnapshot)
        case completion(Completion)
        case planHealthRead
        case applyHealth(HealthReadPlan, [HealthQuery: HealthTotalRead])
        case activityStateChanged(activityId: String, state: DriverActivityState)
        case cardOperationFinished(activityId: String, version: Int)
        case appBecameActive
        case dayMayHaveChanged
        case deepLink(ContractDeepLink.Target)
    }

    enum Outcome {
        case done
        case rejected(LiveActivityError)
        case tracked(TrackReply)
        case synced([LiveActivityStateEntry])
        case state(LiveActivityStateSnapshot)
        case timerStarted(TimerStartResult)
        case completion(tracked: Bool, status: PresentationStatus?)
        case healthPlan(HealthReadPlan?)
    }

    private struct Queued {
        let command: Command
        let reply: ((Outcome) -> Void)?
    }

    private final class CommandQueue: @unchecked Sendable {
        let stream: AsyncStream<Queued>
        private let continuation: AsyncStream<Queued>.Continuation

        init() {
            var captured: AsyncStream<Queued>.Continuation!
            stream = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
            continuation = captured
        }

        func yield(_ item: Queued) {
            continuation.yield(item)
        }
    }

    private struct Context {
        let now: Date
        let resetHour: Int
        let today: HealthDayInfo
        let timer: TimerRunSnapshot?
    }

    /// Per card: the newest wanted content and whether a driver call is out.
    private struct CardOperations {
        struct PendingEnd {
            let content: DriverContent?
            let dismissal: DriverDismissal
        }

        var desired: DriverContent?
        var desiredVersion = 0
        var appliedVersion = 0
        var inFlight = false
        var pendingEnd: PendingEnd?
        var endSent = false
        /// A sign-out while a delayed-removal end is on its way: remove the
        /// card right after that call returns.
        var removeImmediatelyAfterEnd = false
    }

    private static let endVersion = -1

    private let driver: LiveActivityDriving
    private let environment: LiveActivityEnvironment
    private let persistence: TrackedContractsPersistence
    private let queue = CommandQueue()

    private var running = false
    private var loaded = false
    private var file = TrackedContractsFile()
    private var cards: [String: CardOperations] = [:]
    /// Cards native ended itself, so their `.ended`/`.dismissed` updates are
    /// not mistaken for the person removing them.
    private var endedByNative: Set<String> = []
    private var observed: Set<String> = []
    private var readSequence = 0
    /// Set once the account was taken from the Keychain on restore or from the
    /// bridge. Later restores (every unlock) leave it alone, so a restore that
    /// runs while a sign-in is still being saved cannot switch it back.
    private var accountSettled = false

    init(driver: LiveActivityDriving, environment: LiveActivityEnvironment, persistence: TrackedContractsPersistence) {
        self.driver = driver
        self.environment = environment
        self.persistence = persistence
    }

    // MARK: - Queue

    nonisolated func start() {
        Task { await self.run() }
    }

    /// Queued in call order; safe from any thread. The bridge uses this on the
    /// main thread as each message arrives, so arrival order is processing
    /// order. `reply` runs on the engine's executor.
    nonisolated func submit(_ command: Command, reply: ((Outcome) -> Void)? = nil) {
        queue.yield(Queued(command: command, reply: reply))
    }

    /// Queues the command behind everything submitted before it and waits for
    /// its outcome. Never call this from inside the loop.
    nonisolated func perform(_ command: Command) async -> Outcome {
        await withCheckedContinuation { continuation in
            queue.yield(Queued(command: command, reply: { continuation.resume(returning: $0) }))
        }
    }

    private func run() async {
        guard !running else { return }
        running = true
        for await item in queue.stream {
            let before = loaded ? broadcastSignature() : nil
            let outcome = await handle(item.command)
            // Broadcast before the reply, like TIMER_CANCELLED before
            // TIMER_STARTED: whoever acts on the reply has already been told.
            if let before, file.accountScope != nil, broadcastSignature() != before {
                environment.stateChanged(snapshot())
            }
            item.reply?(outcome)
        }
    }

    // MARK: - Health refresh

    /// Reads Health for every occurrence that shows it and applies the result.
    /// Returns today's so-far totals so goal detection can reuse the reads
    /// instead of querying the same metric again.
    @discardableResult
    func refreshHealth() async -> HealthPrefetch? {
        guard case .healthPlan(let plan?) = await perform(.planHealthRead) else { return nil }
        var results: [HealthQuery: HealthTotalRead] = [:]
        for query in plan.queries {
            results[query] = await environment.readHealth(metric: query.metric, from: query.start, to: query.end)
        }
        _ = await perform(.applyHealth(plan, results))

        var today: [HealthMetric: HealthTotalRead] = [:]
        for (query, read) in results where query.start == plan.dayStart && query.end == plan.readAt {
            today[query.metric] = read
        }
        return HealthPrefetch(dayStart: plan.dayStart, totals: today)
    }

    // MARK: - Dispatch

    private func handle(_ command: Command) async -> Outcome {
        switch command {
        case .restore:
            await restore()
            return .done
        case .accountChanged(let userId):
            accountChanged(userId)
            return .done
        case .track(let definition, let account):
            return await track(definition, account: account)
        case .sync(let entries, let account):
            return await sync(entries, account: account)
        case .stop(let key, let account):
            return await stop(key, account: account)
        case .getState:
            return .state(snapshot())
        case .startTimer(let request):
            return await startTimer(request)
        case .timerStarted(let run, let replaced):
            await timerStarted(run, replaced: replaced)
            return .done
        case .timerDiscarded(let run):
            await timerDiscarded(run)
            return .done
        case .timerCompleted(let run):
            await timerCompleted(run)
            return .done
        case .completion(let request):
            return await completion(request)
        case .planHealthRead:
            return .healthPlan(await planHealthRead())
        case .applyHealth(let plan, let results):
            await applyHealth(plan, results)
            return .done
        case .activityStateChanged(let id, let state):
            await activityStateChanged(id, state)
            return .done
        case .cardOperationFinished(let id, let version):
            cardOperationFinished(id, version: version)
            return .done
        case .appBecameActive:
            await appBecameActive()
            return .done
        case .dayMayHaveChanged:
            await dayMayHaveChanged()
            return .done
        case .deepLink(let target):
            deepLink(target)
            return .done
        }
    }

    // MARK: - Restore and account

    /// Launch, including background launches, and whenever protected data
    /// becomes readable. Ends cards that belong to no current record, adopts
    /// the rest, and never creates a card.
    private func restore() async {
        guard driver.isSupported, loadIfNeeded() else { return }
        if !accountSettled {
            switch await environment.account() {
            case .unavailable:
                // Before first unlock the owner cannot be checked. Leave every
                // card alone and try again when protected data is available.
                return
            case .signedOut:
                if file.accountScope != nil || !file.records.isEmpty { switchAccount(to: nil) }
            case .signedIn(let userId):
                if file.accountScope != userId { switchAccount(to: userId) }
            }
            accountSettled = true
        }
        adoptRunningActivities()
        let context = await makeContext()
        await reconcileDays(context)
        refreshCards(context)
        persist()
    }

    private func adoptRunningActivities() {
        var adopted: Set<String> = []
        var byToken: [String: [DriverActivityInfo]] = [:]
        // A card this process is already ending (a result still on show) is
        // left to finish; restore also runs when protected data comes back.
        for info in driver.runningActivities() where info.isLive && !endedByNative.contains(info.id) {
            byToken[info.attributes.occurrenceToken, default: []].append(info)
        }
        for (token, group) in byToken {
            guard let index = file.records.firstIndex(where: { $0.occurrenceToken == token }),
                  file.records[index].terminal == nil, !file.records[index].suppressed,
                  group.allSatisfy({ $0.attributes == LiveActivityPresenter.attributes(for: file.records[index]) }) else {
                // Another account's card, one for an occurrence that ended,
                // or a leftover from a failed create.
                group.forEach { requestEnd($0.id, content: nil, dismissal: .immediate) }
                continue
            }
            // A crash between the create and saving its ID can leave two;
            // keep the one the record knows about.
            let survivor = group.first { $0.id == file.records[index].activityKitId } ?? group[0]
            for duplicate in group where duplicate.id != survivor.id {
                requestEnd(duplicate.id, content: nil, dismissal: .immediate)
            }
            file.records[index].activityKitId = survivor.id
            file.records[index].presentation = .active
            file.records[index].presentationReason = nil
            if cards[survivor.id] == nil { cards[survivor.id] = CardOperations() }
            observe(survivor.id)
            adopted.insert(survivor.id)
        }
        for index in file.records.indices {
            guard let id = file.records[index].activityKitId, !adopted.contains(id) else { continue }
            // Gone while the app was not running: removed by the person or
            // ended by iOS after its time limit. It stays gone until the next
            // explicit open or start.
            file.records[index].activityKitId = nil
            cards[id] = nil
            if file.records[index].terminal == nil {
                file.records[index].suppressed = true
                file.records[index].presentation = .dismissed
                file.records[index].presentationReason = "not_found_on_restore"
            }
        }
    }

    private func accountChanged(_ userId: String?) {
        guard driver.isSupported, loadIfNeeded() else { return }
        accountSettled = true
        // A token refresh for the same person changes nothing.
        guard file.accountScope != userId else { return }
        switchAccount(to: userId)
    }

    /// The generation moves first, so a Health read or a timer event started
    /// for the previous account is dropped when it comes back. Every card is
    /// removed at once, whoever it belonged to, including a finished one still
    /// showing its result: none may outlive its owner's session.
    private func switchAccount(to userId: String?) {
        file.accountGeneration += 1
        var ids = Set(file.records.compactMap(\.activityKitId))
        for info in driver.runningActivities() where info.state != .dismissed {
            ids.insert(info.id)
        }
        for id in ids {
            requestEnd(id, content: nil, dismissal: .immediate)
        }
        file.records.removeAll()
        file.accountScope = userId
        persist()
    }

    // MARK: - Bridge mutations

    private func mutationPrecondition(account: String?) -> LiveActivityError? {
        guard driver.isSupported else { return .unsupported }
        guard loadIfNeeded() else { return .storeUnavailable }
        guard let account else { return .authSessionRequired }
        guard account == file.accountScope else { return .accountMismatch }
        return nil
    }

    private func track(_ definition: ContractDefinition, account: String?) async -> Outcome {
        if let error = mutationPrecondition(account: account) { return .rejected(error) }
        let context = await makeContext()
        do {
            try LiveActivityProtocol.validate(definition, currentDay: context.today, goals: await environment.goals(), now: context.now)
        } catch {
            return .rejected(error as? LiveActivityError ?? .invalidContract("\(error)"))
        }

        let index = upsert(definition, now: context.now)
        if file.records[index].terminal == nil {
            // An explicit open may bring back a card the person removed.
            file.records[index].suppressed = false
            file.focusCounter += 1
            file.records[index].focusSequence = file.focusCounter
            attachRunningTimer(to: index, context: context)
            await present(index, context: context, allowCreate: true)
        }
        refreshCards(context)
        persist()
        return .tracked(trackReply(for: definition.key))
    }

    /// The web app's full list after hydration. Updates definitions, forgets
    /// today's occurrences it no longer lists, keeps focus order and removed
    /// cards as they are, and never creates a card for an occurrence nobody
    /// opened.
    private func sync(_ entries: [SyncEntry], account: String?) async -> Outcome {
        if let error = mutationPrecondition(account: account) { return .rejected(error) }
        let context = await makeContext()
        let goals = await environment.goals()
        var listed: Set<OccurrenceKey> = []
        var rejected: [LiveActivityStateEntry] = []

        func reject(_ key: OccurrenceKey, _ code: String) {
            rejected.append(LiveActivityStateEntry(key: key, status: .failed, focused: false, reason: code, lastUpdatedAt: nil))
        }

        for entry in entries {
            switch entry {
            case .invalid(let key, let error):
                listed.insert(key)
                reject(key, error.code)
            case .valid(let definition):
                guard !listed.contains(definition.key) else {
                    reject(definition.key, "duplicate_occurrence")
                    continue
                }
                listed.insert(definition.key)
                do {
                    try LiveActivityProtocol.validate(definition, currentDay: context.today, goals: goals, now: context.now)
                } catch {
                    reject(definition.key, (error as? LiveActivityError)?.code ?? "invalid_contract")
                    continue
                }
                let index = upsert(definition, now: context.now)
                guard file.records[index].terminal == nil else { continue }
                attachRunningTimer(to: index, context: context)
                // Only a create the person already asked for is retried.
                let retry = [.needsForeground, .disabled].contains(file.records[index].presentation)
                await present(index, context: context, allowCreate: retry)
            }
        }

        let unlisted = file.records.map(\.key).filter { $0.healthDay == context.today.day && !listed.contains($0) }
        unlisted.forEach(removeRecord)
        refreshCards(context)
        persist()
        return .synced(stateEntries().entries + rejected)
    }

    private func stop(_ key: OccurrenceKey, account: String?) async -> Outcome {
        if let error = mutationPrecondition(account: account) { return .rejected(error) }
        removeRecord(key)
        refreshCards(await makeContext())
        persist()
        return .done
    }

    /// `START_TIMER` with a tracking context: the timer is business state and
    /// always starts; tracking and focus follow only once it has started, and a
    /// presentation problem is reported beside it instead of failing it.
    private func startTimer(_ request: TimerStart) async -> Outcome {
        let started = await environment.startTimer(
            activityId: request.activityId,
            activityName: request.activityName,
            durationSeconds: request.durationSeconds
        )
        func result(_ status: String, _ reason: String? = nil) -> Outcome {
            .timerStarted(TimerStartResult(started: started.started, replaced: started.replaced, liveActivityStatus: status, reason: reason))
        }
        guard driver.isSupported else { return result("unsupported") }
        guard loadIfNeeded() else { return result(PresentationStatus.failed.rawValue, LiveActivityError.storeUnavailable.code) }

        let context = await makeContext()
        // The replaced run leaves every other card now. On the card this start
        // is for, the new run simply takes its place below, so restarting a
        // contract's own timer does not end and recreate its card.
        let restartedKey = (try? request.definition.get())?.key
        if let replaced = started.replaced {
            await detachTimer(runId: replaced.runId, context: context, keeping: restartedKey)
        }

        var status = "rejected"
        var reason: String?
        switch request.definition {
        case .failure(let error):
            reason = error.code
        case .success(let definition):
            if let error = mutationPrecondition(account: request.account) {
                reason = error.code
                break
            }
            do {
                try LiveActivityProtocol.validate(definition, currentDay: context.today, goals: await environment.goals(), now: context.now)
            } catch {
                reason = (error as? LiveActivityError)?.code ?? "invalid_contract"
                break
            }
            let index = upsert(definition, now: context.now)
            if let terminal = file.records[index].terminal {
                status = PresentationStatus.ended.rawValue
                reason = terminal.rawValue
                if let replaced = started.replaced {
                    await detachTimer(runId: replaced.runId, context: context)
                }
                break
            }
            for other in file.records.indices where file.records[other].timerRunId == started.started.runId {
                file.records[other].timerRunId = nil
            }
            file.records[index].timerRunId = started.started.runId
            file.records[index].finishedTimer = nil
            file.records[index].suppressed = false
            file.focusCounter += 1
            file.records[index].focusSequence = file.focusCounter
            await present(index, context: context, allowCreate: true)
            let reply = trackReply(for: definition.key)
            status = reply.status.rawValue
            reason = reply.reason
        }
        if let replaced = started.replaced, file.records.contains(where: { $0.timerRunId == replaced.runId }) {
            // Validation failed after all; nothing took the replaced run's place.
            await detachTimer(runId: replaced.runId, context: context)
        }
        refreshCards(context)
        persist()
        return result(status, reason)
    }

    private func completion(_ request: Completion) async -> Outcome {
        if let error = mutationPrecondition(account: request.account) { return .rejected(error) }
        guard let index = file.records.firstIndex(where: { $0.key == request.scope.key }) else {
            return .completion(tracked: false, status: nil)
        }
        let context = await makeContext()
        if request.scope.isContract {
            if file.records[index].terminal == nil {
                complete(index, at: request.scope.completedAt ?? context.now, finishedTimer: nil, context: context)
            }
        } else {
            guard file.records[index].definition.activities.contains(where: { $0.activityId == request.activityId }) else {
                return .rejected(LiveActivityError(code: "invalid_activity_completion", message: "activityId is not part of this contract"))
            }
            if !file.records[index].slotCompletions.contains(request.activityId) {
                file.records[index].slotCompletions.append(request.activityId)
            }
            evaluateHealthCompletion(index, context: context)
        }
        refreshCards(context)
        persist()
        return .completion(tracked: true, status: stateEntries().entries.first { $0.key == request.scope.key }?.status)
    }

    // MARK: - Timer events

    /// A timer started without a tracking context (legacy `START_TIMER`, a
    /// resume). It attaches to today's tracked occurrence that declared this
    /// timer ID; it does not move focus.
    private func timerStarted(_ run: TimerRunSnapshot, replaced: TimerRunSnapshot?) async {
        guard driver.isSupported, loadIfNeeded(), file.accountScope != nil else { return }
        let context = await makeContext()
        if let replaced {
            await detachTimer(runId: replaced.runId, context: context)
        }
        if !file.records.contains(where: { $0.timerRunId == run.runId }),
           let index = file.records.firstIndex(where: { canAttach(run, to: $0, context: context) }) {
            file.records[index].timerRunId = run.runId
            file.records[index].finishedTimer = nil
            await present(index, context: context, allowCreate: true)
        }
        refreshCards(context)
        persist()
    }

    /// Cancelled, paused (cancel now, start again on resume), replaced or
    /// cleared. The card drops its timer; a timer-only card ends.
    private func timerDiscarded(_ run: TimerRunSnapshot) async {
        guard driver.isSupported, loadIfNeeded() else { return }
        let context = await makeContext()
        await detachTimer(runId: run.runId, context: context)
        refreshCards(context)
        persist()
    }

    /// The natural finish, reported once by `TestamentTimer` when native
    /// actually processes it. That can be long after `endsAt` if the app was
    /// suspended; until then the card counted down to zero and went stale.
    private func timerCompleted(_ run: TimerRunSnapshot) async {
        guard driver.isSupported, loadIfNeeded() else { return }
        let context = await makeContext()
        for index in file.records.indices where file.records[index].timerRunId == run.runId {
            file.records[index].timerRunId = nil
            let record = file.records[index]
            if record.definition.completionPolicy.completesOnTimer, run.endsAt <= record.definition.expiresAt {
                complete(index, at: run.endsAt, finishedTimer: run, context: context)
            } else {
                if !(record.definition.hasHealth && record.key.healthDay == context.today.day) {
                    // Nothing else to show: keep "time's up" until the web app
                    // confirms the contract or the occurrence expires.
                    file.records[index].finishedTimer = run
                }
                await present(index, context: context, allowCreate: false)
            }
        }
        refreshCards(context)
        persist()
    }

    private func detachTimer(runId: String, context: Context, keeping kept: OccurrenceKey? = nil) async {
        for index in file.records.indices where file.records[index].timerRunId == runId && file.records[index].key != kept {
            file.records[index].timerRunId = nil
            await present(index, context: context, allowCreate: false)
        }
    }

    private func attachRunningTimer(to index: Int, context: Context) {
        guard let timer = context.timer,
              !file.records.contains(where: { $0.timerRunId == timer.runId }),
              canAttach(timer, to: file.records[index], context: context) else { return }
        file.records[index].timerRunId = timer.runId
        file.records[index].finishedTimer = nil
    }

    /// A run belongs to the occurrence of the health day it started in; it
    /// never moves to the next day's occurrence.
    private func canAttach(_ run: TimerRunSnapshot, to record: TrackedRecord, context: Context) -> Bool {
        guard record.terminal == nil, record.timerRunId == nil,
              record.definition.timerActivityId == run.activityId else { return false }
        let runDay = HealthDayMath.info(containing: run.startedAt, resetHour: context.resetHour, calendar: environment.calendar)
        return runDay.day == record.key.healthDay
    }

    // MARK: - Health

    private func planHealthRead() async -> HealthReadPlan? {
        guard driver.isSupported, loadIfNeeded(), file.accountScope != nil else { return nil }
        let context = await makeContext()
        var queries: Set<HealthQuery> = []
        var targets: [OccurrenceKey: HealthReadTarget] = [:]
        for record in file.records where record.terminal == nil && record.definition.hasHealth && record.key.healthDay == context.today.day {
            let end = min(context.now, context.today.end, record.definition.expiresAt)
            guard end > context.today.start else { continue }
            var slotQueries: [String: HealthQuery] = [:]
            for activity in record.definition.healthActivities {
                guard let metric = activity.metric else { continue }
                let query = HealthQuery(metric: metric, start: context.today.start, end: end)
                slotQueries[activity.activityId] = query
                queries.insert(query)
            }
            targets[record.key] = HealthReadTarget(
                occurrenceToken: record.occurrenceToken,
                definitionGeneration: record.definitionGeneration,
                queries: slotQueries
            )
        }
        guard !queries.isEmpty else { return nil }
        readSequence += 1
        return HealthReadPlan(
            sequence: readSequence,
            accountGeneration: file.accountGeneration,
            readAt: context.now,
            dayStart: context.today.start,
            queries: queries.sorted { ($0.metric.rawValue, $0.end) < ($1.metric.rawValue, $1.end) },
            targets: targets
        )
    }

    /// A failed or locked read keeps the last good value and marks it
    /// unavailable; it never turns into zero. A successful read with no data
    /// clears the old value instead of passing it off as current. Totals may
    /// go down (samples can be deleted); a slot once reached stays reached for
    /// the occurrence, as it does in the web app.
    private func applyHealth(_ plan: HealthReadPlan, _ results: [HealthQuery: HealthTotalRead]) async {
        guard driver.isSupported, loaded, plan.accountGeneration == file.accountGeneration else { return }
        let context = await makeContext()
        for (key, target) in plan.targets {
            guard let index = file.records.firstIndex(where: { $0.key == key }),
                  file.records[index].occurrenceToken == target.occurrenceToken,
                  file.records[index].terminal == nil,
                  file.records[index].definitionGeneration == target.definitionGeneration,
                  file.records[index].lastAppliedReadSequence < plan.sequence else { continue }
            var record = file.records[index]
            record.lastAppliedReadSequence = plan.sequence
            for activity in record.definition.healthActivities {
                guard let metric = activity.metric, let goal = activity.target,
                      let query = target.queries[activity.activityId], query.metric == metric,
                      let read = results[query] else { continue }
                var progress = record.slots[activity.activityId]
                    ?? SlotProgress(metric: metric, value: nil, dataStatus: .waiting, measuredAt: nil, reachedAt: nil)
                switch read {
                case .value(let value):
                    progress.value = value
                    progress.dataStatus = .fresh
                    progress.measuredAt = plan.readAt
                    if value >= goal, progress.reachedAt == nil, plan.readAt <= record.definition.expiresAt {
                        progress.reachedAt = plan.readAt
                    }
                case .noData:
                    progress.value = nil
                    progress.dataStatus = .noData
                    progress.measuredAt = plan.readAt
                case .protectedDataUnavailable, .failed:
                    progress.dataStatus = progress.measuredAt == nil ? .waiting : .unavailable
                }
                record.slots[activity.activityId] = progress
            }
            file.records[index] = record
            evaluateHealthCompletion(index, context: context)
        }
        refreshCards(context)
        persist()
    }

    /// Every Health-mapped slot reached in this occurrence, the deployed web
    /// rule. One slot reached is progress, never the contract.
    private func evaluateHealthCompletion(_ index: Int, context: Context) {
        let record = file.records[index]
        let policy = record.definition.completionPolicy
        guard record.terminal == nil, policy.completesOnHealth, record.key.healthDay == context.today.day else { return }
        let required = record.definition.activities.filter { policy.requiredActivityIds.contains($0.activityId) }
        guard required.count == policy.requiredActivityIds.count,
              required.allSatisfy({ LiveActivityPresenter.isReached($0, in: record) }) else { return }
        let reachedAt = required.compactMap { record.slots[$0.activityId]?.reachedAt }.max() ?? context.now
        complete(index, at: min(reachedAt, context.now), finishedTimer: nil, context: context)
    }

    // MARK: - Lifecycle

    private func appBecameActive() async {
        guard driver.isSupported, loadIfNeeded(), file.accountScope != nil else { return }
        let context = await makeContext()
        await reconcileDays(context)
        for index in file.records.indices {
            let record = file.records[index]
            guard record.terminal == nil, record.activityKitId == nil, !record.suppressed,
                  [.needsForeground, .disabled].contains(record.presentation) else { continue }
            await present(index, context: context, allowCreate: true)
        }
        refreshCards(context)
        persist()
    }

    private func dayMayHaveChanged() async {
        guard driver.isSupported, loadIfNeeded(), file.accountScope != nil else { return }
        let context = await makeContext()
        await reconcileDays(context)
        refreshCards(context)
        persist()
    }

    /// Expiry and health-day rollover. Runs whenever the app gets to run; if it
    /// was suspended at the boundary this is when the card goes, not before.
    /// Finished occurrences of today stay visible to the state query; older
    /// ones are forgotten, since a new day is always a new occurrence.
    private func reconcileDays(_ context: Context) async {
        defer {
            file.records.removeAll { $0.terminal != nil && $0.key.healthDay != context.today.day && $0.activityKitId == nil }
        }
        for key in file.records.map(\.key) {
            guard let index = file.records.firstIndex(where: { $0.key == key }) else { continue }
            let record = file.records[index]
            guard record.terminal == nil else { continue }
            if record.definition.expiresAt <= context.now {
                finish(index, reason: .expired, context: context)
                continue
            }
            guard record.key.healthDay != context.today.day else { continue }
            let timerRunning = context.timer.map { $0.runId == record.timerRunId } ?? false
            if timerRunning {
                // Yesterday's Health no longer applies; the running timer keeps
                // its original occurrence until it finishes.
                await present(index, context: context, allowCreate: false)
            } else {
                finish(index, reason: .dayEnded, context: context)
            }
        }
    }

    // MARK: - Presentation

    /// Decides whether this occurrence should have a card and creates it when
    /// that is allowed. Content of live cards is pushed by `refreshCards`.
    private func present(_ index: Int, context: Context, allowCreate: Bool) async {
        var record = file.records[index]
        guard record.terminal == nil else { return }
        let healthIsCurrent = record.definition.hasHealth && record.key.healthDay == context.today.day
        let timerRunning = context.timer.map { $0.runId == record.timerRunId } ?? false
        let hasContent = healthIsCurrent || timerRunning || record.finishedTimer != nil

        guard hasContent else {
            // A timer-only contract that is not counting down has nothing to
            // show; its selection is kept for when the timer starts.
            if let id = record.activityKitId {
                requestEnd(id, content: nil, dismissal: .immediate)
                record.activityKitId = nil
            }
            if !record.suppressed {
                record.presentation = record.definition.timerActivityId != nil ? .awaitingTimer : .pending
                record.presentationReason = record.definition.timerActivityId != nil ? nil : "nothing_to_show"
            }
            file.records[index] = record
            return
        }
        if record.activityKitId != nil {
            record.presentation = .active
            record.presentationReason = nil
            file.records[index] = record
            return
        }
        // Removed by the person or ended by iOS: the status already says which,
        // and only an explicit open or start (which clears this) brings it back.
        guard !record.suppressed else { return }
        guard allowCreate else {
            // Waits for an explicit open or start; a failed create keeps its
            // own status (needs_foreground, limit_reached, …).
            if [.pending, .awaitingTimer, .active].contains(record.presentation) {
                record.presentation = .pending
                record.presentationReason = "awaiting_open"
            }
            file.records[index] = record
            return
        }

        func refuse(_ status: PresentationStatus, _ reason: String? = nil) {
            record.presentation = status
            record.presentationReason = reason
            file.records[index] = record
        }
        guard await environment.isAppInForeground() else { return refuse(.needsForeground) }
        guard driver.activitiesEnabled() else { return refuse(.disabled) }

        let score = relevanceScores(including: record.key)[record.key] ?? LiveActivityConfig.focusedRelevanceScore
        let content = LiveActivityPresenter.content(
            for: record, timer: context.timer, today: context.today, now: context.now,
            relevanceScore: score, previous: nil
        )
        let attributes = LiveActivityPresenter.attributes(for: record)
        guard LiveActivityPresenter.encodedSize(attributes: attributes, state: content.state) <= LiveActivityConfig.payloadByteLimit else {
            return refuse(.failed, "payload_too_large")
        }
        do {
            let id = try driver.request(attributes: attributes, content: content)
            record.activityKitId = id
            record.presentation = .active
            record.presentationReason = nil
            record.lastUpdatedAt = context.now
            file.records[index] = record
            cards[id] = CardOperations(desired: content, desiredVersion: 1, appliedVersion: 1)
            observe(id)
        } catch let error as DriverRequestError {
            // A refusal is a presentation state, never a reason to retry in a
            // loop or to end someone else's card.
            switch error {
            case .disabled: refuse(.disabled)
            case .limitReached: refuse(.limitReached)
            case .needsForeground: refuse(.needsForeground)
            case .payloadTooLarge: refuse(.failed, "payload_too_large")
            case .unsupported: refuse(.failed, "unsupported")
            case .failed: refuse(.failed, "activitykit_error")
            }
        } catch {
            refuse(.failed, "activitykit_error")
        }
    }

    /// Pushes current content, including relevance, to every live card. Cards
    /// whose content did not change get no ActivityKit call.
    private func refreshCards(_ context: Context) {
        let scores = relevanceScores()
        for index in file.records.indices {
            guard file.records[index].terminal == nil, let id = file.records[index].activityKitId else { continue }
            let content = LiveActivityPresenter.content(
                for: file.records[index], timer: context.timer, today: context.today, now: context.now,
                relevanceScore: scores[file.records[index].key] ?? 1, previous: cards[id]?.desired?.state
            )
            if scheduleUpdate(id, content) {
                file.records[index].lastUpdatedAt = context.now
            }
        }
    }

    /// The most recent explicit open or start scores 100, then down by one per
    /// earlier selection. Nothing else moves focus; when the focused card goes,
    /// the next most recent one is simply first.
    private func relevanceScores(including extra: OccurrenceKey? = nil) -> [OccurrenceKey: Double] {
        let live = file.records
            .filter { $0.terminal == nil && ($0.activityKitId != nil || $0.key == extra) }
            .sorted {
                if $0.focusSequence != $1.focusSequence { return $0.focusSequence > $1.focusSequence }
                return $0.createdSequence > $1.createdSequence
            }
        var scores: [OccurrenceKey: Double] = [:]
        for (rank, record) in live.enumerated() {
            scores[record.key] = max(1, LiveActivityConfig.focusedRelevanceScore - Double(rank))
        }
        return scores
    }

    private func complete(_ index: Int, at date: Date, finishedTimer: TimerRunSnapshot?, context: Context) {
        file.records[index].terminal = .completed
        file.records[index].completedAt = date
        file.records[index].timerRunId = nil
        if let finishedTimer { file.records[index].finishedTimer = finishedTimer }
        file.records[index].presentation = .ended
        file.records[index].presentationReason = TerminalReason.completed.rawValue
        guard let id = file.records[index].activityKitId else { return }
        // The result stays readable on the Lock Screen for a moment. This only
        // schedules removal of a card that has already ended.
        let dismissal = DriverDismissal.after(context.now.addingTimeInterval(LiveActivityConfig.completedDismissalDelay))
        requestEnd(id, content: LiveActivityPresenter.finalContent(for: file.records[index], now: context.now), dismissal: dismissal)
        file.records[index].activityKitId = nil
        file.records[index].lastUpdatedAt = context.now
    }

    /// Expired or out of its day. The Testament Timer is business state and is
    /// left running; only this card stops showing it.
    private func finish(_ index: Int, reason: TerminalReason, context: Context) {
        file.records[index].terminal = reason
        file.records[index].timerRunId = nil
        file.records[index].presentation = .ended
        file.records[index].presentationReason = reason.rawValue
        guard let id = file.records[index].activityKitId else { return }
        requestEnd(id, content: LiveActivityPresenter.finalContent(for: file.records[index], now: context.now), dismissal: .immediate)
        file.records[index].activityKitId = nil
    }

    private func removeRecord(_ key: OccurrenceKey) {
        guard let index = file.records.firstIndex(where: { $0.key == key }) else { return }
        if let id = file.records[index].activityKitId {
            requestEnd(id, content: nil, dismissal: .immediate)
        }
        file.records.remove(at: index)
    }

    private func upsert(_ incoming: ContractDefinition, now: Date) -> Int {
        var definition = incoming
        if let index = file.records.firstIndex(where: { $0.key == definition.key }) {
            var record = file.records[index]
            // Every contract can run the Testament Timer. A timer learned from
            // START_TIMER stays mapped when a later open or sync leaves it out,
            // so a reload mid-countdown cannot drop the timer from its card.
            if definition.timerActivityId == nil {
                definition.timerActivityId = record.definition.timerActivityId
            }
            if record.definition != definition {
                let health = Dictionary(uniqueKeysWithValues: definition.healthActivities.map { ($0.activityId, $0) })
                record.slots = record.slots.filter { health[$0.key]?.metric == $0.value.metric }
                let ids = Set(definition.activities.map(\.activityId))
                record.slotCompletions = record.slotCompletions.filter(ids.contains)
                if record.definition.timerActivityId != definition.timerActivityId {
                    record.timerRunId = nil
                    record.finishedTimer = nil
                }
                record.definition = definition
                record.definitionGeneration += 1
            }
            file.records[index] = record
            return index
        }
        file.createdCounter += 1
        file.records.append(TrackedRecord(
            definition: definition,
            occurrenceToken: UUID().uuidString,
            definitionGeneration: 1,
            createdSequence: file.createdCounter,
            focusSequence: 0,
            presentation: .pending,
            presentationReason: nil,
            activityKitId: nil,
            suppressed: false,
            terminal: nil,
            completedAt: nil,
            slots: [:],
            slotCompletions: [],
            lastAppliedReadSequence: 0,
            timerRunId: nil,
            finishedTimer: nil,
            trackedAt: now,
            lastUpdatedAt: nil
        ))
        return file.records.count - 1
    }

    // MARK: - Driver operations

    @discardableResult
    private func scheduleUpdate(_ id: String, _ content: DriverContent) -> Bool {
        var operations = cards[id] ?? CardOperations()
        guard operations.pendingEnd == nil, operations.desired != content else { return false }
        operations.desired = content
        operations.desiredVersion += 1
        cards[id] = operations
        pump(id)
        return true
    }

    /// End is terminal for the card: later updates are ignored and a stale
    /// result can never bring it back. A second end only matters when it
    /// removes the card sooner (sign-out while a result is still on show).
    private func requestEnd(_ id: String, content: DriverContent?, dismissal: DriverDismissal) {
        endedByNative.insert(id)
        var operations = cards[id] ?? CardOperations()
        if let pending = operations.pendingEnd {
            guard dismissal == .immediate, pending.dismissal != .immediate else { return }
            if operations.endSent {
                operations.removeImmediatelyAfterEnd = true
            } else {
                operations.pendingEnd = CardOperations.PendingEnd(content: pending.content, dismissal: .immediate)
            }
            cards[id] = operations
            return
        }
        operations.pendingEnd = CardOperations.PendingEnd(content: content, dismissal: dismissal)
        cards[id] = operations
        pump(id)
    }

    private func pump(_ id: String) {
        guard var operations = cards[id], !operations.inFlight else { return }
        let driver = self.driver
        if let end = operations.pendingEnd {
            guard !operations.endSent else { return }
            operations.inFlight = true
            operations.endSent = true
            cards[id] = operations
            Task {
                await driver.end(activityId: id, content: end.content, dismissal: end.dismissal)
                self.submit(.cardOperationFinished(activityId: id, version: Self.endVersion))
            }
            return
        }
        guard operations.desiredVersion > operations.appliedVersion, let content = operations.desired else { return }
        operations.inFlight = true
        let version = operations.desiredVersion
        cards[id] = operations
        Task {
            await driver.update(activityId: id, content: content)
            self.submit(.cardOperationFinished(activityId: id, version: version))
        }
    }

    private func cardOperationFinished(_ id: String, version: Int) {
        guard var operations = cards[id] else { return }
        if version == Self.endVersion {
            guard operations.removeImmediatelyAfterEnd else {
                cards[id] = nil
                return
            }
            operations = CardOperations()
            operations.pendingEnd = CardOperations.PendingEnd(content: nil, dismissal: .immediate)
            cards[id] = operations
            pump(id)
            return
        }
        operations.inFlight = false
        operations.appliedVersion = max(operations.appliedVersion, version)
        cards[id] = operations
        pump(id)
    }

    private func observe(_ id: String) {
        guard !observed.contains(id) else { return }
        observed.insert(id)
        driver.observe(activityId: id) { [weak self] state in
            self?.submit(.activityStateChanged(activityId: id, state: state))
        }
    }

    /// The person swiped the card away, or iOS ended it at its time limit.
    /// Nothing recreates it on its own: not a Health update, a reload or a
    /// sync. Focus falls to the next most recent card.
    private func activityStateChanged(_ id: String, _ state: DriverActivityState) async {
        guard state == .ended || state == .dismissed, !endedByNative.contains(id) else { return }
        cards[id] = nil
        guard let index = file.records.firstIndex(where: { $0.activityKitId == id }) else { return }
        file.records[index].activityKitId = nil
        if file.records[index].terminal == nil {
            file.records[index].suppressed = true
            file.records[index].presentation = state == .dismissed ? .dismissed : .ended
            file.records[index].presentationReason = state == .dismissed ? "dismissed" : "system_ended"
        }
        refreshCards(await makeContext())
        persist()
    }

    // MARK: - Deep links

    /// Only a token of the signed-in account's own records navigates anywhere.
    private func deepLink(_ target: ContractDeepLink.Target) {
        guard loadIfNeeded(), file.accountScope != nil,
              let record = file.records.first(where: {
                  $0.occurrenceToken.caseInsensitiveCompare(target.occurrenceToken) == .orderedSame
              }),
              record.key.contractId == target.contractId,
              record.key.healthDay == target.healthDay else { return }
        environment.contractOpened(eventId: UUID().uuidString, key: record.key)
    }

    // MARK: - State

    private func snapshot() -> LiveActivityStateSnapshot {
        let (focused, entries) = stateEntries()
        return LiveActivityStateSnapshot(
            supported: driver.isSupported,
            enabled: driver.activitiesEnabled(),
            focused: focused,
            tracked: entries
        )
    }

    private func stateEntries() -> (focused: OccurrenceKey?, entries: [LiveActivityStateEntry]) {
        let now = environment.now()
        let focused = relevanceScores().max { $0.value < $1.value }?.key
        let entries = file.records
            .sorted { $0.createdSequence < $1.createdSequence }
            .map { record -> LiveActivityStateEntry in
                var status = record.presentation
                var reason = record.presentationReason
                if let id = record.activityKitId {
                    status = .active
                    reason = nil
                    if let stale = cards[id]?.desired?.staleDate, stale <= now {
                        status = .stale
                    }
                }
                return LiveActivityStateEntry(
                    key: record.key, status: status, focused: record.key == focused,
                    reason: reason, lastUpdatedAt: record.lastUpdatedAt
                )
            }
        return (focused, entries)
    }

    /// What `LIVE_ACTIVITY_STATE_CHANGED` is about: statuses, reasons and the
    /// leading card. New Health numbers alone are not a state change.
    private func broadcastSignature() -> [String] {
        stateEntries().entries.map { "\($0.key)|\($0.status.rawValue)|\($0.focused)|\($0.reason ?? "")" }
    }

    private func trackReply(for key: OccurrenceKey) -> TrackReply {
        let entry = stateEntries().entries.first { $0.key == key }
        return TrackReply(key: key, focused: entry?.focused ?? false, status: entry?.status ?? .pending, reason: entry?.reason)
    }

    // MARK: - Storage and context

    private func loadIfNeeded() -> Bool {
        if loaded { return true }
        do {
            file = try persistence.load() ?? TrackedContractsFile()
            readSequence = file.records.map(\.lastAppliedReadSequence).max() ?? 0
            loaded = true
            return true
        } catch {
            return false
        }
    }

    private func persist() {
        guard loaded else { return }
        try? persistence.save(file)
    }

    private func makeContext() async -> Context {
        let now = environment.now()
        let resetHour = await environment.dayResetHour()
        let today = HealthDayMath.info(containing: now, resetHour: resetHour, calendar: environment.calendar)
        return Context(now: now, resetHour: resetHour, today: today, timer: await environment.currentTimer())
    }
}
