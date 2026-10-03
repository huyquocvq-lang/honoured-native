import Foundation

/// Keeps the signature of each active Icon in the App Group cache, where the
/// Icon card's widget reads it (V1.2 M2-08, O-11). Signatures live in the
/// private `signatures` bucket and the signed-in person can read only their
/// own. A signature never changes after signing, so only missing ones are
/// downloaded, and those of Icons that ended are dropped.
actor IconSignatureSync {
    static let shared = IconSignatureSync()

    /// Runs after every health upload; the active Icons rarely change.
    private let minimumInterval: TimeInterval = 15 * 60
    private var lastRun: Date?
    private var isRunning = false

    func run(force: Bool = false) async {
        guard !isRunning, IconSignatureCache.groupIdentifier != nil,
              let baseURL = AppConfig.supabaseURL, !AppConfig.supabaseAnonKey.isEmpty else { return }
        if !force, let lastRun, Date().timeIntervalSince(lastRun) < minimumInterval { return }
        isRunning = true
        defer { isRunning = false }

        do {
            guard let session = try await AuthSessionStore.shared.refreshedSessionIfNeeded() else { return }
            let icons = try await activeIcons(baseURL: baseURL, session: session)
            guard await AuthSessionStore.shared.load()?.userId == session.userId else { return }
            IconSignatureCache.retainOnly(contractIds: Set(icons.map(\.clientId)))
            for icon in icons where IconSignatureCache.load(for: icon.clientId) == nil {
                guard let stored = try? await download(icon.signaturePath, baseURL: baseURL, session: session),
                      let prepared = IconSignatureImage.prepare(stored) else { continue }
                // The account may have changed during the download.
                guard await AuthSessionStore.shared.load()?.userId == session.userId else { return }
                try IconSignatureCache.store(prepared, for: icon.clientId)
            }
            lastRun = Date()
        } catch {
            // Offline or signed out: the next upload or foreground tries again.
        }
    }

    /// Sign-out or account switch: forget everything, including the throttle.
    func reset() {
        lastRun = nil
        IconSignatureCache.removeAll()
    }

    private struct ActiveIcon: Decodable {
        let clientId: String
        let signaturePath: String

        enum CodingKeys: String, CodingKey {
            case clientId = "client_id"
            case signaturePath = "signature_path"
        }
    }

    private func activeIcons(baseURL: URL, session: NativeAuthSession) async throws -> [ActiveIcon] {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/contracts"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "client_id,signature_path"),
            URLQueryItem(name: "icon_weekdays", value: "not.is.null"),
            URLQueryItem(name: "signature_path", value: "not.is.null"),
            URLQueryItem(name: "status", value: "eq.active"),
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        let data = try await get(url, session: session)
        return try JSONDecoder().decode([ActiveIcon].self, from: data)
    }

    private func download(_ path: String, baseURL: URL, session: NativeAuthSession) async throws -> Data {
        var url = baseURL.appendingPathComponent("storage/v1/object/authenticated/signatures")
        for component in path.split(separator: "/") where !component.isEmpty && component != ".." {
            url.appendPathComponent(String(component))
        }
        return try await get(url, session: session)
    }

    private func get(_ url: URL, session: NativeAuthSession) async throws -> Data {
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
