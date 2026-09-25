import AVFoundation
import Foundation
import UserNotifications

/// The "Completion sound" setting mirrored from the web app through
/// `SET_SOUND_ENABLED`, and the sound it attaches to timer and goal
/// notifications. Default is on for a fresh install; the web setting can still
/// disable it explicitly and that choice remains persisted.
enum NotificationSound {
    private static let key = "sound.enabled"
    private static let defaultOnMigrationKey = "sound.default-on.v2"

    /// Drop the approved gong at `ios/Honoured/gong.caf` (`.caf`, `.aiff` or
    /// `.wav`, under 30 s); XcodeGen bundles it as a resource. The system default
    /// remains a safe fallback if a future target omits the approved asset.
    static let gongFileName = "gong.caf"

    static var isEnabled: Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key)
    }

    /// Earlier builds persisted the old default (`false`), which is
    /// indistinguishable from a user choice. Enable sound once when upgrading
    /// to the bundled-gong build; later changes through Settings remain intact.
    static func migrateDefaultToEnabledIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: defaultOnMigrationKey) else { return }
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.set(true, forKey: defaultOnMigrationKey)
    }

    /// Nil when the setting is off: iOS then delivers the notification without
    /// sound or vibration. When on, the bundled gong or the system default.
    static var current: UNNotificationSound? {
        guard isEnabled else { return nil }
        guard isGongBundled else { return .default }
        return UNNotificationSound(named: UNNotificationSoundName(gongFileName))
    }

    static var isGongBundled: Bool {
        let name = (gongFileName as NSString).deletingPathExtension
        let ext = (gongFileName as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext) != nil
    }

    /// `.ambient` keeps in-app audio under the hardware silent switch and lets
    /// it mix with whatever else is playing. This is the baseline WebKit inherits;
    /// the web app must play its gong through Web Audio (`AudioContext`), because
    /// an audible `<audio>` element makes WebKit switch the session to playback,
    /// which ignores the switch. Notification sounds are not affected either way.
    static func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
    }
}
