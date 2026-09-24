import SwiftUI
import WidgetKit

/// The extension only hosts Live Activities. It never reads HealthKit, the
/// Keychain or the network: everything it shows arrives through ActivityKit.
@main
struct HonouredWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ContractLiveActivityWidget()
    }
}
