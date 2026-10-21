import Foundation
import StoreKit
import SwiftUI

/// Who may open the motion probe: Debug builds, Release builds installed from
/// Xcode or as Ad Hoc, and TestFlight builds. An App Store build ignores the
/// link and switches a leftover probe off.
enum MotionProbeAccess {
    private static var cached: Bool?

    /// Development and Ad Hoc installs carry their provisioning profile; App
    /// Store and TestFlight installs do not. Needs no network.
    static var hasEmbeddedProfile: Bool {
        Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") != nil
    }

    @MainActor
    static func isAllowed() async -> Bool {
        #if DEBUG
        return true
        #else
        if hasEmbeddedProfile { return true }
        if let cached { return cached }
        // TestFlight installs report the sandbox environment; App Store
        // installs report production.
        // A failed lookup (offline, say) refuses this time but is not
        // remembered, so the next tap asks again.
        guard let verification = try? await AppTransaction.shared else { return false }
        let allowed = verification.unsafePayloadValue.environment != .production
        cached = allowed
        return allowed
        #endif
    }

    /// What kind of build is running, for the probe screen and the log.
    @MainActor
    static func buildKind() async -> String {
        #if DEBUG
        return "Debug"
        #else
        if hasEmbeddedProfile { return "Release (Xcode or Ad Hoc)" }
        guard let verification = try? await AppTransaction.shared else { return "Release (unknown)" }
        switch verification.unsafePayloadValue.environment {
        case .sandbox: return "TestFlight"
        case .xcode: return "Release (Xcode)"
        case .production: return "App Store"
        default: return "Release (unknown)"
        }
        #endif
    }

    /// `honoured://motion-probe`.
    static func isProbeLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "honoured" && url.host?.lowercased() == "motion-probe"
    }

    /// At launch: keeps a probe that was switched on running, or switches it
    /// off on a build that may not open it. The state is logged as UIKit
    /// reports it: a scene-based app reads `background` here even when the
    /// person opened it, so only an `app_active` run that follows shows a
    /// launch into the foreground.
    @MainActor
    static func applicationDidFinishLaunching(state: UIApplication.State) {
        guard MotionProbe.isEnabled else { return }
        let stateName: String
        switch state {
        case .active: stateName = "active"
        case .inactive: stateName = "inactive"
        case .background: stateName = "background"
        @unknown default: stateName = "unknown"
        }
        MotionProbe.note("lifecycle", reason: "launched", notes: ["state_at_launch": stateName])
        Task { @MainActor in
            guard await isAllowed() else {
                await MotionProbe.shared.setEnabled(false)
                return
            }
            UIDevice.current.isBatteryMonitoringEnabled = true
            MotionProbeMetricKit.shared.start()
            await MotionProbe.shared.recordRun(reason: .launch)
        }
    }
}

/// Shows the probe screen over the web view.
@MainActor
final class MotionProbePresenter: ObservableObject {
    static let shared = MotionProbePresenter()

    @Published var isPresented = false

    func open() {
        Task {
            guard await MotionProbeAccess.isAllowed() else { return }
            isPresented = true
        }
    }
}
