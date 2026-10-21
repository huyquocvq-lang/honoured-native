import XCTest

final class MotionModelsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_000_000)

    func testOnlyStepsAndWalkingDistanceHaveACoreMotionCounterpart() {
        let motion = MotionAvailability(stepCounting: true, distance: true, authorization: .authorized)
        XCTAssertTrue(motion.canRead(.steps))
        XCTAssertTrue(motion.canRead(.distanceWalkingRunning))
        for metric in HealthMetric.allCases where metric != .steps && metric != .distanceWalkingRunning {
            XCTAssertFalse(motion.canRead(metric), metric.rawValue)
        }
    }

    func testNothingIsReadWithoutPermission() {
        for authorization in [MotionAuthorization.notDetermined, .denied, .restricted] {
            let motion = MotionAvailability(stepCounting: true, distance: true, authorization: authorization)
            XCTAssertFalse(motion.canRead(.steps), authorization.rawValue)
            XCTAssertFalse(motion.canRead(.distanceWalkingRunning), authorization.rawValue)
        }
    }

    func testDistanceNeedsItsOwnSensorSupport() {
        let motion = MotionAvailability(stepCounting: true, distance: false, authorization: .authorized)
        XCTAssertTrue(motion.canRead(.steps))
        XCTAssertFalse(motion.canRead(.distanceWalkingRunning))
    }

    func testPayloadReportsTheReadablePermission() {
        let payload = MotionAvailability(stepCounting: true, distance: true, authorization: .denied).payload
        XCTAssertEqual(payload["available"] as? Bool, true)
        XCTAssertEqual(payload["authorization"] as? String, "denied")
        let none = MotionAvailability(stepCounting: false, distance: false, authorization: .notDetermined).payload
        XCTAssertEqual(none["available"] as? Bool, false)
        XCTAssertEqual(none["authorization"] as? String, "notDetermined")
    }

    func testHistoryReadsOnlyRangesCoreMotionStillHoldsInFull() {
        let day: TimeInterval = 24 * 60 * 60
        let hour: TimeInterval = 60 * 60
        XCTAssertTrue(MotionHistory.canRead(from: now, now: now))
        XCTAssertTrue(MotionHistory.canRead(from: now.addingTimeInterval(-6.5 * day), now: now))
        // Seven days back the start of the day has left the history, so that
        // day would come back short; six hours of room keep a day that is
        // being trimmed from being read at all.
        XCTAssertFalse(MotionHistory.canRead(from: now.addingTimeInterval(-7 * day), now: now))
        XCTAssertTrue(MotionHistory.canRead(from: now.addingTimeInterval(-7 * day + 6 * hour), now: now))
        XCTAssertFalse(MotionHistory.canRead(from: now.addingTimeInterval(-7 * day + 6 * hour - 1), now: now))
        XCTAssertEqual(MotionHistory.earliestReadable(now: now), now.addingTimeInterval(-7 * day + 6 * hour))
    }

    func testZeroIsNoHistoryOnlyWhenNothingWasEverCounted() {
        XCTAssertTrue(MotionHistory.zeroMeansNoHistory(stepsSinceHistoryStart: 0))
        XCTAssertFalse(MotionHistory.zeroMeansNoHistory(stepsSinceHistoryStart: 1))
    }

    func testEnergyEstimateMatchesTheProbeReport() {
        let walk = MotionEnergyEstimate(distanceMeters: 2_000, activeSeconds: 1_500)
        XCTAssertEqual(walk.gait, .walking)
        XCTAssertEqual(walk.kilocalories, 70, accuracy: 0.001)
        let run = MotionEnergyEstimate(distanceMeters: 2_000, activeSeconds: 660)
        XCTAssertEqual(run.gait, .running)
        XCTAssertEqual(run.kilocalories, 140, accuracy: 0.001)
        let probe = MotionProbeMath.estimatedActiveKilocalories(distanceMeters: 2_000, activeSeconds: 660)
        XCTAssertEqual(probe.kilocalories, run.kilocalories)
        XCTAssertEqual(probe.gait, .running)
    }

    func testEnergyEstimateWithoutPaceAssumesWalking() {
        let estimate = MotionEnergyEstimate(distanceMeters: 1_000, activeSeconds: nil)
        XCTAssertEqual(estimate.gait, .walking)
        XCTAssertEqual(estimate.kilocalories, 35, accuracy: 0.001)
        XCTAssertEqual(MotionEnergyEstimate(distanceMeters: -5, activeSeconds: 10).kilocalories, 0)
    }

    func testEnergyEstimatePayloadIsLabelledAsAnEstimate() {
        let payload = MotionEnergyEstimate(distanceMeters: 1_000, activeSeconds: nil).payload
        XCTAssertEqual(payload["unit"] as? String, "kcal")
        XCTAssertEqual(payload["source"] as? String, "core_motion")
        XCTAssertEqual(payload["method"] as? String, "distance_pace")
        XCTAssertEqual(payload["assumedWeightKg"] as? Double, 70)
        XCTAssertEqual(payload["gait"] as? String, "walking")
    }
}
