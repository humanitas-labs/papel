import Foundation

/// Inline Markdown emphasis as a toggle over a range of source text. Pure:
/// computes the edit, never touches a view, so the cases are testable.
enum InlineFormat: CaseIterable {
    case bold, italic, underline, strikethrough, code

    var open: String {
        switch self {
        case .bold: "**"
        case .italic: "*"
        case .underline: "<u>"
        case .strikethrough: "~~"
        case .code: "`"
        }
    }

    var close: String {
        switch self {
        case .underline: "</u>"
        default: open
        }
    }

    /// Delimiter pairs the toggle recognises and removes but never writes:
    /// the CommonMark underscore spellings of bold and italic.
    var alternates: [(open: String, close: String)] {
        switch self {
        case .bold: [("__", "__")]
        case .italic: [("_", "_")]
        default: []
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
        for pair in [(open: open, close: close)] + alternates {
            let openLength = pair.open.utf16.count
            let closeLength = pair.close.utf16.count

            // Delimiters just outside the range: unwrap.
            let before = NSRange(location: range.location - openLength, length: openLength)
            let after = NSRange(location: NSMaxRange(range), length: closeLength)
            if before.location >= 0, NSMaxRange(after) <= text.length,
               text.substring(with: before) == pair.open, text.substring(with: after) == pair.close,
               !isPartOfLongerRun(pair.open, before: before, after: after, in: text) {
                let inner = text.substring(with: range)
                return (NSUnionRange(before, after), inner, NSRange(location: before.location, length: range.length))
            }
            // Delimiters at the edges of the range: unwrap.
            if range.length >= openLength + closeLength {
                let selected = text.substring(with: range)
                if selected.hasPrefix(pair.open), selected.hasSuffix(pair.close) {
                    let inner = String(selected.dropFirst(pair.open.count).dropLast(pair.close.count))
                    if !isPartOfLongerRun(
                        pair.open,
                        before: NSRange(location: range.location, length: openLength),
                        after: NSRange(location: NSMaxRange(range) - closeLength, length: closeLength),
                        in: text
                    ) {
                        return (range, inner, NSRange(location: range.location, length: inner.utf16.count))
                    }
                }
            }
        }
        // Otherwise wrap.
        let inner = text.substring(with: range)
        return (range, open + inner + close, NSRange(location: range.location + open.utf16.count, length: range.length))
    }

    /// A single `*` (or `_`) inside a run of exactly two on each side
    /// belongs to a bold pair, so italic must not strip one from `**word**`
    /// or `__word__`; runs of one or three (`***word***`) do carry an
    /// italic delimiter.
    private func isPartOfLongerRun(_ delimiter: String, before: NSRange, after: NSRange, in text: NSString) -> Bool {
        guard self == .italic, let mark = delimiter.utf16.first else { return false }
        var leading = 0
        var index = NSMaxRange(before) - 1
        while index >= 0, text.character(at: index) == mark { leading += 1; index -= 1 }
        var trailing = 0
        index = after.location
        while index < text.length, text.character(at: index) == mark { trailing += 1; index += 1 }
        return leading == 2 && trailing == 2
    }

    /// The run of word characters around `location`; empty when the caret
    /// is not touching a word. An underscore inside a word is part of it
    /// (`snake_case`); a run of them at either end is a delimiter
    /// (`_word_`, `__word__`) and is left outside.
    static func wordRange(at location: Int, in text: NSString) -> NSRange {
        let word = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'’_"))
        let underscore = "_".utf16.first!
        func isWord(_ index: Int) -> Bool {
            guard index >= 0, index < text.length, let scalar = Unicode.Scalar(text.character(at: index)) else { return false }
            return word.contains(scalar)
        }
        var start = location
        while isWord(start - 1) { start -= 1 }
        var end = location
        while isWord(end) { end += 1 }
        while start < end, text.character(at: start) == underscore { start += 1 }
        while end > start, text.character(at: end - 1) == underscore { end -= 1 }
        return NSRange(location: start, length: end - start)
    }
}
