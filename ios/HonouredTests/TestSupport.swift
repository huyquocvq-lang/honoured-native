import XCTest

/// ActivityKit stand-in. Records every card, including ended ones, and lets a
/// test refuse requests, slow updates down or dismiss a card as a person would.
final class FakeDriver: LiveActivityDriving {
    struct Card {
        let id: String
        let attributes: DriverAttributes
        var content: DriverContent
        var state: DriverActivityState
        var dismissal: DriverDismissal?
        var updates = 0
    }

    private let lock = NSLock()
    private var storage: [String: Card] = [:]
    private var order: [String] = []
    private var observers: [String: @Sendable (DriverActivityState) -> Void] = [:]
    private var counter = 0

    var isSupported = true
    var enabled = true
    var requestError: DriverRequestError?
    /// Delays every update, to hold one in flight while something else happens.
    var updateDelayNanoseconds: UInt64 = 0

    private(set) var requestCount = 0

    func activitiesEnabled() -> Bool { locked { enabled } }

    func runningActivities() -> [DriverActivityInfo] {
        locked {
            order.compactMap { storage[$0] }
                .filter { $0.state != .dismissed }
                .map { DriverActivityInfo(id: $0.id, attributes: $0.attributes, state: $0.state) }
        }
    }

    func request(attributes: DriverAttributes, content: DriverContent) throws -> String {
        try locked {
            if let requestError { throw requestError }
            counter += 1
            requestCount += 1
            let id = "card-\(counter)"
            storage[id] = Card(id: id, attributes: attributes, content: content, state: .active)
            order.append(id)
            return id
        }
    }

    func update(activityId: String, content: DriverContent) async {
        let delay = locked { updateDelayNanoseconds }
        if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
        locked {
            guard var card = storage[activityId], card.state == .active || card.state == .stale else { return }
            card.content = content
            card.updates += 1
            storage[activityId] = card
        }
    }

    func end(activityId: String, content: DriverContent?, dismissal: DriverDismissal) async {
        locked {
            guard var card = storage[activityId], card.state != .dismissed else { return }
            if let content, card.state != .ended { card.content = content }
            card.state = dismissal == .immediate ? .dismissed : .ended
            card.dismissal = dismissal
            storage[activityId] = card
        }
    }

    func observe(activityId: String, onChange: @escaping @Sendable (DriverActivityState) -> Void) {
        locked { observers[activityId] = onChange }
    }

    // MARK: Test helpers

    /// A card created by an earlier process, as ActivityKit reports it on relaunch.
    func seed(attributes: DriverAttributes, content: DriverContent, state: DriverActivityState = .active) -> String {
        locked {
            counter += 1
            let id = "seeded-\(counter)"
            storage[id] = Card(id: id, attributes: attributes, content: content, state: state)
            order.append(id)
            return id
        }
    }

    /// The person swipes the card away.
    func dismissByUser(_ id: String) {
        let observer: (@Sendable (DriverActivityState) -> Void)? = locked {
            storage[id]?.state = .dismissed
            return observers[id]
        }
        observer?(.dismissed)
    }

    var all: [Card] { locked { order.compactMap { storage[$0] } } }
    var live: [Card] { all.filter { $0.state == .active || $0.state == .stale } }

    func liveCard(_ contractId: String) -> Card? {
        live.first { $0.attributes.contractId == contractId }
    }

