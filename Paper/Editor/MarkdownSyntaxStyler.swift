import AppKit

@MainActor
final class MarkdownSyntaxStyler {
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: Appearance.bodyFont(),
            .foregroundColor: Appearance.ink,
            .paragraphStyle: Appearance.paragraphStyle(),
            .kern: Appearance.letterSpacing,
        ]
    }

    private static let headingPattern = try! NSRegularExpression(
        pattern: #"(?m)^(#{1,6})[\t ]+(.+)$"#
    )
    private static let strongPattern = try! NSRegularExpression(
        pattern: #"\*\*([^*\n]+)\*\*"#
    )
    private static let emphasisPattern = try! NSRegularExpression(
        pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#
    )
    private static let codePattern = try! NSRegularExpression(
        pattern: #"`([^`\n]+)`"#
    )
    /// `[text](destination)`; an image (`![…]`) is left alone.
    private static let linkPattern = try! NSRegularExpression(
        pattern: #"(?<!!)\[([^\]\n]+)\]\(([^)\s]+)\)"#
    )
    /// Markdown has no underline syntax; `<u>…</u>` is the portable form.
    private static let underlinePattern = try! NSRegularExpression(
        pattern: #"<u>([^<\n]+)</u>"#
    )
    private static let listMarkerPattern = try! NSRegularExpression(
        pattern: #"(?m)^(?:[\t ]*(?:>[\t ]?)*)([-+*]|\d+[A-Za-z]?[.)])[\t ]+(?=\S)"#
    )

    /// Unordered markers render as Apple Notes' two list kinds: `-` as a
    /// dashed list, `*` and `+` as a bulleted one.
    static func renderedListMarker(for source: String) -> String? {
        switch source {
        case "-": "–"
        case "*", "+": "•"
        default: nil
        }
    }
    private static let blockQuotePattern = try! NSRegularExpression(
        pattern: #"(?m)^([\t ]*(?:>[\t ]?)+)(.*)$"#
    )

    func apply(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }

        let source = storage.string
        let fullRange = NSRange(location: 0, length: source.utf16.count)
        let selection = textView.selectedRange()

        storage.beginEditing()
        storage.setAttributes(Self.baseAttributes, range: fullRange)
        applyHeadings(to: storage, source: source, range: fullRange)
        applyBlockQuotes(to: storage, source: source, range: fullRange)
        applyDelimitedStyle(
            Self.strongPattern,
            trait: .bold,
            to: storage,
            source: source,
            range: fullRange
        )
        applyDelimitedStyle(
            Self.emphasisPattern,
            trait: .italic,
            to: storage,
            source: source,
            range: fullRange
        )
        applyInlineCode(to: storage, source: source, range: fullRange)
        applyUnderline(to: storage, source: source, range: fullRange)
        applyLinks(to: storage, source: source, range: fullRange)
        applyListMarkers(to: storage, source: source, range: fullRange)
        storage.endEditing()

        textView.typingAttributes = Self.baseAttributes
        textView.setSelectedRange(selection)
    }

    private func applyHeadings(
        to storage: NSTextStorage,
        source: String,
        range: NSRange
    ) {
        Self.headingPattern.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match else { return }

            let markerRange = match.range(at: 1)
            let contentRange = match.range(at: 2)
            let size = Appearance.headingSize(level: markerRange.length)

            storage.addAttribute(.foregroundColor, value: Appearance.mutedInk, range: markerRange)
            storage.addAttribute(.font, value: Appearance.headingFont(size: size), range: contentRange)
            // The marker and the whitespace up to the content vanish together
            // when the selection leaves the paragraph, so the heading text sits
            // on the margin.
            storage.addAttribute(
                .concealable,
                value: true,
                range: NSRange(location: markerRange.location, length: contentRange.location - markerRange.location)
            )
        }
    }

    /// Adds a symbolic trait to whatever font already covers the content so
    /// bold and italic compose with each other and with block-quote italics.
    private func applyDelimitedStyle(
        _ pattern: NSRegularExpression,
        trait: NSFontDescriptor.SymbolicTraits,
        to storage: NSTextStorage,
        source: String,
        range: NSRange
    ) {
        pattern.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match else { return }
            let contentRange = match.range(at: 1)

            storage.enumerateAttribute(.font, in: contentRange) { value, fontRange, _ in
                let current = (value as? NSFont) ?? Appearance.bodyFont()
                let descriptor = current.fontDescriptor.withSymbolicTraits(
                    current.fontDescriptor.symbolicTraits.union(trait)
                )
                let font = NSFont(descriptor: descriptor, size: current.pointSize) ?? current
                storage.addAttribute(.font, value: font, range: fontRange)
            }
            dimDelimiters(around: contentRange, in: match.range, storage: storage)
        }
    }

    private func applyInlineCode(
        to storage: NSTextStorage,
        source: String,
        range: NSRange
    ) {
        Self.codePattern.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match else { return }

            let contentRange = match.range(at: 1)
            storage.addAttribute(
                .font,
                value: Appearance.codeFont(),
                range: contentRange
            )
            dimDelimiters(around: contentRange, in: match.range, storage: storage)
        }
    }

    private func applyListMarkers(
        to storage: NSTextStorage,
        source: String,
        range: NSRange
    ) {
        Self.listMarkerPattern.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match else { return }
            let markerRange = match.range(at: 1)
            let prefix = (source as NSString).substring(with: match.range)
            let marker = (source as NSString).substring(with: markerRange)
            storage.addAttribute(.foregroundColor, value: Appearance.mutedInk, range: markerRange)
            // Kerning after the marker's last character widens the gap to
            // the text without a source change; the hanging indent accounts
            // for it below. Kern is per glyph, so an ordered marker like
            // `1.` gets it only after the period, not between its glyphs.
            storage.addAttribute(
                .kern, value: Appearance.letterSpacing + Appearance.listMarkerGap,
                range: NSRange(location: NSMaxRange(markerRange) - 1, length: 1)
            )

            var rendered = Array(prefix)
            if let symbol = Self.renderedListMarker(for: marker) {
                storage.addAttribute(.listMarker, value: symbol, range: markerRange)
                storage.addAttribute(.font, value: Appearance.markerFont(for: symbol), range: markerRange)
                // The prefix is ASCII, so UTF-16 and Character offsets agree.
                rendered[markerRange.location - match.range.location] = Character(symbol)
            }
            // Wrapped lines hang under the item's text, measured from the
            // prefix as it renders. Quote lines keep their own style, which
            // already hangs under the quote marker.
            let paragraphRange = (source as NSString).paragraphRange(for: match.range)
            if storage.attribute(.blockQuote, at: match.range.location, effectiveRange: nil) == nil {
                // Non-blank lines that follow without a marker of their own
                // are lazy continuations of the item (a hard-wrapped item);
                // they align under the item's text with no spacing between.
                let continuations = Self.continuationParagraphs(after: paragraphRange, in: source, limit: range.length)
                let itemStyle = Appearance.hangingParagraphStyle(
                    under: String(rendered), indent: Appearance.listIndent, gap: Appearance.listMarkerGap,
                    spacing: continuations.isEmpty ? nil : 0
                )
                storage.addAttribute(.paragraphStyle, value: itemStyle, range: paragraphRange)
                for (index, continuation) in continuations.enumerated() {
                    storage.addAttribute(
                        .paragraphStyle,
                        value: Appearance.flushParagraphStyle(
                            indent: itemStyle.headIndent, spacing: index == continuations.count - 1 ? nil : 0
                        ),
                        range: continuation
                    )
                    // Source that hard-wraps under the marker indents the
                    // continuation with spaces; the paragraph already sits
                    // under the text, so that whitespace is concealed off the
                    // active paragraph rather than rendered on top.
                    let leading = Self.leadingWhitespace(of: continuation, in: source)
                    if leading.length > 0 {
                        storage.addAttribute(.concealable, value: true, range: leading)
                    }
                }
            }
        }
    }

    private func applyBlockQuotes(
        to storage: NSTextStorage,
        source: String,
        range: NSRange
    ) {
        Self.blockQuotePattern.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match else { return }
            let markerRange = match.range(at: 1)
            let contentRange = match.range(at: 2)

            storage.addAttribute(.foregroundColor, value: Appearance.mutedInk, range: markerRange)
            // The whole marker group (`>`, nested `> >`, and their spaces)
            // hides off the active paragraph; the margin rule is the cue.
            storage.addAttribute(.concealable, value: true, range: markerRange)
            if contentRange.length > 0 {
                storage.addAttribute(.font, value: Appearance.italicFont(), range: contentRange)
                storage.addAttribute(.foregroundColor, value: Appearance.quoteInk, range: contentRange)
            }
            // Quote text is inset so the rule stands on the text margin.
            // Consecutive quote lines (a hard-wrapped quote) keep only line
            // spacing between them so they read as one block under one rule.
            let paragraphRange = (source as NSString).paragraphRange(for: match.range)
            let next = NSMaxRange(paragraphRange)
            let continues = next < range.length
                && Self.blockQuotePattern.firstMatch(in: source, range: NSRange(location: next, length: range.length - next))?.range.location == next
            storage.addAttribute(
                .paragraphStyle,
                value: Appearance.flushParagraphStyle(indent: Appearance.quoteIndent, spacing: continues ? 0 : nil),
                range: match.range
            )
            // Include the trailing newline so consecutive quote lines form one
            // run and draw a single unbroken rule.
            storage.addAttribute(.blockQuote, value: true, range: paragraphRange)
        }
    }

    /// Paragraph ranges following `paragraphRange` that continue a list item:
    /// non-blank and not starting a list item, heading, or block quote.
    private static func continuationParagraphs(after paragraphRange: NSRange, in source: String, limit: Int) -> [NSRange] {
        let text = source as NSString
        var found: [NSRange] = []
        var cursor = NSMaxRange(paragraphRange)
        while cursor < limit {
            let paragraph = text.paragraphRange(for: NSRange(location: cursor, length: 0))
            let line = text.substring(with: paragraph)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !startsBlock(line) else { break }
            found.append(paragraph)
            cursor = NSMaxRange(paragraph)
        }
        return found
    }

    private static func leadingWhitespace(of paragraph: NSRange, in source: String) -> NSRange {
        let text = source as NSString
        var end = paragraph.location
        while end < NSMaxRange(paragraph), [0x20, 0x09].contains(text.character(at: end)) { end += 1 }
        return NSRange(location: paragraph.location, length: end - paragraph.location)
    }

    private static func startsBlock(_ line: String) -> Bool {
        let range = NSRange(location: 0, length: line.utf16.count)
        return [listMarkerPattern, headingPattern, blockQuotePattern].contains {
            $0.firstMatch(in: line, range: range)?.range.location == 0
        }
    }

    /// Delimiters are dimmed and, off the active paragraph, concealed; the
    /// styled content between them stays.
    private func applyUnderline(
        to storage: NSTextStorage,
        source: String,
        range: NSRange
    ) {
        Self.underlinePattern.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match else { return }
            let contentRange = match.range(at: 1)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            dimDelimiters(around: contentRange, in: match.range, storage: storage)
        }
    }

    private func applyLinks(
        to storage: NSTextStorage,
        source: String,
        range: NSRange
    ) {
        Self.linkPattern.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match else { return }
            let textRange = match.range(at: 1)
            let destination = (source as NSString).substring(with: match.range(at: 2))
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
            storage.addAttribute(.linkDestination, value: destination, range: textRange)
            // `[` and `](destination)` hide off the active paragraph.
            dimDelimiters(around: textRange, in: match.range, storage: storage)
        }
    }

    private func dimDelimiters(
        around contentRange: NSRange,
        in matchRange: NSRange,
        storage: NSTextStorage
    ) {
        let prefixLength = contentRange.location - matchRange.location
        let suffixLocation = NSMaxRange(contentRange)
        let suffixLength = NSMaxRange(matchRange) - suffixLocation

        for range in [
            NSRange(location: matchRange.location, length: prefixLength),
            NSRange(location: suffixLocation, length: suffixLength),
        ] {
            storage.addAttribute(.foregroundColor, value: Appearance.mutedInk, range: range)
            storage.addAttribute(.concealable, value: true, range: range)
        }
    }
}

