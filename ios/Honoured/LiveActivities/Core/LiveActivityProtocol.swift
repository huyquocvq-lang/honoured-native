import Foundation

/// Parsing and validation for the Live Activity bridge messages. The checks
/// here are structural; `validate(_:currentDay:goals:now:)` adds the ones that
/// need app state, and the engine checks the account.
enum LiveActivityProtocol {
    static let stopReasons: Set<String> = [
        "user_stopped", "contract_cancelled", "contract_deleted", "contract_expired", "contract_broken"
    ]
    static let cancelReasons: Set<String> = ["paused", "cancelled"]
    static let completionScopes: Set<String> = ["contract", "slot"]

    /// Carried by every Live Activity mutation. `bridgeSessionId` is issued by
    /// native per page load and account; `clientSequence` is assigned by the web
    /// app when the person acts and must increase within the session.
    struct MutationEnvelope: Equatable {
        let requestId: String
        let bridgeSessionId: String
        let clientSequence: Int
    }

    static func envelope(from payload: [String: Any], context: [String: Any]? = nil) throws -> MutationEnvelope {
        let source = context ?? payload
        guard let requestId = payload["requestId"] as? String, HonouredIdentifiers.isValidIdentifier(requestId) else {
            throw LiveActivityError.invalidEnvelope("requestId is required for Live Activity mutations")
        }
        guard let sessionId = source["bridgeSessionId"] as? String, HonouredIdentifiers.isValidIdentifier(sessionId) else {
            throw LiveActivityError.invalidEnvelope("bridgeSessionId is required")
        }
        guard let sequence = integer(source["clientSequence"]), sequence > 0 else {
            throw LiveActivityError.invalidEnvelope("clientSequence must be a positive integer")
        }
        return MutationEnvelope(requestId: requestId, bridgeSessionId: sessionId, clientSequence: sequence)
    }

    // MARK: - Contract definition

    /// - Parameter startingTimer: the `activityId` of a `START_TIMER` carrying
    ///   this definition. It becomes the contract's timer when the definition
    ///   names none, and must match when it does.
    static func contractDefinition(from raw: Any?, startingTimer: String? = nil) throws -> ContractDefinition {
        guard let object = raw as? [String: Any] else {
            throw LiveActivityError.invalidContract("contract must be an object")
        }
        let contractId = try identifier(object["contractId"], field: "contractId")
        let contractName = try displayName(object["contractName"], field: "contractName", limit: LiveActivityConfig.maxContractNameLength)
        guard let healthDay = object["healthDay"] as? String, HonouredIdentifiers.isValidHealthDay(healthDay) else {
            throw LiveActivityError.invalidContract("healthDay must be yyyy-MM-dd")
        }
        guard let expiresAt = date(object["expiresAt"]) else {
            throw LiveActivityError.invalidContract("expiresAt must be ISO 8601 with an offset")
        }
        guard let rawActivities = object["activities"] as? [Any],
              (1...LiveActivityConfig.maxSlots).contains(rawActivities.count) else {
            throw LiveActivityError.invalidContract("activities must hold one or two slots")
        }

        let activities = try rawActivities.map(activity)
        guard Set(activities.map(\.activityId)).count == activities.count else {
            throw LiveActivityError.invalidContract("activityId values must be unique")
        }
        guard Set(activities.map(\.slot)).count == activities.count else {
            throw LiveActivityError.invalidContract("each slot may appear once")
        }
        let timerActivities = activities.filter { $0.mode == .timer }
        guard timerActivities.count <= 1 else {
            throw LiveActivityError.invalidContract("a contract has at most one timer activity")
        }

        let declaredTimer = try optionalIdentifier(object["timerActivityId"], field: "timerActivityId")
        if let declaredTimer, let slotTimer = timerActivities.first?.activityId, declaredTimer != slotTimer {
            throw LiveActivityError.invalidContract("timerActivityId must match the timer activity")
        }
        let namedTimer = timerActivities.first?.activityId ?? declaredTimer
        if let startingTimer, let namedTimer, namedTimer != startingTimer {
            throw LiveActivityError.invalidContract("the contract's timer must be the activityId being started")
        }
        let timerActivityId = namedTimer ?? startingTimer

        let policy = try completionPolicy(object["completionPolicy"], activities: activities, timerActivityId: timerActivityId)
        return ContractDefinition(
            contractId: contractId,
            contractName: contractName,
            healthDay: healthDay,
            expiresAt: expiresAt,
            completionPolicy: policy,
            activities: activities,
            timerActivityId: timerActivityId
        )
    }

