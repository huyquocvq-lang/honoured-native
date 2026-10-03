import UIKit

/// The shell is portrait-only, except while the web app's contract screen asks
/// for landscape (`SET_LANDSCAPE_ALLOWED`) so the person can turn the phone and
/// sign on the full-screen pad. Every other screen keeps a portrait layout.
@MainActor
final class OrientationLock {
    static let shared = OrientationLock()

    private(set) var landscapeAllowed = false

    /// Read by `HonouredAppDelegate`; overrides Info.plist, which has to list
    /// landscape for the contract screen to be able to rotate at all.
    var supportedOrientations: UIInterfaceOrientationMask {
        landscapeAllowed ? [.portrait, .landscapeLeft, .landscapeRight] : .portrait
    }

    private init() {}

    func setLandscapeAllowed(_ allowed: Bool) {
        guard allowed != landscapeAllowed else { return }
        landscapeAllowed = allowed
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            // Lets UIKit rotate straight to the way the phone is already held
            // when landscape opens up.
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            // Leaving the contract screen while sideways must return to
            // portrait now, not at the next physical turn of the phone.
            if !allowed {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
            }
        }
    }
}
