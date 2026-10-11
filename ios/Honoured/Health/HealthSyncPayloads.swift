import Foundation

struct HealthSamplePayload: Codable, Equatable {
    let sampleUuid: String
    let metric: String
    let value: Double
    let unit: String
    let startedAt: String
    let endedAt: String
    let sourceName: String
}

struct HealthDeletionPayload: Codable, Equatable {
    let sampleUuid: String
    let metric: String
    let deletedAt: String
}

struct HealthDailyPayload: Codable, Equatable {
    let day: String
    let metric: String
    let total: Double
    let unit: String
}

struct PendingHealthBatch: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: String
    let createdAt: Date
    let samples: [HealthSamplePayload]
    let deletions: [HealthDeletionPayload]
    let daily: [HealthDailyPayload]
    var attempts: Int
}

extension PendingHealthBatch {
    /// The most samples one upload carries. A sample is about 230 bytes of
    /// JSON, so an upload stays near half a megabyte. The API gateway drops a
    /// request of roughly 16 MB or more without any response, and a month of
    /// dense watch data (heart rate from a Garmin, say) easily passes that, so
    /// an unsplit batch kept failing at the head of the queue and held back
    /// every later upload.
    static let maxSamplesPerUpload = 2_000

    var itemCount: Int { samples.count + deletions.count + daily.count }

    /// This batch as upload-sized batches, in order. Deletions and daily
    /// totals travel with the last part, so a sample added and deleted in the
    /// same pass is written before its deletion. The first part keeps this
    /// batch's id and attempts.
    func splitForUpload(maxSamples: Int = maxSamplesPerUpload) -> [PendingHealthBatch] {
        guard maxSamples > 0, samples.count > maxSamples else { return [self] }
        let starts = Array(stride(from: 0, to: samples.count, by: maxSamples))
        return starts.enumerated().map { index, start in
            let isFirst = index == 0
            let isLast = index == starts.count - 1
            return PendingHealthBatch(
                id: isFirst ? id : UUID(),
                userId: userId,
                createdAt: createdAt,
                samples: Array(samples[start..<min(start + maxSamples, samples.count)]),
                deletions: isLast ? deletions : [],
                daily: isLast ? daily : [],
                attempts: isFirst ? attempts : 0
            )
        }
    }

    /// Two halves of this batch, in order, to find the rows the server refuses
    /// while the rest still uploads. Nil for a batch of one item, which is the
    /// refused row itself.
    func halves() -> (PendingHealthBatch, PendingHealthBatch)? {
        guard itemCount > 1 else { return nil }
        let middle = itemCount / 2
        func part(_ range: Range<Int>, id: UUID, attempts: Int) -> PendingHealthBatch {
            let sampleEnd = samples.count
            let deletionEnd = sampleEnd + deletions.count
            func slice<T>(_ items: [T], from offset: Int) -> [T] {
                let lower = max(range.lowerBound - offset, 0)
                let upper = min(range.upperBound - offset, items.count)
                return lower < upper ? Array(items[lower..<upper]) : []
            }
            return PendingHealthBatch(
                id: id,
                userId: userId,
                createdAt: createdAt,
                samples: slice(samples, from: 0),
                deletions: slice(deletions, from: sampleEnd),
                daily: slice(daily, from: deletionEnd),
                attempts: attempts
            )
        }
        return (part(0..<middle, id: id, attempts: 0), part(middle..<itemCount, id: UUID(), attempts: 0))
    }
}

/// What an upload failure means for the batch that caused it.
enum HealthUploadFailure: Equatable {
    /// The session was refused: refresh it and try again.
    case invalidSession
    /// The request itself is refused and would be refused again.
    case refused
    /// Worth trying again later: a server error, a timeout, the network.
    case retryable

    static func classify(statusCode: Int) -> HealthUploadFailure {
        switch statusCode {
        case 401: return .invalidSession
        case 400, 404, 409, 413, 422: return .refused
        default: return .retryable
        }
    }
}
