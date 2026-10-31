import Foundation

/// Keeps the signatures of each active Icon in the App Group cache, where the
/// Icon card's widget reads them (V1.2 M2-08, O-11). Signatures live in the
/// private `signatures` bucket and the signed-in person can read only their
/// own. A signature never changes after it is given, so only missing ones are
/// downloaded, and those of Icons that ended are dropped.
///
/// A target revision (Phase 4 M2) brings a signature of its own: the sync
/// also records when each revision starts and downloads its signature, so a
/// card shows the signature of its own day. The web asks for a sync right
/// after a revision (`SYNC_ICON_REVISIONS`), before the next day's card.
actor IconSignatureSync {
    static let shared = IconSignatureSync()

    /// Runs after every health upload; the active Icons rarely change.
    private let minimumInterval: TimeInterval = 15 * 60
    private var lastRun: Date?
    private var isRunning = false
    /// A forced run asked for while another was running: that one may have
    /// read the server before a revision, so it goes round once more.
    private var rerun = false
    /// Moves on with every reset: a run started before it writes nothing more.
    private var generation = 0

    /// True when the cache now matches the server (every signature is in it);
    /// false when skipped, signed out, offline or an image is still missing.
    @discardableResult
    func run(force: Bool = false) async -> Bool {
        if isRunning {
            if force { rerun = true }
            return false
        }
        guard IconSignatureCache.groupIdentifier != nil,
              let baseURL = AppConfig.supabaseURL, !AppConfig.supabaseAnonKey.isEmpty else { return false }
        if !force, let lastRun, Date().timeIntervalSince(lastRun) < minimumInterval { return false }
        isRunning = true
        defer { isRunning = false }
        var synced = false
        repeat {
            rerun = false
            synced = await sync(baseURL: baseURL)
        } while rerun
        return synced
    }

    private func sync(baseURL: URL) async -> Bool {
        let generation = self.generation
        do {
            guard let session = try await AuthSessionStore.shared.refreshedSessionIfNeeded() else { return false }
            let icons = try await activeIcons(baseURL: baseURL, session: session)
            // Nil when they could not be read: each Icon keeps the revisions
            // it has, and the signings are still brought up to date.
            let revisions = try? await activeRevisions(baseURL: baseURL, session: session)
            var complete = revisions != nil
            guard await isCurrent(generation, session) else { return false }
            IconSignatureCache.retainOnly(contractIds: Set(icons.map(\.clientId)))
            for icon in icons {
                guard await isCurrent(generation, session) else { return false }
                var wanted: [(path: String, isRevision: Bool)] = []
                if IconSignatureCache.load(for: icon.clientId) == nil {
                    wanted.append((icon.signaturePath, false))
                }
                if let revisions {
                    let mine = revisions.filter { $0.clientId == icon.clientId }.map {
                        IconSignatureCache.Revision(revision: $0.revision, effectiveDay: $0.effectiveDay, signaturePath: $0.signaturePath)
                    }
                    // Before any image: a day whose image is still missing
                    // shows no signature, never the one it replaced.
                    try IconSignatureCache.storeRevisions(mine, for: icon.clientId)
                    IconSignatureCache.prune(icon.clientId, keeping: mine)
                    for revision in mine {
                        guard let path = revision.signaturePath,
                              IconSignatureCache.load(for: icon.clientId, signaturePath: path) == nil else { continue }
                        wanted.append((path, true))
                    }
                }
                for item in wanted {
                    guard let image = await image(at: item.path, baseURL: baseURL, session: session) else {
                        complete = false
                        continue
                    }
                    // The account may have changed or signed out meanwhile.
                    guard await isCurrent(generation, session) else { return false }
                    let stored = item.isRevision
                        ? try IconSignatureCache.store(image, for: icon.clientId, signaturePath: item.path)
                        : try IconSignatureCache.store(image, for: icon.clientId)
                    if !stored { complete = false }
                }
            }
            // Incomplete: the next upload or foreground tries again, unthrottled.
            guard complete, await isCurrent(generation, session) else { return false }
            lastRun = Date()
            return true
        } catch {
            // Offline or signed out: the next upload or foreground tries again.
            return false
        }
    }

    /// Sign-out or account switch: forget everything, including the throttle.
    /// A run already going stops writing and goes round once more.
    func reset() {
        generation += 1
        lastRun = nil
        IconSignatureCache.removeAll()
        if isRunning { rerun = true }
    }

    /// Still the account the run began for, and no reset since.
    private func isCurrent(_ generation: Int, _ session: NativeAuthSession) async -> Bool {
        guard generation == self.generation else { return false }
        let userId = await AuthSessionStore.shared.load()?.userId
        return generation == self.generation && userId == session.userId
    }

    private struct ActiveIcon: Decodable {
        let clientId: String
        let signaturePath: String

        enum CodingKeys: String, CodingKey {
            case clientId = "client_id"
            case signaturePath = "signature_path"
        }
    }

    private struct ActiveRevision: Decodable {
        struct Contract: Decodable {
            let clientId: String
            enum CodingKeys: String, CodingKey { case clientId = "client_id" }
        }

        let revision: Int
        let effectiveDay: String
        let signaturePath: String
        let contracts: Contract

        var clientId: String { contracts.clientId }

        enum CodingKeys: String, CodingKey {
            case revision, contracts
            case effectiveDay = "effective_day"
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

    /// The revisions of active Icons (`icon_revisions_v1.sql`). Without that
    /// table every Icon is on its signing, as before; any other failure
    /// throws, so a list already cached is never wiped by a bad network.
    private func activeRevisions(baseURL: URL, session: NativeAuthSession) async throws -> [ActiveRevision] {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/icon_revisions"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "revision,effective_day,signature_path,contracts!inner(client_id)"),
            URLQueryItem(name: "contracts.status", value: "eq.active"),
            URLQueryItem(name: "order", value: "revision.asc"),
        ]
        guard let url = components?.url else { throw URLError(.badURL) }
        do {
            return try JSONDecoder().decode([ActiveRevision].self, from: try await get(url, session: session))
        } catch let failure as HTTPFailure where failure.isMissingTable {
            return []
        }
    }

    /// The signature at `path`, ready for the widget; nil when it could not be
    /// downloaded or prepared.
    private func image(at path: String, baseURL: URL, session: NativeAuthSession) async -> Data? {
        guard let stored = try? await download(path, baseURL: baseURL, session: session) else { return nil }
        return IconSignatureImage.prepare(stored)
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
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else { throw HTTPFailure(status: http.statusCode, body: data) }
        return data
    }

    private struct HTTPFailure: Error {
        let status: Int
        let body: Data

        /// PostgREST's answer for a table that does not exist (after the
        /// migration's rollback), not any 404 a proxy might give.
        var isMissingTable: Bool {
            guard status == 404,
                  let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  let code = object["code"] as? String else { return false }
            return code == "PGRST205" || code == "42P01"
        }
    }
}
