import Foundation
import HealthKit

enum HealthCollectionDeferral: Sendable {
    case noSession
    case healthDataUnavailable
    case protectedDataUnavailable
}

enum HealthCollectionOutcome: Sendable {
    case queued
    case noChanges
    case deferred(HealthCollectionDeferral)
    case failed

    var completedLocalProcessing: Bool {
        switch self {
        case .queued, .noChanges: return true
        case .deferred, .failed: return false
        }
    }
}

actor HealthSyncCoordinator {
    static let shared = HealthSyncCoordinator()

    private var isCollecting = false
    private var needsAnotherCollectionPass = false
    private var collectionWaiters: [CheckedContinuation<HealthCollectionOutcome, Never>] = []
    private var isDraining = false

    private let iso8601 = ISO8601DateFormatter()
    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// Foreground/reconnect entry point. Background HealthKit callbacks call
    /// `collectAndEnqueue()` directly so their completion handlers never wait for
    /// network retries.
    func syncNow() async {
        _ = await collectAndEnqueue()
        await drainQueue()
    }

    /// Coalesces concurrent triggers without dropping a HealthKit change. A trigger
    /// received while a pass is running requests one more full anchored-read pass;
    /// all callers resume after the final pass has durably queued its results.
    func collectAndEnqueue() async -> HealthCollectionOutcome {
        if isCollecting {
            needsAnotherCollectionPass = true
            return await withCheckedContinuation { continuation in
                collectionWaiters.append(continuation)
            }
        }

        isCollecting = true
        var outcome: HealthCollectionOutcome = .failed
        repeat {
            needsAnotherCollectionPass = false
            outcome = await performCollection()
        } while needsAnotherCollectionPass
        isCollecting = false

        if outcome.completedLocalProcessing {
            HealthBackgroundPendingState.clear()
        }

        let waiters = collectionWaiters
        collectionWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: outcome)
        }
        return outcome
    }

    private func performCollection() async -> HealthCollectionOutcome {
        guard let session = await AuthSessionStore.shared.load() else {
            return .deferred(.noSession)
        }
        guard HealthKitService.shared.isAvailable else {
            return .deferred(.healthDataUnavailable)
        }

        var samples: [HealthSamplePayload] = []
        var deletions: [HealthDeletionPayload] = []
        var daily: [HealthDailyPayload] = []
        var reads: [HealthReadResult] = []
        let now = Date()
        let dayStart = await startOfHealthDay(containing: now)

        do {
            for metric in HealthMetric.allCases {
                let result = try await HealthKitService.shared.readNewSamples(for: metric)
                reads.append(result)
                samples += result.added.map {
                    HealthSamplePayload(
                        sampleUuid: $0.uuid.uuidString,
                        metric: metric.rawValue,
                        value: $0.value,
                        unit: metric.unitName,
                        startedAt: iso8601.string(from: $0.startDate),
                        endedAt: iso8601.string(from: $0.endDate),
                        sourceName: $0.sourceName
                    )
                }
                deletions += result.deletedUUIDs.map {
                    HealthDeletionPayload(
                        sampleUuid: $0.uuidString,
                        metric: metric.rawValue,
                        deletedAt: iso8601.string(from: now)
                    )
                }

                // Recompute today plus any historical day receiving a late sample.
                // This populates the initial history and finalizes past days without
                // deriving totals from overlapping iPhone/Watch samples on the server.
                var affectedDays: Set<Date> = [dayStart]
                for sample in result.added {
                    let attributionDate = metric == .sleep
                        ? sample.endDate.addingTimeInterval(-0.001)
                        : sample.startDate
                    affectedDays.insert(await startOfHealthDay(containing: attributionDate))
                }
                for affectedDay in affectedDays.sorted() {
                    let calendar = Calendar.current
                    let dayEnd = calendar.date(byAdding: .day, value: 1, to: affectedDay) ?? now
                    let rangeEnd = min(dayEnd, now)
                    if let total = await HealthKitService.shared.total(
                        for: metric,
                        from: affectedDay,
                        to: rangeEnd
                    ) {
                        daily.append(HealthDailyPayload(
                            day: dayFormatter.string(from: affectedDay),
                            metric: metric.rawValue,
                            total: total,
                            unit: metric.unitName
                        ))
                    }
                }
            }

            let batch = PendingHealthBatch(
                id: UUID(), userId: session.userId, createdAt: now, samples: samples,
                deletions: deletions, daily: daily, attempts: 0
            )
            guard !samples.isEmpty || !deletions.isEmpty || !daily.isEmpty else {
                return .noChanges
            }

            try await OfflineHealthQueue.shared.append(batch)
            for result in reads {
                await HealthKitService.shared.commitAnchor(result.newAnchor, for: result.metric)
            }
            return .queued
        } catch {
            let nsError = error as NSError
            if nsError.domain == HKErrorDomain,
               nsError.code == HKError.Code.errorDatabaseInaccessible.rawValue {
                return .deferred(.protectedDataUnavailable)
            }
            // A failed HealthKit read or queue write must not advance any anchor.
            return .failed
        }
    }

    /// Attempts at most one queued batch and never sleeps. This is safe to start
    /// after acknowledging a HealthKit background delivery.
    func drainOnce() async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }
        _ = await attemptFirstQueuedBatch()
    }

    /// Foreground retry loop. HealthKit observer callbacks must not await this.
    func drainQueue() async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }

        while true {
            switch await attemptFirstQueuedBatch() {
            case .uploaded:
                continue
            case .retryable(let attempts):
                let delay = min(pow(2.0, Double(attempts)), 300)
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch {
                    return
                }
            case .empty, .terminal:
                return
            }
        }
    }

    private enum DrainAttempt {
        case empty
        case uploaded
        case retryable(attempts: Int)
        case terminal
    }

    private func attemptFirstQueuedBatch() async -> DrainAttempt {
        guard let batch = await OfflineHealthQueue.shared.first() else { return .empty }

        do {
            guard var session = try await AuthSessionStore.shared.refreshedSessionIfNeeded() else {
                return .terminal
            }
            guard session.userId == batch.userId else {
                postInvalidSession(reason: "account_mismatch")
                return .terminal
            }

            var refreshedSession: NativeAuthSession?
            do {
                try await SupabaseHealthClient.shared.upload(batch, session: session)
            } catch SupabaseHealthClient.SyncError.invalidSession {
                do {
                    guard let refreshed = try await AuthSessionStore.shared.refreshedSessionIfNeeded(force: true) else {
                        return .terminal
                    }
                    guard refreshed.userId == batch.userId else {
                        postInvalidSession(reason: "account_mismatch")
                        return .terminal
                    }
                    session = refreshed
                    try await SupabaseHealthClient.shared.upload(batch, session: session)
                    refreshedSession = refreshed
                } catch AuthSessionStore.SessionRefreshError.invalidSession {
                    postInvalidSession(reason: "refresh_rejected")
                    return .terminal
                } catch SupabaseHealthClient.SyncError.invalidSession {
                    postInvalidSession(reason: "refreshed_session_rejected")
                    return .terminal
                } catch {
                    return await retryableAttempt(for: batch)
                }
            }

            do {
                try await OfflineHealthQueue.shared.removeFirst(id: batch.id)
            } catch {
                return await retryableAttempt(for: batch)
            }

            if let refreshedSession {
                NativeBridgeEvents.post(type: "AUTH_SESSION_UPDATED", payload: [
                    "userId": refreshedSession.userId,
                    "accessToken": refreshedSession.accessToken,
                    "refreshToken": refreshedSession.refreshToken,
                    "expiresAt": refreshedSession.expiresAt
                ])
            }
            postHealthDataUpdated(for: batch)
            return .uploaded
        } catch AuthSessionStore.SessionRefreshError.invalidSession {
            postInvalidSession(reason: "refresh_rejected")
            return .terminal
        } catch {
            return await retryableAttempt(for: batch)
        }
    }

    private func retryableAttempt(for batch: PendingHealthBatch) async -> DrainAttempt {
        let attempts = (try? await OfflineHealthQueue.shared.recordFailure(id: batch.id)) ?? 0
        return .retryable(attempts: attempts)
    }

    private func postInvalidSession(reason: String) {
        NativeBridgeEvents.post(type: "AUTH_SESSION_INVALID", payload: ["reason": reason])
    }

    private func postHealthDataUpdated(for batch: PendingHealthBatch) {
        NativeBridgeEvents.post(type: "HEALTH_DATA_UPDATED", payload: [
            "syncedAt": iso8601.string(from: Date()),
            "metrics": Array(Set(batch.daily.map(\.metric))).sorted()
        ])
    }

    func clear() async throws {
        try await OfflineHealthQueue.shared.clear()
        HealthBackgroundPendingState.clear()
    }

    private func startOfHealthDay(containing date: Date) async -> Date {
        let hour = await HealthSyncSettings.shared.dayResetHour()
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: date)
        let todayBoundary = calendar.date(byAdding: .hour, value: hour, to: midnight) ?? midnight
        if date >= todayBoundary { return todayBoundary }
        return calendar.date(byAdding: .day, value: -1, to: todayBoundary) ?? todayBoundary
    }
}
