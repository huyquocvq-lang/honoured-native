import Foundation

/// Live Activity protocol v1 on top of bridge v2. Every mutation is checked
/// against `liveActivitySession` right here, on the main thread, as the
/// message arrives, and queued to the engine before anything asynchronous
/// happens, so arrival order is processing order.
extension NativeBridge {
    static let liveActivityMessageTypes: Set<String> = [
        "TRACK_CONTRACT", "SYNC_TRACKED_CONTRACTS", "STOP_TRACKING_CONTRACT", "GET_LIVE_ACTIVITY_STATE"
    ]

    /// Payload of `NATIVE_READY` and `PLATFORM_INFO`.
    @MainActor
    func readyPayload() -> [String: Any] {
        var capabilities = LiveActivityCoordinator.shared.capabilities()
        capabilities["googleSignIn"] = googleSignInCapability()
        return [
            "platform": "ios",
            "bridgeVersion": AppConfig.bridgeVersion,
            "capabilities": capabilities,
            "liveActivityBridgeSessionId": liveActivitySession.id
        ]
    }

    func handleLiveActivity(type: String, payload: [String: Any], reply: @escaping (String, [String: Any]) -> Void) {
        let coordinator = LiveActivityCoordinator.shared
        let sessionId = liveActivitySession.id

        guard coordinator.isSupported else {
            if type == "GET_LIVE_ACTIVITY_STATE" {
                var state = LiveActivityStateSnapshot(supported: false, enabled: false, focused: nil, tracked: []).payload
                state["liveActivityBridgeSessionId"] = sessionId
                reply("LIVE_ACTIVITY_STATE", state)
            } else {
                reply("ERROR", LiveActivityError.unsupported.payload)
            }
            return
        }

        if type == "GET_LIVE_ACTIVITY_STATE" {
            // Read-only: no envelope, never creates or focuses a card.
            coordinator.submit(.getState) { outcome in
                guard case .state(let snapshot) = outcome else { return }
                var state = snapshot.payload
                state["liveActivityBridgeSessionId"] = sessionId
                DispatchQueue.main.async { reply("LIVE_ACTIVITY_STATE", state) }
            }
            return
        }

        guard let admitted = admitLiveActivityMutation(payload: payload, context: nil, reply: reply) else { return }
        let (envelope, account) = admitted
        let finish = liveActivityFinisher(envelope, reply: reply)

        switch type {
        case "TRACK_CONTRACT":
            guard payload["reason"] as? String == "opened" else {
                finish("ERROR", LiveActivityError.invalidContract("reason must be opened").payload)
                return
            }
            let definition: ContractDefinition
            do {
                definition = try LiveActivityProtocol.contractDefinition(from: payload["contract"])
            } catch {
                finish("ERROR", Self.liveActivityErrorPayload(error))
                return
            }
            coordinator.submit(.track(definition, account: account)) { outcome in
                switch outcome {
                case .tracked(let result):
                    var body: [String: Any] = [
                        "contractId": result.key.contractId,
                        "healthDay": result.key.healthDay,
                        "focused": result.focused,
                        "presentationStatus": result.status.rawValue
                    ]
                    if let reason = result.reason { body["reason"] = reason }
                    finish("CONTRACT_TRACKING_ACCEPTED", body)
                    if definition.hasHealth { coordinator.refreshHealthSoon() }
                case .rejected(let error):
                    finish("ERROR", error.payload)
                default:
                    finish("ERROR", ["message": "Unexpected Live Activity result", "code": "internal_error"])
                }
            }

        case "SYNC_TRACKED_CONTRACTS":
            guard let rawContracts = payload["contracts"] as? [Any], rawContracts.count <= LiveActivityConfig.maxTrackedContracts else {
                finish("ERROR", LiveActivityError.invalidContract("contracts must be an array of at most \(LiveActivityConfig.maxTrackedContracts)").payload)
                return
            }
            var entries: [LiveActivityEngine.SyncEntry] = []
            for raw in rawContracts {
                // Without an identity an entry cannot even be reported back,
                // so the whole snapshot is refused rather than half applied.
                guard let object = raw as? [String: Any],
                      let contractId = object["contractId"] as? String, HonouredIdentifiers.isValidIdentifier(contractId),
                      let healthDay = object["healthDay"] as? String, HonouredIdentifiers.isValidHealthDay(healthDay) else {
                    finish("ERROR", LiveActivityError.invalidContract("every contract needs a contractId and a healthDay").payload)
                    return
                }
                do {
                    entries.append(.valid(try LiveActivityProtocol.contractDefinition(from: object)))
                } catch {
                    let key = OccurrenceKey(contractId: contractId, healthDay: healthDay)
                    entries.append(.invalid(key, error as? LiveActivityError ?? .invalidContract("\(error)")))
                }
            }
            coordinator.submit(.sync(entries, account: account)) { outcome in
                switch outcome {
                case .synced(let tracked):
                    finish("TRACKED_CONTRACTS_SYNCED", ["tracked": tracked.map(\.payload)])
                    coordinator.refreshHealthSoon()
                case .rejected(let error):
                    finish("ERROR", error.payload)
                default:
                    finish("ERROR", ["message": "Unexpected Live Activity result", "code": "internal_error"])
                }
            }

        case "STOP_TRACKING_CONTRACT":
            let request: (key: OccurrenceKey, reason: String)
            do {
                request = try LiveActivityProtocol.stopRequest(from: payload)
            } catch {
                finish("ERROR", Self.liveActivityErrorPayload(error))
                return
            }
            // Idempotent, and never cancels the timer or any Health business.
            coordinator.submit(.stop(request.key, account: account)) { outcome in
                if case .rejected(let error) = outcome {
                    finish("ERROR", error.payload)
                    return
                }
                finish("CONTRACT_TRACKING_STOPPED", [
                    "contractId": request.key.contractId,
                    "healthDay": request.key.healthDay,
                    "reason": request.reason,
                    "stopped": true
                ])
            }

        default:
            finish("ERROR", ["message": "Unsupported bridge message: \(type)", "code": "not_implemented"])
        }
    }

