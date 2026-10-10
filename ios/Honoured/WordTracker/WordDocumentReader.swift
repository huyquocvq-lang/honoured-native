import Foundation
import UIKit
import ZIPFoundation

/// One coordinated snapshot of a source: its count, and when the counted
/// content last changed. Neither carries any manuscript text.
struct WordSourceReading: Equatable {
    let count: Int
    /// The newest modification date among the files the count read; nil when
    /// the provider reports none.
    let modifiedAt: Date?
}

/// Reads a coordinated snapshot and returns only a count and a date. No
/// adapter exposes manuscript text outside this file and no failure includes a
/// path or title.
enum WordDocumentReader {
    static let maximumSourceBytes: Int64 = 100 * 1024 * 1024
    static let maximumExpandedBytes: UInt32 = 32 * 1024 * 1024

    static func count(url: URL, kind: WordSourceKind) throws -> Int {
        try read(url: url, kind: kind).count
    }

    static func read(url: URL, kind: WordSourceKind) throws -> WordSourceReading {
        var coordinatorError: NSError?
        var result: Result<WordSourceReading, Error>?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinatorError) { safeURL in
            result = Result { try readCoordinated(url: safeURL, kind: kind) }
        }
        if coordinatorError != nil { throw WordSourceError.providerUnavailable }
        guard let result else { throw WordSourceError.providerUnavailable }
        return try result.get()
    }

    private static func readCoordinated(url: URL, kind: WordSourceKind) throws -> WordSourceReading {
        switch kind {
        case .text:
            let data = try boundedData(url)
            guard let text = WordSourceSupport.decodePlainText(data) else {
                throw WordSourceError.malformedDocument
            }
            return WordSourceReading(count: WordCount.count(text), modifiedAt: newestModification([url]))
        case .richText:
            let data = try boundedData(url)
            let value = try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            return WordSourceReading(count: WordCount.count(value.string), modifiedAt: newestModification([url]))
        case .richTextDirectory:
            // Attachments load with the text, so the whole package is bounded.
            let files = try packageFiles(url)
            let value = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.rtfd],
                documentAttributes: nil
            )
            return WordSourceReading(count: WordCount.count(value.string), modifiedAt: newestModification(files))
        case .word:
            return WordSourceReading(count: try countWord(url), modifiedAt: newestModification([url]))
        case .scrivener:
            let (count, files) = try countScrivener(url)
            return WordSourceReading(count: count, modifiedAt: newestModification(files))
        }
    }

    private static func newestModification(_ files: [URL]) -> Date? {
        files.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }.max()
    }

    private static func boundedData(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw WordSourceError.malformedDocument }
        if let size = values.fileSize, Int64(size) > maximumSourceBytes { throw WordSourceError.documentTooLarge }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    /// The package's regular files, refusing a package over the size bound.
    private static func packageFiles(_ root: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else {
            throw WordSourceError.malformedDocument
        }
        var files: [URL] = []
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
            if total > maximumSourceBytes { throw WordSourceError.documentTooLarge }
            files.append(file)
        }
        return files
    }

    private static func countWord(_ url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw WordSourceError.malformedDocument }
        if let size = values.fileSize, Int64(size) > maximumSourceBytes { throw WordSourceError.documentTooLarge }
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw WordSourceError.malformedDocument
        }
        guard let entry = archive["word/document.xml"],
              entry.type == .file,
              entry.uncompressedSize <= maximumExpandedBytes else {
            throw WordSourceError.malformedDocument
        }
        var xml = Data()
        xml.reserveCapacity(Int(entry.uncompressedSize))
        do {
            _ = try archive.extract(entry, bufferSize: 32 * 1024) { chunk in
                guard xml.count + chunk.count <= Int(maximumExpandedBytes) else {
                    throw WordSourceError.documentTooLarge
                }
                xml.append(chunk)
            }
        } catch let error as WordSourceError {
            throw error
        } catch {
            // A bad CRC, truncated entry or unsupported compression.
            throw WordSourceError.malformedDocument
        }
        guard let text = SelectedXMLTextParser.word().parse(xml) else {
            throw WordSourceError.malformedDocument
        }
        return WordCount.count(text)
    }

    /// The Draft total, and the files it was read from: the binder, which
    /// decides what is in the Draft, and each counted document.
    private static func countScrivener(_ root: URL) throws -> (count: Int, files: [URL]) {
        let values = try root.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw WordSourceError.malformedDocument }
        let project = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        ).first { $0.pathExtension.lowercased() == "scrivx" }
        guard let project else { throw WordSourceError.malformedDocument }
        let binderData = try boundedData(project)
        guard let ids = ScrivenerDraftParser().parse(binderData), !ids.isEmpty else {
            throw WordSourceError.malformedDocument
        }
        let dataRoot = root.appendingPathComponent("Files/Data", isDirectory: true)
        var total = 0
        var files = [project]
        for id in ids {
            let folder = dataRoot.appendingPathComponent(id, isDirectory: true)
            let candidates = ["content.rtf", "content.txt"]
            for name in candidates {
                let file = folder.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: file.path) else { continue }
                files.append(file)
                if name.hasSuffix(".rtf") {
                    let value = try NSAttributedString(
                        data: boundedData(file),
                        options: [.documentType: NSAttributedString.DocumentType.rtf],
                        documentAttributes: nil
                    )
                    total += WordCount.count(value.string)
                } else if let text = WordSourceSupport.decodePlainText(try boundedData(file)) {
                    total += WordCount.count(text)
                }
                break
            }
        }
        return (total, files)
    }
}

/// Collects binder UUIDs strictly below the first Scrivener 3 Draft folder.
/// Research, Trash and snapshots live outside that subtree and are excluded.
final class ScrivenerDraftParser: NSObject, XMLParserDelegate {
    private var itemStack: [(id: String?, inDraft: Bool)] = []
    private var result: [String] = []
    private var foundDraft = false
    private var failed = false

    func parse(_ data: Data) -> [String]? {
        itemStack.removeAll(keepingCapacity: true)
        result.removeAll(keepingCapacity: true)
        foundDraft = false
        failed = false
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !failed, foundDraft else { return nil }
        return result
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?, qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "BinderItem" else { return }
        let type = attributeDict["Type"]?.lowercased()
        let parentInDraft = itemStack.last?.inDraft ?? false
        let startsDraft = !foundDraft && type == "draftfolder"
        if startsDraft { foundDraft = true }
        let inDraft = parentInDraft || startsDraft
        let rawId = attributeDict["UUID"]
        // Binder IDs become directory components below Files/Data. Scrivener
        // normally emits UUIDs, but rejecting separators/dot components also
        // prevents a crafted project from escaping its package directory.
        let id = rawId.flatMap(Self.safeBinderId)
        itemStack.append((id, inDraft))
        if parentInDraft, let id, type != "folder", type != "draftfolder" { result.append(id) }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?, qualifiedName qName: String?
    ) {
        if elementName == "BinderItem", !itemStack.isEmpty { itemStack.removeLast() }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) { failed = true }
    func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
        failed = true
        parser.abortParsing()
        return nil
    }

    private static func safeBinderId(_ value: String) -> String? {
        guard !value.isEmpty, value.count <= 128,
              value != ".", value != "..",
              !value.contains("/"), !value.contains("\\"),
              value.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_"
              }) else { return nil }
        return value
    }
}
