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
    /// `***both***` and `___both___`: bold and italic at once. Matched
    /// before the doubles, which would otherwise take the inner pair and
    /// leave the outer delimiters plain.
    private static let strongEmphasisPattern = try! NSRegularExpression(
        pattern: #"\*\*\*([^*\n]+)\*\*\*|(?<!\w)___(?=\S)([^_\n]+?)(?<=\S)___(?!\w)"#
    )
    private static let strongPattern = try! NSRegularExpression(
        pattern: #"\*\*([^*\n]+)\*\*"#
    )
    private static let emphasisPattern = try! NSRegularExpression(
        pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#
    )
    /// The underscore spellings, `__strong__` and `_emphasis_`. Following
    /// CommonMark, an underscore run is a delimiter only at a word boundary
    /// (`\w` includes `_`, so a neighbouring underscore disqualifies it too)
    /// and the content starts and ends with something visible, so
    /// `snake_case_name`, `a_b`, `_leading`, and `trailing_` stay literal.
    /// Asterisks keep their intraword behaviour above.
    private static let underscoreStrongPattern = try! NSRegularExpression(
        pattern: #"(?<!\w)__(?=\S)([^_\n]+?)(?<=\S)__(?!\w)"#
    )
    private static let underscoreEmphasisPattern = try! NSRegularExpression(
        pattern: #"(?<!\w)_(?=\S)([^_\n]+?)(?<=\S)_(?!\w)"#
    )
    /// A code span opens and closes with backtick runs of the same length,
    /// so `` ` `` holds a literal backtick; the closer can neither borrow
    /// from nor donate to a neighbouring run.
    private static let codePattern = try! NSRegularExpression(
        pattern: #"(?<!`)(`+)([^\n]+?)(?<!`)\1(?!`)"#
    )
    /// `[text](destination)`; an image (`![…]`) is left alone.
    private static let linkPattern = try! NSRegularExpression(
        pattern: #"(?<!!)\[([^\]\n]+)\]\(([^)\s]+)\)"#
    )
    /// An HTML comment, `<!-- … -->`, across lines; one never closed runs
    /// to the end of the document, as a browser reads it.
    private static let commentPattern = try! NSRegularExpression(
        pattern: #"<!--[\s\S]*?(?:-->|\z)"#
    )
    /// `->` in prose draws as a single arrow off the active paragraph.
    private static let arrowPattern = try! NSRegularExpression(
        pattern: #"(?<![-<])->(?!>)"#
    )
    /// Markdown has no underline syntax; `<u>…</u>` is the portable form.
    private static let underlinePattern = try! NSRegularExpression(
        pattern: #"<u>([^<\n]+)</u>"#
    )
    /// `~~text~~` strikes through. Only the double tilde counts: a lone `~`
    /// is ordinary prose (`~5 minutes`, `~/.config`).
    private static let strikethroughPattern = try! NSRegularExpression(
        pattern: #"~~([^~\n]+)~~"#
    )
    /// A block image: `![alt](destination)` alone on its line. An image
    /// inside a sentence is left as typed.
    private static let blockImagePattern = try! NSRegularExpression(
        pattern: #"(?m)^[\t ]*!\[([^\]\n]*)\]\(([^)\s]+)\)[\t ]*$"#
    )
    nonisolated static let listMarkerPattern = try! NSRegularExpression(
        // `\S` or end of line: an item freshly continued by Return is just
        // `- ` and must already sit like a list item, not inherit the
        // previous line's indent until its first character.
        pattern: #"(?m)^(?:[\t ]*(?:>[\t ]?)*)([-+*]|\d+[A-Za-z]?[.)])[\t ]+(?=\S|$)"#
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
    /// A fenced code block: an opening fence line (with an optional info
    /// string), its lines, and a matching closing fence. An unterminated
    /// fence stays ordinary text, so a half-typed fence never swallows the
    /// rest of the document.
    private static let codeBlockPattern = try! NSRegularExpression(
        pattern: #"(?ms)^(`{3,}|~{3,})[^\n]*$\n(.*?)^\1[`~]*[\t ]*$"#
    )

    func apply(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }

        let source = storage.string
        let fullRange = NSRange(location: 0, length: source.utf16.count)
        let selection = textView.selectedRange()

        storage.beginEditing()
        storage.setAttributes(Self.baseAttributes, range: fullRange)
        applyThematicBreaks(to: storage, source: source, range: fullRange)
        applyHeadings(to: storage, source: source, range: fullRange)
        applyBlockQuotes(to: storage, source: source, range: fullRange)
        // Code spans go first among the inline styles: the passes below
        // skip anything already set in the code font, so span content
        // stays literal.
        applyInlineCode(to: storage, source: source, range: fullRange)
        applyDelimitedStyle(
            Self.strongEmphasisPattern,
            trait: [.bold, .italic],
            to: storage,
            source: source,
            range: fullRange
        )
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
        applyDelimitedStyle(
            Self.underscoreStrongPattern,
            trait: .bold,
            to: storage,
            source: source,
            range: fullRange
        )
        applyDelimitedStyle(
            Self.underscoreEmphasisPattern,
            trait: .italic,
            to: storage,
            source: source,
            range: fullRange
        )
        applyUnderline(to: storage, source: source, range: fullRange)
        applyStrikethrough(to: storage, source: source, range: fullRange)
        applyLinks(to: storage, source: source, range: fullRange)
        applyArrows(to: storage, source: source, range: fullRange)
        let imageURLs = applyBlockImages(
            to: storage, source: source, range: fullRange,
            documentURL: (textView as? PapelTextView)?.documentURL,
            width: Self.measure(of: textView),
            excluding: Self.fencedCodeRanges(in: source, range: fullRange)
                + Self.commentRanges(in: source, range: fullRange)
        )
        applyListMarkers(to: storage, source: source, range: fullRange)
        applyCodeBlocks(to: storage, source: source, range: fullRange)
        applyComments(to: storage, source: source, range: fullRange)
        // Concealed characters stay in the layout as zero-advance control
        // glyphs; a kern (the letter spacing) on them would still widen the
        // line off the active paragraph, so they carry none.
        storage.enumerateAttribute(.concealable, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            storage.addAttribute(.kern, value: 0, range: range)
        }
        storage.endEditing()
        (textView as? PapelTextView)?.clearCheckingMarksInCode()

        textView.typingAttributes = Self.baseAttributes
        textView.setSelectedRange(selection)
        (textView as? PapelTextView)?.watchImages(imageURLs)
    }

    /// `---`, `***`, or `___` alone on a line is a thematic break: the
    /// source conceals off the active paragraph and a hairline rule draws
    /// across the measure instead. Inside a code fence the later code pass
    /// resets the line, so fenced runes stay literal.
    private static let thematicBreakPattern = try! NSRegularExpression(
        pattern: #"(?m)^(?:-{3,}|\*{3,}|_{3,})[\t ]*$"#
    )

    private func applyThematicBreaks(
        to storage: NSTextStorage,
        source: String,
        range: NSRange
    ) {
        Self.thematicBreakPattern.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match else { return }
            storage.addAttribute(.foregroundColor, value: Appearance.mutedInk, range: match.range)
            storage.addAttribute(.concealable, value: true, range: match.range)
            storage.addAttribute(.thematicBreak, value: true, range: match.range)
        }
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
            guard let match, !Self.isCode(at: match.range.location, in: storage) else { return }
            let contentRange = (1..<match.numberOfRanges)
                .map { match.range(at: $0) }
                .first { $0.location != NSNotFound } ?? match.range

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
        let text = source as NSString
        Self.codePattern.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match else { return }

            var contentRange = match.range(at: 2)
            // One space each side is part of the delimiters when both are
            // present (how `` ` `` carries a backtick), so it hides with
            // them and stays outside the chip.
            if contentRange.length > 2,
               text.character(at: contentRange.location) == 0x20,
               text.character(at: NSMaxRange(contentRange) - 1) == 0x20 {
                contentRange = NSRange(location: contentRange.location + 1, length: contentRange.length - 2)
            }
            storage.addAttribute(
                .font,
                value: Appearance.codeFont(),
                range: contentRange
            )
            // The band colour marks the span as a chip: the layout manager
            // recognises it in `fillBackgroundRectArray` and rounds it.
            storage.addAttribute(.backgroundColor, value: Appearance.codeBlockBackground, range: contentRange)
            dimDelimiters(around: contentRange, in: match.range, storage: storage)
        }
    }

    /// The first-line indent for a list item whose match starts at
    /// `location`: the base list indent plus a full nesting step per two
    /// leading spaces (or a tab), less the width those characters already
    /// take when rendered — so the marker lands on the step and the layout
    /// never depends on which paragraph is active.
    private static func nestedIndent(at location: Int, in source: String) -> CGFloat {
        let text = source as NSString
        var index = location
        var level = 0
        var spaces = 0
        var whitespace = ""
        while index < text.length {
            switch text.character(at: index) {
            case 0x09: level += 1; whitespace += "\t"
            case 0x20: spaces += 1; whitespace += " "
            default: index = text.length; continue
            }
            index += 1
        }
        level += spaces / 2
        guard level > 0 else { return Appearance.listIndent }
        let width = (whitespace as NSString).size(withAttributes: [.font: Appearance.bodyFont()]).width
        return max(
            Appearance.listIndent,
            Appearance.listIndent + CGFloat(level) * Appearance.listNestIndent - width
        )
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
                storage.addAttribute(.glyphSubstitute, value: symbol, range: markerRange)
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
                    under: String(rendered),
                    indent: Self.nestedIndent(at: match.range.location, in: source),
                    gap: Appearance.listMarkerGap,
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

    /// Fenced source is literal, so this pass runs last and starts the
    /// block's attributes over: emphasis, lists, links, and arrows styled
    /// by the passes above are cleared, everything is set in the code font,
    /// and the fence lines dim and hide off the active paragraph. The
    /// `.codeBlock` mark lets the text view draw the background band.
    private func applyCodeBlocks(
        to storage: NSTextStorage,
        source: String,
        range: NSRange
    ) {
        let text = source as NSString
        Self.codeBlockPattern.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match else { return }
            let block = text.paragraphRange(for: match.range)

            var attributes = Self.baseAttributes
            attributes[.font] = Appearance.codeFont()
            // No spacing inside the block, so the band is one unbroken
            // panel; the closing fence keeps the ordinary spacing to
            // whatever follows.
            attributes[.paragraphStyle] = Appearance.flushParagraphStyle(
                indent: Appearance.codeBlockInset, spacing: 0
            )
            storage.setAttributes(attributes, range: block)
            let closingLine = text.paragraphRange(for: NSRange(location: NSMaxRange(match.range) - 1, length: 0))
            storage.addAttribute(
                .paragraphStyle,
                value: Appearance.flushParagraphStyle(indent: Appearance.codeBlockInset),
                range: closingLine
            )
            storage.addAttribute(.codeBlock, value: true, range: block)

            let openingLine = text.paragraphRange(for: NSRange(location: match.range.location, length: 0))
            for line in [openingLine, closingLine] {
                var fence = line
                while fence.length > 0 {
                    let last = text.character(at: NSMaxRange(fence) - 1)
                    guard last == 0x0A || last == 0x0D else { break }
                    fence.length -= 1
                }
                guard fence.length > 0 else { continue }
                storage.addAttribute(.foregroundColor, value: Appearance.mutedInk, range: fence)
                // The first fence character draws as an invisible space
                // instead of concealing: a fragment that starts with `.null`
                // glyphs attaches them to the previous fragment, whose
                // paragraph spacing then reads from the fence's spacing-0
                // style — the line above the block would shift on reveal. A
                // real glyph keeps the fence row its own fragment.
                storage.addAttribute(.glyphSubstitute, value: " ", range: NSRange(location: fence.location, length: 1))
                if fence.length > 1 {
                    storage.addAttribute(
                        .concealable, value: true,
                        range: NSRange(location: fence.location + 1, length: fence.length - 1)
                    )
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
            guard let match, !Self.isCode(at: match.range.location, in: storage) else { return }
            let contentRange = match.range(at: 1)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            dimDelimiters(around: contentRange, in: match.range, storage: storage)
        }
    }

    /// `~~text~~`: the content is struck through in its own ink; the tildes
    /// are dimmed and, off the active paragraph, concealed.
    private func applyStrikethrough(
        to storage: NSTextStorage,
        source: String,
        range: NSRange
    ) {
        Self.strikethroughPattern.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match, !Self.isCode(at: match.range.location, in: storage) else { return }
            let contentRange = match.range(at: 1)
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: contentRange)
            dimDelimiters(around: contentRange, in: match.range, storage: storage)
        }
    }

    private func applyLinks(
        to storage: NSTextStorage,
        source: String,
        range: NSRange
    ) {
        Self.linkPattern.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match, !Self.isCode(at: match.range.location, in: storage) else { return }
            let textRange = match.range(at: 1)
            let destination = (source as NSString).substring(with: match.range(at: 2))
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: textRange)
            storage.addAttribute(.linkDestination, value: destination, range: textRange)
            storage.addAttribute(.address, value: true, range: match.range(at: 2))
            storage.addAttribute(.cursor, value: NSCursor.pointingHand, range: textRange)
            // `[` and `](destination)` hide off the active paragraph.
            dimDelimiters(around: textRange, in: match.range, storage: storage)
        }
    }

    /// The width a block image may take: the text container's, less its
    /// padding. A view not yet sized (no window) takes the configured
    /// measure, which is what the container becomes once it has one.
    static func measure(of textView: NSTextView) -> CGFloat {
        guard let container = textView.textContainer else { return Appearance.maximumMeasure }
        let width = container.size.width - 2 * container.lineFragmentPadding
        return width > 0 ? width : Appearance.maximumMeasure
    }

    /// A block image whose file loads reserves a band under its line — the
    /// paragraph spacing grows by the image's fitted height — and conceals
    /// its whole source off the active paragraph; the text view draws the
    /// bitmap in the band. The band is reserved whether the line is
    /// concealed or revealed, so the caret entering it moves nothing. A
    /// missing or remote file shows its alt text muted and italic with the
    /// punctuation concealed, the way a link shows its text. Returns every
    /// local file an image referred to, present or not, for the view to watch.
    private func applyBlockImages(
        to storage: NSTextStorage,
        source: String,
        range: NSRange,
        documentURL: URL?,
        width: CGFloat,
        excluding fenced: [NSRange]
    ) -> Set<URL> {
        let text = source as NSString
        var urls: Set<URL> = []
        Self.blockImagePattern.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match, !Self.isCode(at: match.range.location, in: storage),
                  !fenced.contains(where: { NSLocationInRange(match.range.location, $0) })
            else { return }
            let altRange = match.range(at: 1)
            let destination = text.substring(with: match.range(at: 2))
            storage.addAttribute(.address, value: true, range: match.range(at: 2))
            let syntax = NSRange(location: text.range(of: "![", options: [], range: match.range).location, length: 0)
            let opener = NSRange(location: syntax.location, length: altRange.location - syntax.location)
            let closer = NSRange(location: NSMaxRange(altRange), length: NSMaxRange(match.range) - NSMaxRange(altRange))

            let url = MarkdownResource.localURL(for: destination, relativeTo: documentURL)
            if let url { urls.insert(url) }
            guard let url, let dimensions = ImageStore.shared.dimensions(for: url) else {
                storage.addAttribute(.font, value: Appearance.italicFont(), range: altRange)
                storage.addAttribute(.foregroundColor, value: Appearance.mutedInk, range: altRange)
                for range in [opener, closer] {
                    storage.addAttribute(.foregroundColor, value: Appearance.mutedInk, range: range)
                    storage.addAttribute(.concealable, value: true, range: range)
                }
                return
            }

            let paragraph = text.paragraphRange(for: match.range)
            let size = ImageStore.fit(dimensions.naturalSize, width: width)
            storage.addAttribute(
                .paragraphStyle,
                value: Appearance.paragraphStyle(spacing: size.height + Appearance.paragraphSpacing),
                range: paragraph
            )
            storage.addAttribute(.imageSource, value: url, range: paragraph)
            storage.addAttribute(.foregroundColor, value: Appearance.mutedInk, range: match.range)
            // As with a fence, the first character draws as an invisible
            // space so the line keeps its own fragment; the rest conceals.
            storage.addAttribute(.glyphSubstitute, value: " ", range: NSRange(location: opener.location, length: 1))
            storage.addAttribute(
                .concealable, value: true,
                range: NSRange(location: opener.location + 1, length: NSMaxRange(closer) - opener.location - 1)
            )
        }
        return urls
    }

    /// `->` renders as `→`: the `-` is concealed and the `>` is drawn with
    /// the arrow glyph, so the pair takes one glyph's width off the active
    /// paragraph and reads as typed on it. Code spans keep their source.
    private func applyArrows(
        to storage: NSTextStorage,
        source: String,
        range: NSRange
    ) {
        Self.arrowPattern.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match, !Self.isCode(at: match.range.location, in: storage) else { return }
            storage.addAttribute(.concealable, value: true, range: NSRange(location: match.range.location, length: 1))
            let arrow = NSRange(location: match.range.location + 1, length: 1)
            storage.addAttribute(.glyphSubstitute, value: "→", range: arrow)
            storage.addAttribute(.font, value: Appearance.markerFont(for: "→"), range: arrow)
        }
    }

    /// The ranges of HTML comments outside fenced code, from the source
    /// alone, for the passes that run before the comment pass.
    private static func commentRanges(in source: String, range: NSRange) -> [NSRange] {
        let fenced = fencedCodeRanges(in: source, range: range)
        var ranges: [NSRange] = []
        commentPattern.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match, !fenced.contains(where: { NSLocationInRange(match.range.location, $0) }) else { return }
            ranges.append(match.range)
        }
        return ranges
    }

    /// A comment recedes into the muted ink, delimiters and all, so a
    /// note-to-self or a disabled section reads as one and not as the
    /// document. Nothing inside it is Markdown: earlier passes' styling is
    /// undone, and nothing conceals, so `<!--` and `-->` stay in view.
    /// Comments inside code stay code; this pass runs after the code pass,
    /// so the code font marks them.
    private func applyComments(
        to storage: NSTextStorage,
        source: String,
        range: NSRange
    ) {
        Self.commentPattern.enumerateMatches(in: source, range: range) { match, _, _ in
            guard let match, !Self.isCode(at: match.range.location, in: storage) else { return }
            for key in [NSAttributedString.Key.concealable, .glyphSubstitute, .underlineStyle, .strikethroughStyle, .linkDestination,
                        .address, .cursor, .imageSource, .thematicBreak, .backgroundColor] {
                storage.removeAttribute(key, range: match.range)
            }
            storage.addAttribute(.font, value: Appearance.bodyFont(), range: match.range)
            storage.addAttribute(.foregroundColor, value: Appearance.mutedInk, range: match.range)
        }
    }

    /// The ranges of fenced code blocks. The block-image pass runs before
    /// the code pass (which resets whole lines), so `isCode` cannot see the
    /// code font yet; an image-looking line inside a fence renders literal
    /// but must also not resolve, decode, or watch the file it names.
    private static func fencedCodeRanges(in source: String, range: NSRange) -> [NSRange] {
        var ranges: [NSRange] = []
        codeBlockPattern.enumerateMatches(in: source, range: range) { match, _, _ in
            if let match { ranges.append(match.range) }
        }
        return ranges
    }

    /// The GitHub-style slug of a heading: lowercased, punctuation dropped
    /// (hyphens and underscores kept), spaces and tabs as hyphens — so
    /// anchors written for GitHub resolve in Papel.
    static func slug(_ heading: String) -> String {
        var slug = ""
        for character in heading.trimmingCharacters(in: .whitespaces).lowercased() {
            if character.isLetter || character.isNumber || character == "_" || character == "-" {
                slug.append(character)
            } else if character == " " || character == "\t" {
                slug.append("-")
            }
        }
        return slug
    }

    /// The content range of the heading a `#fragment` names, or nil for one
    /// naming no heading. A repeated heading takes `-1`, `-2`… suffixes in
    /// document order, as on GitHub; matching is against the heading text,
    /// whose markdown punctuation the slug drops anyway.
    static func fragmentRange(_ fragment: String, in source: String) -> NSRange? {
        var target = fragment.hasPrefix("#") ? String(fragment.dropFirst()) : fragment
        target = (target.removingPercentEncoding ?? target).lowercased()
        guard !target.isEmpty else { return nil }

        let text = source as NSString
        var counts: [String: Int] = [:]
        var found: NSRange?
        headingPattern.enumerateMatches(in: source, range: NSRange(location: 0, length: text.length)) { match, _, stop in
            guard let match else { return }
            let content = match.range(at: 2)
            let base = Self.slug(text.substring(with: content))
            let seen = counts[base, default: 0]
            counts[base] = seen + 1
            if (seen == 0 ? base : "\(base)-\(seen)") == target {
                found = content
                stop.pointee = true
            }
        }
        return found
    }

    /// Whether the character sits inside a code span (the code font is
    /// applied by the first inline pass, so later passes can skip it).
    private static func isCode(at location: Int, in storage: NSTextStorage) -> Bool {
        guard location < storage.length else { return false }
        return storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont == Appearance.codeFont()
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

