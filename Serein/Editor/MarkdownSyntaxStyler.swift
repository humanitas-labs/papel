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
    private static let listMarkerPattern = try! NSRegularExpression(
        pattern: #"(?m)^(?:[\t ]*(?:>[\t ]?)*)([-+*]|\d+[.)])[\t ]+(?=\S)"#
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
            // Kerning on the marker widens the gap to the text without a
            // source change; the hanging indent accounts for it below.
            storage.addAttribute(.kern, value: Appearance.letterSpacing + Appearance.listMarkerGap, range: markerRange)

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
                storage.addAttribute(
                    .paragraphStyle,
                    value: Appearance.hangingParagraphStyle(
                        under: String(rendered), indent: Appearance.listIndent, gap: Appearance.listMarkerGap
                    ),
                    range: paragraphRange
                )
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
            }
            // Quote text sits on the margin. Consecutive quote lines (a
            // hard-wrapped quote) keep only line spacing between them so
            // they read as one block under one rule.
            let paragraphRange = (source as NSString).paragraphRange(for: match.range)
            let next = NSMaxRange(paragraphRange)
            let continues = next < range.length
                && Self.blockQuotePattern.firstMatch(in: source, range: NSRange(location: next, length: range.length - next))?.range.location == next
            storage.addAttribute(
                .paragraphStyle,
                value: Appearance.paragraphStyle(spacing: continues ? 0 : nil),
                range: match.range
            )
            // Include the trailing newline so consecutive quote lines form one
            // run and draw a single unbroken rule.
            storage.addAttribute(.blockQuote, value: true, range: paragraphRange)
        }
    }

    /// Delimiters are dimmed and, off the active paragraph, concealed; the
    /// styled content between them stays.
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

