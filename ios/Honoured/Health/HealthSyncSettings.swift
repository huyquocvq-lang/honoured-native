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
    /// user's reset hour. Shared by daily totals and goal detection so
    /// `health_daily.day` and "reached today" always mean the same window.
    func healthDayStart(containing date: Date) -> Date {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: date)
        let todayBoundary = calendar.date(byAdding: .hour, value: dayResetHour(), to: midnight) ?? midnight
        if date >= todayBoundary { return todayBoundary }
        return calendar.date(byAdding: .day, value: -1, to: todayBoundary) ?? todayBoundary
    }

    /// `yyyy-MM-dd` of a health-day start, the value stored in `health_daily.day`.
    nonisolated static func dayString(_ dayStart: Date) -> String {
        dayFormatter.string(from: dayStart)
    }

    private nonisolated static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func reset() {
        defaults.removeObject(forKey: goalsKey)
        defaults.removeObject(forKey: dayResetHourKey)
    }
}

