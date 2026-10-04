import XCTest

final class PushTokenSupportTests: XCTestCase {
    func testTokensAreLowerCaseHex() {
        XCTAssertEqual(PushTokenSupport.hex(Data([0x00, 0xAB, 0x10, 0xFF])), "00ab10ff")
        XCTAssertEqual(PushTokenSupport.hex(Data()), "")
    }

    func testEnvironmentComesFromTheEmbeddedProfile() {
        XCTAssertEqual(PushTokenSupport.environment(provisioningProfile: Self.profile(aps: "development")), .sandbox)
        XCTAssertEqual(PushTokenSupport.environment(provisioningProfile: Self.profile(aps: "production")), .production)
    }

    /// App Store and TestFlight builds carry no profile; anything unreadable
    /// counts as production too.
    func testWithoutAReadableProfileTheEnvironmentIsProduction() {
        XCTAssertEqual(PushTokenSupport.environment(provisioningProfile: nil), .production)
        XCTAssertEqual(PushTokenSupport.environment(provisioningProfile: Data("not a profile".utf8)), .production)
        XCTAssertEqual(PushTokenSupport.environment(provisioningProfile: Self.profile(aps: nil)), .production)
        XCTAssertEqual(PushTokenSupport.environment(provisioningProfile: Data("<?xml version=\"1.0\"?><plist".utf8)), .production)
    }

    func testFingerprintChangesWithEveryField() {
        func print(
            user: String = "u", kind: PushTokenSupport.Kind = .activity, token: String = "ab",
            environment: PushTokenSupport.Environment = .sandbox, enabled: Bool? = true, os: String = "18.1",
            contract: String? = "c", day: String? = "2026-10-06"
        ) -> String {
            PushTokenSupport.fingerprint(
                userId: user, kind: kind, token: token, environment: environment,
                liveActivitiesEnabled: enabled, osVersion: os, contractId: contract, iconDay: day
            )
        }
        let base = print()
        XCTAssertEqual(base, print())
        let variants = [
            print(user: "v"), print(kind: .device), print(token: "cd"), print(environment: .production),
            print(enabled: false), print(enabled: nil), print(os: "18.2"), print(contract: "d"), print(day: "2026-10-07"),
        ]
        XCTAssertFalse(variants.contains(base))
        XCTAssertEqual(Set(variants).count, variants.count)
    }

    func testEveryTokenIsResentOnceADay() {
        let now = Date(timeIntervalSince1970: 1_791_280_800)
        XCTAssertTrue(PushTokenSupport.needsFullSync(lastFullSync: nil, now: now))
        XCTAssertFalse(PushTokenSupport.needsFullSync(lastFullSync: now.addingTimeInterval(-23 * 3600), now: now))
        XCTAssertTrue(PushTokenSupport.needsFullSync(lastFullSync: now.addingTimeInterval(-24 * 3600), now: now))
        // A clock set back must not stop the daily resend.
        XCTAssertTrue(PushTokenSupport.needsFullSync(lastFullSync: now.addingTimeInterval(3600), now: now))
    }

    func testCardTokensOlderThanTwoDaysAreForgotten() {
        // 2026-10-06 00:30 UTC
        let now = Date(timeIntervalSince1970: 1_791_246_600)
        XCTAssertEqual(PushTokenSupport.oldestCardDay(now: now), "2026-10-04")
    }

    /// An embedded.mobileprovision is a CMS envelope around an XML plist.
    private static func profile(aps: String?) -> Data {
        var entitlements: [String: Any] = ["application-identifier": "TEAM.com.example.app"]
        if let aps { entitlements["aps-environment"] = aps }
        let plist = try! PropertyListSerialization.data(
            fromPropertyList: ["Name": "Example", "Entitlements": entitlements], format: .xml, options: 0
        )
        return Data([0x30, 0x82, 0x1F, 0x00, 0x06, 0x09]) + plist + Data([0xA0, 0x82, 0x0D, 0x00])
    }
}
