import Foundation
import WebKit

final class NativeBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?

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
                    reply("ACCESS_STATUS", status)
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

    /// - Parameter requestId: echoed back from the inbound message that caused this
    ///   reply. The web app uses its presence to tell a solicited reply from an
    ///   unsolicited broadcast, so that answering a request cannot trigger another.
    func send(type: String, payload: [String: Any], requestId: String? = nil) {
        var payload = payload
        if let requestId { payload["requestId"] = requestId }
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
