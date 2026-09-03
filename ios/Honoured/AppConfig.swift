import Foundation

enum AppConfig {
    static let webAppURL = URL(string: "https://honour-your-word.lovable.app")!
    static let bridgeVersion = 1
    static let revenueCatEntitlementID = "honoured_plus"

    static var revenueCatAPIKey: String {
        let raw = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String ?? ""
        return raw.hasPrefix("$(") ? "" : raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
