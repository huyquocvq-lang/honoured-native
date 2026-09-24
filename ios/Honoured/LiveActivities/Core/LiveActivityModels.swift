import Foundation

// Pure model for contract Live Activities. Nothing in `Core/` touches app
// singletons, ActivityKit or HealthKit queries, so the unit tests compile it on
// its own with fake drivers and clocks.

enum LiveActivityConfig {
    static let protocolVersion = 1
    static let minimumOS = "16.2"
    static let maxContractNameLength = 80
    static let maxActivityNameLength = 60
    static let maxSlots = 2
    /// ActivityKit's limit for attributes plus content state.
    static let payloadByteLimit = 4096
    /// A UX default from the plan, not a HealthKit promise: a Health reading
    /// older than this makes the card stale. Tune it here after device QA.
    static let healthStaleInterval: TimeInterval = 60 * 60
    /// How long a finished card stays on the Lock Screen to show its result.
    /// It governs removal of an already ended card only.
    static let completedDismissalDelay: TimeInterval = 30
    static let replyCacheLimit = 64
    /// Upper bound for one `SYNC_TRACKED_CONTRACTS`; iOS shows far fewer cards.
    static let maxTrackedContracts = 20
    static let focusedRelevanceScore = 100.0
}

/// One contract on one health day. Standing contracts get a new contract ID
/// every day in the web app, and a contract that spans a day boundary is a
/// separate occurrence per day, so a new day never updates yesterday's card.
struct OccurrenceKey: Hashable, Codable, CustomStringConvertible {
    let contractId: String
    let healthDay: String

    var description: String { "\(contractId)@\(healthDay)" }
}

enum TrackedSlot: String, Codable, CaseIterable {
    case primary
    case secondary
}

enum TrackedActivityMode: String, Codable {
    /// Measured from HealthKit against a goal the web app also sent in `SET_GOALS`.
    case health
    /// Completed by the Testament Timer; its `activityId` is the timer's.
    case timer
    /// Not measurable; shown by name only.
    case manual
}

struct TrackedActivity: Codable, Equatable {
    var activityId: String
    var slot: TrackedSlot
    var name: String
    var mode: TrackedActivityMode
    var metric: HealthMetric?
    /// Canonical unit of `metric`.
    var target: Double?
    /// `km` or `mi` for distance metrics, display only.
    var displayUnit: String?
}

/// When native may present an occurrence as honoured by itself. Mirrors the
/// rules of the deployed web app (checked 23/09 against the production
/// bundle): a contract is honoured once every Health-mapped slot is reached on
/// the same health day, or when its Testament Timer finishes naturally, or
/// when the person reports it. Only the web app records the outcome; native
/// uses this to decide what the card shows and when it ends.
enum CompletionPolicy: Codable, Equatable {
    case allHealthSlots(requiredActivityIds: [String])
    case timerCompletion(timerActivityId: String)
    case allHealthSlotsOrTimer(requiredActivityIds: [String], timerActivityId: String)
    /// Progress only; the card ends as honoured when the web app confirms it
    /// with `ACTIVITY_COMPLETED { scope: "contract" }`.
    case webAuthoritative

    var kind: String {
        switch self {
        case .allHealthSlots: return "all_health_slots"
        case .timerCompletion: return "timer_completion"
        case .allHealthSlotsOrTimer: return "all_health_slots_or_timer"
        case .webAuthoritative: return "web_authoritative"
        }
    }

    var requiredActivityIds: [String] {
        switch self {
        case .allHealthSlots(let ids), .allHealthSlotsOrTimer(let ids, _): return ids
        case .timerCompletion, .webAuthoritative: return []
        }
    }

    var timerActivityId: String? {
        switch self {
        case .timerCompletion(let id), .allHealthSlotsOrTimer(_, let id): return id
        case .allHealthSlots, .webAuthoritative: return nil
        }
    }

    var completesOnHealth: Bool { !requiredActivityIds.isEmpty }
    var completesOnTimer: Bool { timerActivityId != nil }
}

