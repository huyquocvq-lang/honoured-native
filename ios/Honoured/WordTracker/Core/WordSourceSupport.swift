import Foundation

enum WordSourceSupport {
    static let supportedExtensions = ["docx", "txt", "rtf", "rtfd", "scriv"]

    /// The opaque id shape the server accepts (`contracts_word_source_id_opaque`).
    static func isValidSourceId(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 128 && value.unicodeScalars.allSatisfy {
            ($0.isASCII && CharacterSet.alphanumerics.contains($0)) || $0 == "-" || $0 == "_"
        }
    }

    /// Maps a file-system failure to a code that is safe to send to the page;
    /// anything unrecognised stays generic so no path or message leaks out.
    static func safeError(_ error: Error) -> WordSourceError {
        if let error = error as? WordSourceError { return error }
        guard let cocoa = error as? CocoaError else { return .providerUnavailable }
        switch cocoa.code {
        case .fileNoSuchFile, .fileReadNoSuchFile:
            return .missing
        case .fileReadNoPermission:
            return .permissionDenied
        case .fileReadCorruptFile, .fileReadInapplicableStringEncoding, .fileReadUnknownStringEncoding:
            return .malformedDocument
        case .fileReadTooLarge:
            return .documentTooLarge
        default:
            return .providerUnavailable
        }
    }

    static func kind(fileExtension: String, isDirectory: Bool) -> WordSourceKind? {
        switch fileExtension.lowercased() {
        case "docx" where !isDirectory: return .word
        case "txt" where !isDirectory: return .text
        case "rtf" where !isDirectory: return .richText
        case "rtfd" where isDirectory: return .richTextDirectory
        case "scriv" where isDirectory: return .scrivener
        default: return nil
        }
    }

    static func decodePlainText(_ data: Data) -> String? {
        if let value = String(data: data, encoding: .utf8) { return value }
        if data.starts(with: [0xFE, 0xFF]), let value = String(data: data, encoding: .utf16BigEndian) { return value }
        if data.starts(with: [0xFF, 0xFE]), let value = String(data: data, encoding: .utf16LittleEndian) { return value }
        // TextEdit can produce BOM-less UTF-16. ASCII-range text has its zero
        // bytes predominantly on one side, which lets us choose without first
        // mis-decoding little-endian data as generic UTF-16.
        let sample = data.prefix(256)
        let evenZeros = sample.enumerated().filter { $0.offset.isMultiple(of: 2) && $0.element == 0 }.count
        let oddZeros = sample.enumerated().filter { !$0.offset.isMultiple(of: 2) && $0.element == 0 }.count
        if oddZeros > evenZeros * 2, let value = String(data: data, encoding: .utf16LittleEndian) { return value }
        if evenZeros > oddZeros * 2, let value = String(data: data, encoding: .utf16BigEndian) { return value }
        if let value = String(data: data, encoding: .utf16LittleEndian) { return value }
        if let value = String(data: data, encoding: .utf16BigEndian) { return value }
        return nil
    }
}

/// Extracts visible text from XML elements without using regex against XML.
///
/// Text inside selected elements is joined as written: Word splits one word
/// across several `w:t` runs (formatting, revisions) and the parser reports
/// entities such as `&apos;` as separate pieces, so a separator between
/// pieces would invent words. Words are separated only where a break element
/// (paragraph, tab, line break) starts or ends. Skipped subtrees are ignored.
final class SelectedXMLTextParser: NSObject, XMLParserDelegate {
    private let selectedNames: Set<String>
    private let breakNames: Set<String>
    private let skippedNames: Set<String>
    private var depth = 0
    private var skipDepth = 0
    private var text = ""
    private(set) var failed = false

    init(selectedNames: Set<String>, breakNames: Set<String> = [], skippedNames: Set<String> = []) {
        self.selectedNames = selectedNames
        self.breakNames = breakNames
        self.skippedNames = skippedNames
    }

    /// `word/document.xml`: `w:t` text, broken at paragraphs, tabs and line
    /// breaks. `mc:Fallback` repeats a text box's content for old readers.
    static func word() -> SelectedXMLTextParser {
        SelectedXMLTextParser(selectedNames: ["t"], breakNames: ["p", "tab", "br", "cr"], skippedNames: ["Fallback"])
    }

    func parse(_ data: Data) -> String? {
        depth = 0
        skipDepth = 0
        text = ""
        failed = false
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !failed else { return nil }
        return text
    }

    private static func localName(_ elementName: String) -> String {
        elementName.split(separator: ":").last.map(String.init) ?? elementName
    }

    private func matches(_ names: Set<String>, _ elementName: String) -> Bool {
        names.contains(elementName) || names.contains(Self.localName(elementName))
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if matches(skippedNames, elementName) { skipDepth += 1 }
        if matches(breakNames, elementName) { text.append("\n") }
        if matches(selectedNames, elementName) { depth += 1 }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if depth > 0, skipDepth == 0 { text.append(string) }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if matches(selectedNames, elementName) { depth = max(depth - 1, 0) }
        if matches(breakNames, elementName) { text.append("\n") }
        if matches(skippedNames, elementName) { skipDepth = max(skipDepth - 1, 0) }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        failed = true
    }

    func parser(
        _ parser: XMLParser,
        resolveExternalEntityName name: String,
        systemID: String?
    ) -> Data? {
        failed = true
        parser.abortParsing()
        return nil
    }
}
