import XCTest

/// Payloads as WebKit delivers them: JSON decoded into Foundation objects.
private func json(_ text: String) -> [String: Any] {
    // swiftlint:disable:next force_try
    try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
}

final class LiveActivityProtocolTests: XCTestCase {
    private let walk = """
    {
      "contractId": "contract-walk",
      "contractName": "  Morning\\n   Walk ",
      "healthDay": "2026-09-23",
      "expiresAt": "2026-09-24T00:00:00+07:00",
      "timerActivityId": "contract-walk",
      "completionPolicy": { "kind": "all_health_slots", "requiredActivityIds": ["contract-walk:primary"] },
      "activities": [
        { "activityId": "contract-walk:primary", "slot": "primary", "name": "Walking", "mode": "health",
          "metric": "steps", "target": 8000, "unit": "count" }
      ]
    }
    """

    private func contract(_ edit: (inout [String: Any]) -> Void) -> [String: Any] {
        var object = json(walk)
        edit(&object)
        return object
    }

    private func activity(_ edit: (inout [String: Any]) -> Void) -> [String: Any] {
        contract { object in
            var activities = object["activities"] as! [[String: Any]]
            edit(&activities[0])
            object["activities"] = activities
        }
    }

    private func code(_ raw: [String: Any], startingTimer: String? = nil) -> String? {
        do {
            _ = try LiveActivityProtocol.contractDefinition(from: raw, startingTimer: startingTimer)
            return nil
        } catch {
            return (error as? LiveActivityError)?.code ?? "other"
        }
    }

    // MARK: - Definitions

    func testParsesTheDocumentedHealthPayload() throws {
        let definition = try LiveActivityProtocol.contractDefinition(from: json(walk))
        XCTAssertEqual(definition.key, OccurrenceKey(contractId: "contract-walk", healthDay: "2026-09-23"))
        XCTAssertEqual(definition.contractName, "Morning Walk", "whitespace and newlines collapse to one line")
        XCTAssertEqual(definition.expiresAt, ISO8601DateFormatter().date(from: "2026-09-23T17:00:00Z"))
        XCTAssertEqual(definition.completionPolicy, .allHealthSlots(requiredActivityIds: ["contract-walk:primary"]))
        XCTAssertEqual(definition.timerActivityId, "contract-walk")
        XCTAssertEqual(definition.activities.first?.metric, .steps)
        XCTAssertEqual(definition.activities.first?.target, 8000)
    }

