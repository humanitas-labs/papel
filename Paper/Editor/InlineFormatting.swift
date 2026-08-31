import Foundation

/// Inline Markdown emphasis as a toggle over a range of source text. Pure:
/// computes the edit, never touches a view, so the cases are testable.
enum InlineFormat: CaseIterable {
    case bold, italic, underline, code

    var open: String {
        switch self {
        case .bold: "**"
        case .italic: "*"
        case .underline: "<u>"
        case .code: "`"
        }
    }

    var close: String {
        switch self {
        case .underline: "</u>"
        default: open
        }
    }

    /// The single edit that toggles the format at `selection`: the range to
    /// replace, its replacement, and the selection afterwards (in the edited
    /// text). A caret takes the word under it; a caret in whitespace inserts
    /// an empty pair and sits between its delimiters.
    func toggle(in text: NSString, selection: NSRange) -> (range: NSRange, replacement: String, selection: NSRange) {
        var range = selection
        if range.length == 0 { range = Self.wordRange(at: range.location, in: text) }
        if range.length == 0 {
            return (range, open + close, NSRange(location: range.location + open.utf16.count, length: 0))
        }
        let openLength = open.utf16.count
        let closeLength = close.utf16.count

        // Delimiters just outside the range: unwrap.
        let before = NSRange(location: range.location - openLength, length: openLength)
        let after = NSRange(location: NSMaxRange(range), length: closeLength)
        if before.location >= 0, NSMaxRange(after) <= text.length,
           text.substring(with: before) == open, text.substring(with: after) == close,
           !isPartOfLongerRun(before: before, after: after, in: text) {
            let inner = text.substring(with: range)
            return (NSUnionRange(before, after), inner, NSRange(location: before.location, length: range.length))
        }
        // Delimiters at the edges of the range: unwrap.
        if range.length >= openLength + closeLength {
            let selected = text.substring(with: range)
            if selected.hasPrefix(open), selected.hasSuffix(close) {
                let inner = String(selected.dropFirst(open.count).dropLast(close.count))
                if !isPartOfLongerRun(
                    before: NSRange(location: range.location, length: openLength),
                    after: NSRange(location: NSMaxRange(range) - closeLength, length: closeLength),
                    in: text
                ) {
                    return (range, inner, NSRange(location: range.location, length: inner.utf16.count))
                }
            }
        }
        // Otherwise wrap.
        let inner = text.substring(with: range)
        return (range, open + inner + close, NSRange(location: range.location + openLength, length: range.length))
    }

    /// A single `*` inside a run of exactly two on each side belongs to a
    /// bold pair, so italic must not strip one star from `**word**`; runs
    /// of one or three (`***word***`) do carry an italic star.
    private func isPartOfLongerRun(before: NSRange, after: NSRange, in text: NSString) -> Bool {
        guard self == .italic else { return false }
        let star = "*".utf16.first!
        var leading = 0
        var index = NSMaxRange(before) - 1
        while index >= 0, text.character(at: index) == star { leading += 1; index -= 1 }
        var trailing = 0
        index = after.location
        while index < text.length, text.character(at: index) == star { trailing += 1; index += 1 }
        return leading == 2 && trailing == 2
    }

    /// The run of word characters around `location`; empty when the caret
    /// is not touching a word.
    static func wordRange(at location: Int, in text: NSString) -> NSRange {
        let word = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'’_"))
        func isWord(_ index: Int) -> Bool {
            guard index >= 0, index < text.length, let scalar = Unicode.Scalar(text.character(at: index)) else { return false }
            return word.contains(scalar)
        }
        var start = location
        while isWord(start - 1) { start -= 1 }
        var end = location
        while isWord(end) { end += 1 }
        return NSRange(location: start, length: end - start)
    }
}
