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

    // MARK: - This iPhone (Phase 4 M1.5)

    func testThisIPhoneTravelsAsAnOrdinarySourceSoOlderWebBuildsKeepWorking() {
        let payload = HealthSourcePreference.thisIPhone.payload
        XCTAssertEqual(payload, ["mode": "source", "sourceId": "this_iphone"])
        XCTAssertEqual(HealthSourcePreference.parse(mode: payload["mode"], sourceId: payload["sourceId"]), .thisIPhone)
    }

    func testThisIPhoneIdCannotNameAHealthKitSource() {
        for source in [watch, phone, garmin] {
            XCTAssertNotEqual(source.id, HealthSourceDescriptor.thisIPhoneId)
        }
        XCTAssertFalse(HealthSourceDescriptor.thisIPhoneId.contains("|"))
        XCTAssertNotEqual(HealthSourceDescriptor.thisIPhoneId, HealthSourceDescriptor.coreMotionId)
        XCTAssertEqual(HealthSourceDescriptor.thisIPhone.kind, .thisIPhone)
        XCTAssertEqual(HealthSourceDescriptor.thisIPhone.kind.rawValue, "this_iphone")
        XCTAssertEqual(HealthSourceDescriptor.thisIPhone.name, "iPhone")
    }

    func testAPreviouslyChosenIPhoneSourceStaysAnOrdinarySource() {
        // A choice saved by the old picker ("Vu's iPhone") is still honoured;
        // the web app moves people onto the three options.
        XCTAssertEqual(HealthSourcePreference.parse(mode: "source", sourceId: phone.id), .source(phone.id))
    }

    func testThisIPhoneNarrowsTheReadToTheDeviceAndIsStillHealthKit() {
        for available in [[phone, watch], [garmin], []] {
            let result = HealthSourceSelector.resolve(preference: .thisIPhone, available: available, thisIPhoneReadable: true)
            XCTAssertEqual(result.selected, .thisIPhone)
            XCTAssertFalse(result.requestedSourceMissing)
            XCTAssertEqual(result.readingSource, .healthKit)
            XCTAssertEqual(result.iconSource, .healthKitIPhone)
        }
    }

    func testThisIPhoneWithoutSamplesFallsBackToTheCombinedTotalAndSaysSo() {
        let result = HealthSourceSelector.resolve(
            preference: .thisIPhone, available: [phone, watch], motionReadable: true, thisIPhoneReadable: false
        )
        XCTAssertNil(result.selected)
        XCTAssertTrue(result.requestedSourceMissing)
        XCTAssertEqual(result.readingSource, .healthKit)
        XCTAssertEqual(result.iconSource, .healthKit)
    }

    func testThisIPhoneNeverAddsCoreMotion() {
        let result = HealthSourceSelector.resolve(preference: .thisIPhone, available: [], motionReadable: true, thisIPhoneReadable: true)
        XCTAssertNotEqual(result.readingSource, .coreMotion)
    }

    func testIconSourceTellsTheCombinedTotalFromThisIPhone() {
        XCTAssertEqual(HealthSourceSelector.resolve(preference: .automatic, available: [phone]).iconSource, .healthKit)
        XCTAssertEqual(HealthSourceSelector.resolve(preference: .source(phone.id), available: [phone]).iconSource, .healthKit)
        XCTAssertEqual(
            HealthSourceSelector.resolve(preference: .coreMotion, available: [], motionReadable: true).iconSource,
            .coreMotion
        )
        XCTAssertEqual(IconMeasurementSource.healthKitIPhone.rawValue, "healthkit_iphone")
    }

    func testDailyBasisForThisIPhoneNamesTheModel() {
        XCTAssertEqual(HealthSourcePreference.thisIPhone.dailyBasis(motionReadable: true, thisIPhoneModel: "iPhone16,2"), "this_iphone:iPhone16,2")
        XCTAssertEqual(HealthSourcePreference.thisIPhone.dailyBasis(motionReadable: true, thisIPhoneModel: nil), "combined")
        XCTAssertNotEqual(
            HealthSourcePreference.thisIPhone.dailyBasis(motionReadable: true, thisIPhoneModel: "iPhone16,2"),
            HealthSourcePreference.thisIPhone.dailyBasis(motionReadable: true, thisIPhoneModel: "iPhone17,1")
        )
    }
}
