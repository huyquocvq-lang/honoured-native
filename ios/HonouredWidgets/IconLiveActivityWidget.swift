import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

/// One card per Icon day (V1.2 M2-08). It has no actions; a tap opens the app.
struct IconLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IconActivityAttributes.self) { context in
            IconLockScreenView(
                facts: context.attributes.facts,
                state: context.state,
                isStale: context.isStale,
                signature: Self.signature(for: context.attributes.facts.contractId)
            )
            .activityBackgroundTint(HonouredPalette.background.opacity(0.92))
            .activitySystemActionForegroundColor(HonouredPalette.ink)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IconExpandedLeadingView()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    IconExpandedTrailingView(facts: context.attributes.facts)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    IconExpandedBottomView(facts: context.attributes.facts, state: context.state, isStale: context.isStale)
                }
            } compactLeading: {
                IconCompactLeadingView()
            } compactTrailing: {
                IconCompactTrailingView(facts: context.attributes.facts, state: context.state)
            } minimal: {
                IconMinimalView()
            }
            .keylineTint(HonouredPalette.gold)
        }
    }

    private static func signature(for contractId: String) -> UIImage? {
        IconSignatureCache.load(for: contractId).flatMap(UIImage.init(data:))
    }
}

#if DEBUG
struct IconLiveActivityWidget_Previews: PreviewProvider {
    static let attributes = IconActivityAttributes(facts: IconCardPreviewStates.facts)

    static var previews: some View {
        Group {
            attributes.previewContext(IconCardPreviewStates.morning, viewKind: .content)
                .previewDisplayName("Lock Screen · morning")
            attributes.previewContext(IconCardPreviewStates.evening, viewKind: .content)
                .previewDisplayName("Lock Screen · evening")
            attributes.previewContext(IconCardPreviewStates.honoured, viewKind: .content)
                .previewDisplayName("Lock Screen · honoured")
            attributes.previewContext(IconCardPreviewStates.morning, viewKind: .dynamicIsland(.expanded))
                .previewDisplayName("Expanded")
            attributes.previewContext(IconCardPreviewStates.morning, viewKind: .dynamicIsland(.compact))
                .previewDisplayName("Compact")
        }
    }
}
#endif