    func testJsonOneIsANumberNotABoolean() throws {
        let definition = try LiveActivityProtocol.contractDefinition(from: activity { $0["target"] = 1 })
        XCTAssertEqual(definition.activities.first?.target, 1)
        XCTAssertEqual(LiveActivityProtocol.integer(json(#"{"n":1}"#)["n"]), 1)
        XCTAssertNil(LiveActivityProtocol.number(json(#"{"b":true}"#)["b"]))
        XCTAssertNil(LiveActivityProtocol.integer(json(#"{"n":1.5}"#)["n"]))
    }

    func testRejectsInvalidHealthActivities() {
        XCTAssertEqual(code(activity { $0["unit"] = "meters" }), "invalid_contract", "unit must be canonical")
        XCTAssertEqual(code(activity { $0["metric"] = "stairs" }), "invalid_contract")
        XCTAssertEqual(code(activity { $0["target"] = 0 }), "invalid_contract")
        XCTAssertEqual(code(activity { $0["target"] = -5 }), "invalid_contract")
        XCTAssertEqual(code(activity { $0["target"] = "8000" }), "invalid_contract")
        XCTAssertEqual(code(activity { $0["target"] = true }), "invalid_contract")
        XCTAssertEqual(code(activity { $0["displayUnit"] = "km" }), "invalid_contract", "displayUnit is for distance only")
        XCTAssertEqual(code(activity { $0["mode"] = "manual" }), "invalid_contract", "metric fields on a manual slot")
        XCTAssertEqual(code(activity { $0["slot"] = "tertiary" }), "invalid_contract")
        XCTAssertEqual(code(activity { $0["activityId"] = String(repeating: "a", count: 129) }), "invalid_contract")
        XCTAssertEqual(code(activity { $0["name"] = "  " }), "invalid_contract")
    }

    func testDistanceKeepsItsDisplayUnit() throws {
        let raw = activity {
            $0["metric"] = "distance_cycling"
            $0["unit"] = "meters"
            $0["target"] = 20_000
            $0["displayUnit"] = "mi"
        }
        XCTAssertEqual(try LiveActivityProtocol.contractDefinition(from: raw).activities.first?.displayUnit, "mi")
        XCTAssertEqual(code(activity {
            $0["metric"] = "distance_cycling"
            $0["unit"] = "meters"
            $0["displayUnit"] = "yd"
        }), "invalid_contract")
    }

    func testSlotsAreOneOrTwoAndUnique() {
        let second: [String: Any] = ["activityId": "contract-walk:secondary", "slot": "secondary", "name": "Energy", "mode": "health", "metric": "active_energy", "target": 300, "unit": "kcal"]
        XCTAssertEqual(code(contract { $0["activities"] = [] }), "invalid_contract")
        XCTAssertEqual(code(contract {
            var activities = $0["activities"] as! [[String: Any]]
            activities.append(activities[0])
            $0["activities"] = activities
        }), "invalid_contract", "duplicate activity")
        XCTAssertEqual(code(contract {
            var activities = $0["activities"] as! [[String: Any]]
            activities += [second, second]
            $0["activities"] = activities
        }), "invalid_contract", "three slots")
        let two = contract {
            var activities = $0["activities"] as! [[String: Any]]
            activities.append(second)
            $0["activities"] = activities
            $0["completionPolicy"] = ["kind": "all_health_slots", "requiredActivityIds": ["contract-walk:primary", "contract-walk:secondary"]]
        }
        XCTAssertNil(code(two))
    }

    func testAllHealthSlotsMustNameEveryHealthSlot() {
        let second: [String: Any] = ["activityId": "contract-walk:secondary", "slot": "secondary", "name": "Energy", "mode": "health", "metric": "active_energy", "target": 300, "unit": "kcal"]
        let subset = contract {
            var activities = $0["activities"] as! [[String: Any]]
            activities.append(second)
            $0["activities"] = activities
        }
        XCTAssertEqual(code(subset), "invalid_contract", "one of two Health slots is not the web rule")
        XCTAssertEqual(code(contract { $0["completionPolicy"] = ["kind": "all_health_slots", "requiredActivityIds": ["other"]] }), "invalid_contract")
        XCTAssertEqual(code(contract { $0["completionPolicy"] = ["kind": "all_health_slots", "requiredActivityIds": [] as [String]] }), "invalid_contract")
        XCTAssertEqual(code(contract { $0["completionPolicy"] = ["kind": "whatever"] }), "invalid_contract")
    }

    func testTimerPoliciesNeedTheContractsTimer() throws {
        let timerOnly: [String: Any] = json("""
        { "contractId": "c-med", "contractName": "Meditation", "healthDay": "2026-09-23",
          "expiresAt": "2026-09-23T20:00:00.000Z",
          "completionPolicy": { "kind": "timer_completion", "timerActivityId": "c-med" },
          "activities": [ { "activityId": "c-med", "slot": "primary", "name": "Sit", "mode": "timer" } ] }
        """)
        XCTAssertEqual(try LiveActivityProtocol.contractDefinition(from: timerOnly).timerActivityId, "c-med")

        let orTimer = contract { $0["completionPolicy"] = ["kind": "all_health_slots_or_timer", "requiredActivityIds": ["contract-walk:primary"], "timerActivityId": "contract-walk"] }
        XCTAssertEqual(try LiveActivityProtocol.contractDefinition(from: orTimer).completionPolicy,
                       .allHealthSlotsOrTimer(requiredActivityIds: ["contract-walk:primary"], timerActivityId: "contract-walk"))

        let noTimer = contract {
            $0["timerActivityId"] = nil
            $0["completionPolicy"] = ["kind": "timer_completion", "timerActivityId": "contract-walk"]
        }
        XCTAssertEqual(code(noTimer), "invalid_contract")
        XCTAssertNil(code(noTimer, startingTimer: "contract-walk"), "START_TIMER supplies the timer")
        XCTAssertEqual(code(json(walk), startingTimer: "another-timer"), "invalid_contract")
        XCTAssertEqual(code(contract { $0["completionPolicy"] = ["kind": "timer_completion", "timerActivityId": "someone-else"] }), "invalid_contract")
    }

    func testJsonNullMeansAbsentForOptionalFields() throws {
        let manual = contract {
            $0["timerActivityId"] = NSNull()
            $0["completionPolicy"] = ["kind": "web_authoritative"]
            $0["activities"] = [["activityId": "m", "slot": "primary", "name": "Read", "mode": "manual",
                                 "metric": NSNull(), "target": NSNull(), "unit": NSNull()]]
        }
        let definition = try LiveActivityProtocol.contractDefinition(from: manual)
        XCTAssertNil(definition.timerActivityId)
        XCTAssertNil(try LiveActivityProtocol.contractDefinition(from: activity { $0["displayUnit"] = NSNull() }).activities.first?.displayUnit)
        XCTAssertNil(try LiveActivityProtocol.completionScope(from: json(#"{"activityId":"c","source":"manual","contractId":null,"scope":null}"#)),
                     "nulls are a legacy payload")
        let scope = try LiveActivityProtocol.completionScope(from: json(#"{"activityId":"c","scope":"slot","contractId":"c","healthDay":"2026-09-23","completedAt":null}"#))
        XCTAssertNil(scope?.completedAt)
        XCTAssertNil(LiveActivityProtocol.present(NSNull()))
    }

    func testLongNamesAreTruncatedNotRejected() throws {
        let definition = try LiveActivityProtocol.contractDefinition(from: contract { $0["contractName"] = String(repeating: "Walk ", count: 40) })
        XCTAssertEqual(definition.contractName.count, LiveActivityConfig.maxContractNameLength)
        XCTAssertTrue(definition.contractName.hasSuffix("…"))
    }

    // MARK: - Environment checks

    func testValidateAgainstDayGoalsAndExpiry() throws {
        let definition = try LiveActivityProtocol.contractDefinition(from: json(walk))
        let now = ISO8601DateFormatter().date(from: "2026-09-23T03:00:00Z")!
        let day = HealthDayInfo(day: "2026-09-23", start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(80_000))
        let goal = GoalSnapshot(activityId: "contract-walk:primary", metric: .steps, target: 8000)
        XCTAssertNoThrow(try LiveActivityProtocol.validate(definition, currentDay: day, goals: [goal], now: now))

        let other = HealthDayInfo(day: "2026-09-24", start: day.start, end: day.end)
        XCTAssertThrowsError(try LiveActivityProtocol.validate(definition, currentDay: other, goals: [goal], now: now)) {
            XCTAssertEqual(($0 as? LiveActivityError)?.details["expectedHealthDay"], "2026-09-24")
        }
        XCTAssertThrowsError(try LiveActivityProtocol.validate(definition, currentDay: day, goals: [], now: now)) {
            XCTAssertEqual(($0 as? LiveActivityError)?.code, "goal_definition_mismatch")
        }
        let moved = GoalSnapshot(activityId: "contract-walk:primary", metric: .steps, target: 9000)
        XCTAssertThrowsError(try LiveActivityProtocol.validate(definition, currentDay: day, goals: [moved], now: now))
        let wrongMetric = GoalSnapshot(activityId: "contract-walk:primary", metric: .activeEnergy, target: 8000)
        XCTAssertThrowsError(try LiveActivityProtocol.validate(definition, currentDay: day, goals: [wrongMetric], now: now))
        XCTAssertThrowsError(try LiveActivityProtocol.validate(definition, currentDay: day, goals: [goal], now: definition.expiresAt)) {
            XCTAssertEqual(($0 as? LiveActivityError)?.code, "occurrence_expired")
        }
    }

    // MARK: - Envelope and other payloads

    func testEnvelopeNeedsRequestSessionAndPositiveIntegerSequence() throws {
        let ok = try LiveActivityProtocol.envelope(from: json(#"{"requestId":"r1","bridgeSessionId":"s1","clientSequence":1}"#))
        XCTAssertEqual(ok, LiveActivityProtocol.MutationEnvelope(requestId: "r1", bridgeSessionId: "s1", clientSequence: 1))
        let context = json(#"{"bridgeSessionId":"s2","clientSequence":7}"#)
        XCTAssertEqual(try LiveActivityProtocol.envelope(from: json(#"{"requestId":"r2"}"#), context: context).clientSequence, 7)
        for bad in [
            #"{"bridgeSessionId":"s1","clientSequence":1}"#,
            #"{"requestId":"r1","clientSequence":1}"#,
            #"{"requestId":"r1","bridgeSessionId":"s1","clientSequence":0}"#,
            #"{"requestId":"r1","bridgeSessionId":"s1","clientSequence":-1}"#,
            #"{"requestId":"r1","bridgeSessionId":"s1","clientSequence":1.5}"#,
            #"{"requestId":"r1","bridgeSessionId":"s1","clientSequence":"1"}"#,
            #"{"requestId":"r1","bridgeSessionId":"s1","clientSequence":true}"#
        ] {
            XCTAssertThrowsError(try LiveActivityProtocol.envelope(from: json(bad)), bad) {
                XCTAssertEqual(($0 as? LiveActivityError)?.code, "invalid_envelope")
            }
        }
    }

    func testStopNeedsAnOccurrenceAndAKnownReason() throws {
        let stop = try LiveActivityProtocol.stopRequest(from: json(#"{"contractId":"c","healthDay":"2026-09-23","reason":"contract_deleted"}"#))
        XCTAssertEqual(stop.key, OccurrenceKey(contractId: "c", healthDay: "2026-09-23"))
        XCTAssertThrowsError(try LiveActivityProtocol.stopRequest(from: json(#"{"contractId":"c","healthDay":"2026-09-23","reason":"completed"}"#)))
        XCTAssertThrowsError(try LiveActivityProtocol.stopRequest(from: json(#"{"contractId":"c","reason":"user_stopped"}"#)))
    }

    func testCompletionScopeIsOptionalAndStrictWhenPresent() throws {
        XCTAssertNil(try LiveActivityProtocol.completionScope(from: json(#"{"activityId":"c","source":"manual"}"#)), "legacy payload")
        let scope = try XCTUnwrap(LiveActivityProtocol.completionScope(from: json(#"{"activityId":"c","source":"timer","scope":"contract","contractId":"c","healthDay":"2026-09-23","completedAt":"2026-09-23T09:00:00Z"}"#)))
        XCTAssertTrue(scope.isContract)
        XCTAssertEqual(scope.key.contractId, "c")
        XCTAssertNotNil(scope.completedAt)
        XCTAssertThrowsError(try LiveActivityProtocol.completionScope(from: json(#"{"activityId":"c","scope":"contract"}"#)))
        XCTAssertThrowsError(try LiveActivityProtocol.completionScope(from: json(#"{"activityId":"c","scope":"everything","contractId":"c","healthDay":"2026-09-23"}"#)))
        XCTAssertThrowsError(try LiveActivityProtocol.completionScope(from: json(#"{"activityId":"c","contractId":"c","healthDay":"2026-09-23"}"#)), "scope is required once any field is sent")
    }

    func testCapabilityAndStatePayloads() {
        let capabilities = LiveActivityProtocol.capabilities(supported: true, enabled: false)["liveActivities"] as? [String: Any]
        XCTAssertEqual(capabilities?["protocolVersion"] as? Int, 1)
        XCTAssertEqual(capabilities?["supported"] as? Bool, true)
        XCTAssertEqual(capabilities?["enabled"] as? Bool, false)
        XCTAssertEqual(capabilities?["minimumOS"] as? String, "16.2")
        let unsupported = LiveActivityProtocol.capabilities(supported: false, enabled: true)["liveActivities"] as? [String: Any]
        XCTAssertEqual(unsupported?["enabled"] as? Bool, false)

        let key = OccurrenceKey(contractId: "c", healthDay: "2026-09-23")
        let snapshot = LiveActivityStateSnapshot(supported: true, enabled: true, focused: key, tracked: [
            LiveActivityStateEntry(key: key, status: .awaitingTimer, focused: true, reason: nil, lastUpdatedAt: nil)
        ])
        let payload = snapshot.payload
        XCTAssertTrue(JSONSerialization.isValidJSONObject(payload))
        XCTAssertEqual((payload["focusedOccurrence"] as? [String: String])?["contractId"], "c")
        XCTAssertEqual(((payload["tracked"] as? [[String: Any]])?.first)?["presentationStatus"] as? String, "awaiting_timer")
        XCTAssertTrue(JSONSerialization.isValidJSONObject(LiveActivityError.goalDefinitionMismatch(activityId: "a").payload))
    }
}

final class LiveActivityBridgeSessionTests: XCTestCase {
    private func envelope(_ requestId: String, _ sequence: Int, _ session: String) -> LiveActivityProtocol.MutationEnvelope {
        LiveActivityProtocol.MutationEnvelope(requestId: requestId, bridgeSessionId: session, clientSequence: sequence)
    }

    private func code(_ admission: LiveActivityBridgeSession.Admission) -> String? {
        if case .rejected(let error) = admission { return error.code }
        return nil
    }

    func testAdmissionOrderingAndReplay() {
        var counter = 0
        let session = LiveActivityBridgeSession { counter += 1; return "s\(counter)" }
        XCTAssertEqual(code(session.admit(envelope("r0", 1, "s1"))), "auth_session_required", "a new page is unbound")

        XCTAssertFalse(session.bind(account: "a"), "the first bind keeps the ID the page already has")
        guard case .accepted(let account) = session.admit(envelope("r1", 1, "s1")) else { return XCTFail("accept") }
        XCTAssertEqual(account, "a")
        guard case .inFlight = session.admit(envelope("r1", 1, "s1")) else { return XCTFail("in flight") }
        session.finish(envelope("r1", 1, "s1"), type: "CONTRACT_TRACKING_ACCEPTED", payload: ["focused": true])
        guard case .replay(let type, let payload) = session.admit(envelope("r1", 1, "s1")) else { return XCTFail("replay") }
        XCTAssertEqual(type, "CONTRACT_TRACKING_ACCEPTED")
        XCTAssertEqual(payload["focused"] as? Bool, true)

        XCTAssertEqual(code(session.admit(envelope("r1", 2, "s1"))), "request_id_reused")
        XCTAssertEqual(code(session.admit(envelope("r2", 1, "s1"))), "stale_sequence")
        guard case .accepted = session.admit(envelope("r3", 5, "s1")) else { return XCTFail("gaps are fine") }
        XCTAssertEqual(code(session.admit(envelope("r4", 6, "elsewhere"))), "stale_bridge_session")
    }

    func testSessionRotatesOnReloadSignOutAndAnotherUserOnly() {
        var counter = 0
        let session = LiveActivityBridgeSession { counter += 1; return "s\(counter)" }
        session.bind(account: "a")
        XCTAssertFalse(session.bind(account: "a"), "token refresh")
        XCTAssertEqual(session.id, "s1")
        _ = session.admit(envelope("r1", 3, "s1"))

        XCTAssertTrue(session.bind(account: "b"))
        XCTAssertEqual(session.id, "s2")
        XCTAssertEqual(code(session.admit(envelope("r5", 9, "s1"))), "stale_bridge_session")
        guard case .accepted(let account) = session.admit(envelope("r5", 1, "s2")) else { return XCTFail("fresh sequence space") }
        XCTAssertEqual(account, "b")

        session.finish(envelope("r1", 3, "s1"), type: "LATE", payload: [:])
        guard case .inFlight = session.admit(envelope("r5", 1, "s2")) else { return XCTFail("a reply for an old page is not stored") }

        session.unbind()
        XCTAssertEqual(session.id, "s3")
        XCTAssertEqual(code(session.admit(envelope("r6", 1, "s3"))), "auth_session_required")

        session.bind(account: "a")
        session.pageWillLoad()
        XCTAssertEqual(session.id, "s4")
        XCTAssertNil(session.boundAccount)
    }
}
