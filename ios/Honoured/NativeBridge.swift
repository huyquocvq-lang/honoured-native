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
            markWebReadyAndFlush()
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
                }
                reply("HEALTH_PERMISSION_STATUS", await service.permissionStatusPayload(for: parsed.metrics))
            }
        case "GET_HEALTH_STATUS":
            Task { @MainActor in
                reply("HEALTH_PERMISSION_STATUS", await HealthKitService.shared.permissionStatusPayload(for: HealthMetric.allCases))
            }
        default:
            reply("ERROR", [
                "message": "\(type) is not implemented in this build",
                "code": "not_implemented"
            ])
        }
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
