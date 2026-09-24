import Foundation

enum AppConfig {
    static let bridgeVersion = 2

    /// The RevenueCat entitlement the shell checks. Production is
    /// `honoured_plus`; a developer build can point at its own entitlement
    /// with REVENUECAT_ENTITLEMENT_ID in .env, so testing against a personal
    /// RevenueCat project never edits tracked source. An unset value keeps
    /// the production identifier.
    static var revenueCatEntitlementID: String {
        let value = infoString("RevenueCatEntitlementID")
        return value.isEmpty ? "honoured_plus" : value
    }

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
        #if DEBUG
        // The bridge stub signs in with fake sessions and fake Health totals;
        // none of that may ever reach the real backend.
        if BridgeStub.isEnabled { return nil }
        #endif
        let value = infoString("SupabaseURL")
        return value.isEmpty ? nil : URL(string: value)
    }

    static var supabaseAnonKey: String {
        infoString("SupabaseAnonKey")
    }

    /// Public Google client IDs. Nil when missing, malformed, or when the
    /// reversed iOS client ID is not registered as a URL scheme, which turns
    /// Google Sign-In off (`configured: false`) instead of crashing the SDK.
    static var googleClientConfig: GoogleClientConfig? {
        let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        return GoogleClientConfig.validate(
            clientID: infoString("GoogleIOSClientID"),
            serverClientID: infoString("GoogleServerClientID"),
            registeredSchemes: schemes
        )
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
