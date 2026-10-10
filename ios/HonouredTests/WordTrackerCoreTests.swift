import XCTest
import ZIPFoundation

final class WordTrackerCoreTests: XCTestCase {
    func testDeterministicUnicodeWordRule() {
        XCTAssertEqual(WordCount.count("Hello, world!"), 2)
        XCTAssertEqual(WordCount.count("don't mother-in-law rock ’n’ roll"), 5)
        XCTAssertEqual(WordCount.count("Việt Nam 2026 — café"), 4)
        XCTAssertEqual(WordCount.count("... \n\t"), 0)
    }

    func testCountsWordsInOtherScriptsAndNumbers() {
        // Combining marks stay inside their word.
        XCTAssertEqual(WordCount.count("Vie\u{0323}\u{0302}t Nam"), 2)
        XCTAssertEqual(WordCount.count("हिंदी में लिखना"), 3)
        XCTAssertEqual(WordCount.count("كَتَبَ الطَّالِبُ الدَّرْسَ"), 3)
        // Chinese and Japanese characters count one each, as in Word; Korean
        // is written with spaces.
        XCTAssertEqual(WordCount.count("日本語のテキスト"), 8)
        XCTAssertEqual(WordCount.count("Honoured アプリ"), 4)
        XCTAssertEqual(WordCount.count("한국어 텍스트"), 2)
        // A number is one word; a full stop between words still splits them.
        XCTAssertEqual(WordCount.count("1,000 words in 3.14 hours at 10:30"), 7)
        XCTAssertEqual(WordCount.count("end.Start, 1. 2"), 4)
    }

    func testWordReminderListIsCheckedAndSorted() throws {
        let list: [Any] = [
            ["contractId": "c-2", "day": "2026-10-12", "at": "2026-10-12T20:30:00Z", "subtitle": "Writing · 500 words"],
            ["contractId": "c-1", "day": "2026-10-11", "at": "2026-10-11T20:30:00.000Z", "subtitle": NSNull()],
            ["contractId": "c-1", "day": "2026-10-11", "at": "2026-10-11T21:00:00Z"],
        ]
        let reminders = try XCTUnwrap(WordReminder.parseList(list))
        XCTAssertEqual(reminders.map(\.identifier), ["word-reminder.c-1.2026-10-11", "word-reminder.c-2.2026-10-12"])
        XCTAssertEqual(reminders[0].fireAt, ISO8601DateFormatter().date(from: "2026-10-11T20:30:00Z"))
        XCTAssertNil(reminders[0].subtitle)
        XCTAssertEqual(reminders[1].subtitle, "Writing · 500 words")
        XCTAssertEqual(WordReminder.parseList([Any]()), [])
    }

    func testMalformedWordReminderListsAreRefused() {
        let good: [String: Any] = ["contractId": "c", "day": "2026-10-11", "at": "2026-10-11T20:30:00Z"]
        func with(_ key: String, _ value: Any?) -> [Any] {
            var entry = good
            entry[key] = value
            return [entry]
        }
        XCTAssertNil(WordReminder.parseList(nil))
        XCTAssertNil(WordReminder.parseList("not a list"))
        XCTAssertNil(WordReminder.parseList(Array(repeating: good, count: 33)))
        XCTAssertNil(WordReminder.parseList(with("contractId", nil)))
        XCTAssertNil(WordReminder.parseList(with("contractId", "")))
        XCTAssertNil(WordReminder.parseList(with("contractId", String(repeating: "x", count: 257))))
        XCTAssertNil(WordReminder.parseList(with("day", "11/10/2026")))
        XCTAssertNil(WordReminder.parseList(with("at", "tomorrow")))
        XCTAssertNil(WordReminder.parseList(with("at", 1_760_000_000)))
        XCTAssertNil(WordReminder.parseList(with("subtitle", 42)))
        XCTAssertNil(WordReminder.parseList(with("subtitle", String(repeating: "x", count: 121))))
    }

    func testEveryAdapterUsesTheSamePlainTextResult() {
        let fixture = "One  two\nthree—four five's six-seven."
        XCTAssertEqual(WordCount.count(fixture), 6)
        XCTAssertEqual(WordCount.count(fixture.precomposedStringWithCanonicalMapping), 6)
    }

    func testSupportedKindsAreStrictAboutPackages() {
        XCTAssertEqual(WordSourceSupport.kind(fileExtension: "DOCX", isDirectory: false), .word)
        XCTAssertEqual(WordSourceSupport.kind(fileExtension: "rtfd", isDirectory: true), .richTextDirectory)
        XCTAssertEqual(WordSourceSupport.kind(fileExtension: "scriv", isDirectory: true), .scrivener)
        XCTAssertNil(WordSourceSupport.kind(fileExtension: "scriv", isDirectory: false))
        XCTAssertNil(WordSourceSupport.kind(fileExtension: "pages", isDirectory: true))
    }

