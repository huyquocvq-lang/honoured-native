import Foundation
import WebKit

final class NativeBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?

    /// Broadcasts raised before the web app has sent APP_READY (a notification
    /// tapped on cold start, a goal reached during a background sync) are held
    /// here and flushed right after NATIVE_READY, so they cannot land on a page
    /// that has no listener yet. Bounded so a stuck WebView cannot grow it forever.
    private var pendingBroadcasts: [(type: String, payload: [String: Any])] = []
    private var isWebReady = false
    private let pendingLimit = 50

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNativeEvent(_:)),
            name: NativeBridgeEvents.notification,
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

    private static let v2MessageTypes: Set<String> = [
        "SET_AUTH_SESSION", "CLEAR_AUTH_SESSION",
        "REQUEST_HEALTH_PERMISSION", "GET_HEALTH_STATUS", "QUERY_HEALTH_METRICS",
        "SET_GOALS", "SET_DAY_RESET_HOUR",
        "START_TIMER", "CANCEL_TIMER", "GET_TIMER_STATE",
        "ACTIVITY_COMPLETED", "SET_SOUND_ENABLED",
        "SIGN_IN_WITH_APPLE",
    ]

    /// Called when the WebView starts a new main-frame load. Anything broadcast
    /// from now until the next APP_READY is queued instead of dropped.
    func webViewWillReload() {
        isWebReady = false
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else {
            send(type: "ERROR", payload: ["message": "Invalid bridge message"])
            return
        }

        let payload = body["payload"] as? [String: Any] ?? [:]
        let requestID = payload["requestId"] as? String
        let reply: (String, [String: Any]) -> Void = { [weak self] replyType, replyPayload in
            self?.send(type: replyType, payload: replyPayload, requestId: requestID)
        }

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

        switch type {
        case "APP_READY":
            reply("NATIVE_READY", [
                "platform": "ios",
                "bridgeVersion": AppConfig.bridgeVersion
            ])
        case "GET_PLATFORM_INFO":
            reply("PLATFORM_INFO", [
                "platform": "ios",
                "bridgeVersion": AppConfig.bridgeVersion
            ])
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
                    // read as "not subscribed".
                    if status["isSubscribed"] != nil {
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
                    reply("ACCESS_STATUS", ["isSubscribed": false, "source": "logout"])
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
            Task {
                do {
                    let previousUserId = await AuthSessionStore.shared.load()?.userId
                    if let previousUserId, previousUserId != userId {
                        try await HealthSyncCoordinator.shared.clear()
                        await HealthKitService.shared.resetSyncState()
                        await HealthSyncSettings.shared.reset()
                    }
                    try await AuthSessionStore.shared.save(NativeAuthSession(
                        userId: userId,
                        accessToken: accessToken,
                        refreshToken: refreshToken,
                        expiresAt: expiresAt
                    ))
                    reply("AUTH_SESSION_ACCEPTED", ["userId": userId])
                    HealthBackgroundObserver.shared.enableBackgroundDelivery()
                    await HealthSyncCoordinator.shared.syncNow()
                } catch {
                    reply("ERROR", ["message": error.localizedDescription, "code": "auth_session_store_failed"])
                }
            }
        case "CLEAR_AUTH_SESSION":
            Task {
                do {
                    try await AuthSessionStore.shared.clear()
                    try await HealthSyncCoordinator.shared.clear()
                    await HealthKitService.shared.resetSyncState()
                    await HealthSyncSettings.shared.reset()
                    HealthBackgroundObserver.shared.disableBackgroundDelivery()
                    reply("AUTH_SESSION_CLEARED", [:])
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
                await HealthSyncSettings.shared.setDayResetHour(hour)
                reply("DAY_RESET_HOUR_ACCEPTED", ["hour": hour])
            }
        default:
            reply("ERROR", [
                "message": "\(type) is not implemented in this build",
                "code": "not_implemented"
            ])
        }
    }

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

    private static func number(_ raw: Any?) -> Double? {
        if raw is Bool { return nil }
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        return nil
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
            if pendingBroadcasts.count >= pendingLimit {
                pendingBroadcasts.removeFirst()
            }
            pendingBroadcasts.append((type, payload))
            return
        }

        dispatch(type: type, payload: payload)
    }

    private func markWebReadyAndFlush() {
        isWebReady = true
        let queued = pendingBroadcasts
        pendingBroadcasts.removeAll()
        for event in queued {
            dispatch(type: event.type, payload: event.payload)
        }
    }

    private func dispatch(type: String, payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let payloadJSON = String(data: payloadData, encoding: .utf8) else { return }

        let escapedType = type.replacingOccurrences(of: "'", with: "\\'")
        let script = """
        window.dispatchEvent(new CustomEvent('honoured:native', {
          detail: { bridgeVersion: \(AppConfig.bridgeVersion), type: '\(escapedType)', payload: \(payloadJSON) }
        }));
        """

        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript(script)
        }
    }
}

enum NativeBridgeEvents {
    static let notification = Notification.Name("HonouredNativeBridgeEvent")

    static func post(type: String, payload: [String: Any]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: notification,
                object: nil,
                userInfo: ["type": type, "payload": payload]
            )
        }
    }
}