struct ContractDefinition: Codable, Equatable {
    var contractId: String
    var contractName: String
    var healthDay: String
    var expiresAt: Date
    var completionPolicy: CompletionPolicy
    var activities: [TrackedActivity]
    /// Testament Timer activity ID mapped to this contract. The web app starts
    /// timers with the contract ID, so that is what it normally is.
    var timerActivityId: String?

    var key: OccurrenceKey { OccurrenceKey(contractId: contractId, healthDay: healthDay) }
    var healthActivities: [TrackedActivity] { activities.filter { $0.mode == .health } }
    var hasHealth: Bool { !healthActivities.isEmpty }
}

/// A goal from the latest `SET_GOALS`, the single source of Health targets.
struct GoalSnapshot: Equatable {
    let activityId: String
    let metric: HealthMetric
    let target: Double
}

// MARK: - Health day

struct HealthDayInfo: Equatable {
    let day: String
    let start: Date
    let end: Date
}

/// The health-day boundary used everywhere: local midnight shifted by the
/// user's reset hour. `HealthSyncSettings` delegates here so `health_daily`,
/// goal detection and Live Activity windows can never disagree.
enum HealthDayMath {
    static func dayStart(containing date: Date, resetHour: Int, calendar: Calendar) -> Date {
        let midnight = calendar.startOfDay(for: date)
        let todayBoundary = calendar.date(byAdding: .hour, value: resetHour, to: midnight) ?? midnight
        if date >= todayBoundary { return todayBoundary }
        return calendar.date(byAdding: .day, value: -1, to: todayBoundary) ?? todayBoundary
    }

    static func dayString(_ dayStart: Date, calendar: Calendar) -> String {
        dayFormatter(calendar).string(from: dayStart)
    }

    static func info(containing date: Date, resetHour: Int, calendar: Calendar) -> HealthDayInfo {
        let start = dayStart(containing: date, resetHour: resetHour, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return HealthDayInfo(day: dayString(start, calendar: calendar), start: start, end: end)
    }

    /// The window a named health day covers under `resetHour`.
    static func window(forDay day: String, resetHour: Int, calendar: Calendar) -> HealthDayInfo? {
        guard let date = dayFormatter(calendar).date(from: day) else { return nil }
        let midnight = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .hour, value: resetHour, to: midnight) ?? midnight
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        guard dayString(start, calendar: calendar) == day else { return nil }
        return HealthDayInfo(day: day, start: start, end: end)
    }

    private static func dayFormatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

// MARK: - Records

/// Presentation of the card, kept apart from the contract's business state.
/// `stale` and `disabled` never mean the contract failed.
enum PresentationStatus: String, Codable {
    case pending
    case active
    case stale
    case awaitingTimer = "awaiting_timer"
    case needsForeground = "needs_foreground"
    case disabled
    case limitReached = "limit_reached"
    case dismissed
    case ended
    case failed
}

enum TerminalReason: String, Codable {
    case completed
    case expired
    case dayEnded = "day_ended"
}

/// Cached Health progress of one slot. `value == nil` is unknown, never zero.
struct SlotProgress: Codable, Equatable {
    var metric: HealthMetric
    var value: Double?
    var dataStatus: HonouredLiveActivityState.DataStatus
    var measuredAt: Date?
    /// First reading at or above the target in this occurrence. Sticky, like
    /// the web app's reached-slot store: a later deletion or a raised target
    /// does not take it back.
    var reachedAt: Date?
}

struct TrackedRecord: Codable, Equatable {
    var definition: ContractDefinition
    /// Random, per occurrence; goes into the ActivityKit attributes and the
    /// deep link so both can be matched back to this account's record.
    var occurrenceToken: String
    /// Bumped whenever the definition changes, so Health results read for an
    /// older definition are discarded.
    var definitionGeneration: Int
    var createdSequence: Int
    /// Native-issued order of explicit opens and starts. 0 = never selected.
    var focusSequence: Int
    var presentation: PresentationStatus
    var presentationReason: String?
    var activityKitId: String?
    /// The person (or iOS) removed the card. Nothing recreates it until the
    /// next explicit open or start.
    var suppressed: Bool
    var terminal: TerminalReason?
    var completedAt: Date?
    var slots: [String: SlotProgress]
    var slotCompletions: [String]
    var lastAppliedReadSequence: Int
    /// Testament Timer run attached to this occurrence.
    var timerRunId: String?
    /// Kept after a natural finish when the card stays up, so it can show it.
    var finishedTimer: TimerRunSnapshot?
    var trackedAt: Date
    var lastUpdatedAt: Date?

