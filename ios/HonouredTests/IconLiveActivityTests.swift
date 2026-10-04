import SwiftUI
import XCTest

@MainActor
final class IconLiveActivityTests: XCTestCase {
    private var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["HONOURED_RENDER_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    // MARK: - Facts and copy

    func testFactsNormaliseLabelsAndCutFreeText() {
        let facts = IconCardPreviewStates.longFacts
        XCTAssertEqual(facts.weekday, "WED")
        XCTAssertEqual(facts.sessionLabel, "WED · 128 OF 261")
        XCTAssertEqual(facts.targetUnit, "KILOMETRES")
        XCTAssertLessThanOrEqual(facts.activityName.count, IconCardFacts.maxActivityName)
        XCTAssertLessThanOrEqual(facts.because.count, IconCardFacts.maxBecause)
        XCTAssertTrue(facts.because.hasSuffix("…"))
        XCTAssertEqual(IconCardPreviewStates.facts.sessionLabel, "TUE · 5 OF 17")
    }

    func testSessionNumbersStayInRange() {
        let facts = IconCardFacts(
            contractId: "c", iconDay: "2026-10-02", weekday: "fri", sessionNumber: 0, totalSessions: 0,
            targetValue: "1", targetUnit: "km", activityName: "Run", because: "", deadline: Date()
        )
        XCTAssertEqual(facts.sessionLabel, "FRI · 1 OF 1")
    }

    func testAffirmationsRotateOnePerIconDay() {
        XCTAssertEqual(IconCopy.affirmation(sessionNumber: 1), "You've got this.")
        XCTAssertEqual(IconCopy.affirmation(sessionNumber: 2), "You're closer than you think.")
        XCTAssertEqual(IconCopy.affirmation(sessionNumber: IconCopy.affirmations.count + 1), "You've got this.")
        XCTAssertEqual(Set(IconCopy.affirmations).count, IconCopy.affirmations.count, "no line repeats within a rotation")
        XCTAssertTrue(IconCopy.affirmations.allSatisfy { $0.count <= 30 }, "every line fits beside the signature")
        XCTAssertEqual(IconLiveActivityState.morning(sessionNumber: 2, at: Date()).line, "You're closer than you think.")
        XCTAssertEqual(IconLiveActivityState.evening(at: Date()).line, "Finish what you signed.")
        XCTAssertEqual(IconLiveActivityState.result(.honoured, at: Date()).line, "HONOURED")
        XCTAssertEqual(IconLiveActivityState.result(.broken, at: Date()).result, .broken)
    }

    func testDeadlineLabelSaysMidnightForAZeroCutOff() throws {
        let sydney = try XCTUnwrap(TimeZone(identifier: "Australia/Sydney"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = sydney
        let late = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 23, minute: 59)))
        let midnight = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 0, minute: 0)))
        let morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 9, minute: 5)))
        XCTAssertEqual(IconCopy.deadlineLabel(late, timeZone: sydney), "Due 11:59 pm")
        XCTAssertEqual(IconCopy.deadlineLabel(midnight, timeZone: sydney), "Due midnight")
        XCTAssertEqual(IconCopy.deadlineLabel(morning, timeZone: sydney), "Due 9:05 am")
    }

    /// ActivityKit (and the APNs Live Activity payload) allow 4 KB for
    /// attributes and state together; the longest allowed text must fit.
    func testLongestCardFitsTheFourKilobyteLimit() throws {
        let encoder = JSONEncoder()
        let facts = try encoder.encode(IconCardPreviewStates.longFacts)
        let state = try encoder.encode(IconLiveActivityState.result(.honoured, at: Date()))
        XCTAssertLessThan(facts.count + state.count, 4096)
    }

    func testCardDataRoundTripsAsPlainJSON() throws {
        let facts = IconCardPreviewStates.facts
        let decoded = try JSONDecoder().decode(IconCardFacts.self, from: JSONEncoder().encode(facts))
        XCTAssertEqual(decoded, facts)
        let state = IconCardPreviewStates.evening
        XCTAssertEqual(try JSONDecoder().decode(IconLiveActivityState.self, from: JSONEncoder().encode(state)), state)
    }

    /// The exact JSON the push job sends as `attributes` and `content-state`.
    func testDecodesTheServerPushPayload() throws {
        let attributes = Data("""
        {"facts":{"contractId":"local-1","iconDay":"2026-10-06","weekday":"TUE","sessionNumber":5,"totalSessions":92,
                  "targetValue":"10,000","targetUnit":"STEPS","activityName":"Walking","because":"Spring","deadline":1791295200}}
        """.utf8)
        let state = Data(#"{"phase":"evening","line":"Finish what you signed.","updatedAt":1791280800}"#.utf8)
        struct Attributes: Decodable { let facts: IconCardFacts }
        let facts = try JSONDecoder().decode(Attributes.self, from: attributes).facts
        XCTAssertEqual(facts.sessionLabel, "TUE · 5 OF 92")
        XCTAssertEqual(facts.deadline, Date(timeIntervalSince1970: 1_791_295_200))
        let decoded = try JSONDecoder().decode(IconLiveActivityState.self, from: state)
        XCTAssertEqual(decoded.phase, .evening)
        XCTAssertNil(decoded.result)
        XCTAssertEqual(decoded.updatedAt, Date(timeIntervalSince1970: 1_791_280_800))
        // Dates stay Unix seconds whatever strategy a decoder uses.
        let other = JSONDecoder()
        other.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try other.decode(IconLiveActivityState.self, from: state).updatedAt, decoded.updatedAt)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(facts)) as? [String: Any]
        XCTAssertEqual(encoded?["deadline"] as? Double, 1_791_295_200)
    }

    // MARK: - Signature cache

    func testSignatureFileNameIsStableAndPathFree() {
        let name = IconSignatureCache.fileName(for: "../evil/id")
        XCTAssertEqual(name, IconSignatureCache.fileName(for: "../evil/id"))
        XCTAssertNotEqual(name, IconSignatureCache.fileName(for: "other"))
        XCTAssertFalse(name.contains("/"))
        XCTAssertTrue(name.hasSuffix(".png"))
        XCTAssertEqual(name.count, 64 + 4)
    }

    func testWithoutAnAppGroupNothingIsStoredOrRead() throws {
        // The host-less test bundle declares no App Group, like a build
        // without the entitlement.
        XCTAssertNil(IconSignatureCache.groupIdentifier)
        XCTAssertFalse(try IconSignatureCache.store(Data([0x89, 0x50]), for: "c"))
        XCTAssertNil(IconSignatureCache.load(for: "c"))
    }

    // MARK: - Rendering

    func testEveryIconCardRendersInEveryPresentation() throws {
        if let outputDirectory {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }
        let signature = Self.sampleSignature()
        for (name, facts, state) in IconCardPreviewStates.all {
            for size in [DynamicTypeSize.large, .accessibility2] {
                let suffix = size == .large ? "" : "-large-text"
                try render(
                    IconLockScreenView(facts: facts, state: state, signature: signature)
                        .background(HonouredPalette.background)
                        .environment(\.dynamicTypeSize, size),
                    width: 360, maxHeight: 160, name: "icon-lock-\(name)\(suffix)"
                )
            }
            try render(island(facts, state), width: 370, maxHeight: nil, name: "icon-expanded-\(name)")
            try render(compact(facts, state), width: 250, maxHeight: nil, name: "icon-compact-\(name)")
        }
        for (index, _) in IconCopy.affirmations.enumerated() {
            let state = IconLiveActivityState.morning(sessionNumber: index + 1, at: IconCardPreviewStates.now)
            for size in [DynamicTypeSize.large, .accessibility2] {
                let suffix = size == .large ? "" : "-large-text"
                try render(
                    IconLockScreenView(facts: IconCardPreviewStates.facts, state: state, signature: signature)
                        .background(HonouredPalette.background)
                        .environment(\.dynamicTypeSize, size),
                    width: 360, maxHeight: 160, name: "icon-lock-affirmation-\(index + 1)\(suffix)"
                )
            }
        }
        try render(
            IconLockScreenView(facts: IconCardPreviewStates.facts, state: IconCardPreviewStates.morning, signature: nil)
                .background(HonouredPalette.background),
            width: 360, maxHeight: 160, name: "icon-lock-morning-no-signature"
        )
    }

    private func island(_ facts: IconCardFacts, _ state: IconLiveActivityState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                IconExpandedLeadingView()
                Spacer()
                IconExpandedTrailingView(facts: facts)
            }
            IconExpandedBottomView(facts: facts, state: state)
        }
        .padding(14)
        .background(Color.black)
    }

    private func compact(_ facts: IconCardFacts, _ state: IconLiveActivityState) -> some View {
        HStack(spacing: 24) {
            HStack {
                IconCompactLeadingView()
                Spacer(minLength: 60)
                IconCompactTrailingView(facts: facts, state: state)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Capsule().fill(Color.black))
            IconMinimalView()
                .frame(width: 26, height: 26)
                .padding(5)
                .background(Circle().fill(Color.black))
        }
        .padding(8)
        .background(Color(white: 0.3))
    }

    /// A pen stroke drawn in code, standing in for a cached signature PNG.
    private static func sampleSignature() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 48))
        return renderer.image { context in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 6, y: 38))
            path.addCurve(to: CGPoint(x: 60, y: 14), controlPoint1: CGPoint(x: 20, y: 4), controlPoint2: CGPoint(x: 40, y: 44))
            path.addCurve(to: CGPoint(x: 150, y: 24), controlPoint1: CGPoint(x: 80, y: -4), controlPoint2: CGPoint(x: 110, y: 46))
            UIColor.white.setStroke()
            path.lineWidth = 3
            path.stroke()
            context.cgContext.flush()
        }
    }

    private func render<V: View>(_ view: V, width: CGFloat, maxHeight: CGFloat?, name: String) throws {
        let renderer = ImageRenderer(content: view.frame(width: width).environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage, name)
        XCTAssertGreaterThan(image.size.height, 20, name)
        if let maxHeight {
            XCTAssertLessThanOrEqual(image.size.height, maxHeight, "\(name) is taller than the Lock Screen allows")
        }
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
