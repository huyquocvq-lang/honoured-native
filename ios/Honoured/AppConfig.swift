import Foundation

enum AppConfig {
    static let bridgeVersion = 2
    static let revenueCatEntitlementID = "honoured_plus"

    static var webAppURL: URL {
        let value = infoString("HonouredWebAppURL")
        guard let url = URL(string: value), !value.isEmpty else {
            fatalError("HONOURED_WEB_APP_URL is not configured. Copy ios/Config.xcconfig.example to ios/Config.xcconfig and set it.")
        }
        return url
    }

    static var revenueCatAPIKey: String {
        infoString("RevenueCatAPIKey")
    }

    /// Nil leaves native HealthKit sync disabled rather than crashing.
    static var supabaseURL: URL? {
        let value = infoString("SupabaseURL")
        return value.isEmpty ? nil : URL(string: value)
    }

    static var supabaseAnonKey: String {
        infoString("SupabaseAnonKey")
    }

    static var healthSyncTaskIdentifier: String {
        (Bundle.main.bundleIdentifier ?? "com.honoured.app") + ".healthsync"
    }

    /// Reads an Info.plist string injected from Config.xcconfig. An unset
    /// xcconfig variable arrives as the literal "$(NAME)", which is treated as empty.
    private static func infoString(_ key: String) -> String {
        let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
        return raw.hasPrefix("$(") ? "" : raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
