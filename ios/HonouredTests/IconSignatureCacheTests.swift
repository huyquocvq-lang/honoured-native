import XCTest

/// The signature cache the Icon card's widget reads (`IconSignatureCache`),
/// on a folder of the test's own: the host-less bundle has no App Group.
final class IconSignatureCacheTests: XCTestCase {
    private var folder: URL!
    private let signing = Data("signing".utf8)
    private let first = Data("revision 1".utf8)
    private let second = Data("revision 2".utf8)
    private let path1 = "u/local-1/revisions/aaa.png"
    private let path2 = "u/local-1/revisions/bbb.png"

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        IconSignatureCache.directoryOverride = folder
    }

    override func tearDownWithError() throws {
        IconSignatureCache.directoryOverride = nil
        try? FileManager.default.removeItem(at: folder)
    }

    private var revisions: [IconSignatureCache.Revision] {
        [
            .init(revision: 1, effectiveDay: "2026-10-07", signaturePath: path1),
            .init(revision: 2, effectiveDay: "2026-10-10", signaturePath: path2),
        ]
    }

    private func files() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
    }

    // MARK: - Names

    func testFileNamesAreStableAndPathFree() {
        let name = IconSignatureCache.fileName(for: "../evil/id")
        XCTAssertEqual(name, IconSignatureCache.fileName(for: "../evil/id"))
        XCTAssertNotEqual(name, IconSignatureCache.fileName(for: "other"))
        XCTAssertFalse(name.contains("/"))
        XCTAssertEqual(name.count, 64 + 4, "the name earlier builds gave the signing")
        let revision = IconSignatureCache.fileName(for: "../evil/id", signaturePath: "u/../x/revisions/r.png")
        XCTAssertFalse(revision.contains("/"))
        XCTAssertEqual(revision.prefix(64), name.prefix(64), "retainOnly keeps an Icon's files by their shared stem")
    }

    func testEachSignatureHasAFileOfItsOwn() {
        let one = IconSignatureCache.fileName(for: "local-1", signaturePath: path1)
        XCTAssertNotEqual(one, IconSignatureCache.fileName(for: "local-1", signaturePath: path2))
        XCTAssertNotEqual(one, IconSignatureCache.fileName(for: "local-1"))
        XCTAssertNotEqual(one, IconSignatureCache.fileName(for: "local-2", signaturePath: path1))
    }

    // MARK: - The signature of a card's day

    func testEachDayShowsTheSignatureOfTheRevisionInForce() throws {
        try IconSignatureCache.store(signing, for: "local-1")
        try IconSignatureCache.store(first, for: "local-1", signaturePath: path1)
        try IconSignatureCache.store(second, for: "local-1", signaturePath: path2)
        try IconSignatureCache.storeRevisions(revisions, for: "local-1")
        XCTAssertEqual(IconSignatureCache.load(for: "local-1", iconDay: "2026-10-06"), signing, "before the first revision")
        XCTAssertEqual(IconSignatureCache.load(for: "local-1", iconDay: "2026-10-07"), first, "its effective day")
        XCTAssertEqual(IconSignatureCache.load(for: "local-1", iconDay: "2026-10-09"), first)
        XCTAssertEqual(IconSignatureCache.load(for: "local-1", iconDay: "2026-10-10"), second)
        XCTAssertEqual(IconSignatureCache.load(for: "local-1", iconDay: "2026-12-31"), second)
    }

    func testANeverRevisedIconShowsItsSigning() throws {
        try IconSignatureCache.store(signing, for: "local-1")
        XCTAssertEqual(IconSignatureCache.revisions(for: "local-1"), [])
        XCTAssertEqual(IconSignatureCache.load(for: "local-1", iconDay: "2026-10-07"), signing)
    }

    func testAMissingImageShowsNoSignatureNotTheOneItReplaced() throws {
        // The list is written before the images are downloaded.
        try IconSignatureCache.store(signing, for: "local-1")
        try IconSignatureCache.store(first, for: "local-1", signaturePath: path1)
        try IconSignatureCache.storeRevisions(revisions, for: "local-1")
        XCTAssertEqual(IconSignatureCache.load(for: "local-1", iconDay: "2026-10-09"), first)
        XCTAssertNil(IconSignatureCache.load(for: "local-1", iconDay: "2026-10-10"), "revision 2's image is not here yet")
    }

    func testAnUnreadableListShowsNoSignature() throws {
        try IconSignatureCache.store(signing, for: "local-1")
        try IconSignatureCache.storeRevisions(revisions, for: "local-1")
        let list = try XCTUnwrap(files().first { $0.hasSuffix(".revisions.json") })
        try Data("{".utf8).write(to: folder.appendingPathComponent(list))
        XCTAssertNil(IconSignatureCache.revisions(for: "local-1"))
        XCTAssertNil(IconSignatureCache.load(for: "local-1", iconDay: "2026-10-06"), "the day's revision is unknown")
        XCTAssertEqual(IconSignatureCache.load(for: "local-1", iconDay: "2026-10-06", targetRevision: 0), signing,
                       "a card that knows it is on the signing")
    }

    func testAListFromTheEarlierBuildShowsNoRevisionSignature() throws {
        // 1.0.9 (2) wrote the list without paths, and its images as -r<n>.png.
        try IconSignatureCache.store(signing, for: "local-1")
        let old = Data(#"[{"revision":1,"effectiveDay":"2026-10-07"}]"#.utf8)
        let name = IconSignatureCache.fileName(for: "local-1").dropLast(4) + ".revisions.json"
        try old.write(to: folder.appendingPathComponent(String(name)))
        XCTAssertEqual(IconSignatureCache.revisions(for: "local-1"), [.init(revision: 1, effectiveDay: "2026-10-07")])
        XCTAssertEqual(IconSignatureCache.load(for: "local-1", iconDay: "2026-10-06"), signing)
        XCTAssertNil(IconSignatureCache.load(for: "local-1", iconDay: "2026-10-07"), "until the next sync names its image")
    }

    func testTheCardsOwnRevisionWinsOverAStaleList() throws {
        // The app knows the day is on revision 2 before the list does.
        try IconSignatureCache.store(signing, for: "local-1")
        try IconSignatureCache.store(first, for: "local-1", signaturePath: path1)
        try IconSignatureCache.storeRevisions(Array(revisions.prefix(1)), for: "local-1")
        XCTAssertEqual(IconSignatureCache.load(for: "local-1", iconDay: "2026-10-10"), first, "by the list alone")
        XCTAssertNil(IconSignatureCache.load(for: "local-1", iconDay: "2026-10-10", targetRevision: 2),
                     "never revision 1's signature on a revision 2 day")
        XCTAssertEqual(IconSignatureCache.load(for: "local-1", iconDay: "2026-10-10", targetRevision: 1), first)
        try IconSignatureCache.store(second, for: "local-1", signaturePath: path2)
        try IconSignatureCache.storeRevisions(revisions, for: "local-1")
        XCTAssertEqual(IconSignatureCache.load(for: "local-1", iconDay: "2026-10-10", targetRevision: 2), second)
    }

    func testTwoRevisionsTheSameDayShowTheLater() {
        let sameDay: [IconSignatureCache.Revision] = [
            .init(revision: 2, effectiveDay: "2026-10-07"),
            .init(revision: 1, effectiveDay: "2026-10-07"),
        ]
        XCTAssertEqual(IconSignatureCache.revision(on: "2026-10-08", among: sameDay), 2)
        XCTAssertEqual(IconSignatureCache.revision(on: "2026-10-06", among: sameDay), 0)
    }

    // MARK: - Clean-up

    func testPruneDropsImagesOfRevisionsNoLongerThere() throws {
        try IconSignatureCache.store(signing, for: "local-1")
        try IconSignatureCache.store(first, for: "local-1", signaturePath: path1)
        try IconSignatureCache.store(second, for: "local-1", signaturePath: path2)
        try IconSignatureCache.store(signing, for: "local-2")
        try IconSignatureCache.store(first, for: "local-2", signaturePath: path1)
        // A rollback dropped revision 2; a later revision has a new path.
        let kept = Array(revisions.prefix(1))
        try IconSignatureCache.storeRevisions(kept, for: "local-1")
        IconSignatureCache.prune("local-1", keeping: kept)
        XCTAssertNil(IconSignatureCache.load(for: "local-1", signaturePath: path2))
        XCTAssertEqual(IconSignatureCache.load(for: "local-1", signaturePath: path1), first)
        XCTAssertEqual(IconSignatureCache.load(for: "local-1"), signing)
        XCTAssertEqual(IconSignatureCache.revisions(for: "local-1"), kept)
        XCTAssertEqual(IconSignatureCache.load(for: "local-2", signaturePath: path1), first, "another Icon's files stay")
    }

    func testRetainOnlyAndRemoveAll() throws {
        try IconSignatureCache.store(signing, for: "local-1")
        try IconSignatureCache.store(first, for: "local-1", signaturePath: path1)
        try IconSignatureCache.storeRevisions(revisions, for: "local-1")
        try IconSignatureCache.store(signing, for: "local-2")
        IconSignatureCache.retainOnly(contractIds: ["local-1"])
        XCTAssertEqual(files().count, 3, "the ended Icon's signing goes; the active one's three files stay")
        XCTAssertNil(IconSignatureCache.load(for: "local-2"))
        IconSignatureCache.removeAll()
        XCTAssertEqual(files(), [])
        XCTAssertNil(IconSignatureCache.load(for: "local-1", iconDay: "2026-10-07"))
    }

    func testAnEmptyListMeansNeverRevised() throws {
        try IconSignatureCache.storeRevisions(revisions, for: "local-1")
        try IconSignatureCache.storeRevisions([], for: "local-1")
        XCTAssertEqual(IconSignatureCache.revisions(for: "local-1"), [])
    }

    func testTooLargeOrEmptyImagesAreNotStored() throws {
        XCTAssertFalse(try IconSignatureCache.store(Data(), for: "c"))
        XCTAssertFalse(try IconSignatureCache.store(Data(count: IconSignatureCache.maxBytes + 1), for: "c", signaturePath: path1))
        XCTAssertEqual(files(), [])
    }

    func testWithoutAContainerNothingIsStoredOrRead() throws {
        // The host-less bundle declares no App Group, like a build without
        // the entitlement.
        IconSignatureCache.directoryOverride = nil
        XCTAssertNil(IconSignatureCache.groupIdentifier)
        XCTAssertFalse(try IconSignatureCache.store(signing, for: "c"))
        XCTAssertFalse(try IconSignatureCache.store(signing, for: "c", signaturePath: path1))
        XCTAssertFalse(try IconSignatureCache.storeRevisions(revisions, for: "c"))
        XCTAssertNil(IconSignatureCache.load(for: "c"))
        XCTAssertNil(IconSignatureCache.load(for: "c", iconDay: "2026-10-07"))
        XCTAssertEqual(IconSignatureCache.revisions(for: "c"), [])
    }

    // MARK: - The card's revision

    func testTheCardCarriesItsRevisionAndPushCardsLeaveItOut() throws {
        var facts = IconCardPreviewStates.facts
        XCTAssertNil(facts.targetRevision)
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(facts)) as? [String: Any]
        XCTAssertNil(plain?["targetRevision"], "the JSON stays the one earlier builds and the push job use")
        facts.targetRevision = 2
        XCTAssertEqual(try JSONDecoder().decode(IconCardFacts.self, from: JSONEncoder().encode(facts)).targetRevision, 2)
        let push = Data("""
        {"contractId":"local-1","iconDay":"2026-10-06","weekday":"TUE","sessionNumber":5,"totalSessions":92,
         "targetValue":"10,000","targetUnit":"STEPS","activityName":"Walking","because":"Spring","deadline":1791295200}
        """.utf8)
        XCTAssertNil(try JSONDecoder().decode(IconCardFacts.self, from: push).targetRevision)
    }
}
