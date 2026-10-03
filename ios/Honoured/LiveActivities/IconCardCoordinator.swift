import Foundation
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Keeps Icon cards in step with the person's Icon days whenever the app runs
/// (V1.2 M2-09, local lifecycle). Once the app is in the foreground after an
/// Icon day's first reminder, its card opens; it turns to the evening line at
/// the evening reminder on its own (stale date), shows HONOURED when the day is
/// stamped and closes at the cut-off. `IconCardPlan` decides; this applies it.
/// Push-to-start (M2-07) will open the same cards without the app.
@MainActor
final class IconCardCoordinator {
    static let shared = IconCardCoordinator()

    private var isRefreshing = false
    private let defaults = UserDefaults.standard
    private static let startedPrefix = "honoured.iconCards.started."

    func refresh() async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *), !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let stored = await AuthSessionStore.shared.load() else {
            // Signed out: no card may outlive the account.
            await endAllCards()
            return
        }
        guard let baseURL = AppConfig.supabaseURL, !AppConfig.supabaseAnonKey.isEmpty,
              let session = try? await AuthSessionStore.shared.refreshedSessionIfNeeded(),
              session.userId == stored.userId,
              let days = try? await fetchDays(baseURL: baseURL, session: session) else {
            // Offline or the session needs the web app: leave the cards as they are.
            return
        }
        // The account may have changed while the days were fetched.
        guard await AuthSessionStore.shared.load()?.userId == session.userId else { return }

        let now = Date()
        let activities = Activity<IconActivityAttributes>.activities
        let running = activities.map {
            RunningIconCard(
                id: $0.id, contractId: $0.attributes.facts.contractId, iconDay: $0.attributes.facts.iconDay,
                state: $0.content.state, staleDate: $0.content.staleDate
            )
        }
        let canStart = UIApplication.shared.applicationState == .active
            && ActivityAuthorizationInfo().areActivitiesEnabled
        var started = startedCards(for: session.userId, now: now)
        let actions = IconCardPlan.actions(
            days: days, running: running, started: Set(started.keys), now: now, canStart: canStart
        )
        for action in actions {
            switch action {
            case let .start(facts, state, staleDate):
                do {
                    _ = try Activity.request(
                        attributes: IconActivityAttributes(facts: facts),
                        content: ActivityContent(state: state, staleDate: staleDate)
                    )
                } catch {
                    // Too many activities or Live Activities turned off: try again next time.
                    continue
                }
                started[IconCardPlan.key(contractId: facts.contractId, iconDay: facts.iconDay)] = facts.deadline
            case let .update(id, state, staleDate):
                await activities.first { $0.id == id }?.update(ActivityContent(state: state, staleDate: staleDate))
            case let .end(id):
                await activities.first { $0.id == id }?.end(nil, dismissalPolicy: .immediate)
            }
        }
        saveStartedCards(started, for: session.userId)
        #endif
    }

    /// Sign-out or account switch: close every card and forget what was shown.
    func reset() async {
        await endAllCards()
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.startedPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func endAllCards() async {
        #if canImport(ActivityKit)
        guard #available(iOS 16.2, *) else { return }
        for activity in Activity<IconActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #endif
    }

    // MARK: - Started cards

    /// Card key → that day's cut-off, so old entries can be dropped.
    private func startedCards(for userId: String, now: Date) -> [String: Date] {
        let raw = defaults.dictionary(forKey: Self.startedPrefix + userId) as? [String: Double] ?? [:]
        let horizon = now.addingTimeInterval(-2 * 24 * 3600)
        return raw.reduce(into: [:]) { result, entry in
            let deadline = Date(timeIntervalSince1970: entry.value)
            if deadline > horizon { result[entry.key] = deadline }
        }
    }

    private func saveStartedCards(_ cards: [String: Date], for userId: String) {
        defaults.set(cards.mapValues(\.timeIntervalSince1970), forKey: Self.startedPrefix + userId)
    }

    // MARK: - Server

    private func fetchDays(baseURL: URL, session: NativeAuthSession) async throws -> [IconCardDay] {
        let now = Date()
        let rows = try await get(
            baseURL: baseURL, path: "rest/v1/icon_days", session: session,
            query: [
                "select": "contract_id,day,session_number,deadline_at,morning_at,evening_at,status,"
                    + "contracts!inner(client_id,primary_activity,primary_target,because,status)",
                "contracts.status": "eq.active",
                "deadline_at": "gt.\(IconTimestamp.format(now))",
                "order": "deadline_at.asc",
            ],
            extra: [URLQueryItem(name: "deadline_at", value: "lt.\(IconTimestamp.format(now.addingTimeInterval(36 * 3600)))")]
        )
        let contractIds = Set(try JSONDecoder().decode([IconContractRef].self, from: rows).map(\.contract_id))
        guard !contractIds.isEmpty else { return [] }
        let counts = try await get(
            baseURL: baseURL, path: "rest/v1/icon_days", session: session,
            query: [
                "select": "contract_id,session_number",
                "contract_id": "in.(\(contractIds.sorted().joined(separator: ",")))",
            ]
        )
        var totals: [String: Int] = [:]
        for entry in try JSONDecoder().decode([IconSessionRef].self, from: counts) {
            totals[entry.contract_id] = max(totals[entry.contract_id] ?? 0, entry.session_number)
        }
        return try IconCardRows.days(from: rows, totals: totals)
    }

    private struct IconContractRef: Decodable { let contract_id: String }
    private struct IconSessionRef: Decodable { let contract_id: String; let session_number: Int }

    private func get(
        baseURL: URL, path: String, session: NativeAuthSession,
        query: [String: String], extra: [URLQueryItem] = []
    ) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } + extra
        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
