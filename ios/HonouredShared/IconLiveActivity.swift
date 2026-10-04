import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

// The Icon card (V1.2 M2-08): one Live Activity per Icon day, shown at the
// morning and evening reminder times and closing on the day's result.
// Compiled into the app and the widget extension, so it stays free of app
// services. Every field is a plain value: the app builds a card for a local
// start, and the push job (M2-07, public.icon_push_plan in the database)
// builds the same JSON on the server; dates are Unix seconds in both.

/// What stays the same for one Icon day.
struct IconCardFacts: Codable, Hashable {
    /// The web app's contract id (`contracts.client_id`).
    var contractId: String
    /// The Icon day, `yyyy-MM-dd`.
    var iconDay: String
    /// Short weekday, upper case: `TUE`.
    var weekday: String
    var sessionNumber: Int
    var totalSessions: Int
    /// The target as the person wrote it, split for layout: `10,000` and `STEPS`.
    var targetValue: String
    var targetUnit: String
    /// The activity name: `Walking`.
    var activityName: String
    /// The contract's "Because…" line.
    var because: String
    /// The day's cut-off; shown in the device's own time zone.
    var deadline: Date

    /// ActivityKit caps attributes plus state at 4 KB, the APNs Live Activity
    /// payload too, so free text is cut before it gets here.
    static let maxActivityName = 40
    static let maxBecause = 120
    static let maxTarget = 16

    init(
        contractId: String, iconDay: String, weekday: String, sessionNumber: Int, totalSessions: Int,
        targetValue: String, targetUnit: String, activityName: String, because: String, deadline: Date
    ) {
        self.contractId = contractId
        self.iconDay = iconDay
        self.weekday = String(weekday.prefix(3)).uppercased()
        self.sessionNumber = max(1, sessionNumber)
        self.totalSessions = max(self.sessionNumber, totalSessions)
        self.targetValue = Self.cut(targetValue, to: Self.maxTarget)
        self.targetUnit = Self.cut(targetUnit, to: Self.maxTarget).uppercased()
        self.activityName = Self.cut(activityName, to: Self.maxActivityName)
        self.because = Self.cut(because, to: Self.maxBecause)
        self.deadline = deadline
    }

    /// `TUE · 5 OF 17`
    var sessionLabel: String { "\(weekday) · \(sessionNumber) OF \(totalSessions)" }

    // Dates travel as Unix seconds: the push-to-start job writes this JSON and
    // ActivityKit decodes it with its own decoder, so nothing may depend on a
    // date decoding strategy. Decoding goes through `init` to apply the limits.
    private enum CodingKeys: String, CodingKey {
        case contractId, iconDay, weekday, sessionNumber, totalSessions
        case targetValue, targetUnit, activityName, because, deadline
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            contractId: try c.decode(String.self, forKey: .contractId),
            iconDay: try c.decode(String.self, forKey: .iconDay),
            weekday: try c.decode(String.self, forKey: .weekday),
            sessionNumber: try c.decode(Int.self, forKey: .sessionNumber),
            totalSessions: try c.decode(Int.self, forKey: .totalSessions),
            targetValue: try c.decode(String.self, forKey: .targetValue),
            targetUnit: try c.decode(String.self, forKey: .targetUnit),
            activityName: try c.decode(String.self, forKey: .activityName),
            because: try c.decode(String.self, forKey: .because),
            deadline: Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .deadline))
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(contractId, forKey: .contractId)
        try c.encode(iconDay, forKey: .iconDay)
        try c.encode(weekday, forKey: .weekday)
        try c.encode(sessionNumber, forKey: .sessionNumber)
        try c.encode(totalSessions, forKey: .totalSessions)
        try c.encode(targetValue, forKey: .targetValue)
        try c.encode(targetUnit, forKey: .targetUnit)
        try c.encode(activityName, forKey: .activityName)
        try c.encode(because, forKey: .because)
        try c.encode(deadline.timeIntervalSince1970, forKey: .deadline)
    }

    private static func cut(_ text: String, to limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// What changes during the day.
struct IconLiveActivityState: Codable, Hashable {
    enum Phase: String, Codable, Hashable {
        /// From the morning reminder: the day's affirmation.
        case morning
        /// From the evening reminder until the cut-off: "Finish what you signed."
        case evening
        /// The day is stamped; shown briefly before the card closes.
        case result
    }

    enum Result: String, Codable, Hashable {
        case honoured
        case broken
    }

    var phase: Phase
    /// The line of the moment: the affirmation, the evening line or the result.
    var line: String
    var result: Result?
    var updatedAt: Date

    init(phase: Phase, line: String, result: Result?, updatedAt: Date) {
        self.phase = phase
        self.line = line
        self.result = result
        self.updatedAt = updatedAt
    }

    // Unix seconds, like `IconCardFacts`; a push may omit `result`.
    private enum CodingKeys: String, CodingKey { case phase, line, result, updatedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = try c.decode(Phase.self, forKey: .phase)
        line = try c.decode(String.self, forKey: .line)
        result = try c.decodeIfPresent(Result.self, forKey: .result)
        updatedAt = Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .updatedAt))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(phase, forKey: .phase)
        try c.encode(line, forKey: .line)
        try c.encodeIfPresent(result, forKey: .result)
        try c.encode(updatedAt.timeIntervalSince1970, forKey: .updatedAt)
    }

    /// A morning card is stale from the evening reminder on (its `staleDate`),
    /// so the widget can switch to the evening line while the app is not running.
    func displayLine(isStale: Bool) -> String {
        phase == .morning && isStale ? IconCopy.eveningLine : line
    }

    static func morning(sessionNumber: Int, at date: Date) -> Self {
        Self(phase: .morning, line: IconCopy.affirmation(sessionNumber: sessionNumber), result: nil, updatedAt: date)
    }

    static func evening(at date: Date) -> Self {
        Self(phase: .evening, line: IconCopy.eveningLine, result: nil, updatedAt: date)
    }

    static func result(_ result: Result, at date: Date) -> Self {
        Self(phase: .result, line: IconCopy.resultLine(result), result: result, updatedAt: date)
    }
}

#if canImport(ActivityKit)
@available(iOS 16.1, *)
struct IconActivityAttributes: ActivityAttributes {
    typealias ContentState = IconLiveActivityState

    let facts: IconCardFacts
}
#endif

/// The card's fixed words.
enum IconCopy {
    static let title = "Icon"
    /// One affirmation per Icon day, in turn. The first two come from the
    /// scope; the rest are drafts awaiting the client's approval (O-12). Each
    /// fits one Lock Screen line beside the signature and the cut-off.
    static let affirmations = [
        "You've got this.",
        "You're closer than you think.",
        "Today is part of the promise.",
        "Keep your word to yourself.",
        "Small steps, kept promises.",
        "Become what you signed.",
        "Prove it again today.",
    ]
    static let eveningLine = "Finish what you signed."

    static func affirmation(sessionNumber: Int) -> String {
        affirmations[(max(sessionNumber, 1) - 1) % affirmations.count]
    }

    static func resultLine(_ result: IconLiveActivityState.Result) -> String {
        switch result {
        case .honoured: return "HONOURED"
        case .broken: return "BROKEN"
        }
    }

    /// `Due 11:59 pm`, or `Due midnight` for a cut-off at 00:00.
    static func deadlineLabel(_ deadline: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: deadline)
        if parts.hour == 0 && parts.minute == 0 { return "Due midnight" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "h:mm a"
        return "Due " + formatter.string(from: deadline).lowercased()
    }
}
