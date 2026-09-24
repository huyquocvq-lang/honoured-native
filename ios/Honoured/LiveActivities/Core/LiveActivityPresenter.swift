import Foundation

/// What one card should look like right now. Pure: the same record, timer and
/// clock always give the same content, which is what lets the engine skip an
/// ActivityKit update when nothing visible changed.
enum LiveActivityPresenter {
    /// Content for a live card.
    static func content(
        for record: TrackedRecord,
        timer: TimerRunSnapshot?,
        today: HealthDayInfo,
        now: Date,
        relevanceScore: Double,
        previous: HonouredLiveActivityState?
    ) -> DriverContent {
        let healthIsCurrent = record.key.healthDay == today.day
        let health = healthIsCurrent ? healthParts(for: record) : []
        let runningTimer = timer.flatMap { $0.runId == record.timerRunId ? $0 : nil }
        let shownTimer = runningTimer.map { Self.timerPart($0, finished: false) }
            ?? record.finishedTimer.map { Self.timerPart($0, finished: true) }

        var state = HonouredLiveActivityState(
            contractName: record.definition.contractName,
            status: .active,
            displaySlot: health.first(where: { !$0.reached })?.activityId ?? health.first?.activityId,
            timer: shownTimer,
            health: health,
            completedAt: nil,
            updatedAt: now,
            validUntil: record.definition.expiresAt
        )
        if let previous, sameDisplay(previous, state) {
            state.updatedAt = previous.updatedAt
        }

        var staleCandidates: [Date] = [record.definition.expiresAt]
        if !health.isEmpty {
            staleCandidates.append(today.end)
            // The stalest slot decides: a card is only as current as its oldest reading.
            let readings = health.map { $0.dataStatus == .waiting ? nil : $0.measuredAt }
            let oldest = readings.contains(where: { $0 == nil })
                ? record.trackedAt
                : readings.compactMap { $0 }.min() ?? record.trackedAt
            staleCandidates.append(oldest.addingTimeInterval(LiveActivityConfig.healthStaleInterval))
        }
        if let runningTimer {
            // The countdown stops at zero on its own; after that the card is
            // stale until the app runs again and reconciles the timer.
            staleCandidates.append(runningTimer.endsAt)
        }
        return DriverContent(state: state, staleDate: staleCandidates.min(), relevanceScore: relevanceScore)
    }

    /// The last content a finished card shows before it is dismissed.
    static func finalContent(for record: TrackedRecord, now: Date) -> DriverContent {
        let health = healthParts(for: record)
        let state = HonouredLiveActivityState(
            contractName: record.definition.contractName,
            status: record.terminal == .completed ? .completed : .ended,
            displaySlot: health.first?.activityId,
            timer: record.finishedTimer.map { timerPart($0, finished: true) },
            health: health,
            completedAt: record.completedAt,
            updatedAt: now,
            validUntil: record.definition.expiresAt
        )
        return DriverContent(state: state, staleDate: nil, relevanceScore: 0)
    }

    static func attributes(for record: TrackedRecord) -> DriverAttributes {
        DriverAttributes(
            contractId: record.key.contractId,
            healthDay: record.key.healthDay,
            occurrenceToken: record.occurrenceToken
        )
    }

    /// Encoded attributes plus state, the figure ActivityKit limits to 4 KB.
    static func encodedSize(attributes: DriverAttributes, state: HonouredLiveActivityState) -> Int {
        let encoder = JSONEncoder()
        let attributeBytes = (try? encoder.encode(attributes).count) ?? Int.max / 2
        let stateBytes = (try? encoder.encode(state).count) ?? Int.max / 2
        return attributeBytes + stateBytes
    }

    static func isReached(_ activity: TrackedActivity, in record: TrackedRecord) -> Bool {
        record.slots[activity.activityId]?.reachedAt != nil || record.slotCompletions.contains(activity.activityId)
    }

    private static func healthParts(for record: TrackedRecord) -> [HonouredLiveActivityState.HealthPart] {
        record.definition.healthActivities.compactMap { activity in
            guard let metric = activity.metric, let target = activity.target else { return nil }
            let progress = record.slots[activity.activityId]
            return HonouredLiveActivityState.HealthPart(
                activityId: activity.activityId,
                slot: activity.slot.rawValue,
                name: activity.name,
                metric: metric.rawValue,
                value: progress?.value,
                target: target,
                displayUnit: activity.displayUnit,
                reached: isReached(activity, in: record),
                dataStatus: progress?.dataStatus ?? .waiting,
                measuredAt: progress?.measuredAt
            )
        }
    }

    private static func timerPart(_ run: TimerRunSnapshot, finished: Bool) -> HonouredLiveActivityState.TimerPart {
        HonouredLiveActivityState.TimerPart(
            activityId: run.activityId,
            name: run.activityName,
            startedAt: run.startedAt,
            endsAt: run.endsAt,
            finished: finished
        )
    }

    private static func sameDisplay(_ lhs: HonouredLiveActivityState, _ rhs: HonouredLiveActivityState) -> Bool {
        var lhs = lhs
        lhs.updatedAt = rhs.updatedAt
        return lhs == rhs
    }
}
