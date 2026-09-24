import Foundation
import UIKit
import UserNotifications

/// Owns local-notification permission, scheduling and the delegate that turns a
/// tapped notification into a `NOTIFICATION_OPENED` bridge event. Timer and goal
/// notifications are scheduled through here so their payloads always carry the
/// `kind` / `activityId` pair the web app navigates on.
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    enum Kind: String {
        case timer
        case goal
    }

    private enum UserInfoKey {
        static let kind = "kind"
        static let activityId = "activityId"
    }

    private let center = UNUserNotificationCenter.current()
    private let lock = NSLock()
    private var installed = false

    private override init() {
        super.init()
    }

    /// Sets the delegate. Must run before `application(_:didFinishLaunchingWithOptions:)`
    /// returns, otherwise a tap that launched the app is not delivered to it.
    func install() {
        lock.lock()
        defer { lock.unlock() }
        guard !installed else { return }
        installed = true
        center.delegate = self
    }

    // MARK: - Permission

    /// Shows the system prompt only if the user has never been asked. This is
    /// called from the first `START_TIMER` or non-empty `SET_GOALS`, never at
    /// launch, so the request arrives with context.
    @discardableResult
    func requestPermissionIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    func isAuthorized() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined, .denied: return false
        @unknown default: return false
        }
    }

    func isUndetermined() async -> Bool {
        await center.notificationSettings().authorizationStatus == .notDetermined
    }

    /// Whether this notification is actually sitting in Notification Center.
    /// Permission is not proof of delivery: a Focus mode, a permission revoked
    /// mid-timer and a request cancelled before its trigger all leave nothing
    /// on screen.
    func wasDelivered(identifier: String) async -> Bool {
        await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { delivered in
                continuation.resume(returning: delivered.contains { $0.request.identifier == identifier })
            }
        }
    }

    /// The permission state the web app is allowed to act on: whether banners
    /// can be shown at all, and whether the person has been asked yet. Both
    /// false means they declined, and only Settings can change that.
    func statusPayload() async -> [String: Any] {
        let status = await center.notificationSettings().authorizationStatus
        return [
            "authorized": status == .authorized || status == .provisional || status == .ephemeral,
            "undetermined": status == .notDetermined
        ]
    }

    /// Opens this app's page in iOS Settings — the only place a declined
    /// notification permission can be turned back on, because iOS asks once.
    @MainActor
    func openSystemSettings() -> Bool {
        guard let url = URL(string: UIApplication.openSettingsURLString),
              UIApplication.shared.canOpenURL(url) else { return false }
        UIApplication.shared.open(url)
        return true
    }

    // MARK: - Scheduling

    /// Schedules a one-shot notification. `identifier` is stable per activity
    /// (`timer-<activityId>`, `goal-<activityId>-<day>`) so re-scheduling replaces
    /// rather than duplicates, and cancelling needs no bookkeeping.
    func schedule(
        identifier: String,
        kind: Kind,
        activityId: String,
        title: String,
        body: String,
        at date: Date,
        sound: UNNotificationSound?
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        content.userInfo = [
            UserInfoKey.kind: kind.rawValue,
            UserInfoKey.activityId: activityId
        ]

        let interval = max(date.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func cancel(identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// A notification firing while the app is in the foreground is never shown:
    /// the timer and goal owners emit their bridge event instead and the web app
    /// runs the in-app celebration.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        defer { completionHandler([]) }
        guard let (kind, activityId) = Self.target(of: notification.request.content.userInfo) else { return }
        switch kind {
        case .timer:
            Task { await TestamentTimer.shared.notificationPresentedInForeground(activityId: activityId) }
        case .goal:
            break
        }
    }

    /// Runs for a tap whether the app was in the background or launched cold. The
    /// event goes through the durable store, so it survives until a WebView is
    /// ready even if that is on a later launch.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let (kind, activityId) = Self.target(of: response.notification.request.content.userInfo) else { return }

        Task {
            // Settle the owning feature first so its completion event is stored
            // ahead of the navigation event.
            if kind == .timer {
                // A tapped banner was seen, so the timer is settled as notified
                // here; `reconcile()` would have to infer it.
                await TestamentTimer.shared.notificationTapped(activityId: activityId)
            }
            NativeBridgeEvents.postDurable(type: "NOTIFICATION_OPENED", payload: [
                "kind": kind.rawValue,
                "activityId": activityId
            ])
        }
    }

    private static func target(of userInfo: [AnyHashable: Any]) -> (Kind, String)? {
        guard let rawKind = userInfo[UserInfoKey.kind] as? String,
              let kind = Kind(rawValue: rawKind),
              let activityId = userInfo[UserInfoKey.activityId] as? String,
              !activityId.isEmpty else { return nil }
        return (kind, activityId)
    }
}
