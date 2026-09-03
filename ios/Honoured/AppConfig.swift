import Foundation

enum AppConfig {
    static let bridgeVersion = 1
    static let revenueCatEntitlementID = "honoured_plus"

    static var webAppURL: URL {
        let raw = Bundle.main.object(forInfoDictionaryKey: "HonouredWebAppURL") as? String ?? ""
        let value = raw.hasPrefix("$(") ? "" : raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), !value.isEmpty else {
            fatalError("HONOURED_WEB_APP_URL is not configured. Copy ios/Config.xcconfig.example to ios/Config.xcconfig and set it.")
        }
        return url
    }

    static var revenueCatAPIKey: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String ?? ""
        return raw.hasPrefix("$(") ? "" : raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
