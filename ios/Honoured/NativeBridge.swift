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
        case "CHECK_ACCESS":
            send(type: "ACCESS_STATUS", payload: [
                "isSubscribed": false,
                "trialActive": false,
                "source": "foundation_stub"
            ])
        case "START_PURCHASE", "RESTORE_PURCHASES", "START_SESSION":
            send(type: "ERROR", payload: [
                "message": "\(type) is reserved for a later implementation step"
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
