import Foundation

/// A quiet local reminder shortly before a word Icon's cut-off, asking the
/// writer to open Honoured so the day's count can be read in time. The web
/// app owns the schedule and always sends the whole list; native only checks
/// it and replaces whatever it scheduled before.
struct WordReminder: Equatable {
    static let identifierPrefix = "word-reminder."
    static let maximumCount = 32

    let contractId: String
    let day: String
    let fireAt: Date
    let subtitle: String?

    /// Stable per Icon day, so sending the same list again changes nothing.
    var identifier: String { Self.identifierPrefix + contractId + "." + day }

    /// The listed reminders, soonest first, or nil when the list is malformed.
    /// The list names every Icon day still waiting for its count, including
    /// one whose reminder time has passed, so that reminder stays on screen;
    /// only future ones are scheduled. A repeated Icon day keeps its first entry.
    static func parseList(_ value: Any?) -> [WordReminder]? {
        guard let items = value as? [Any], items.count <= maximumCount else { return nil }
        var reminders: [WordReminder] = []
        var seen = Set<String>()
        for item in items {
            guard let entry = item as? [String: Any],
                  let contractId = entry["contractId"] as? String,
                  !contractId.isEmpty, contractId.count <= 256,
                  let day = entry["day"] as? String, isDay(day),
                  let at = entry["at"] as? String, let fireAt = date(at) else { return nil }
            var subtitle: String?
            if let raw = entry["subtitle"], !(raw is NSNull) {
                guard let text = raw as? String, text.count <= 120 else { return nil }
                subtitle = text.isEmpty ? nil : text
            }
            let reminder = WordReminder(contractId: contractId, day: day, fireAt: fireAt, subtitle: subtitle)
            guard seen.insert(reminder.identifier).inserted else { continue }
            reminders.append(reminder)
        }
        return reminders.sorted { $0.fireAt < $1.fireAt }
    }

    private static func isDay(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
