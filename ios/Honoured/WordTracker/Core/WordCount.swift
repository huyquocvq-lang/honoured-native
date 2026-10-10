import Foundation

/// One deterministic word rule for every M3 document adapter. It deliberately
/// does not depend on the device language:
/// - letters and numbers form a word, together with the combining marks that
///   follow them (Hindi vowel signs, Arabic vowel marks, decomposed accents);
/// - an internal apostrophe or hyphen keeps the pieces together, and so does
///   a `.`, `,` or `:` between digits (`1,000`, `3.14`, `10:30`);
/// - Chinese and Japanese are written without spaces, so each Han, Hiragana or
///   Katakana character counts as one word, as in Microsoft Word.
enum WordCount {
    private static let cjk = #"\p{Han}\p{Hiragana}\p{Katakana}"#
    private static let start = #"[[\p{L}\p{N}]--["# + cjk + #"]]"#
    private static let rest = #"[[\p{L}\p{M}\p{N}]--["# + cjk + #"]]"#
    private static let expression = try! NSRegularExpression(
        pattern: "[" + cjk + "]|" + start + rest + "*(?:['’\\-]" + start + rest + "*|(?<=\\p{N})[.,:](?=\\p{N})" + rest + "+)*",
        options: []
    )

    static func count(_ text: String) -> Int {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.numberOfMatches(in: text, range: range)
    }
}

enum WordSourceKind: String, Codable, CaseIterable {
    case word
    case text
    case richText = "rich_text"
    case richTextDirectory = "rich_text_directory"
    case scrivener
}

enum WordSourceError: String, Error, Equatable {
    case unsupportedType = "unsupported_type"
    case permissionDenied = "permission_denied"
    case missing
    case sourceMismatch = "source_mismatch"
    case malformedDocument = "malformed_document"
    case providerUnavailable = "provider_unavailable"
    case documentTooLarge = "document_too_large"
}
