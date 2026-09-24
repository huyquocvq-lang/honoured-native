import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

// Compiled into both the app and the HonouredWidgets extension. Keep it free of
// app services: the widget renders only what ActivityKit hands it and never
// touches HealthKit, tokens or the backend.

// MARK: - Content state

/// Everything a contract's Live Activity displays. Plain `Codable` so the app
/// can build and compare it without ActivityKit; `HonouredActivityAttributes`
/// adopts it as its `ContentState`. Display metadata only — never tokens or raw
/// Health samples. ActivityKit caps attributes plus state at 4 KB, so names are
/// truncated before they get here.
struct HonouredLiveActivityState: Codable, Hashable {
    enum Status: String, Codable, Hashable {
        /// Counting down and/or showing Health progress.
        case active
        /// Honoured under the contract's completion policy or confirmed by the web app.
        case completed
        /// The occurrence stopped being tracked (expired, day closed, stopped).
        case ended
    }

    enum DataStatus: String, Codable, Hashable {
        /// The last read returned a value.
        case fresh
        /// The last read succeeded and Health has nothing recorded in the window.
        case noData
        /// Nothing has been read successfully yet.
        case waiting
        /// The last read failed, usually because the device is locked; `value`
        /// is the last good reading and `measuredAt` says when it was taken.
        case unavailable
    }

    struct TimerPart: Codable, Hashable {
        var activityId: String
        var name: String
        var startedAt: Date
        var endsAt: Date
        /// Native processed the natural finish. Until then a countdown that
        /// reached zero only means the app has not run since.
        var finished: Bool
    }

    struct HealthPart: Codable, Hashable {
        var activityId: String
        /// `primary` or `secondary`.
        var slot: String
        var name: String
        /// Bridge metric identifier (`steps`, `distance_cycling`, …).
        var metric: String
        /// Canonical unit (count, meters, kcal, minutes, bpm). Nil is "unknown",
        /// never zero.
        var value: Double?
        var target: Double
        /// `km` or `mi` for distance metrics when the web app chose one.
        var displayUnit: String?
        var reached: Bool
        var dataStatus: DataStatus
        var measuredAt: Date?
    }

    var contractName: String
    var status: Status
    /// `activityId` of the Health slot compact presentations lead with.
    var displaySlot: String?
    var timer: TimerPart?
    var health: [HealthPart]
    var completedAt: Date?
    var updatedAt: Date
    var validUntil: Date

    var displayedHealth: HealthPart? {
        health.first { $0.activityId == displaySlot } ?? health.first
    }

    var reachedCount: Int { health.filter(\.reached).count }
}

#if canImport(ActivityKit)
/// Stable identity of one tracked contract occurrence. Everything that can
/// change lives in the content state so it updates in place.
@available(iOS 16.1, *)
struct HonouredActivityAttributes: ActivityAttributes {
    typealias ContentState = HonouredLiveActivityState

    let contractId: String
    let healthDay: String
    /// Random per occurrence. Ties the card, and its deep link, to the native
    /// record of the account that created it.
    let occurrenceToken: String
}
#endif

// MARK: - Identifiers

enum HonouredIdentifiers {
    static let maxIdentifierLength = 128

    /// Contract and activity IDs are opaque strings from the web app. They
    /// only need to be bounded and printable; nothing is inferred from them.
    static func isValidIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= maxIdentifierLength, value.utf8.count <= maxIdentifierLength * 4,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    /// `yyyy-MM-dd` naming a real calendar date.
    static func isValidHealthDay(_ value: String) -> Bool {
        guard value.count == 10, value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else {
            return false
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value) else { return false }
        return formatter.string(from: date) == value
    }

    static func isValidOccurrenceToken(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }
}

// MARK: - Deep link

/// `honoured://contract/<percent-encoded id>?day=<health day>&occurrence=<token>`.
/// Opening it only navigates: the app maps the token to a record of the account
/// that is signed in now and ignores anything it does not recognise. No auth or
/// session data ever goes into the URL.
enum ContractDeepLink {
    static let scheme = "honoured"
    static let host = "contract"

    struct Target: Hashable {
        let contractId: String
        let healthDay: String
        let occurrenceToken: String
    }

    private static let segmentAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%;")
        return allowed
    }()

    static func url(for target: Target) -> URL? {
        guard HonouredIdentifiers.isValidIdentifier(target.contractId),
              HonouredIdentifiers.isValidHealthDay(target.healthDay),
              HonouredIdentifiers.isValidOccurrenceToken(target.occurrenceToken),
              let segment = target.contractId.addingPercentEncoding(withAllowedCharacters: segmentAllowed) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.percentEncodedPath = "/" + segment
        components.queryItems = [
            URLQueryItem(name: "day", value: target.healthDay),
            URLQueryItem(name: "occurrence", value: target.occurrenceToken)
        ]
        return components.url
    }

    static func parse(_ url: URL) -> Target? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme,
              components.host?.lowercased() == host,
              components.user == nil, components.password == nil, components.port == nil,
              components.fragment == nil else { return nil }

        let path = components.percentEncodedPath
        guard path.hasPrefix("/") else { return nil }
        let segment = String(path.dropFirst())
        guard !segment.isEmpty, !segment.contains("/"),
              let contractId = segment.removingPercentEncoding,
              HonouredIdentifiers.isValidIdentifier(contractId) else { return nil }

        let items = components.queryItems ?? []
        guard items.count == 2,
              let day = single("day", in: items), HonouredIdentifiers.isValidHealthDay(day),
              let token = single("occurrence", in: items), HonouredIdentifiers.isValidOccurrenceToken(token) else {
            return nil
        }
        return Target(contractId: contractId, healthDay: day, occurrenceToken: token)
    }

    private static func single(_ name: String, in items: [URLQueryItem]) -> String? {
        let matches = items.filter { $0.name == name }
        guard matches.count == 1 else { return nil }
        return matches[0].value
    }
}

