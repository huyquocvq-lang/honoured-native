import XCTest

final class HealthSourcePreferenceTests: XCTestCase {
    private let watch = HealthSourceDescriptor.make(
        name: "Apple Watch",
        bundleIdentifier: "com.apple.health.watch"
    )
    private let phone = HealthSourceDescriptor.make(
        name: "Vu's iPhone",
        bundleIdentifier: "com.apple.health.iphone"
    )
    private let garmin = HealthSourceDescriptor.make(
        name: "Garmin Connect",
        bundleIdentifier: "com.garmin.connect"
    )

    func testAutomaticPrefersAppleWatchOverPhone() {
        let result = HealthSourceSelector.resolve(preference: .automatic, available: [phone, watch])
        XCTAssertEqual(result.selected, watch)
        XCTAssertFalse(result.requestedSourceMissing)
    }

    func testAutomaticUsesPhoneWhenNoWatchExists() {
        let result = HealthSourceSelector.resolve(preference: .automatic, available: [phone])
        XCTAssertEqual(result.selected, phone)
    }

    func testManualSelectionWinsOverAutomaticRanking() {
        let result = HealthSourceSelector.resolve(preference: .source(phone.id), available: [watch, phone])
        XCTAssertEqual(result.selected, phone)
        XCTAssertFalse(result.requestedSourceMissing)
    }

    func testMissingManualSourceFallsBackToBestAvailable() {
        let result = HealthSourceSelector.resolve(preference: .source("missing"), available: [phone, watch])
        XCTAssertEqual(result.selected, watch)
        XCTAssertTrue(result.requestedSourceMissing)
    }

    func testPhoneRanksAheadOfThirdPartySources() {
        let result = HealthSourceSelector.resolve(preference: .automatic, available: [phone, garmin])
        XCTAssertEqual(result.selected, phone)
    }

    func testEmptySourcesUseAggregateFallback() {
        let result = HealthSourceSelector.resolve(preference: .automatic, available: [])
        XCTAssertNil(result.selected)
        XCTAssertFalse(result.requestedSourceMissing)
    }

    func testPreferencePayloadParsingRejectsIncompleteSource() {
        XCTAssertEqual(HealthSourcePreference.parse(mode: "automatic", sourceId: nil), .automatic)
        XCTAssertEqual(HealthSourcePreference.parse(mode: "source", sourceId: watch.id), .source(watch.id))
        XCTAssertNil(HealthSourcePreference.parse(mode: "source", sourceId: nil))
        XCTAssertNil(HealthSourcePreference.parse(mode: "other", sourceId: nil))
    }
}
