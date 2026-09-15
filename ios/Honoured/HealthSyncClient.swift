import Foundation

struct HealthSamplePayload: Codable {
    let sampleUuid: String
    let metric: String
    let value: Double
    let unit: String
    let startedAt: String
    let endedAt: String
    let sourceName: String
}

struct HealthDeletionPayload: Codable {
    let sampleUuid: String
    let metric: String
    let deletedAt: String
}

struct HealthDailyPayload: Codable {
    let day: String
    let metric: String
    let total: Double
    let unit: String
}

struct PendingHealthBatch: Codable, Identifiable {
    let id: UUID
    let userId: String
    let createdAt: Date
    let samples: [HealthSamplePayload]
    let deletions: [HealthDeletionPayload]
    let daily: [HealthDailyPayload]
    var attempts: Int
}

actor SupabaseHealthClient {
    static let shared = SupabaseHealthClient()

    func upload(_ batch: PendingHealthBatch, session: NativeAuthSession) async throws {
        guard let baseURL = AppConfig.supabaseURL, !AppConfig.supabaseAnonKey.isEmpty else {
            throw SyncError.notConfigured
        }
        if !batch.samples.isEmpty || !batch.deletions.isEmpty {
            try await rpc(
                "upsert_health_samples",
                body: SamplesRequest(batch: SamplesBody(samples: batch.samples, deletions: batch.deletions)),
                baseURL: baseURL,
                session: session
            )
        }
        if !batch.daily.isEmpty {
            try await rpc(
                "upsert_health_daily",
                body: DailyRequest(rows: batch.daily),
                baseURL: baseURL,
                session: session
            )
        }
    }

    private func rpc<T: Encodable>(
        _ name: String,
        body: T,
        baseURL: URL,
        session: NativeAuthSession
    ) async throws {
        let url = baseURL.appendingPathComponent("rest/v1/rpc/\(name)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SyncError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 { throw SyncError.invalidSession }
            throw SyncError.http(http.statusCode)
        }
    }

    private struct SamplesBody: Codable {
        let samples: [HealthSamplePayload]
        let deletions: [HealthDeletionPayload]
    }
    private struct SamplesRequest: Codable { let batch: SamplesBody }
    private struct DailyRequest: Codable { let rows: [HealthDailyPayload] }

    enum SyncError: LocalizedError {
        case notConfigured, invalidResponse, invalidSession, http(Int)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Supabase native sync is not configured"
            case .invalidResponse: return "Supabase returned an invalid response"
            case .invalidSession: return "The Supabase session is no longer valid"
            case .http(let code): return "Supabase request failed with HTTP \(code)"
            }
        }
    }
}
