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
        name: "Connect",
        bundleIdentifier: "com.garmin.connect.mobile"
    )

    func testAutomaticReadsTheCombinedTotalWhateverDevicesExist() {
        for available in [[phone, watch], [phone, garmin], [phone], [garmin], []] {
            let result = HealthSourceSelector.resolve(preference: .automatic, available: available)
            XCTAssertNil(result.selected, "\(available.map(\.name))")
            XCTAssertFalse(result.requestedSourceMissing)
        }
    }

    func testManualSelectionNarrowsTheReadToThatSource() {
        let result = HealthSourceSelector.resolve(preference: .source(phone.id), available: [watch, phone])
        XCTAssertEqual(result.selected, phone)
        XCTAssertFalse(result.requestedSourceMissing)
    }

    func testManualSelectionCanPickAThirdPartyWatch() {
        let result = HealthSourceSelector.resolve(preference: .source(garmin.id), available: [phone, garmin])
        XCTAssertEqual(result.selected, garmin)
        XCTAssertFalse(result.requestedSourceMissing)
    }

    func testMissingManualSourceFallsBackToTheCombinedTotal() {
        let result = HealthSourceSelector.resolve(preference: .source("missing"), available: [phone, watch])
        XCTAssertNil(result.selected)
        XCTAssertTrue(result.requestedSourceMissing)
    }

    func testDescriptorKindStillLabelsTheSource() {
        XCTAssertEqual(watch.kind, .appleWatch)
        XCTAssertEqual(phone.kind, .iPhone)
        XCTAssertEqual(garmin.kind, .otherWatch)
    }

    func testPreferencePayloadParsingRejectsIncompleteSource() {
        XCTAssertEqual(HealthSourcePreference.parse(mode: "automatic", sourceId: nil), .automatic)
        XCTAssertEqual(HealthSourcePreference.parse(mode: "source", sourceId: watch.id), .source(watch.id))
        XCTAssertNil(HealthSourcePreference.parse(mode: "source", sourceId: nil))
        XCTAssertNil(HealthSourcePreference.parse(mode: "other", sourceId: nil))
    }
}
