import AVFoundation
import Foundation
import UserNotifications

/// The "Completion sound" setting mirrored from the web app through
/// `SET_SOUND_ENABLED`, and the sound it attaches to timer and goal
/// notifications. Default is off, so a fresh install notifies silently.
enum NotificationSound {
    private static let key = "sound.enabled"

    /// Drop the approved gong at `ios/Honoured/gong.caf` (`.caf`, `.aiff` or
    /// `.wav`, under 30 s); XcodeGen bundles it as a resource on the next
    /// `xcodegen generate`. Until it exists the system default sound stands in
    /// so an enabled setting is still audible.
    static let gongFileName = "gong.caf"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key)
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
