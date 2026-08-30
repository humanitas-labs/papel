import AppKit

@MainActor
final class MarkdownSyntaxStyler {
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: Appearance.bodyFont(),
            .foregroundColor: Appearance.ink,
            .paragraphStyle: Appearance.paragraphStyle(),
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
        pattern: #"(?m)^[\t ]*(?:[-+*]|\d+[.)])[\t ]+"#
    )
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
            storage.addAttribute(.foregroundColor, value: Appearance.mutedInk, range: match.range)
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
            if contentRange.length > 0 {
                storage.addAttribute(.font, value: Appearance.italicFont(), range: contentRange)
            }
            let marker = (source as NSString).substring(with: markerRange)
            storage.addAttribute(
                .paragraphStyle,
                value: Appearance.quoteParagraphStyle(hangingUnder: marker),
                range: match.range
            )
            // Include the trailing newline so consecutive quote lines form one
            // run and draw a single unbroken rule.
            let paragraphRange = (source as NSString).paragraphRange(for: match.range)
            storage.addAttribute(.blockQuote, value: true, range: paragraphRange)
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

        storage.addAttribute(
            .foregroundColor,
            value: Appearance.mutedInk,
            range: NSRange(location: matchRange.location, length: prefixLength)
        )
        storage.addAttribute(
            .foregroundColor,
            value: Appearance.mutedInk,
            range: NSRange(location: suffixLocation, length: suffixLength)
        )
    }
}

