import Foundation
import Security
import UIKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Registers this install's APNs tokens with Supabase (V1.2 M2-06): the device
/// token for the standard push fallback, ActivityKit's push-to-start token
/// (iOS 17.2+) and the update token of each Icon card. The `icon-push` job
/// (M2-07) addresses them. Signing out removes them. No token, installation id
/// or session reaches a log.
@MainActor
final class PushTokenRegistry {
    static let shared = PushTokenRegistry()

    private struct CardToken {
        let contractId: String
        let iconDay: String
        let token: String
    }

    private let defaults = UserDefaults.standard
    /// Server calls run one at a time, in order, so a sign-out is never
    /// overtaken by a registration queued before it.
    private let operations = SerialAsyncQueue()
    private var deviceToken: String?
    private var pushToStartToken: String?
    /// Card key (contract and Icon day) → that card's update token.
    private var cardTokens: [String: CardToken] = [:]
    private var observedCards = Set<String>()
    private var isObserving = false
    /// Bumped when the account goes: work queued before that sends nothing.
    private var generation = 0

    private static let sentKey = "honoured.push.sent"
    private static let fullSyncKey = "honoured.push.fullSyncAt"
    private static let pendingUnregisterKey = "honoured.push.pendingUnregister"

    /// From launch: ActivityKit hands tokens only to observers that exist,
    /// including in the background launch that follows a push-started card.
    func start() {
        guard !isObserving else { return }
        isObserving = true
        #if canImport(ActivityKit)
        if #available(iOS 17.2, *) {
            Task {
                for await data in Activity<IconActivityAttributes>.pushToStartTokenUpdates {
                    self.pushToStartToken = PushTokenSupport.hex(data)
                    self.scheduleSync()
                }
            }
        }
        if #available(iOS 16.2, *) {
            Task {
                for await activity in Activity<IconActivityAttributes>.activityUpdates {
                    self.observeCard(activity)
                }
            }
            Task {
                // Turning Live Activities off moves this install to the alert fallback.
                for await _ in ActivityAuthorizationInfo().activityEnablementUpdates {
                    self.scheduleSync()
                }
            }
            Activity<IconActivityAttributes>.activities.forEach(observeCard)
        }
        #endif
        scheduleSync()
    }

    #if canImport(ActivityKit)
    /// Follows one Icon card's update token so the server can update and close
    /// it. Also called for cards the app starts itself.
    @available(iOS 16.2, *)
    func observeCard(_ activity: Activity<IconActivityAttributes>) {
        guard observedCards.insert(activity.id).inserted else { return }
        let facts = activity.attributes.facts
        let state = activity.content.state
        Task { await IconCardCoordinator.shared.noteShown(facts, state: state) }
        Task {
            for await data in activity.pushTokenUpdates {
                self.cardTokens[IconCardPlan.key(contractId: facts.contractId, iconDay: facts.iconDay)] = CardToken(
                    contractId: facts.contractId, iconDay: facts.iconDay, token: PushTokenSupport.hex(data)
                )
                self.scheduleSync()
            }
        }
    }
    #endif

    func setDeviceToken(_ data: Data) {
        deviceToken = PushTokenSupport.hex(data)
        scheduleSync()
    }

    /// Sends every token that changed since it was last accepted, and all of
    /// them once a day so the server heals from anything it dropped.
    func scheduleSync() {
        let generation = generation
        operations.enqueue { await self.sync(generation: generation) }
    }

    /// Signing out or switching account: from now on this install gets nothing
    /// for the account. Needs no session, so it works after the web app has
    /// revoked it; offline, it is retried before the next registration.
    func forgetAccount() {
        generation += 1
        cardTokens.removeAll()
        defaults.removeObject(forKey: Self.sentKey)
        defaults.removeObject(forKey: Self.fullSyncKey)
        defaults.set(true, forKey: Self.pendingUnregisterKey)
        operations.enqueue { await self.unregisterIfPending() }
    }

    private func sync(generation: Int) async {
        guard generation == self.generation else { return }
        await unregisterIfPending()
        guard !defaults.bool(forKey: Self.pendingUnregisterKey),
              let baseURL = AppConfig.supabaseURL, !AppConfig.supabaseAnonKey.isEmpty,
              let installationId = PushInstallation.id(),
              let session = await usableSession(),
              generation == self.generation else { return }

        let now = Date()
        let environment = Self.environment
        let topic = Bundle.main.bundleIdentifier ?? ""
        let osVersion = UIDevice.current.systemVersion
        let liveActivitiesEnabled = Self.liveActivitiesEnabled
        let lastFullSync = defaults.object(forKey: Self.fullSyncKey) as? Double
        let fullSync = PushTokenSupport.needsFullSync(
            lastFullSync: lastFullSync.map(Date.init(timeIntervalSince1970:)), now: now
        )
        let stored = defaults.dictionary(forKey: Self.sentKey) as? [String: String] ?? [:]
        let oldestDay = PushTokenSupport.oldestCardDay(now: now)
        cardTokens = cardTokens.filter { $0.value.iconDay >= oldestDay }

        var slots: [(key: String, kind: PushTokenSupport.Kind, token: String, card: CardToken?)] = []
        if let deviceToken { slots.append(("device", .device, deviceToken, nil)) }
        if let pushToStartToken { slots.append(("push_to_start", .pushToStart, pushToStartToken, nil)) }
        for (key, card) in cardTokens { slots.append(("activity|" + key, .activity, card.token, card)) }

        // Only current slots are kept, so ended cards do not pile up here.
        var sent: [String: String] = [:]
        var allAccepted = true
        for slot in slots {
            let fingerprint = PushTokenSupport.fingerprint(
                userId: session.userId, kind: slot.kind, token: slot.token, environment: environment,
                liveActivitiesEnabled: liveActivitiesEnabled, osVersion: osVersion,
                contractId: slot.card?.contractId, iconDay: slot.card?.iconDay
            )
            if !fullSync, stored[slot.key] == fingerprint {
                sent[slot.key] = fingerprint
                continue
            }
            guard generation == self.generation else { return }
            var body: [String: Any] = [
                "p_installation_id": installationId.uuidString,
                "p_kind": slot.kind.rawValue,
                "p_token": slot.token,
                "p_environment": environment.rawValue,
                "p_topic": topic,
                "p_os_version": osVersion,
            ]
            if let liveActivitiesEnabled { body["p_live_activities_enabled"] = liveActivitiesEnabled }
            if let card = slot.card {
                body["p_contract_client_id"] = card.contractId
                body["p_icon_day"] = card.iconDay
            }
            if (try? await rpc("register_push_token", body: body, baseURL: baseURL, accessToken: session.accessToken)) != nil {
                sent[slot.key] = fingerprint
            } else {
                allAccepted = false // offline or refused: the next trigger retries
            }
        }
        guard generation == self.generation else { return }
        defaults.set(sent, forKey: Self.sentKey)
        if fullSync, allAccepted, !slots.isEmpty {
            defaults.set(now.timeIntervalSince1970, forKey: Self.fullSyncKey)
        }
    }

    /// In the foreground the web app refreshes the session and its next
    /// `SET_AUTH_SESSION` syncs again; in the background (a card the server
    /// started, a health wake) native refreshes it itself.
    private func usableSession() async -> NativeAuthSession? {
        guard UIApplication.shared.applicationState == .active else {
            return try? await AuthSessionStore.shared.refreshedSessionIfNeeded()
        }
        guard let session = await AuthSessionStore.shared.load(),
              session.expiresAt > Date().timeIntervalSince1970 + 60 else { return nil }
        return session
    }

    private func unregisterIfPending() async {
        guard defaults.bool(forKey: Self.pendingUnregisterKey) else { return }
        guard let baseURL = AppConfig.supabaseURL, !AppConfig.supabaseAnonKey.isEmpty,
              let installationId = PushInstallation.id() else { return }
        let body = ["p_installation_id": installationId.uuidString]
        if (try? await rpc("unregister_push_tokens", body: body, baseURL: baseURL, accessToken: nil)) != nil {
            defaults.removeObject(forKey: Self.pendingUnregisterKey)
        }
    }

    private static var environment: PushTokenSupport.Environment {
        #if targetEnvironment(simulator)
        return .sandbox
        #else
        let profile = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
            .flatMap { try? Data(contentsOf: $0) }
        return PushTokenSupport.environment(provisioningProfile: profile)
        #endif
    }

    private static var liveActivitiesEnabled: Bool? {
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) { return ActivityAuthorizationInfo().areActivitiesEnabled }
        #endif
        return nil
    }

    /// `accessToken` nil calls as anon: only `unregister_push_tokens` allows it.
    private func rpc(_ name: String, body: [String: Any], baseURL: URL, accessToken: String?) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc/\(name)"), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// A random id for this install, kept in the Keychain for this device only: it
/// survives a reinstall but never moves to another phone with a backup. The
/// server lets whoever presents it stop pushes to the install, so it stays
/// secret like a token.
private enum PushInstallation {
    private static let service = (Bundle.main.bundleIdentifier ?? "com.honoured.app") + ".push-installation"
    private static let account = "installation-id"

    /// Nil while the Keychain is locked (before the first unlock): try later.
    static func id() -> UUID? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        if status == errSecSuccess {
            return (result as? Data).flatMap { String(data: $0, encoding: .utf8) }.flatMap(UUID.init(uuidString:))
        }
        guard status == errSecItemNotFound else { return nil }
        let id = UUID()
        let added = SecItemAdd([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(id.uuidString.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ] as CFDictionary, nil)
        return added == errSecSuccess ? id : nil
    }
}
