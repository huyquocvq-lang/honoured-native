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

    func reset() {
        defaults.removeObject(forKey: goalsKey)
        defaults.removeObject(forKey: dayResetHourKey)
    }
}

