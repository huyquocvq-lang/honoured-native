#if DEBUG
import Foundation

/// Sample content for previews and for the snapshot renders in the unit
/// tests: timer, Health, mixed, unknown, stale, completed, long names.
enum LiveActivityPreviewStates {
    static let now = Date(timeIntervalSince1970: 1_790_139_600) // 2026-09-23 12:00 +07:00

    static func health(
        _ id: String, slot: String = "primary", name: String, metric: String, value: Double?, target: Double,
        displayUnit: String? = nil, status: HonouredLiveActivityState.DataStatus = .fresh, measuredMinutesAgo: Double = 2
    ) -> HonouredLiveActivityState.HealthPart {
        HonouredLiveActivityState.HealthPart(
            activityId: id, slot: slot, name: name, metric: metric, value: value, target: target,
            displayUnit: displayUnit, reached: (value ?? 0) >= target, dataStatus: status,
            measuredAt: status == .waiting ? nil : now.addingTimeInterval(-measuredMinutesAgo * 60)
        )
    }

    static func state(
        _ name: String,
        status: HonouredLiveActivityState.Status = .active,
        timer: HonouredLiveActivityState.TimerPart? = nil,
        health: [HonouredLiveActivityState.HealthPart] = []
    ) -> HonouredLiveActivityState {
        HonouredLiveActivityState(
            contractName: name,
            status: status,
            displaySlot: health.first(where: { !$0.reached })?.activityId ?? health.first?.activityId,
            timer: timer,
            health: health,
            completedAt: status == .completed ? now : nil,
            updatedAt: now,
            validUntil: now.addingTimeInterval(12 * 3600)
        )
    }

    static func runningTimer(_ name: String, minutesLeft: Double = 25, total: Double = 30) -> HonouredLiveActivityState.TimerPart {
        HonouredLiveActivityState.TimerPart(
            activityId: "c-timer", name: name,
            startedAt: Date().addingTimeInterval(-(total - minutesLeft) * 60),
            endsAt: Date().addingTimeInterval(minutesLeft * 60),
            finished: false
        )
    }

    static let timerOnly = state("Meditation", timer: runningTimer("Meditation", minutesLeft: 9, total: 10))

    static let mixed = state(
        "Run 30",
        timer: runningTimer("Running"),
        health: [health("c-run:primary", name: "Exercise", metric: "exercise_minutes", value: 12, target: 30)]
    )

    static let twoSlots = state("Walk and burn", health: [
        health("c-two:primary", name: "Walking", metric: "steps", value: 6240, target: 8000),
        health("c-two:secondary", slot: "secondary", name: "Active energy", metric: "active_energy", value: 400, target: 400)
    ])

    static let distance = state("Evening ride", health: [
        health("c-ride:primary", name: "Cycling", metric: "distance_cycling", value: 12_400, target: 20_000, displayUnit: "km")
    ])

    static let unknown = state("Morning Walk", health: [
        health("c-walk:primary", name: "Walking", metric: "steps", value: nil, target: 8000, status: .waiting)
    ])

    static let noData = state("Swim", health: [
        health("c-swim:primary", name: "Swimming", metric: "distance_swimming", value: nil, target: 500, status: .noData)
    ])

    static let stale = state("Morning Walk", health: [
        health("c-walk:primary", name: "Walking", metric: "steps", value: 4200, target: 8000, status: .unavailable, measuredMinutesAgo: 95)
    ])

    static let completed = state("Walk and burn", status: .completed, health: [
        health("c-two:primary", name: "Walking", metric: "steps", value: 8420, target: 8000),
        health("c-two:secondary", slot: "secondary", name: "Active energy", metric: "active_energy", value: 410, target: 400)
    ])

    static let longNames = state(
        "Walk to the river and back before the sun comes up every single day",
        health: [
            health("c-long:primary", name: "Walking the long way round the park", metric: "steps", value: 12_345, target: 15_000),
            health("c-long:secondary", slot: "secondary", name: "Burning energy on the steepest hill", metric: "active_energy", value: 12, target: 650)
        ]
    )

    static let all: [(name: String, state: HonouredLiveActivityState)] = [
        ("timer-only", timerOnly), ("mixed", mixed), ("two-slots", twoSlots), ("distance", distance),
        ("unknown", unknown), ("no-data", noData), ("stale", stale), ("completed", completed), ("long-names", longNames)
    ]
}
#endif
