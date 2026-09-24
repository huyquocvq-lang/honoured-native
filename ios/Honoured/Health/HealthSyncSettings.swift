import Foundation

struct HealthGoal: Codable {
    let activityId: String
    let activityName: String
    let metric: HealthMetric
    let target: Double
    let unit: String
}

actor HealthSyncSettings {
    static let shared = HealthSyncSettings()

    private let defaults = UserDefaults.standard
    private let goalsKey = "healthkit.goals"
    private let dayResetHourKey = "healthkit.day-reset-hour"

    func replaceGoals(_ goals: [HealthGoal]) throws {
        defaults.set(try JSONEncoder().encode(goals), forKey: goalsKey)
    }

    func currentGoals() -> [HealthGoal] {
        guard let data = defaults.data(forKey: goalsKey) else { return [] }
        return (try? JSONDecoder().decode([HealthGoal].self, from: data)) ?? []
    }

    func setDayResetHour(_ hour: Int) {
        defaults.set(hour, forKey: dayResetHourKey)
    }

    func dayResetHour() -> Int {
        defaults.object(forKey: dayResetHourKey) as? Int ?? 0
    }

    /// Start of the health day containing `date`: local midnight shifted by the
    /// user's reset hour. Shared by daily totals, goal detection and Live
    /// Activities (through `HealthDayMath`) so `health_daily.day`, "reached
    /// today" and a card's day always mean the same window.
    func healthDayStart(containing date: Date) -> Date {
        HealthDayMath.dayStart(containing: date, resetHour: dayResetHour(), calendar: .current)
    }

    /// `yyyy-MM-dd` of a health-day start, the value stored in `health_daily.day`.
    /// Uses the current time zone at every call, so a time-zone change is not
    /// masked by a formatter created before it.
    nonisolated static func dayString(_ dayStart: Date) -> String {
        HealthDayMath.dayString(dayStart, calendar: .current)
    }

    func reset() {
        defaults.removeObject(forKey: goalsKey)
        defaults.removeObject(forKey: dayResetHourKey)
    }
}

