import SwiftUI
import XCTest

/// Renders every card variant offscreen: timer, Health, mixed, unknown, stale,
/// completed and long names, in the Lock Screen and Dynamic Island shapes, in
/// both light-on-dark text sizes. This checks the views build and lay out for
/// each state; it is not how iOS composes them on a device. Set
/// `TEST_RUNNER_HONOURED_RENDER_DIR` to also write the PNGs to a folder.
@MainActor
final class LiveActivityViewRenderTests: XCTestCase {
    private var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["HONOURED_RENDER_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    func testEveryStateRendersInEveryPresentation() throws {
        if let outputDirectory {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }
        for (name, state) in LiveActivityPreviewStates.all {
            for size in [DynamicTypeSize.large, .accessibility2] {
                let suffix = size == .large ? "" : "-large-text"
                try render(lockScreen(state).environment(\.dynamicTypeSize, size), width: 360, name: "lock-\(name)\(suffix)")
            }
            try render(island(state), width: 370, name: "expanded-\(name)")
            try render(compact(state), width: 250, name: "compact-\(name)")
        }
        try render(lockScreen(LiveActivityPreviewStates.stale, isStale: true), width: 360, name: "lock-stale-flagged")
        try render(lockScreen(finishedWhileSuspended, isStale: true), width: 360, name: "lock-timer-at-zero")
    }

    /// A countdown that passed zero while the app was suspended: stale, not
    /// finished, and never shown as honoured.
    private var finishedWhileSuspended: HonouredLiveActivityState {
        var state = LiveActivityPreviewStates.timerOnly
        state.timer?.startedAt = Date().addingTimeInterval(-700)
        state.timer?.endsAt = Date().addingTimeInterval(-100)
        return state
    }

    private func lockScreen(_ state: HonouredLiveActivityState, isStale: Bool = false) -> some View {
        ContractLockScreenView(state: state, isStale: isStale)
            .background(HonouredPalette.background)
    }

    private func island(_ state: HonouredLiveActivityState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ExpandedLeadingView(state: state)
                Spacer()
                ExpandedTrailingView(state: state, isStale: false)
            }
            ExpandedBottomView(state: state, isStale: false)
        }
        .padding(14)
        .background(Color.black)
    }

    private func compact(_ state: HonouredLiveActivityState) -> some View {
        HStack(spacing: 24) {
            HStack {
                CompactLeadingView(state: state)
                Spacer(minLength: 60)
                CompactTrailingView(state: state, isStale: false)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(Color.black))
            MinimalView(state: state, isStale: false)
                .frame(width: 26, height: 26)
                .padding(5)
                .background(Circle().fill(Color.black))
        }
        .padding(8)
        .background(Color(white: 0.3))
    }

    private func render<V: View>(_ view: V, width: CGFloat, name: String) throws {
        let renderer = ImageRenderer(content: view.frame(width: width).environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage, name)
        XCTAssertGreaterThan(image.size.height, 20, name)
        let data = try XCTUnwrap(image.pngData())
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let outputDirectory {
            try data.write(to: outputDirectory.appendingPathComponent("\(name).png"))
        }
    }
}