    /// `START_TIMER` with a `trackingContext`. The envelope is checked before
    /// the timer is touched, so a transport retry replays the first reply and
    /// never starts a second run. A contract the engine cannot track does not
    /// stop the timer; `liveActivityStatus` says what happened to the card.
    func startTrackedTimer(
        activityId: String,
        activityName: String,
        durationSeconds: Double,
        payload: [String: Any],
        context rawContext: Any,
        reply: @escaping (String, [String: Any]) -> Void
    ) {
        guard let context = rawContext as? [String: Any] else {
            reply("ERROR", LiveActivityError.invalidEnvelope("trackingContext must be an object").payload)
            return
        }
        guard let admitted = admitLiveActivityMutation(payload: payload, context: context, reply: reply) else { return }
        let (envelope, account) = admitted
        let finish = liveActivityFinisher(envelope, reply: reply)

        let definition: Result<ContractDefinition, LiveActivityError>
        if let declared = LiveActivityProtocol.present(context["timerActivityId"]), declared as? String != activityId {
            definition = .failure(.invalidContract("trackingContext.timerActivityId must be the activityId being started"))
        } else {
            do {
                definition = .success(try LiveActivityProtocol.contractDefinition(from: context["contract"], startingTimer: activityId))
            } catch {
                definition = .failure(error as? LiveActivityError ?? .invalidContract("\(error)"))
            }
        }

        let request = LiveActivityEngine.TimerStart(
            activityId: activityId,
            activityName: activityName,
            durationSeconds: durationSeconds,
            account: account,
            definition: definition
        )
        LiveActivityCoordinator.shared.submit(.startTimer(request)) { [weak self] outcome in
            guard case .timerStarted(let result) = outcome else { return }
            DispatchQueue.main.async {
                // Same order as the legacy path: the replaced timer's broadcast
                // goes out before the reply.
                if let replaced = result.replaced {
                    self?.send(type: "TIMER_CANCELLED", payload: ["activityId": replaced.activityId])
                }
                var body: [String: Any] = [
                    "activityId": result.started.activityId,
                    "endsAt": TestamentTimer.iso8601.string(from: result.started.endsAt),
                    "liveActivityStatus": result.liveActivityStatus
                ]
                if let reason = result.reason { body["liveActivityReason"] = reason }
                finish("TIMER_STARTED", body)
                if case .success(let tracked) = definition, tracked.hasHealth {
                    LiveActivityCoordinator.shared.refreshHealthSoon()
                }
                Task {
                    // The first timer ever is the agreed moment to ask; the
                    // reply is already out, so the sheet cannot time it out.
                    if await NotificationCoordinator.shared.isUndetermined(),
                       await NotificationCoordinator.shared.requestPermissionIfNeeded() {
                        await TestamentTimer.shared.rescheduleNotificationIfRunning(activityId: activityId)
                    }
                }
            }
        }
    }

    /// Checks the envelope and the session. Returns nil after replying when
    /// the message must not run: a replayed retry, one still in flight, or a
    /// stale session, sequence or account.
    func admitLiveActivityMutation(
        payload: [String: Any],
        context: [String: Any]?,
        reply: (String, [String: Any]) -> Void
    ) -> (LiveActivityProtocol.MutationEnvelope, String)? {
        let envelope: LiveActivityProtocol.MutationEnvelope
        do {
            envelope = try LiveActivityProtocol.envelope(from: payload, context: context)
        } catch {
            reply("ERROR", Self.liveActivityErrorPayload(error))
            return nil
        }
        switch liveActivitySession.admit(envelope) {
        case .accepted(let account):
            return (envelope, account)
        case .replay(let type, let stored):
            reply(type, stored)
            return nil
        case .inFlight:
            return nil
        case .rejected(let error):
            reply("ERROR", error.payload)
            return nil
        }
    }

    /// Replies and keeps the reply for transport retries of the same request.
    func liveActivityFinisher(
        _ envelope: LiveActivityProtocol.MutationEnvelope,
        reply: @escaping (String, [String: Any]) -> Void
    ) -> (String, [String: Any]) -> Void {
        { [weak self] type, payload in
            DispatchQueue.main.async {
                self?.liveActivitySession.finish(envelope, type: type, payload: payload)
                reply(type, payload)
            }
        }
    }

    static func liveActivityErrorPayload(_ error: Error) -> [String: Any] {
        (error as? LiveActivityError)?.payload ?? ["message": error.localizedDescription, "code": "invalid_contract"]
    }
}