    var key: OccurrenceKey { definition.key }
}

/// The persisted store: one account's records plus the native counters.
struct TrackedContractsFile: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = TrackedContractsFile.currentSchemaVersion
    var accountScope: String?
    var accountGeneration = 0
    var focusCounter = 0
    var createdCounter = 0
    var records: [TrackedRecord] = []
}

// MARK: - Inputs from the rest of the app

/// A HealthKit read that keeps "no data" apart from "could not read".
enum HealthTotalRead: Equatable, Sendable {
    case value(Double)
    case noData
    case protectedDataUnavailable
    case failed

    var numericValue: Double? {
        if case .value(let value) = self { return value }
        return nil
    }
}

struct TimerRunSnapshot: Codable, Equatable, Sendable {
    let runId: String
    let activityId: String
    let activityName: String
    let startedAt: Date
    let endsAt: Date
}

enum NativeAccountState: Equatable {
    case signedIn(String)
    case signedOut
    /// The Keychain cannot be read yet (before first unlock).
    case unavailable
}

// MARK: - Errors

struct LiveActivityError: Error, Equatable {
    let code: String
    let message: String
    var details: [String: String] = [:]

    static func invalidEnvelope(_ message: String) -> LiveActivityError {
        LiveActivityError(code: "invalid_envelope", message: message)
    }

    static func invalidContract(_ message: String) -> LiveActivityError {
        LiveActivityError(code: "invalid_contract", message: message)
    }

    static let staleBridgeSession = LiveActivityError(
        code: "stale_bridge_session",
        message: "bridgeSessionId does not belong to this page and account; use the latest liveActivityBridgeSessionId"
    )
    static let staleSequence = LiveActivityError(
        code: "stale_sequence",
        message: "clientSequence must increase within a bridge session"
    )
    static let requestIdReused = LiveActivityError(
        code: "request_id_reused",
        message: "requestId was already used for a different clientSequence"
    )
    static let authSessionRequired = LiveActivityError(
        code: "auth_session_required",
        message: "Send SET_AUTH_SESSION before Live Activity mutations"
    )
    static let accountMismatch = LiveActivityError(
        code: "account_mismatch",
        message: "The signed-in account changed; resend with the new session"
    )
    static let unsupported = LiveActivityError(
        code: "live_activities_unsupported",
        message: "Live Activities need iOS \(LiveActivityConfig.minimumOS) or later"
    )
    static let storeUnavailable = LiveActivityError(
        code: "store_unavailable",
        message: "Live Activity state cannot be read until the device is unlocked"
    )
    static let occurrenceExpired = LiveActivityError(
        code: "occurrence_expired",
        message: "expiresAt has already passed"
    )

    static func healthDayMismatch(expected: String) -> LiveActivityError {
        LiveActivityError(
            code: "health_day_mismatch",
            message: "healthDay is not the current health day; resync the reset hour and resend",
            details: ["expectedHealthDay": expected]
        )
    }

    static func goalDefinitionMismatch(activityId: String) -> LiveActivityError {
        LiveActivityError(
            code: "goal_definition_mismatch",
            message: "Health activity \(activityId) must match a goal from the latest SET_GOALS (activityId, metric, target, unit)",
            details: ["activityId": activityId]
        )
    }

    var payload: [String: Any] {
        var payload: [String: Any] = ["message": message, "code": code]
        for (key, value) in details { payload[key] = value }
        return payload
    }
}
