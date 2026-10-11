import Foundation

/// The daily totals the server holds for one account, as far as this process
/// knows, so a collection pass uploads only the totals that changed. Kept in
/// memory only: a new process knows nothing yet and sends every total once,
/// which also repairs a server row that changed behind the app's back.
struct HealthDailyLedger {
    /// How long unchanged totals go unsent. Home shows "Updated …" from the
    /// newest `health_daily.updated_at`, so this bounds how old that label
    /// looks while the numbers themselves are current.
    static let defaultRefreshInterval: TimeInterval = 60 * 60

    let refreshInterval: TimeInterval

    private struct Key: Hashable {
        let day: String
        let metric: String

        init(_ row: HealthDailyPayload) {
            day = row.day
            metric = row.metric
        }
    }

    private var userId: String?
    private var uploaded: [Key: Double] = [:]
    private var lastUploadAt: Date?

    init(refreshInterval: TimeInterval = HealthDailyLedger.defaultRefreshInterval) {
        self.refreshInterval = refreshInterval
    }

    /// The totals of `daily` worth uploading for `userId`: each one that
    /// differs from the newest value still queued for it, or else from the
    /// last one uploaded. All of them once nothing is queued and no total has
    /// gone up for `refreshInterval`, so the server's "updated" time stays
    /// fresh. `queued` is the account's queued totals, oldest first.
    func totalsToUpload(
        _ daily: [HealthDailyPayload],
        userId: String,
        queued: [HealthDailyPayload],
        now: Date
    ) -> [HealthDailyPayload] {
        let isSameAccount = userId == self.userId
        if queued.isEmpty {
            let lastUpload = isSameAccount ? lastUploadAt : nil
            guard let lastUpload, now.timeIntervalSince(lastUpload) < refreshInterval else { return daily }
        }
        var known = isSameAccount ? uploaded : [:]
        for row in queued { known[Key(row)] = row.total }
        return daily.filter { known[Key($0)] != $0.total }
    }

    /// Records totals the server accepted for `userId`.
    mutating func recordUpload(_ daily: [HealthDailyPayload], userId: String, at date: Date) {
        guard !daily.isEmpty else { return }
        if userId != self.userId {
            self = HealthDailyLedger(refreshInterval: refreshInterval)
            self.userId = userId
        }
        for row in daily { uploaded[Key(row)] = row.total }
        lastUploadAt = date
    }

    mutating func reset() {
        self = HealthDailyLedger(refreshInterval: refreshInterval)
    }
}
