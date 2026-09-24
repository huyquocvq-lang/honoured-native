import Foundation
import WebKit

final class NativeBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?

    /// Broadcasts raised before the web app has sent APP_READY (a session
    /// refreshed in the background, a health sync finishing) are held here and
    /// flushed right after NATIVE_READY, so they cannot land on a page that has
    /// no listener yet. Bounded so a stuck WebView cannot grow it forever. This
    /// queue survives a reload only; events that must survive a relaunch go
    /// through `NativeEventStore` and are merged in by `createdAt` on flush.
    private var pendingBroadcasts: [(type: String, payload: [String: Any], createdAt: Date)] = []
    private var isWebReady = false
    private let pendingLimit = 50

    /// Orders and deduplicates Live Activity mutations for the current page and
    /// account. Main thread only, like the script message callbacks.
    let liveActivitySession = LiveActivityBridgeSession()

    /// Google Sign-In ownership for the current page: context, attempt and
    /// page generation. Main thread only.
    let googleAuth = GoogleAuthState()
    var googleTimeouts: [String: DispatchWorkItem] = [:]
    var signOutGoogleAfterPresentation = false

    /// The user of the last `SET_AUTH_SESSION` on this bridge.
    private var boundAuthUserId: String?

    /// The exact origin the auth messages must come from. Nil (feature off)
    /// when the configured web app URL is not HTTPS.
    let trustedWebOrigin = TrustedWebOrigin(url: AppConfig.webAppURL)

    /// Native session writes (`SET_AUTH_SESSION`, `CLEAR_AUTH_SESSION`) run
    /// strictly in arrival order, so an older write can never land after a
    /// newer one and revive a session that was cleared.
    static let authMutations = SerialAsyncQueue()

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNativeEvent(_:)),
            name: NativeBridgeEvents.notification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleStoredEventsChanged),
            name: NativeEventStore.changed,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleNativeEvent(_ notification: Notification) {
        guard let type = notification.userInfo?["type"] as? String else { return }
        let payload = notification.userInfo?["payload"] as? [String: Any] ?? [:]
        send(type: type, payload: payload)
    }

    /// A durable event was appended while this bridge is alive. If the page is
    /// ready it goes out now; otherwise it stays on disk until the ready flush.
    @objc private func handleStoredEventsChanged() {
        guard isWebReady else { return }
        flushStoredEvents()
    }

    private static let v2MessageTypes: Set<String> = [
        "SET_AUTH_SESSION", "CLEAR_AUTH_SESSION",
        "REQUEST_HEALTH_PERMISSION", "GET_HEALTH_STATUS", "QUERY_HEALTH_METRICS",
        "SET_GOALS", "SET_DAY_RESET_HOUR",
        "START_TIMER", "CANCEL_TIMER", "GET_TIMER_STATE",
        "ACTIVITY_COMPLETED", "SET_SOUND_ENABLED",
        "GET_NOTIFICATION_STATUS", "OPEN_NOTIFICATION_SETTINGS",
        "SIGN_IN_WITH_APPLE",
    ]

    /// Called when the WebView starts a new main-frame load. Anything broadcast
    /// from now until the next APP_READY is queued instead of dropped.
    func webViewWillReload() {
        isWebReady = false
        invalidateGoogleDocument()
    }

    /// The page that owned any Google attempt is going away: its result, and
    /// any reply still pending for it, must not reach the next document.
    private func invalidateGoogleDocument() {
        for item in googleTimeouts.values { item.cancel() }
        googleTimeouts.removeAll()
        googleAuth.documentWillChange()
    }

    /// The new page replaced the old one. Only now do Live Activity mutations
    /// of the old page stop being accepted: a navigation that fails before
    /// this point leaves the old page, and its session, in place.
    func webViewDidCommitNavigation() {
        liveActivitySession.pageWillLoad()
        invalidateGoogleDocument()
    }

    /// A state hint queued for a page that is not ready describes the account
    /// that was signed in when it was queued; after an account message the new
    /// page asks with GET_LIVE_ACTIVITY_STATE instead.
    private func dropQueuedLiveActivityState() {
        pendingBroadcasts.removeAll { $0.type == "LIVE_ACTIVITY_STATE_CHANGED" }
    }

    /// Queued auth broadcasts describe the account that was signed in when
    /// they were raised. After a switch or sign-out they would hand the old
    /// account's tokens or state to the new page.
    private func dropQueuedAuthBroadcasts() {
        pendingBroadcasts.removeAll { $0.type == "AUTH_SESSION_UPDATED" || $0.type == "AUTH_SESSION_INVALID" }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            send(type: "ERROR", payload: ["message": "Invalid bridge message"])
            return
        }

        let payload = body["payload"] as? [String: Any] ?? [:]
        let requestID = payload["requestId"] as? String

        // Checked before anything else, including the ready flush: a frame or
        // page that is not the trusted main frame gets no reply at all.
        if Self.googleMessageTypes.contains(type) {
            guard isTrustedAuthMessage(message) else { return }
            if !isWebReady { markWebReadyAndFlush() }
            handleGoogle(type: type, payload: payload, requestId: requestID)
            return
        }
        let reply: (String, [String: Any]) -> Void = { [weak self] replyType, replyPayload in
            self?.send(type: replyType, payload: replyPayload, requestId: requestID)
        }
        #if DEBUG
        if type == "STUB_LOG" {
            BridgeStub.log(payload["line"] as? String ?? "")
            return
        }
        if BridgeStub.isEnabled, type.hasPrefix("STUB_") {
            BridgeStub.handle(type: type, payload: payload, reply: reply)
            return
        }
        #endif

        // Any inbound message proves the web app's bridge module is running and
        // listening. The current web build never sends APP_READY, so waiting for
        // it alone would hold queued broadcasts forever. Deferred to function
        // exit so the reply to this message goes out before the backlog.
        let isFirstMessageSinceLoad = !isWebReady
        defer { if isFirstMessageSinceLoad { markWebReadyAndFlush() } }

        if Self.v2MessageTypes.contains(type) {
            handleV2(type: type, payload: payload, reply: reply)
            return
        }
        if Self.liveActivityMessageTypes.contains(type) {
            handleLiveActivity(type: type, payload: payload, reply: reply)
            return
        }

        switch type {
        case "APP_READY":
            reply("NATIVE_READY", readyPayload())
        case "GET_PLATFORM_INFO":
            reply("PLATFORM_INFO", readyPayload())
        case "IDENTIFY_USER":
            guard let userID = payload["userId"] as? String, !userID.isEmpty else {
                reply("IDENTIFY_FAILED", ["message": "Missing userId"])
                return
            }
            Task { @MainActor [weak self] in
                switch await SubscriptionService.shared.identify(appUserID: userID) {
                case .completed(let status):
                    reply("IDENTIFY_SUCCESS", status)
                    // The already-identified shortcut skips the CustomerInfo fetch, so
                    // its payload carries no verdict. Broadcasting it as a status would
                    // read as "not subscribed". A verdict for a user RevenueCat is no
                    // longer bound to (a newer sign-in or logout ran) is not sent.
                    if status["isSubscribed"] != nil, SubscriptionService.shared.isIdentified(as: userID) {
                        reply("ACCESS_STATUS", status)
                    }
                case .cancelled:
                    reply("IDENTIFY_FAILED", ["message": "Unexpected cancellation"])
                case .failed(let message):
                    reply("IDENTIFY_FAILED", ["message": message])
                }
            }
        case "LOGOUT_USER":
            Task { @MainActor [weak self] in
                switch await SubscriptionService.shared.logout() {
                case .completed:
                    reply("LOGOUT_SUCCESS", ["isSubscribed": false])
                    // A sign-in queued after this logout may already own the
                    // RevenueCat identity; its status must not be overwritten.
                    if SubscriptionService.shared.isAnonymous {
                        reply("ACCESS_STATUS", ["isSubscribed": false, "source": "logout"])
                    }
                case .cancelled:
                    reply("LOGOUT_FAILED", ["message": "Unexpected cancellation"])
                case .failed(let message):
                    reply("LOGOUT_FAILED", ["message": message])
                }
            }
        case "CHECK_ACCESS":
            guard let userID = payload["userId"] as? String, !userID.isEmpty else {
                reply("ACCESS_STATUS", ["isSubscribed": false, "source": "missing_user_id"])
                return
            }
            Task { @MainActor [weak self] in
                switch await SubscriptionService.shared.identify(appUserID: userID) {
                case .completed:
                    let status = await SubscriptionService.shared.accessStatus()
                    guard SubscriptionService.shared.isIdentified(as: userID) else {
                        reply("ACCESS_STATUS", ["isSubscribed": false, "source": "identity_changed"])
                        return
                    }
                    reply("ACCESS_STATUS", status)
                case .cancelled:
                    reply("ACCESS_STATUS", ["isSubscribed": false, "source": "identify_cancelled"])
                case .failed(let message):
                    reply("ACCESS_STATUS", ["isSubscribed": false, "source": "identify_failed", "message": message])
                }
            }
        case "START_PURCHASE":
            guard let userID = payload["userId"] as? String, !userID.isEmpty else {
                reply("PURCHASE_FAILED", ["message": "Missing userId"])
                return
            }
            let packageIdentifier = payload["packageIdentifier"] as? String
            Task { @MainActor [weak self] in
                switch await SubscriptionService.shared.identify(appUserID: userID) {
                case .completed:
                    switch await SubscriptionService.shared.purchase(packageIdentifier: packageIdentifier) {
                    case .completed(let status):
                        reply("PURCHASE_SUCCESS", status)
                        reply("ACCESS_STATUS", status)
                    case .cancelled:
                        reply("PURCHASE_CANCELLED", [:])
                    case .failed(let message):
                        reply("PURCHASE_FAILED", ["message": message])
                    }
                case .cancelled:
                    reply("PURCHASE_FAILED", ["message": "Could not identify signed-in user"])
                case .failed(let message):
                    reply("PURCHASE_FAILED", ["message": message])
                }
            }
        case "RESTORE_PURCHASES":
            guard let userID = payload["userId"] as? String, !userID.isEmpty else {
                reply("RESTORE_FAILED", ["message": "Missing userId"])
                return
            }
            Task { @MainActor [weak self] in
                switch await SubscriptionService.shared.identify(appUserID: userID) {
                case .completed:
                    switch await SubscriptionService.shared.restore() {
                    case .completed(let status):
                        reply("RESTORE_SUCCESS", status)
                        reply("ACCESS_STATUS", status)
                    case .cancelled:
                        reply("RESTORE_SUCCESS", ["isSubscribed": false])
                    case .failed(let message):
                        reply("RESTORE_FAILED", ["message": message])
                    }
                case .cancelled:
                    reply("RESTORE_FAILED", ["message": "Could not identify signed-in user"])
                case .failed(let message):
                    reply("RESTORE_FAILED", ["message": message])
                }
            }
        case "START_SESSION":
            reply("ERROR", [
                "message": "Trial sessions are enforced by Supabase RPC from the authenticated web app"
            ])
        default:
            reply("ERROR", ["message": "Unsupported bridge message: \(type)"])
        }
    }

    // MARK: - v2

    /// Each case is replaced as its feature lands. Until then the web app gets a
    /// distinguishable "not implemented" rather than "unsupported", so it can tell
    /// a native build that is too old from one that is merely incomplete.
    private func handleV2(type: String, payload: [String: Any], reply: @escaping (String, [String: Any]) -> Void) {
        switch type {
        case "SET_AUTH_SESSION":
            guard let userId = payload["userId"] as? String, !userId.isEmpty,
                  let accessToken = payload["accessToken"] as? String, !accessToken.isEmpty,
                  let refreshToken = payload["refreshToken"] as? String, !refreshToken.isEmpty,
                  let expiresAt = Self.number(payload["expiresAt"]),
                  expiresAt.isFinite, expiresAt > 0 else {
                reply("ERROR", ["message": "Invalid auth session", "code": "invalid_auth_session"])
                return
            }
            // Before any await: a Live Activity mutation sent after this message
            // must already see the new account, and one meant for the previous
            // account must be refused. The same user refreshing keeps both.
            liveActivitySession.bind(account: userId)
            LiveActivityCoordinator.shared.accountChanged(userId)
            dropQueuedLiveActivityState()
            // A different owner invalidates any Google attempt; a token refresh
            // for the same user keeps a link flow alive.
            googleAuth.sessionOwnerChanged(to: userId)
            if boundAuthUserId != userId { dropQueuedAuthBroadcasts() }
            boundAuthUserId = userId
            let liveActivitySessionId = liveActivitySession.id
            Self.authMutations.enqueue {
                do {
                    let previousUserId = await AuthSessionStore.shared.load()?.userId
                    if let previousUserId, previousUserId != userId {
                        try await HealthSyncCoordinator.shared.clear()
                        await HealthKitService.shared.resetSyncState()
                        await HealthSyncSettings.shared.reset()
                        try await NativeEventStore.shared.clear()
                        await TestamentTimer.shared.clear()
                        await GoalMonitor.shared.clear()
                        AppleSignInCoordinator.shared.clear()
                        NotificationCoordinator.shared.cancelAll()
                    }
                    try await AuthSessionStore.shared.save(NativeAuthSession(
                        userId: userId,
                        accessToken: accessToken,
                        refreshToken: refreshToken,
                        expiresAt: expiresAt
                    ))
                    reply("AUTH_SESSION_ACCEPTED", ["userId": userId, "liveActivityBridgeSessionId": liveActivitySessionId])
                    HealthBackgroundObserver.shared.enableBackgroundDelivery()
                    HealthBackgroundRefresh.shared.schedule()
                    await HealthSyncCoordinator.shared.syncNow()
                } catch {
                    reply("ERROR", ["message": error.localizedDescription, "code": "auth_session_store_failed"])
                }
            }
        case "CLEAR_AUTH_SESSION":
            // Ends every Honoured card and forgets the account's tracking
            // before anything else can run.
            liveActivitySession.unbind()
            LiveActivityCoordinator.shared.accountChanged(nil)
            dropQueuedLiveActivityState()
            googleAuth.sessionOwnerChanged(to: nil)
            dropQueuedAuthBroadcasts()
            boundAuthUserId = nil
            let liveActivitySessionId = liveActivitySession.id
            Self.authMutations.enqueue {
                do {
                    try await AuthSessionStore.shared.clear()
                    try await HealthSyncCoordinator.shared.clear()
                    await HealthKitService.shared.resetSyncState()
                    await HealthSyncSettings.shared.reset()
                    try await NativeEventStore.shared.clear()
                    await TestamentTimer.shared.clear()
                    await GoalMonitor.shared.clear()
                    AppleSignInCoordinator.shared.clear()
                    NotificationCoordinator.shared.cancelAll()
                    HealthBackgroundObserver.shared.disableBackgroundDelivery()
                    HealthBackgroundRefresh.shared.cancel()
                    reply("AUTH_SESSION_CLEARED", ["liveActivityBridgeSessionId": liveActivitySessionId])
                } catch {
                    reply("ERROR", ["message": error.localizedDescription, "code": "auth_session_clear_failed"])
                }
            }
        case "REQUEST_HEALTH_PERMISSION":
            let parsed = HealthMetric.parse(payload["metrics"])
            guard parsed.unknown.isEmpty else {
                reply("ERROR", ["message": "Unknown metrics: \(parsed.unknown.joined(separator: ", "))", "code": "unknown_metric"])
                return
            }
            Task { @MainActor in
                let service = HealthKitService.shared
                if service.isAvailable {
                    do {
                        try await service.requestAuthorization(for: parsed.metrics)
                    } catch {
                        reply("ERROR", ["message": error.localizedDescription, "code": "health_authorization_failed"])
                        return
                    }
                    HealthBackgroundObserver.shared.enableBackgroundDelivery()
                }
                reply("HEALTH_PERMISSION_STATUS", await service.permissionStatusPayload(for: parsed.metrics))
                await HealthSyncCoordinator.shared.syncNow()
            }
        case "GET_HEALTH_STATUS":
            Task { @MainActor in
                reply("HEALTH_PERMISSION_STATUS", await HealthKitService.shared.permissionStatusPayload(for: HealthMetric.allCases))
            }
        case "QUERY_HEALTH_METRICS":
            let parsed = HealthMetric.parse(payload["metrics"])
            guard parsed.unknown.isEmpty else {
                reply("ERROR", ["message": "Unknown metrics: \(parsed.unknown.joined(separator: ", "))", "code": "unknown_metric"])
                return
            }
            guard let from = Self.date(from: payload["from"]),
                  let to = Self.date(from: payload["to"]),
                  from < to else {
                reply("ERROR", ["message": "from/to must be ISO 8601 with from < to", "code": "invalid_range"])
                return
            }
            Task {
                var metrics: [String: Any] = [:]
                for metric in parsed.metrics {
                    if let value = await HealthKitService.shared.total(for: metric, from: from, to: to) {
                        metrics[metric.rawValue] = ["value": value, "unit": metric.unitName]
                    } else {
                        metrics[metric.rawValue] = NSNull()
                    }
                }
                reply("HEALTH_METRICS", [
                    "from": Self.iso8601.string(from: from),
                    "to": Self.iso8601.string(from: to),
                    "metrics": metrics
                ])
            }
        case "SET_GOALS":
            guard let rawGoals = payload["goals"] as? [[String: Any]] else {
                reply("ERROR", ["message": "goals must be an array", "code": "invalid_goals"])
                return
            }
            do {
                let goals = try rawGoals.map(Self.parseGoal)
                Task {
                    do {
                        try await HealthSyncSettings.shared.replaceGoals(goals)
                        reply("GOALS_ACCEPTED", ["count": goals.count])
                        // First goal of the day is the agreed moment to ask; the
                        // reply has already gone out so the sheet cannot time it out.
                        if !goals.isEmpty {
                            await NotificationCoordinator.shared.requestPermissionIfNeeded()
                            await GoalMonitor.shared.evaluate()
                        }
                    } catch {
                        reply("ERROR", ["message": error.localizedDescription, "code": "goals_save_failed"])
                    }
                }
            } catch {
                reply("ERROR", ["message": error.localizedDescription, "code": "invalid_goal"])
            }
        case "SET_DAY_RESET_HOUR":
            guard let hour = payload["hour"] as? Int, (0...23).contains(hour) else {
                reply("ERROR", ["message": "hour must be an integer from 0 through 23", "code": "invalid_day_reset_hour"])
                return
            }
            Task {
                let changed = await HealthSyncSettings.shared.dayResetHour() != hour
                await HealthSyncSettings.shared.setDayResetHour(hour)
                reply("DAY_RESET_HOUR_ACCEPTED", ["hour": hour])
                if changed {
                    await GoalMonitor.shared.clear()
                    await GoalMonitor.shared.evaluate()
                    // The current health day may be a different one now; cards
                    // of the old day stop showing its Health numbers.
                    LiveActivityCoordinator.shared.dayMayHaveChanged()
                }
            }
        case "SIGN_IN_WITH_APPLE":
            Task { @MainActor in
                switch await AppleSignInCoordinator.shared.signIn() {
                case .success(let payload):
                    reply("APPLE_SIGN_IN_SUCCESS", payload)
                case .cancelled:
                    reply("APPLE_SIGN_IN_FAILED", ["code": "cancelled", "message": "Sign in with Apple was cancelled"])
                case .failed(let message):
                    reply("APPLE_SIGN_IN_FAILED", ["code": "failed", "message": message])
                }
            }
        case "SET_SOUND_ENABLED":
            guard let enabled = Self.bool(payload["enabled"]) else {
                reply("ERROR", ["message": "enabled must be a boolean", "code": "invalid_sound_state"])
                return
            }
            NotificationSound.setEnabled(enabled)
            reply("SOUND_STATE", ["enabled": enabled, "gongBundled": NotificationSound.isGongBundled])
            Task {
                // A timer already counting down keeps its pending notification;
                // re-adding it under the same identifier swaps the sound in or out.
                await TestamentTimer.shared.rescheduleNotificationIfRunning()
            }
        case "ACTIVITY_COMPLETED":
            guard let activityId = payload["activityId"] as? String, !activityId.isEmpty,
                  let source = payload["source"] as? String,
                  Self.completionSources.contains(source) else {
                reply("ERROR", [
                    "message": "activityId and a source of timer, healthkit or manual are required",
                    "code": "invalid_activity_completion"
                ])
                return
            }
            let scope: LiveActivityProtocol.CompletionScope?
            do {
                scope = try LiveActivityProtocol.completionScope(from: payload)
            } catch {
                reply("ERROR", Self.liveActivityErrorPayload(error))
                return
            }
            guard let scope else {
                // Legacy payload: mark the celebration exactly as before and
                // infer nothing about the contract from the ID.
                Task {
                    await GoalMonitor.shared.markCelebrated(activityId: activityId)
                    reply("ACTIVITY_COMPLETION_ACCEPTED", ["activityId": activityId, "source": source])
                }
                return
            }
            completeTrackedActivity(activityId: activityId, source: source, scope: scope, payload: payload, reply: reply)
        case "START_TIMER":
            guard let activityId = payload["activityId"] as? String, !activityId.isEmpty,
                  let activityName = payload["activityName"] as? String, !activityName.isEmpty,
                  let duration = Self.number(payload["durationSeconds"]), duration.isFinite, duration > 0 else {
                reply("ERROR", ["message": "activityId, activityName and a positive durationSeconds are required", "code": "invalid_timer"])
                return
            }
            if let trackingContext = LiveActivityProtocol.present(payload["trackingContext"]) {
                if LiveActivityCoordinator.shared.isSupported {
                    startTrackedTimer(
                        activityId: activityId, activityName: activityName, durationSeconds: duration,
                        payload: payload, context: trackingContext, reply: reply
                    )
                    return
                }
                // Below iOS 16.2 the context is ignored and the timer starts as
                // it always has; the reply says the card was not possible.
                startLegacyTimer(activityId: activityId, activityName: activityName, duration: duration, liveActivityStatus: "unsupported", reply: reply)
                return
            }
            startLegacyTimer(activityId: activityId, activityName: activityName, duration: duration, liveActivityStatus: nil, reply: reply)
        case "CANCEL_TIMER":
            cancelTimer(payload: payload, reply: reply)
        case "GET_TIMER_STATE":
            Task {
                await TestamentTimer.shared.reconcile()
                if let timer = await TestamentTimer.shared.current() {
                    reply("TIMER_STATE", [
                        "active": true,
                        "activityId": timer.activityId,
                        "endsAt": TestamentTimer.iso8601.string(from: timer.endsAt)
                    ])
                } else {
                    reply("TIMER_STATE", ["active": false])
                }
            }
        case "GET_NOTIFICATION_STATUS":
            Task {
                reply("NOTIFICATION_STATUS", await NotificationCoordinator.shared.statusPayload())
            }
        case "OPEN_NOTIFICATION_SETTINGS":
            // iOS asks for notification permission once. Once declined, the
            // only way back is the system Settings page, so the web app needs
            // to be able to send the person there.
            Task { @MainActor in
                let opened = NotificationCoordinator.shared.openSystemSettings()
                var payload = await NotificationCoordinator.shared.statusPayload()
                payload["opened"] = opened
                reply("NOTIFICATION_STATUS", payload)
            }
        default:
            reply("ERROR", [
                "message": "\(type) is not implemented in this build",
                "code": "not_implemented"
            ])
        }
    }

    // MARK: - Timer

    /// The original `START_TIMER`, unchanged for payloads without a tracking
    /// context. `TestamentTimer` tells the Live Activity engine about the run,
    /// which attaches it to a tracked contract that declared this timer.
    private func startLegacyTimer(
        activityId: String,
        activityName: String,
        duration: Double,
        liveActivityStatus: String?,
        reply: @escaping (String, [String: Any]) -> Void
    ) {
        Task {
            let askPermission = await NotificationCoordinator.shared.isUndetermined()
            let result = await TestamentTimer.shared.start(
                activityId: activityId, activityName: activityName, durationSeconds: duration
            )
            if let replaced = result.replaced {
                send(type: "TIMER_CANCELLED", payload: ["activityId": replaced.activityId])
            }
            var body: [String: Any] = [
                "activityId": result.timer.activityId,
                "endsAt": TestamentTimer.iso8601.string(from: result.timer.endsAt)
            ]
            if let liveActivityStatus { body["liveActivityStatus"] = liveActivityStatus }
            reply("TIMER_STARTED", body)
            // First timer ever is the agreed moment to ask. The reply is already
            // out, so the sheet cannot time the request out on the web side.
            if askPermission, await NotificationCoordinator.shared.requestPermissionIfNeeded() {
                await TestamentTimer.shared.rescheduleNotificationIfRunning(activityId: activityId)
            }
        }
    }

    /// `reason` (`paused` or `cancelled`, default `cancelled`) is echoed back.
    /// Native has no pause: a pause is a cancel and a resume is a new start
    /// with the remaining time. Either way the card drops the timer; a card
    /// that shows nothing else ends until the timer runs again.
    private func cancelTimer(payload: [String: Any], reply: @escaping (String, [String: Any]) -> Void) {
        guard let activityId = payload["activityId"] as? String, !activityId.isEmpty else {
            reply("ERROR", ["message": "activityId is required", "code": "invalid_timer"])
            return
        }
        // The cancel is what matters; an unknown reason never blocks it.
        let requestedReason = payload["reason"] as? String ?? "cancelled"
        let reason = LiveActivityProtocol.cancelReasons.contains(requestedReason) ? requestedReason : "cancelled"
        var finish = reply
        if let rawContext = LiveActivityProtocol.present(payload["trackingContext"]), LiveActivityCoordinator.shared.isSupported {
            guard let context = rawContext as? [String: Any] else {
                reply("ERROR", LiveActivityError.invalidEnvelope("trackingContext must be an object").payload)
                return
            }
            guard let admitted = admitLiveActivityMutation(payload: payload, context: context, reply: reply) else { return }
            finish = liveActivityFinisher(admitted.0, reply: reply)
        }
        Task {
            switch await TestamentTimer.shared.cancel(activityId: activityId) {
            case .cancelled, .nothingRunning:
                finish("TIMER_CANCELLED", ["activityId": activityId, "reason": reason])
            case .differentTimerRunning(let running):
                finish("ERROR", [
                    "message": "The running timer is for \(running.activityId)",
                    "code": "timer_not_active"
                ])
            }
        }
    }

    // MARK: - Completion

    /// `ACTIVITY_COMPLETED` with `scope`, `contractId` and `healthDay`. The
    /// celebration marker is set for the occurrence's own health day, so a
    /// completion received after the reset never silences today's goal.
    /// `scope: contract` ends that card as honoured; `scope: slot` only marks
    /// the slot. The web app remains the one that records the outcome.
    private func completeTrackedActivity(
        activityId: String,
        source: String,
        scope: LiveActivityProtocol.CompletionScope,
        payload: [String: Any],
        reply: @escaping (String, [String: Any]) -> Void
    ) {
        // The web app has honoured this contract whatever happens to the card:
        // silence native's own goal announcement first, for the occurrence's
        // own health day. Marking twice is harmless, so a retry or a stale
        // envelope cannot leave a notification behind.
        let marker = Task {
            await GoalMonitor.shared.markCelebrated(activityId: activityId, day: scope.key.healthDay)
        }
        var body: [String: Any] = [
            "activityId": activityId,
            "source": source,
            "contractId": scope.key.contractId,
            "healthDay": scope.key.healthDay,
            "scope": scope.isContract ? "contract" : "slot"
        ]
        let coordinator = LiveActivityCoordinator.shared
        guard coordinator.isSupported else {
            Task {
                await marker.value
                body["liveActivityStatus"] = "unsupported"
                reply("ACTIVITY_COMPLETION_ACCEPTED", body)
            }
            return
        }
        guard let admitted = admitLiveActivityMutation(payload: payload, context: nil, reply: reply) else { return }
        let (envelope, account) = admitted
        let finish = liveActivityFinisher(envelope, reply: reply)
        let completion = LiveActivityEngine.Completion(scope: scope, activityId: activityId, account: account)
        coordinator.submit(.completion(completion)) { outcome in
            Task {
                await marker.value
                switch outcome {
                case .completion(let tracked, let status):
                    body["tracked"] = tracked
                    if let status { body["presentationStatus"] = status.rawValue }
                    finish("ACTIVITY_COMPLETION_ACCEPTED", body)
                case .rejected(let error):
                    finish("ERROR", error.payload)
                default:
                    finish("ERROR", ["message": "Unexpected Live Activity result", "code": "internal_error"])
                }
            }
        }
    }

    private static let completionSources: Set<String> = ["timer", "healthkit", "manual"]

    private static func parseGoal(_ raw: [String: Any]) throws -> HealthGoal {
        guard let activityId = raw["activityId"] as? String, !activityId.isEmpty,
              let activityName = raw["activityName"] as? String, !activityName.isEmpty,
              let metricName = raw["metric"] as? String,
              let metric = HealthMetric(rawValue: metricName),
              let target = number(raw["target"]), target.isFinite, target > 0,
              let unit = raw["unit"] as? String, unit == metric.unitName else {
            throw BridgePayloadError.invalidGoal
        }
        return HealthGoal(
            activityId: activityId,
            activityName: activityName,
            metric: metric,
            target: target,
            unit: unit
        )
    }

    private enum BridgePayloadError: LocalizedError {
        case invalidGoal

        var errorDescription: String? {
            "Each goal needs activityId, activityName, a known metric, a positive target and its canonical unit"
        }
    }

    // MARK: - Dates

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601NoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Accepts both `2026-09-14T04:00:00.000Z` (JavaScript `toISOString`) and
    /// the same without fractional seconds.
    private static func date(from raw: Any?) -> Date? {
        guard let string = raw as? String else { return nil }
        return iso8601.date(from: string) ?? iso8601NoFraction.date(from: string)
    }

    /// JSON `true`/`false` only. JavaScript numbers arrive as NSNumber too, so
    /// the CoreFoundation type is checked rather than relying on `as? Bool`.
    private static func bool(_ raw: Any?) -> Bool? {
        guard let raw, CFGetTypeID(raw as CFTypeRef) == CFBooleanGetTypeID() else { return nil }
        return raw as? Bool
    }

    /// JSON numbers only. `raw is Bool` is also true for the numbers 0 and 1
    /// from JSON, which rejected a 1-second timer or a target of 1, so booleans
    /// are told apart by their CoreFoundation type instead.
    private static func number(_ raw: Any?) -> Double? {
        LiveActivityProtocol.number(raw)
    }

    // MARK: - Sending

    /// - Parameter requestId: echoed back from the inbound message that caused this
    ///   reply. The web app uses its presence to tell a solicited reply from an
    ///   unsolicited broadcast, so that answering a request cannot trigger another.
    func send(type: String, payload: [String: Any], requestId: String? = nil) {
        var payload = payload
        if let requestId { payload["requestId"] = requestId }

        // NATIVE_READY is what tells the page a bridge exists at all, so it must
        // never wait in the queue behind itself.
        let isBroadcast = requestId == nil && type != "NATIVE_READY"
        if isBroadcast && !isWebReady {
            enqueuePending(type: type, payload: payload, createdAt: Date())
            return
        }

        dispatch(type: type, payload: payload)
    }

    private func enqueuePending(type: String, payload: [String: Any], createdAt: Date) {
        if pendingBroadcasts.count >= pendingLimit {
            pendingBroadcasts.removeFirst()
        }
        pendingBroadcasts.append((type, payload, createdAt))
    }

    /// Flushes the in-memory queue together with anything persisted across a
    /// relaunch, oldest first, so a `GOAL_REACHED` from last night still lands
    /// before the `NOTIFICATION_OPENED` that launched the app this morning.
    private func markWebReadyAndFlush() {
        isWebReady = true
        flushStoredEvents()
    }

    private func flushStoredEvents() {
        Task { @MainActor [weak self] in
            let stored = await NativeEventStore.shared.drain()
            guard let self else { return }

            var queued = self.pendingBroadcasts
            self.pendingBroadcasts.removeAll()
            queued += stored.map { ($0.type, $0.payloadObject(), $0.createdAt) }
            queued.sort { $0.createdAt < $1.createdAt }

            // The page may have started reloading while the store was read. Keep
            // the batch for the next ready flush rather than evaluating into a
            // page that is going away.
            guard self.isWebReady else {
                for event in queued {
                    self.enqueuePending(type: event.type, payload: event.payload, createdAt: event.createdAt)
                }
                return
            }
            for event in queued {
                self.dispatch(type: event.type, payload: event.payload)
            }
        }
    }

    /// Auth replies: evaluated only if the page that asked is still the one
    /// loaded when the script actually runs.
    func dispatchNow(type: String, payload: [String: Any], generation: Int) {
        guard let script = Self.eventScript(type: type, payload: payload) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.googleAuth.documentGeneration,
                  let webView = self.webView,
                  self.trustedWebOrigin?.matches(url: webView.url) == true else { return }
            webView.evaluateJavaScript(script)
        }
    }

    private static func eventScript(type: String, payload: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(payload),
              let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let payloadJSON = String(data: payloadData, encoding: .utf8) else { return nil }
        let escapedType = type.replacingOccurrences(of: "'", with: "\\'")
        return """
        window.dispatchEvent(new CustomEvent('honoured:native', {
          detail: { bridgeVersion: \(AppConfig.bridgeVersion), type: '\(escapedType)', payload: \(payloadJSON) }
        }));
        """
    }

    private func dispatch(type: String, payload: [String: Any]) {
        guard let script = Self.eventScript(type: type, payload: payload) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(script)
        }
    }
}

enum NativeBridgeEvents {
    static let notification = Notification.Name("HonouredNativeBridgeEvent")

    /// In-memory delivery. Reaches a live bridge now or after the next reload,
    /// but is lost if no WebView exists yet. Use for events the web app can
    /// recover on its own (`HEALTH_DATA_UPDATED`) and for anything carrying a
    /// token, which must never be written to disk.
    static func post(type: String, payload: [String: Any]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: notification,
                object: nil,
                userInfo: ["type": type, "payload": payload]
            )
        }
    }

    /// Persisted delivery for `NOTIFICATION_OPENED`, `GOAL_REACHED` and
    /// `TIMER_COMPLETED`: survives a cold start and a background launch with no
    /// scene. The store notifies any live bridge, which flushes it once ready.
    static func postDurable(type: String, payload: [String: Any]) {
        let createdAt = Date()
        Task {
            try? await NativeEventStore.shared.append(type: type, payload: payload, createdAt: createdAt)
        }
    }
}
