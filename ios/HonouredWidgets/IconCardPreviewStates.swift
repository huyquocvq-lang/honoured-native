#if DEBUG
import Foundation

/// Sample Icon cards for previews and the render tests: morning, evening,
/// both results, a midnight cut-off and long text.
enum IconCardPreviewStates {
    static let now = Date(timeIntervalSince1970: 1_790_139_600) // 2026-09-23 12:00 +07:00

    /// Tuesday 29 September 2026, 23:59 in the device's zone.
    static var tuesdayCutoff: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 29, hour: 23, minute: 59))!
    }

    static var midnightCutoff: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 0, minute: 0))!
    }

    static var facts: IconCardFacts {
        IconCardFacts(
            contractId: "preview-icon", iconDay: "2026-09-29", weekday: "Tue", sessionNumber: 5, totalSessions: 17,
            targetValue: "10,000", targetUnit: "steps", activityName: "Walking",
            because: "Spring has begun, all life has sprung.", deadline: tuesdayCutoff
        )
    }

    static var midnightFacts: IconCardFacts {
        IconCardFacts(
            contractId: "preview-icon", iconDay: "2026-09-29", weekday: "Tue", sessionNumber: 1, totalSessions: 92,
            targetValue: "33", targetUnit: "min", activityName: "Running",
            because: "Spring has started, it's warrior season.", deadline: midnightCutoff
        )
    }

    static var longFacts: IconCardFacts {
        IconCardFacts(
            contractId: "preview-icon", iconDay: "2026-09-29", weekday: "Wednesday", sessionNumber: 128, totalSessions: 261,
            targetValue: "15,000,000", targetUnit: "kilometres", activityName: "Very long custom activity name for testing truncation",
            because: "Because the person who signed this wrote a very long reason that cannot possibly fit on a Lock Screen card in one line, or even in two lines",
            deadline: tuesdayCutoff
        )
    }

    static let morning = IconLiveActivityState.morning(sessionNumber: 5, at: now)
    static let morningSecond = IconLiveActivityState.morning(sessionNumber: 6, at: now)
    static let evening = IconLiveActivityState.evening(at: now)
    static let honoured = IconLiveActivityState.result(.honoured, at: now)
    static let broken = IconLiveActivityState.result(.broken, at: now)

    static var all: [(String, IconCardFacts, IconLiveActivityState)] {
        [
            ("morning", facts, morning),
            ("morning-next-affirmation", facts, morningSecond),
            ("evening", facts, evening),
            ("honoured", facts, honoured),
            ("broken", facts, broken),
            ("midnight-cutoff", midnightFacts, evening),
            ("long-text", longFacts, morning),
        ]
    }
}
#endif