    private static func activity(_ raw: Any) throws -> TrackedActivity {
        guard let object = raw as? [String: Any] else {
            throw LiveActivityError.invalidContract("each activity must be an object")
        }
        let activityId = try identifier(object["activityId"], field: "activityId")
        guard let slotName = object["slot"] as? String, let slot = TrackedSlot(rawValue: slotName) else {
            throw LiveActivityError.invalidContract("slot must be primary or secondary")
        }
        let name = try displayName(object["name"], field: "name", limit: LiveActivityConfig.maxActivityNameLength)
        guard let modeName = object["mode"] as? String, let mode = TrackedActivityMode(rawValue: modeName) else {
            throw LiveActivityError.invalidContract("mode must be health, timer or manual")
        }

        guard mode == .health else {
            guard present(object["metric"]) == nil, present(object["target"]) == nil, present(object["unit"]) == nil else {
                throw LiveActivityError.invalidContract("metric, target and unit belong to health activities only")
            }
            return TrackedActivity(activityId: activityId, slot: slot, name: name, mode: mode)
        }

        guard let metricName = object["metric"] as? String, let metric = HealthMetric(rawValue: metricName) else {
            throw LiveActivityError.invalidContract("health activity \(activityId) needs a known metric")
        }
        guard let target = number(object["target"]), target.isFinite, target > 0 else {
            throw LiveActivityError.invalidContract("health activity \(activityId) needs a positive finite target")
        }
        guard let unit = object["unit"] as? String, unit == metric.unitName else {
            throw LiveActivityError.invalidContract("health activity \(activityId) must use the canonical unit \(metric.unitName)")
        }
        var displayUnit: String?
        if let rawUnit = present(object["displayUnit"]) {
            let isDistance = [HealthMetric.distanceWalkingRunning, .distanceCycling, .distanceSwimming].contains(metric)
            guard isDistance, let value = rawUnit as? String, value == "km" || value == "mi" else {
                throw LiveActivityError.invalidContract("displayUnit is km or mi, for distance metrics only")
            }
            displayUnit = value
        }
        return TrackedActivity(
            activityId: activityId, slot: slot, name: name, mode: .health,
            metric: metric, target: target, displayUnit: displayUnit
        )
    }

    private static func completionPolicy(_ raw: Any?, activities: [TrackedActivity], timerActivityId: String?) throws -> CompletionPolicy {
        guard let object = raw as? [String: Any], let kind = object["kind"] as? String else {
            throw LiveActivityError.invalidContract("completionPolicy.kind is required")
        }
        let healthIds = Set(activities.filter { $0.mode == .health }.map(\.activityId))

        func required() throws -> [String] {
            guard let ids = object["requiredActivityIds"] as? [String], Set(ids).count == ids.count else {
                throw LiveActivityError.invalidContract("requiredActivityIds must be a list of unique IDs")
            }
            // Mirrors the web rule: every Health-mapped slot, never a subset.
            guard !healthIds.isEmpty, Set(ids) == healthIds else {
                throw LiveActivityError.invalidContract("requiredActivityIds must name exactly the contract's health activities")
            }
            return ids
        }

        func timer() throws -> String {
            guard let id = object["timerActivityId"] as? String, let timerActivityId, id == timerActivityId else {
                throw LiveActivityError.invalidContract("completionPolicy.timerActivityId must name the contract's timer")
            }
            return id
        }

        switch kind {
        case "all_health_slots":
            return .allHealthSlots(requiredActivityIds: try required())
        case "timer_completion":
            return .timerCompletion(timerActivityId: try timer())
        case "all_health_slots_or_timer":
            return .allHealthSlotsOrTimer(requiredActivityIds: try required(), timerActivityId: try timer())
        case "web_authoritative":
            return .webAuthoritative
        default:
            throw LiveActivityError.invalidContract("unknown completionPolicy.kind \(kind)")
        }
    }

    /// Checks that need the app's state. Health targets have a single source,
    /// `SET_GOALS`: a definition that disagrees is refused rather than creating
    /// a second target for the same activity.
    static func validate(_ definition: ContractDefinition, currentDay: HealthDayInfo, goals: [GoalSnapshot], now: Date) throws {
        guard definition.healthDay == currentDay.day else {
            throw LiveActivityError.healthDayMismatch(expected: currentDay.day)
        }
        guard definition.expiresAt > now else {
            throw LiveActivityError.occurrenceExpired
        }
        for activity in definition.healthActivities {
            guard let goal = goals.first(where: { $0.activityId == activity.activityId }),
                  goal.metric == activity.metric,
                  let target = activity.target,
                  abs(goal.target - target) <= max(1e-9, abs(target) * 1e-9) else {
                throw LiveActivityError.goalDefinitionMismatch(activityId: activity.activityId)
            }
        }
    }

    // MARK: - Other payloads

    static func stopRequest(from payload: [String: Any]) throws -> (key: OccurrenceKey, reason: String) {
        let contractId = try identifier(payload["contractId"], field: "contractId", code: "invalid_stop")
        guard let healthDay = payload["healthDay"] as? String, HonouredIdentifiers.isValidHealthDay(healthDay) else {
            throw LiveActivityError(code: "invalid_stop", message: "healthDay must be yyyy-MM-dd")
        }
        guard let reason = payload["reason"] as? String, stopReasons.contains(reason) else {
            throw LiveActivityError(code: "invalid_stop", message: "reason must be one of \(stopReasons.sorted().joined(separator: ", "))")
        }
        return (OccurrenceKey(contractId: contractId, healthDay: healthDay), reason)
    }

    struct CompletionScope: Equatable {
        let key: OccurrenceKey
        let isContract: Bool
        let completedAt: Date?
    }