// MARK: - Formatting

/// Turns canonical values into short display text. Units are converted for
/// display only (meters → km/mi); the stored values stay canonical.
enum HonouredLiveActivityFormat {
    static func progress(value: Double?, target: Double) -> Double? {
        guard let value, target > 0, value.isFinite else { return nil }
        return min(max(value / target, 0), 1)
    }

    static func symbol(forMetric metric: String) -> String {
        switch metric {
        case "steps": return "figure.walk"
        case "distance_walking_running": return "figure.run"
        case "distance_cycling": return "bicycle"
        case "distance_swimming": return "figure.pool.swim"
        case "active_energy": return "flame.fill"
        case "basal_energy": return "flame"
        case "heart_rate": return "heart.fill"
        case "exercise_minutes": return "figure.mixed.cardio"
        case "sleep": return "bed.double.fill"
        default: return "circle.dashed"
        }
    }

    static let timerSymbol = "hourglass"
    static let completedSymbol = "checkmark.seal.fill"

    /// "6,240", "3.2 km", "320 kcal", "18 min", "7 h 05 min", "72 bpm".
    static func valueText(_ value: Double, metric: String, displayUnit: String?, locale: Locale = .current) -> String {
        switch metric {
        case "steps":
            return number(value, decimals: 0, locale: locale)
        case "distance_walking_running", "distance_cycling", "distance_swimming":
            let unit = distanceUnit(displayUnit, locale: locale)
            return "\(number(value / unit.meters, decimals: 1, locale: locale)) \(unit.label)"
        case "active_energy", "basal_energy":
            return "\(number(value, decimals: 0, locale: locale)) kcal"
        case "heart_rate":
            return "\(number(value, decimals: 0, locale: locale)) bpm"
        case "sleep":
            let minutes = Int(value.rounded())
            guard minutes >= 60 else { return "\(minutes) min" }
            return String(format: "%d h %02d min", minutes / 60, minutes % 60)
        default:
            return "\(number(value, decimals: 0, locale: locale)) min"
        }
    }

    /// "8,000 steps", "5 km", "400 kcal", "30 min", "8 h", "150 bpm".
    static func targetText(_ target: Double, metric: String, displayUnit: String?, locale: Locale = .current) -> String {
        switch metric {
        case "steps":
            return "\(number(target, decimals: 0, locale: locale)) steps"
        case "sleep":
            let minutes = Int(target.rounded())
            if minutes % 60 == 0 { return "\(minutes / 60) h" }
            return valueText(target, metric: metric, displayUnit: displayUnit, locale: locale)
        default:
            return valueText(target, metric: metric, displayUnit: displayUnit, locale: locale)
        }
    }

    /// Fits a Dynamic Island compact slot: "6.2k", "3.2km", "320", "18m", "7h05".
    static func shortValueText(_ value: Double, metric: String, displayUnit: String?, locale: Locale = .current) -> String {
        switch metric {
        case "steps":
            if value >= 10_000 { return "\(Int((value / 1000).rounded(.down)))k" }
            if value >= 1_000 { return "\(number((value / 100).rounded(.down) / 10, decimals: 1, locale: locale))k" }
            return number(value, decimals: 0, locale: locale)
        case "distance_walking_running", "distance_cycling", "distance_swimming":
            let unit = distanceUnit(displayUnit, locale: locale)
            return "\(number(value / unit.meters, decimals: 1, locale: locale))\(unit.label)"
        case "sleep":
            let minutes = Int(value.rounded())
            return minutes >= 60 ? String(format: "%dh%02d", minutes / 60, minutes % 60) : "\(minutes)m"
        case "exercise_minutes":
            return "\(Int(value.rounded()))m"
        default:
            return number(value, decimals: 0, locale: locale)
        }
    }

    private static func distanceUnit(_ displayUnit: String?, locale: Locale) -> (meters: Double, label: String) {
        switch displayUnit {
        case "mi": return (1609.344, "mi")
        case "km": return (1000, "km")
        default:
            return usesMiles(locale) ? (1609.344, "mi") : (1000, "km")
        }
    }

    private static func usesMiles(_ locale: Locale) -> Bool {
        locale.measurementSystem == .us || locale.measurementSystem == .uk
    }

    private static func number(_ value: Double, decimals: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = decimals
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: value)) ?? String(Int(value.rounded()))
    }
}
