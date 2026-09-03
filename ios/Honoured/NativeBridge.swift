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

        switch type {
        case "APP_READY":
            send(type: "NATIVE_READY", payload: [
                "platform": "ios",
                "bridgeVersion": AppConfig.bridgeVersion
            ])
        case "GET_PLATFORM_INFO":
            send(type: "PLATFORM_INFO", payload: [
                "platform": "ios",
                "bridgeVersion": AppConfig.bridgeVersion
            ])
        case "IDENTIFY_USER":
            guard let userID = payload["userId"] as? String, !userID.isEmpty else {
                send(type: "IDENTIFY_FAILED", payload: ["message": "Missing userId"])
                return
            }
            Task { @MainActor [weak self] in
                switch await SubscriptionService.shared.identify(appUserID: userID) {
                case .completed(let status):
                    self?.send(type: "IDENTIFY_SUCCESS", payload: status)
                    self?.send(type: "ACCESS_STATUS", payload: status)
                case .cancelled:
                    self?.send(type: "IDENTIFY_FAILED", payload: ["message": "Unexpected cancellation"])
                case .failed(let message):
                    self?.send(type: "IDENTIFY_FAILED", payload: ["message": message])
                }
            }
        case "LOGOUT_USER":
            Task { @MainActor [weak self] in
                switch await SubscriptionService.shared.logout() {
                case .completed:
                    self?.send(type: "LOGOUT_SUCCESS", payload: ["isSubscribed": false])
                    self?.send(type: "ACCESS_STATUS", payload: ["isSubscribed": false, "source": "logout"])
                case .cancelled:
                    self?.send(type: "LOGOUT_FAILED", payload: ["message": "Unexpected cancellation"])
                case .failed(let message):
                    self?.send(type: "LOGOUT_FAILED", payload: ["message": message])
                }
            }
        case "CHECK_ACCESS":
            Task { @MainActor [weak self] in
                let status = await SubscriptionService.shared.accessStatus()
                self?.send(type: "ACCESS_STATUS", payload: status)
            }
        case "START_PURCHASE":
            guard let userID = payload["userId"] as? String, !userID.isEmpty else {
                send(type: "PURCHASE_FAILED", payload: ["message": "Missing userId"])
                return
            }
            let packageIdentifier = payload["packageIdentifier"] as? String
            Task { @MainActor [weak self] in
                switch await SubscriptionService.shared.identify(appUserID: userID) {
                case .completed:
                    switch await SubscriptionService.shared.purchase(packageIdentifier: packageIdentifier) {
                    case .completed(let status):
                        self?.send(type: "PURCHASE_SUCCESS", payload: status)
                        self?.send(type: "ACCESS_STATUS", payload: status)
                    case .cancelled:
                        self?.send(type: "PURCHASE_CANCELLED", payload: [:])
                    case .failed(let message):
                        self?.send(type: "PURCHASE_FAILED", payload: ["message": message])
                    }
                case .cancelled:
                    self?.send(type: "PURCHASE_FAILED", payload: ["message": "Could not identify signed-in user"])
                case .failed(let message):
                    self?.send(type: "PURCHASE_FAILED", payload: ["message": message])
                }
            }
        case "RESTORE_PURCHASES":
            guard let userID = payload["userId"] as? String, !userID.isEmpty else {
                send(type: "RESTORE_FAILED", payload: ["message": "Missing userId"])
                return
            }
            Task { @MainActor [weak self] in
                switch await SubscriptionService.shared.identify(appUserID: userID) {
                case .completed:
                    switch await SubscriptionService.shared.restore() {
                    case .completed(let status):
                        self?.send(type: "RESTORE_SUCCESS", payload: status)
                        self?.send(type: "ACCESS_STATUS", payload: status)
                    case .cancelled:
                        self?.send(type: "RESTORE_SUCCESS", payload: ["isSubscribed": false])
                    case .failed(let message):
                        self?.send(type: "RESTORE_FAILED", payload: ["message": message])
                    }
                case .cancelled:
                    self?.send(type: "RESTORE_FAILED", payload: ["message": "Could not identify signed-in user"])
                case .failed(let message):
                    self?.send(type: "RESTORE_FAILED", payload: ["message": message])
                }
            }
        case "START_SESSION":
            send(type: "ERROR", payload: [
                "message": "Trial sessions are enforced by Supabase RPC from the authenticated web app"
            ])
        default:
            send(type: "ERROR", payload: ["message": "Unsupported bridge message: \(type)"])
        }
    }

    func send(type: String, payload: [String: Any]) {
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