    /// The optional additions to `ACTIVITY_COMPLETED`. Nil for a legacy payload,
    /// which keeps marking the celebration exactly as before.
    static func completionScope(from payload: [String: Any]) throws -> CompletionScope? {
        let scopeFields = ["scope", "contractId", "healthDay", "completedAt"]
        guard scopeFields.contains(where: { present(payload[$0]) != nil }) else { return nil }
        guard let scope = payload["scope"] as? String, completionScopes.contains(scope) else {
            throw LiveActivityError(code: "invalid_activity_completion", message: "scope must be contract or slot")
        }
        let contractId = try identifier(payload["contractId"], field: "contractId", code: "invalid_activity_completion")
        guard let healthDay = payload["healthDay"] as? String, HonouredIdentifiers.isValidHealthDay(healthDay) else {
            throw LiveActivityError(code: "invalid_activity_completion", message: "healthDay must be yyyy-MM-dd")
        }
        var completedAt: Date?
        if let raw = present(payload["completedAt"]) {
            guard let parsed = date(raw) else {
                throw LiveActivityError(code: "invalid_activity_completion", message: "completedAt must be ISO 8601")
            }
            completedAt = parsed
        }
        return CompletionScope(
            key: OccurrenceKey(contractId: contractId, healthDay: healthDay),
            isContract: scope == "contract",
            completedAt: completedAt
        )
    }

    // MARK: - Replies

    static func capabilities(supported: Bool, enabled: Bool) -> [String: Any] {
        [
            "liveActivities": [
                "protocolVersion": LiveActivityConfig.protocolVersion,
                "supported": supported,
                "enabled": supported && enabled,
                "minimumOS": LiveActivityConfig.minimumOS
            ]
        ]
    }

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // MARK: - Primitive parsing

    /// JSON `null` arrives from WebKit as `NSNull`. For an optional field it
    /// means the same as leaving the field out.
    static func present(_ raw: Any?) -> Any? {
        guard let raw, !(raw is NSNull) else { return nil }
        return raw
    }

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func date(_ raw: Any?) -> Date? {
        guard let string = raw as? String else { return nil }
        return iso8601Fractional.date(from: string) ?? iso8601.date(from: string)
    }

    /// JSON numbers only. `raw is Bool` is also true for the numbers 0 and 1
    /// bridged from JSON, so booleans are told apart by their CoreFoundation type.
    static func number(_ raw: Any?) -> Double? {
        guard let raw, let number = raw as? NSNumber,
              CFGetTypeID(number as CFTypeRef) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    static func integer(_ raw: Any?) -> Int? {
        guard let value = number(raw), value.isFinite, value.rounded() == value,
              value >= 0, value <= 9_007_199_254_740_991 else { return nil }
        return Int(value)
    }

    private static func identifier(_ raw: Any?, field: String, code: String = "invalid_contract") throws -> String {
        guard let value = raw as? String, HonouredIdentifiers.isValidIdentifier(value) else {
            throw LiveActivityError(code: code, message: "\(field) must be a non-empty string of at most \(HonouredIdentifiers.maxIdentifierLength) characters")
        }
        return value
    }

    private static func optionalIdentifier(_ raw: Any?, field: String) throws -> String? {
        guard let raw = present(raw) else { return nil }
        return try identifier(raw, field: field)
    }

    /// Collapses whitespace so a name always fits one line, drops control
    /// characters, and truncates rather than rejects a long name: names are
    /// display text written by the person.
    private static func displayName(_ raw: Any?, field: String, limit: Int) throws -> String {
        guard let value = raw as? String else {
            throw LiveActivityError.invalidContract("\(field) is required")
        }
        let cleaned = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
        let name = String(String.UnicodeScalarView(cleaned))
        guard !name.isEmpty else {
            throw LiveActivityError.invalidContract("\(field) must not be empty")
        }
        guard name.count > limit else { return name }
        return String(name.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

// MARK: - State payloads

struct LiveActivityStateEntry: Equatable {
    let key: OccurrenceKey
    let status: PresentationStatus
    let focused: Bool
    let reason: String?
    let lastUpdatedAt: Date?

    var payload: [String: Any] {
        var payload: [String: Any] = [
            "contractId": key.contractId,
            "healthDay": key.healthDay,
            "presentationStatus": status.rawValue,
            "focused": focused
        ]
        if let reason { payload["reason"] = reason }
        if let lastUpdatedAt { payload["lastUpdatedAt"] = LiveActivityProtocol.iso8601.string(from: lastUpdatedAt) }
        return payload
    }
}

struct LiveActivityStateSnapshot: Equatable {
    var supported: Bool
    var enabled: Bool
    var focused: OccurrenceKey?
    var tracked: [LiveActivityStateEntry]

    var payload: [String: Any] {
        var payload: [String: Any] = [
            "supported": supported,
            "enabled": supported && enabled,
            "tracked": tracked.map(\.payload)
        ]
        if let focused {
            payload["focusedOccurrence"] = ["contractId": focused.contractId, "healthDay": focused.healthDay]
        }
        return payload
    }
}