    func anyCard(_ contractId: String) -> Card? {
        all.last { $0.attributes.contractId == contractId }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

/// Clock, account, timer and Health for the engine, all controllable.
final class FakeEnvironment: LiveActivityEnvironment {
    private let lock = NSLock()
    private var _now: Date
    private var _resetHour = 0
    private var _goals: [GoalSnapshot] = []
    private var _account: NativeAccountState = .signedIn("user-a")
    private var _timer: TimerRunSnapshot?
    private var _foreground = true
    private var _health: [HealthMetric: HealthTotalRead] = [:]
    private var _reads: [HealthQuery] = []
    private var _changes: [LiveActivityStateSnapshot] = []
    private var _opened: [OccurrenceKey] = []
    private var _readGate: (() async -> Void)?

    let calendar: Calendar

    init(now: Date, timeZone: TimeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!) {
        _now = now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    var clock: Date {
        get { locked { _now } }
        set { locked { _now = newValue } }
    }
    var resetHour: Int {
        get { locked { _resetHour } }
        set { locked { _resetHour = newValue } }
    }
    var goalList: [GoalSnapshot] {
        get { locked { _goals } }
        set { locked { _goals = newValue } }
    }
    var accountState: NativeAccountState {
        get { locked { _account } }
        set { locked { _account = newValue } }
    }
    var timer: TimerRunSnapshot? {
        get { locked { _timer } }
        set { locked { _timer = newValue } }
    }
    var foreground: Bool {
        get { locked { _foreground } }
        set { locked { _foreground = newValue } }
    }
    var health: [HealthMetric: HealthTotalRead] {
        get { locked { _health } }
        set { locked { _health = newValue } }
    }
    /// Runs inside every Health read, to hold reads open while a test acts.
    var readGate: (() async -> Void)? {
        get { locked { _readGate } }
        set { locked { _readGate = newValue } }
    }
    var reads: [HealthQuery] { locked { _reads } }
    var changes: [LiveActivityStateSnapshot] { locked { _changes } }
    var opened: [OccurrenceKey] { locked { _opened } }

    func now() -> Date { clock }
    func dayResetHour() async -> Int { resetHour }
    func goals() async -> [GoalSnapshot] { goalList }
    func account() async -> NativeAccountState { accountState }
    func currentTimer() async -> TimerRunSnapshot? { timer }
    func isAppInForeground() async -> Bool { foreground }

    func startTimer(activityId: String, activityName: String, durationSeconds: Double) async -> (started: TimerRunSnapshot, replaced: TimerRunSnapshot?) {
        locked {
            let replaced = _timer
            let run = TimerRunSnapshot(
                runId: UUID().uuidString, activityId: activityId, activityName: activityName,
                startedAt: _now, endsAt: _now.addingTimeInterval(durationSeconds)
            )
            _timer = run
            return (run, replaced)
        }
    }

    func readHealth(metric: HealthMetric, from: Date, to: Date) async -> HealthTotalRead {
        let gate = readGate
        await gate?()
        return locked {
            _reads.append(HealthQuery(metric: metric, start: from, end: to))
            return _health[metric] ?? .noData
        }
    }

    func stateChanged(_ snapshot: LiveActivityStateSnapshot) {
        locked { _changes.append(snapshot) }
    }

    func contractOpened(eventId: String, key: OccurrenceKey) {
        locked { _opened.append(key) }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

/// One engine wired to fakes, started and signed in as `user-a`.
struct EngineHarness {
    let engine: LiveActivityEngine
    let driver: FakeDriver
    let environment: FakeEnvironment
    let persistence: InMemoryTrackedContractsPersistence

    /// 2026-09-23 10:00 in Ho Chi Minh City (UTC+7, no DST).
    static let morning = Date(timeIntervalSince1970: 1_790_132_400)

    static func make(
        now: Date = morning,
        persistence: InMemoryTrackedContractsPersistence = InMemoryTrackedContractsPersistence(),
        driver: FakeDriver = FakeDriver(),
        environment: FakeEnvironment? = nil,
        signIn: String? = "user-a"
    ) async -> EngineHarness {
        let environment = environment ?? FakeEnvironment(now: now)
        if let signIn { environment.accountState = .signedIn(signIn) }
        let engine = LiveActivityEngine(driver: driver, environment: environment, persistence: persistence)
        engine.start()
        _ = await engine.perform(.restore)
        if let signIn { _ = await engine.perform(.accountChanged(signIn)) }
        return EngineHarness(engine: engine, driver: driver, environment: environment, persistence: persistence)
    }

    var today: String {
        HealthDayMath.info(containing: environment.clock, resetHour: environment.resetHour, calendar: environment.calendar).day
    }

    // MARK: Definitions

    func healthContract(
        _ id: String,
        slots: [(slot: TrackedSlot, metric: HealthMetric, target: Double)] = [(.primary, .steps, 8000)],
        policy: String = "all_health_slots",
        timer: Bool = true,
        expiresIn: TimeInterval = 6 * 3600,
        day: String? = nil
    ) -> ContractDefinition {
        let activities = slots.map {
            TrackedActivity(activityId: "\(id):\($0.slot.rawValue)", slot: $0.slot, name: "\($0.metric.rawValue) \(id)", mode: .health, metric: $0.metric, target: $0.target)
        }
        let ids = activities.map(\.activityId)
        let completion: CompletionPolicy
        switch policy {
        case "all_health_slots_or_timer": completion = .allHealthSlotsOrTimer(requiredActivityIds: ids, timerActivityId: id)
        case "web_authoritative": completion = .webAuthoritative
        default: completion = .allHealthSlots(requiredActivityIds: ids)
        }
        return ContractDefinition(
            contractId: id, contractName: "Contract \(id)", healthDay: day ?? today,
            expiresAt: environment.clock.addingTimeInterval(expiresIn), completionPolicy: completion,
            activities: activities, timerActivityId: timer ? id : nil
        )
    }

    func timerContract(_ id: String, policy: CompletionPolicy? = nil) -> ContractDefinition {
        ContractDefinition(
            contractId: id, contractName: "Timer \(id)", healthDay: today,
            expiresAt: environment.clock.addingTimeInterval(6 * 3600),
            completionPolicy: policy ?? .timerCompletion(timerActivityId: id),
            activities: [TrackedActivity(activityId: id, slot: .primary, name: "Sit", mode: .timer)],
            timerActivityId: id
        )
    }

    /// Makes `SET_GOALS` agree with these definitions.
    func setGoals(for definitions: [ContractDefinition]) {
        environment.goalList = definitions.flatMap { definition in
            definition.healthActivities.map { GoalSnapshot(activityId: $0.activityId, metric: $0.metric!, target: $0.target!) }
        }
    }

    // MARK: Commands

    @discardableResult
    func track(_ definition: ContractDefinition, account: String? = "user-a") async -> LiveActivityEngine.Outcome {
        await engine.perform(.track(definition, account: account))
    }

    func state() async -> LiveActivityStateSnapshot {
        guard case .state(let snapshot) = await engine.perform(.getState) else {
            XCTFail("no state")
            return LiveActivityStateSnapshot(supported: false, enabled: false, focused: nil, tracked: [])
        }
        return snapshot
    }

    func entry(_ contractId: String) async -> LiveActivityStateEntry? {
        await state().tracked.first { $0.key.contractId == contractId }
    }

    /// Waits for queued ActivityKit calls to land.
    func settle() async {
        for _ in 0..<20 {
            _ = await engine.perform(.getState)
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

func trackReply(_ outcome: LiveActivityEngine.Outcome, file: StaticString = #filePath, line: UInt = #line) -> LiveActivityEngine.TrackReply? {
    guard case .tracked(let reply) = outcome else {
        XCTFail("expected tracked, got \(outcome)", file: file, line: line)
        return nil
    }
    return reply
}

func rejection(_ outcome: LiveActivityEngine.Outcome) -> String? {
    if case .rejected(let error) = outcome { return error.code }
    return nil
}
