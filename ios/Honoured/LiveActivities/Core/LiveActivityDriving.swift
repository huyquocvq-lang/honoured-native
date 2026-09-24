import Foundation

/// ActivityKit behind a protocol. `ActivityKitDriver` is the real one; tests
/// use a fake that records calls and can refuse requests or dismiss cards.
protocol LiveActivityDriving: AnyObject {
    /// The OS can run Live Activities with relevance scores (iOS 16.2+).
    var isSupported: Bool { get }
    /// The person allows Live Activities for this app right now.
    func activitiesEnabled() -> Bool
    /// Every Honoured card iOS still knows about, including ones created before
    /// a relaunch. The source of truth on restore, not the persisted IDs.
    func runningActivities() -> [DriverActivityInfo]
    /// Starts a card. Must be called while the app is in the foreground.
    func request(attributes: DriverAttributes, content: DriverContent) throws -> String
    func update(activityId: String, content: DriverContent) async
    func end(activityId: String, content: DriverContent?, dismissal: DriverDismissal) async
    /// Reports state changes of a card (dismissed by the person, ended by iOS).
    func observe(activityId: String, onChange: @escaping @Sendable (DriverActivityState) -> Void)
}

struct DriverAttributes: Codable, Equatable {
    let contractId: String
    let healthDay: String
    let occurrenceToken: String
}

struct DriverContent: Equatable {
    var state: HonouredLiveActivityState
    /// When iOS should treat the card as out of date. Not an end time.
    var staleDate: Date?
    var relevanceScore: Double
}

enum DriverDismissal: Equatable {
    case immediate
    case after(Date)
}

enum DriverActivityState: Equatable {
    case active
    case stale
    case ended
    case dismissed
    case other
}

struct DriverActivityInfo: Equatable {
    let id: String
    let attributes: DriverAttributes
    let state: DriverActivityState

    var isLive: Bool { state == .active || state == .stale || state == .other }
}

enum DriverRequestError: Error, Equatable {
    case disabled
    case limitReached
    case needsForeground
    case payloadTooLarge
    case unsupported
    case failed(String)
}

/// Everything the engine needs from the rest of the app. The app wires the
/// real services in `LiveActivityCoordinator`; tests pass fakes.
protocol LiveActivityEnvironment: AnyObject {
    func now() -> Date
    var calendar: Calendar { get }
    func dayResetHour() async -> Int
    /// Goals from the latest `SET_GOALS`.
    func goals() async -> [GoalSnapshot]
    func account() async -> NativeAccountState
    func currentTimer() async -> TimerRunSnapshot?
    /// Starts the Testament Timer, replacing any running one.
    func startTimer(activityId: String, activityName: String, durationSeconds: Double) async -> (started: TimerRunSnapshot, replaced: TimerRunSnapshot?)
    /// Foreground (active or inactive), where ActivityKit accepts new cards.
    func isAppInForeground() async -> Bool
    func readHealth(metric: HealthMetric, from: Date, to: Date) async -> HealthTotalRead
    /// Unsolicited `LIVE_ACTIVITY_STATE_CHANGED`.
    func stateChanged(_ snapshot: LiveActivityStateSnapshot)
    /// `LIVE_ACTIVITY_OPENED`, delivered once the web app is ready.
    func contractOpened(eventId: String, key: OccurrenceKey)
}
