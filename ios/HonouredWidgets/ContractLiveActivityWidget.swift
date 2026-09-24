import ActivityKit
import SwiftUI
import WidgetKit

/// One card per tracked contract occurrence. Tapping any presentation opens
/// that contract in the app; there are no business actions on the card.
struct ContractLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HonouredActivityAttributes.self) { context in
            ContractLockScreenView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(HonouredPalette.background.opacity(0.92))
                .activitySystemActionForegroundColor(HonouredPalette.ink)
                .widgetURL(Self.link(context.attributes))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(state: context.state, isStale: context.isStale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(state: context.state, isStale: context.isStale)
                }
            } compactLeading: {
                CompactLeadingView(state: context.state)
            } compactTrailing: {
                CompactTrailingView(state: context.state, isStale: context.isStale)
            } minimal: {
                MinimalView(state: context.state, isStale: context.isStale)
            }
            .keylineTint(HonouredPalette.gold)
            .widgetURL(Self.link(context.attributes))
        }
    }

    private static func link(_ attributes: HonouredActivityAttributes) -> URL? {
        ContractDeepLink.url(for: ContractDeepLink.Target(
            contractId: attributes.contractId,
            healthDay: attributes.healthDay,
            occurrenceToken: attributes.occurrenceToken
        ))
    }
}

#if DEBUG
struct ContractLiveActivityWidget_Previews: PreviewProvider {
    static let attributes = HonouredActivityAttributes(
        contractId: "preview", healthDay: "2026-09-23", occurrenceToken: "7C9D2B8E-3F0A-4F43-9A56-0D2E9B1C4A77"
    )

    static var previews: some View {
        Group {
            attributes.previewContext(LiveActivityPreviewStates.mixed, viewKind: .content)
                .previewDisplayName("Lock Screen · mixed")
            attributes.previewContext(LiveActivityPreviewStates.twoSlots, viewKind: .dynamicIsland(.expanded))
                .previewDisplayName("Expanded · two slots")
            attributes.previewContext(LiveActivityPreviewStates.timerOnly, viewKind: .dynamicIsland(.compact))
                .previewDisplayName("Compact · timer")
            attributes.previewContext(LiveActivityPreviewStates.unknown, viewKind: .dynamicIsland(.minimal))
                .previewDisplayName("Minimal · unknown")
            attributes.previewContext(LiveActivityPreviewStates.completed, viewKind: .content)
                .previewDisplayName("Lock Screen · completed")
        }
    }
}
#endif