    func testPlainTextDecodesUTF8AndUTF16() {
        let value = "A café manuscript"
        XCTAssertEqual(WordSourceSupport.decodePlainText(Data(value.utf8)), value)
        XCTAssertEqual(
            WordSourceSupport.decodePlainText(value.data(using: .utf16LittleEndian)!),
            value
        )
    }

    func testXMLParserReadsOnlySelectedTextNodes() throws {
        let xml = Data("""
        <?xml version="1.0"?>
        <w:document xmlns:w="urn:w"><w:body><w:p><w:t>Hello</w:t><w:tab/><w:t>world</w:t></w:p><meta>secret</meta></w:body></w:document>
        """.utf8)
        let text = try XCTUnwrap(SelectedXMLTextParser.word().parse(xml))
        XCTAssertEqual(WordCount.count(text), 2)
        XCTAssertFalse(text.contains("secret"))
    }

    func testWordJoinsRunsSplitInsideAWord() {
        // Word splits a word into runs for formatting and revision marks.
        XCTAssertEqual(wordCount(#"<w:p><w:r><w:t>Hel</w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>lo</w:t></w:r><w:r><w:t xml:space="preserve"> world</w:t></w:r></w:p>"#), 2)
        XCTAssertEqual(wordCount("<w:p><w:r><w:t>don&apos;t stop</w:t></w:r></w:p>"), 2)
    }

    func testWordSeparatesParagraphsTabsAndBreaks() {
        XCTAssertEqual(wordCount("<w:p><w:r><w:t>one</w:t></w:r></w:p><w:p><w:r><w:t>two</w:t></w:r></w:p>"), 2)
        XCTAssertEqual(wordCount("<w:p><w:r><w:t>one</w:t><w:tab/><w:t>two</w:t><w:br/><w:t>three</w:t></w:r></w:p>"), 3)
    }

    func testWordCountsATextBoxOnce() {
        let box = """
        <w:p><w:r><mc:AlternateContent xmlns:mc="urn:mc">
        <mc:Choice><w:txbxContent><w:p><w:r><w:t>boxed words</w:t></w:r></w:p></w:txbxContent></mc:Choice>
        <mc:Fallback><w:txbxContent><w:p><w:r><w:t>boxed words</w:t></w:r></w:p></w:txbxContent></mc:Fallback>
        </mc:AlternateContent></w:r></w:p>
        """
        XCTAssertEqual(wordCount(box), 2)
    }

    func testSourceIdsMatchTheServerShape() {
        XCTAssertTrue(WordSourceSupport.isValidSourceId(UUID().uuidString.lowercased()))
        XCTAssertTrue(WordSourceSupport.isValidSourceId("src_1-A"))
        for bad in ["", "a/b", "..", "café", "a b", String(repeating: "a", count: 129)] {
            XCTAssertFalse(WordSourceSupport.isValidSourceId(bad), bad)
        }
    }

    func testFileErrorsMapToSafeCodes() {
        XCTAssertEqual(WordSourceSupport.safeError(CocoaError(.fileReadNoSuchFile)), .missing)
        XCTAssertEqual(WordSourceSupport.safeError(CocoaError(.fileReadNoPermission)), .permissionDenied)
        XCTAssertEqual(WordSourceSupport.safeError(WordSourceError.documentTooLarge), .documentTooLarge)
        XCTAssertEqual(WordSourceSupport.safeError(URLError(.notConnectedToInternet)), .providerUnavailable)
    }

    /// Acceptance: the same text gives the same count in every supported format.
    func testEveryFormatCountsTheSameText() throws {
        let fixture = "Chapter one.\nIt’s a mother-in-law's café\t2026!"
        let expected = WordCount.count(fixture)
        XCTAssertEqual(expected, 7)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let text = dir.appendingPathComponent("draft.txt")
        try Data(fixture.utf8).write(to: text)
        let rich = dir.appendingPathComponent("draft.rtf")
        try rtf(fixture).write(to: rich)
        let package = dir.appendingPathComponent("draft.rtfd", isDirectory: true)
        let attributed = NSAttributedString(string: fixture)
        try attributed.fileWrapper(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
        ).write(to: package, options: [], originalContentsURL: nil)

        let word = dir.appendingPathComponent("draft.docx")
        try docx(document: """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        <w:p><w:r><w:t>Chap</w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>ter</w:t></w:r><w:r><w:t xml:space="preserve"> one.</w:t></w:r></w:p>
        <w:p><w:r><w:t>It’s a mother-in-law</w:t></w:r><w:r><w:t>&apos;s café</w:t></w:r><w:r><w:tab/><w:t>2026!</w:t></w:r></w:p>
        </w:body></w:document>
        """, at: word)

        let scrivener = dir.appendingPathComponent("Novel.scriv", isDirectory: true)
        try FileManager.default.createDirectory(at: scrivener, withIntermediateDirectories: true)
        try Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <ScrivenerProject><Binder>
          <BinderItem UUID="DRAFT-1" Type="DraftFolder"><Title>Manuscript</Title><Children>
            <BinderItem UUID="SCENE-1" Type="Text"><Title>Scene</Title></BinderItem>
          </Children></BinderItem>
          <BinderItem UUID="NOTES-1" Type="ResearchFolder"><Children>
            <BinderItem UUID="NOTE-1" Type="Text"/>
          </Children></BinderItem>
        </Binder></ScrivenerProject>
        """.utf8).write(to: scrivener.appendingPathComponent("Novel.scrivx"))
        for (id, body) in [("SCENE-1", fixture), ("NOTE-1", "research notes never count")] {
            let folder = scrivener.appendingPathComponent("Files/Data/\(id)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try rtf(body).write(to: folder.appendingPathComponent("content.rtf"))
        }

        let sources: [(URL, WordSourceKind)] = [
            (text, .text), (rich, .richText), (package, .richTextDirectory), (word, .word), (scrivener, .scrivener),
        ]
        for (url, kind) in sources {
            XCTAssertEqual(try WordDocumentReader.count(url: url, kind: kind), expected, kind.rawValue)
        }
    }

    func testANonZipWordFileIsMalformed() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".docx")
        try Data("not a zip".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertThrowsError(try WordDocumentReader.count(url: file, kind: .word)) {
            XCTAssertEqual($0 as? WordSourceError, .malformedDocument)
        }
    }

    private func wordCount(_ body: String) -> Int? {
        let xml = Data(#"<w:document xmlns:w="urn:w"><w:body>\#(body)</w:body></w:document>"#.utf8)
        return SelectedXMLTextParser.word().parse(xml).map(WordCount.count)
    }

    private func rtf(_ text: String) throws -> Data {
        let value = NSAttributedString(string: text)
        return try value.data(
            from: NSRange(location: 0, length: value.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    private func docx(document: String, at url: URL) throws {
        let archive = try Archive(url: url, accessMode: .create)
        let data = Data(document.utf8)
        try archive.addEntry(with: "word/document.xml", type: .file, uncompressedSize: Int64(data.count)) { position, size in
            data.subdata(in: Int(position)..<Int(position) + size)
        }
    }

    func testXMLParserRejectsMalformedInput() {
        XCTAssertNil(SelectedXMLTextParser(selectedNames: ["t"]).parse(Data("<t>open".utf8)))
    }

    func testScrivenerParserKeepsOnlyDraftDocuments() throws {
        let xml = Data("""
        <ScrivenerProject><Binder>
          <BinderItem UUID="draft" Type="DraftFolder"><Title>Manuscript</Title><Children>
            <BinderItem UUID="chapter" Type="Folder"><Children>
              <BinderItem UUID="scene-1" Type="Text"><Title>Scene</Title></BinderItem>
            </Children></BinderItem>
            <BinderItem UUID="scene-2" Type="Text"><Title>Scene 2</Title></BinderItem>
          </Children></BinderItem>
          <BinderItem UUID="research" Type="ResearchFolder"><Children>
            <BinderItem UUID="secret" Type="Text"/>
          </Children></BinderItem>
          <BinderItem UUID="trash" Type="TrashFolder"/>
        </Binder></ScrivenerProject>
        """.utf8)
        XCTAssertEqual(try XCTUnwrap(ScrivenerDraftParser().parse(xml)), ["scene-1", "scene-2"])
    }

    func testScrivenerParserRejectsUnsafeBinderPathComponents() throws {
        let xml = Data("""
        <ScrivenerProject><Binder>
          <BinderItem UUID="draft" Type="DraftFolder"><Children>
            <BinderItem UUID="../../outside" Type="Text"/>
            <BinderItem UUID="safe_scene-1" Type="Text"/>
          </Children></BinderItem>
        </Binder></ScrivenerProject>
        """.utf8)
        XCTAssertEqual(try XCTUnwrap(ScrivenerDraftParser().parse(xml)), ["safe_scene-1"])
    }
}
