import Foundation

/// Pure helpers for APNs token registration (V1.2 M2-06). Foundation only, so
/// the host-less test target compiles it.
enum PushTokenSupport {
    /// The slot kinds the server's `register_push_token` accepts.
    enum Kind: String {
        case device
        case pushToStart = "push_to_start"
        case activity
    }

    enum Environment: String {
        case sandbox
        case production
    }

    /// Token bytes as the lower-case hex string APNs addresses.
    static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    /// Which APNs gateway this build's tokens belong to, read from the
    /// embedded provisioning profile: Xcode and ad-hoc development builds carry
    /// `aps-environment = development`. App Store and TestFlight builds have no
    /// embedded profile and always use production.
    static func environment(provisioningProfile: Data?) -> Environment {
        guard let profile = provisioningProfile,
              let start = profile.range(of: Data("<?xml".utf8)),
              let end = profile.range(of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: profile.subdata(in: start.lowerBound..<end.upperBound), format: nil
              ) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let aps = entitlements["aps-environment"] as? String else {
            return .production
        }
        return aps == "development" ? .sandbox : .production
    }

    /// What was last sent for one slot, so an unchanged token is not sent again.
    static func fingerprint(
        userId: String, kind: Kind, token: String, environment: Environment,
        liveActivitiesEnabled: Bool?, osVersion: String, contractId: String? = nil, iconDay: String? = nil
    ) -> String {
        [userId, kind.rawValue, token, environment.rawValue,
         liveActivitiesEnabled.map { $0 ? "1" : "0" } ?? "-", osVersion,
         contractId ?? "", iconDay ?? ""].joined(separator: "|")
    }

    /// Every token is sent again once a day, so rows the server dropped come back.
    static func needsFullSync(lastFullSync: Date?, now: Date) -> Bool {
        guard let lastFullSync else { return true }
        return now.timeIntervalSince(lastFullSync) >= 24 * 3600 || lastFullSync > now
    }

    /// Card tokens for Icon days before this one (`yyyy-MM-dd`) are forgotten;
    /// the server drops them after three days as well.
    static func oldestCardDay(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now.addingTimeInterval(-2 * 24 * 3600))
    }
}
