import Foundation

/// Which flagged spellings are worth an underline. The checker marks any
/// token it does not know, and a document about software is full of
/// tokens that are not words: commit hashes, versions, hex colours,
/// paths, identifiers, acronyms. Those are dropped by shape; a plain
/// misspelling keeps its mark. Grammar results are never filtered here.
enum SpellCheckFilter {
    /// Whether a spelling mark on `range` should stand. The flagged token
    /// is judged together with the run of non-space characters around it,
    /// so `buld` inside `docs/buld.md` and `ae103` inside `(50ae103)` go
    /// with their neighbours.
    static func keepsMark(at range: NSRange, in text: NSString) -> Bool {
        let clipped = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        guard clipped.length > 0 else { return false }
        let token = text.substring(with: clipped)
        // Only single tokens are judged by shape; a range spanning words
        // is someone else's mark.
        guard !token.contains(where: \.isWhitespace) else { return true }
        let run = text.substring(with: run(around: clipped, in: text))
        return isProse(token: token, run: run)
    }

    /// The run containing `range`: out to whitespace, a bracket, or a
    /// quote on either side (so link text stops at `](`), with trailing
    /// commas and stops trimmed.
    static func run(around range: NSRange, in text: NSString) -> NSRange {
        var start = range.location
        while start > 0, !isBoundary(text.character(at: start - 1)) { start -= 1 }
        var end = NSMaxRange(range)
        while end < text.length, !isBoundary(text.character(at: end)) { end += 1 }
        while start < end, trailing.contains(text.character(at: start)) { start += 1 }
        while end > start, trailing.contains(text.character(at: end - 1)) { end -= 1 }
        // Never trim into the token itself.
        start = min(start, range.location)
        end = max(end, NSMaxRange(range))
        return NSRange(location: start, length: end - start)
    }

    static func isProse(token: String, run: String) -> Bool {
        if run.contains(where: \.isNumber) { return false }
        if run.contains(where: { "/_@\\".contains($0) }) { return false }
        if isHexColor(run) { return false }
        let letters = token.filter(\.isLetter)
        if letters.count >= 3, letters == letters.uppercased(), token.allSatisfy({ $0.isLetter || $0 == "-" || $0 == "'" }) {
            return false
        }
        return true
    }

    private static func isHexColor(_ run: String) -> Bool {
        guard run.hasPrefix("#"), (4...9).contains(run.count) else { return false }
        return run.dropFirst().allSatisfy(\.isHexDigit)
    }

    private static let boundaries: Set<unichar> = Set("()[]{}<>\"'“”‘’ \t\n\r\u{A0}".utf16)
    private static let trailing: Set<unichar> = Set(",.;:!?".utf16)

    private static func isBoundary(_ character: unichar) -> Bool {
        boundaries.contains(character)
    }
}
