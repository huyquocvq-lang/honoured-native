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

    // MARK: - Core Motion (Phase 3 M2-C)

    func testCoreMotionTravelsAsAnOrdinarySourceSoOlderWebBuildsKeepWorking() {
        let payload = HealthSourcePreference.coreMotion.payload
        XCTAssertEqual(payload, ["mode": "source", "sourceId": "core_motion"])
        XCTAssertEqual(HealthSourcePreference.parse(mode: payload["mode"], sourceId: payload["sourceId"]), .coreMotion)
    }

    func testCoreMotionIdCannotNameAHealthKitSource() {
        for source in [watch, phone, garmin] {
            XCTAssertNotEqual(source.id, HealthSourceDescriptor.coreMotionId)
            XCTAssertTrue(source.id.contains("|"))
        }
        XCTAssertFalse(HealthSourceDescriptor.coreMotionId.contains("|"))
        XCTAssertEqual(HealthSourceDescriptor.coreMotion.kind, .coreMotion)
    }

    func testReadableCoreMotionReplacesHealthKitWhateverSourcesExist() {
        for available in [[phone, watch], [garmin], []] {
            let result = HealthSourceSelector.resolve(preference: .coreMotion, available: available, motionReadable: true)
            XCTAssertEqual(result.selected, .coreMotion)
            XCTAssertFalse(result.requestedSourceMissing)
            XCTAssertEqual(result.readingSource, .coreMotion)
        }
    }

    func testUnreadableCoreMotionFallsBackToTheCombinedTotalAndSaysSo() {
        let result = HealthSourceSelector.resolve(preference: .coreMotion, available: [phone, watch], motionReadable: false)
        XCTAssertNil(result.selected)
        XCTAssertTrue(result.requestedSourceMissing)
        XCTAssertEqual(result.readingSource, .healthKit)
    }

    func testAHealthKitSourceIsStillReadFromHealthKit() {
        XCTAssertEqual(HealthSourceSelector.resolve(preference: .automatic, available: [phone]).readingSource, .healthKit)
        XCTAssertEqual(
            HealthSourceSelector.resolve(preference: .source(garmin.id), available: [garmin], motionReadable: true).readingSource,
            .healthKit
        )
    }

    func testDailyBasisChangesWhenCoreMotionBecomesReadable() {
        XCTAssertEqual(HealthSourcePreference.automatic.dailyBasis(motionReadable: true), "combined")
        XCTAssertEqual(HealthSourcePreference.source(garmin.id).dailyBasis(motionReadable: true), "source:\(garmin.id)")
        XCTAssertEqual(HealthSourcePreference.coreMotion.dailyBasis(motionReadable: false), "combined")
        XCTAssertEqual(HealthSourcePreference.coreMotion.dailyBasis(motionReadable: true), "core_motion")
    }
}
