import XCTest

final class HealthSyncPayloadTests: XCTestCase {
    private func sample(_ index: Int) -> HealthSamplePayload {
        HealthSamplePayload(
            sampleUuid: UUID().uuidString, metric: "heart_rate", value: Double(60 + index % 40), unit: "bpm",
            startedAt: "2026-10-01T00:00:00Z", endedAt: "2026-10-01T00:00:00Z", sourceName: "Connect"
        )
    }

    private func batch(samples: Int, deletions: Int = 0, daily: Int = 0, attempts: Int = 0) -> PendingHealthBatch {
        PendingHealthBatch(
            id: UUID(), userId: "user-a", createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            samples: (0..<samples).map(sample),
            deletions: (0..<deletions).map { _ in
                HealthDeletionPayload(sampleUuid: UUID().uuidString, metric: "steps", deletedAt: "2026-10-01T00:00:00Z")
            },
            daily: (0..<daily).map { HealthDailyPayload(day: "2026-10-\(10 + $0)", metric: "steps", total: 1000, unit: "count") },
            attempts: attempts
        )
    }

    func testABatchWithinTheLimitIsUploadedAsItIs() {
        let small = batch(samples: PendingHealthBatch.maxSamplesPerUpload, deletions: 3, daily: 2, attempts: 4)
        XCTAssertEqual(small.splitForUpload(), [small])
    }

    func testALargeBatchIsSplitInOrderWithDeletionsAndTotalsLast() {
        let large = batch(samples: 4_500, deletions: 3, daily: 31, attempts: 7)
        let parts = large.splitForUpload()
        XCTAssertEqual(parts.map(\.samples.count), [2_000, 2_000, 500])
        XCTAssertEqual(parts.flatMap(\.samples), large.samples)
        XCTAssertEqual(parts.map(\.deletions.count), [0, 0, 3])
        XCTAssertEqual(parts.map(\.daily.count), [0, 0, 31])
        XCTAssertEqual(parts.first?.id, large.id)
        XCTAssertEqual(parts.map(\.attempts), [7, 0, 0])
        XCTAssertEqual(Set(parts.map(\.id)).count, 3)
        XCTAssertTrue(parts.allSatisfy { $0.userId == large.userId && $0.createdAt == large.createdAt })
    }

    /// The API gateway drops a request of about 16 MB without answering; an
    /// upload stays far below that.
    func testAnUploadStaysFarBelowTheGatewayLimit() throws {
        let part = try XCTUnwrap(batch(samples: 70_000).splitForUpload().first)
        let body = try JSONEncoder().encode(part.samples)
        XCTAssertLessThan(body.count, 1_000_000)
    }

    func testHalvesKeepEveryRowInOrder() throws {
        let mixed = batch(samples: 3, deletions: 2, daily: 2, attempts: 5)
        let (first, second) = try XCTUnwrap(mixed.halves())
        XCTAssertEqual(first.itemCount + second.itemCount, mixed.itemCount)
        XCTAssertEqual(first.samples + second.samples, mixed.samples)
        XCTAssertEqual(first.deletions + second.deletions, mixed.deletions)
        XCTAssertEqual(first.daily + second.daily, mixed.daily)
        XCTAssertEqual(first.itemCount, 3)
        XCTAssertEqual(first.id, mixed.id)
        XCTAssertNotEqual(second.id, mixed.id)
        XCTAssertEqual([first.attempts, second.attempts], [0, 0])
    }

    func testHalvingNarrowsARefusedBatchToSingleRows() {
        var pending = [batch(samples: 5, daily: 1)]
        var singles = 0
        while let next = pending.popLast() {
            if let (a, b) = next.halves() { pending += [a, b] } else { singles += 1 }
        }
        XCTAssertEqual(singles, 6)
        XCTAssertNil(batch(samples: 0, daily: 1).halves())
    }

    func testUploadFailuresAreClassified() {
        XCTAssertEqual(HealthUploadFailure.classify(statusCode: 401), .invalidSession)
        for status in [400, 404, 409, 413, 422] {
            XCTAssertEqual(HealthUploadFailure.classify(statusCode: status), .refused, "\(status)")
        }
        for status in [403, 408, 429, 500, 502, 503, 504] {
            XCTAssertEqual(HealthUploadFailure.classify(statusCode: status), .retryable, "\(status)")
        }
    }
}
