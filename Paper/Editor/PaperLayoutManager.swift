import AppKit

extension NSAttributedString.Key {
    /// Marks block-quote paragraphs so the text view can draw their rule.
    static let blockQuote = NSAttributedString.Key("paper.blockQuote")

    /// Marks fenced-code-block paragraphs (fences included) so the text
    /// view can draw their background band.
    static let codeBlock = NSAttributedString.Key("paper.codeBlock")

    /// Marks Markdown punctuation that is hidden whenever the selection is
    /// not on its paragraph. A pure annotation: the characters stay in
    /// storage and in the saved file.
    static let concealable = NSAttributedString.Key("paper.concealable")

    /// Marks a character drawn as another glyph off the active paragraph:
    /// the value is the single character to draw in its place (`–` for a `-`
    /// list marker, `•` for `*` and `+`, `→` for the `>` of `->`). The
    /// source character is untouched.
    static let glyphSubstitute = NSAttributedString.Key("paper.glyphSubstitute")
    static let thematicBreak = NSAttributedString.Key("paper.thematicBreak")
    /// The destination of a Markdown link, as its source string, on the
    /// link's text. Opened with ⌘-click; a plain click places the caret.
    static let linkDestination = NSAttributedString.Key("paper.linkDestination")
    /// The `(destination)` of a link or image: a path or URL, not prose,
    /// so text checking leaves it alone.
    static let address = NSAttributedString.Key("paper.address")
    /// Marks a paragraph that is a block image (`![alt](file)` alone on its
    /// line) whose file loaded; the value is the resolved file `URL`. The
    /// paragraph's spacing reserves the band the text view draws it in.
    static let imageSource = NSAttributedString.Key("paper.imageSource")
}

/// TextKit 1 layout manager that computes margin decorations and conceals
/// marked punctuation. It does not draw decorations: `NSTextView` clips
/// layout-manager drawing to the text container, and the block-quote rule
/// sits in the margin outside it, so `PaperTextView` draws the rects this
/// returns.
///
/// Concealment is a glyph-generation decision. Every `.concealable`
/// character outside `activeRange` gets a `.null` glyph property, which lays
/// out with zero advance and draws nothing. Storage, undo, find, and copy
/// never see the difference.
final class PaperLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    /// Characters whose punctuation is shown: the paragraphs touched by the
    /// selection. Empty until the text view sets it.
    private(set) var activeRange = NSRange(location: 0, length: 0)

    override init() {
        super.init()
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// Changes the revealed range, regenerating glyphs only for the parts of
    /// the old and new ranges that carry concealable punctuation or list
    /// markers. Paragraphs without either cost nothing to enter or leave.
    func setActiveRange(_ range: NSRange) {
        let previous = activeRange
        guard range != previous else { return }
        activeRange = range

        for stale in [previous, range] {
            guard let clipped = clip(stale), containsRenderMarks(clipped) else { continue }
            invalidateGlyphs(forCharacterRange: clipped, changeInLength: 0, actualCharacterRange: nil)
            // Layout must be invalidated through to the end: with contiguous
            // layout, re-laying only the paragraph leaves the fragments after
            // it stale and double-counts its paragraph spacing.
            let toEnd = NSRange(location: clipped.location, length: (textStorage?.length ?? 0) - clipped.location)
            invalidateLayout(forCharacterRange: toEnd, actualCharacterRange: nil)
            invalidateDisplay(forCharacterRange: toEnd)
        }
    }

    /// Whether the character is concealed under the current active range.
    func isConcealed(characterAt index: Int) -> Bool {
        guard let storage = textStorage, index < storage.length,
              !NSLocationInRange(index, activeRange) else { return false }
        return storage.attribute(.concealable, at: index, effectiveRange: nil) != nil
    }

    private func clip(_ range: NSRange) -> NSRange? {
        guard let storage = textStorage else { return nil }
        let clipped = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
        return clipped.length > 0 ? clipped : nil
    }

    private func containsRenderMarks(_ range: NSRange) -> Bool {
        guard let storage = textStorage else { return false }
        var found = false
        storage.enumerateAttributes(in: range) { attributes, _, stop in
            if attributes[.concealable] != nil || attributes[.glyphSubstitute] != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    // MARK: - NSLayoutManagerDelegate

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
        properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
        characterIndexes: UnsafePointer<Int>,
        font: NSFont,
        forGlyphRange glyphRange: NSRange
    ) -> Int {
        guard let storage = textStorage, glyphRange.length > 0 else { return 0 }

        // Most batches lie inside one unmarked attribute run; leave those to
        // the default generation without touching every glyph.
        var runRange = NSRange(location: NSNotFound, length: 0)
        var run = markers(at: characterIndexes[0], in: storage, effectiveRange: &runRange)
        if run.isEmpty, NSMaxRange(runRange) > characterIndexes[glyphRange.length - 1] {
            return 0
        }

        var replacedProperties: [NSLayoutManager.GlyphProperty]?
        var replacedGlyphs: [CGGlyph]?
        for offset in 0..<glyphRange.length {
            let index = characterIndexes[offset]
            if !NSLocationInRange(index, runRange) {
                // One lookup per attribute run. `effectiveRange` (not the
                // longest) matters: merging unmarked runs would scan the
                // document to the next heading for every batch of glyphs.
                run = markers(at: index, in: storage, effectiveRange: &runRange)
            }
            guard !run.isEmpty, !NSLocationInRange(index, activeRange) else { continue }

            if run.contains(.concealable) {
                if replacedProperties == nil {
                    replacedProperties = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
                }
                // Control glyphs with zero advancement, not `.null`: a null
                // glyph at a paragraph's start attaches to the previous
                // line's fragment, and that fragment then drops its
                // paragraph spacing — the layout jumped when a heading's
                // concealed marker followed an empty line. A control glyph
                // stays in its own fragment, draws nothing, and takes no
                // width (the zero advancement comes from the control-action
                // delegate below).
                replacedProperties?[offset] = .controlCharacter
            } else if let rendered = run.substitute, let glyph = Self.glyph(for: rendered, in: font) {
                if replacedGlyphs == nil {
                    replacedGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
                }
                replacedGlyphs?[offset] = glyph
            }
        }

        guard replacedProperties != nil || replacedGlyphs != nil else { return 0 }
        let finalProperties = replacedProperties ?? Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
        let finalGlyphs = replacedGlyphs ?? Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length))
        finalProperties.withUnsafeBufferPointer { propertyBuffer in
            finalGlyphs.withUnsafeBufferPointer { glyphBuffer in
                layoutManager.setGlyphs(
                    glyphBuffer.baseAddress!,
                    properties: propertyBuffer.baseAddress!,
                    characterIndexes: characterIndexes,
                    font: font,
                    forGlyphRange: glyphRange
                )
            }
        }
        return glyphRange.length
    }

    /// Concealed characters were generated as control glyphs; they take no
    /// space. Real control characters (tabs, line breaks) keep their action.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldUse action: NSLayoutManager.ControlCharacterAction,
        forControlCharacterAt charIndex: Int
    ) -> NSLayoutManager.ControlCharacterAction {
        guard let storage = textStorage, charIndex < storage.length,
              storage.attribute(.concealable, at: charIndex, effectiveRange: nil) != nil,
              !NSLocationInRange(charIndex, activeRange)
        else { return action }
        let character = (storage.string as NSString).character(at: charIndex)
        guard character != 0x0A, character != 0x0D, character != 0x09 else { return action }
        return .zeroAdvancement
    }

    /// The used rect's bottom after the previous complete layout, for the
    /// vacated-area invalidation below.
    private var lastUsedBottom: CGFloat = 0

    /// Every display invalidation in TextKit is character-based, so when an
    /// edit shortens the layout, the strip the text vacated below the new
    /// bottom holds no characters and is never repainted — the old last line
    /// survives there as stale pixels (a deleted newline appeared to leave
    /// its paragraph duplicated). When a completed layout ends higher than
    /// the previous one, redraw the strip between the two bottoms.
    func layoutManager(
        _ layoutManager: NSLayoutManager,
        didCompleteLayoutFor textContainer: NSTextContainer?,
        atEnd layoutFinishedFlag: Bool
    ) {
        guard layoutFinishedFlag else { return }
        // Layout always completes on the main thread; the unsafe capture is
        // the region checker's price for hopping into the actor to reach the
        // text view.
        nonisolated(unsafe) let manager = self
        MainActor.assumeIsolated {
            guard let container = manager.textContainers.first else { return }
            let bottom = manager.usedRect(for: container).maxY
            let stale = manager.lastUsedBottom
            manager.lastUsedBottom = bottom
            guard bottom < stale, let textView = container.textView else { return }
            let origin = textView.textContainerOrigin
            textView.setNeedsDisplay(NSRect(
                x: 0,
                y: origin.y + bottom,
                width: textView.bounds.width,
                height: stale - bottom
            ))
        }
    }

    /// The rendering marks on the attribute run at `index`.
    private struct Marks {
        var concealable = false
        var substitute: Character?
        var isEmpty: Bool { !concealable && substitute == nil }
        func contains(_ key: NSAttributedString.Key) -> Bool { key == .concealable && concealable }
    }

    private func markers(at index: Int, in storage: NSTextStorage, effectiveRange: NSRangePointer) -> Marks {
        let attributes = storage.attributes(at: index, effectiveRange: effectiveRange)
        var marks = Marks()
        marks.concealable = attributes[.concealable] != nil
        marks.substitute = (attributes[.glyphSubstitute] as? String)?.first
        return marks
    }

    /// The font's glyph for a single character, or nil when the font lacks
    /// it (the source character is drawn instead).
    static func glyph(for character: Character, in font: NSFont) -> CGGlyph? {
        let units = Array(String(character).utf16)
        guard units.count == 1 else { return nil }
        var glyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font, units, &glyph, 1), glyph != 0 else { return nil }
        return glyph
    }

    /// The origin `drawBackground(forGlyphRange:at:)` was last given, so the
    /// chip drawing below can place container-coordinate rects itself; the
    /// rects TextKit passes to `fillBackgroundRectArray` are already offset.
    private var backgroundDrawOrigin = NSPoint.zero

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        backgroundDrawOrigin = origin
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    /// Chip rects (in text-container coordinates) for an inline code span:
    /// one per line fragment the span touches, clamped to the glyphs it holds
    /// there. TextKit's own background rects are selection-shaped — a wrapped
    /// run extends the first line to the fragment's trailing edge and starts
    /// the next at its leading edge — which warps a chip meant to hug text.
    func codeChipRects(forCharacterRange charRange: NSRange) -> [NSRect] {
        let glyphs = glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        var rects: [NSRect] = []
        enumerateLineFragments(forGlyphRange: glyphs) { _, _, container, fragmentGlyphs, _ in
            let intersection = NSIntersectionRange(fragmentGlyphs, glyphs)
            guard intersection.length > 0 else { return }
            let rect = self.boundingRect(forGlyphRange: intersection, in: container)
            // A fragment holding only concealed (zero-advance) span glyphs
            // has nothing to chip.
            guard rect.width > 0.5 else { return }
            rects.append(rect)
        }
        return rects
    }

    /// Inline `code` spans carry the band colour as a background attribute;
    /// those fills are drawn as rounded chips hugging the glyph box instead
    /// of full-height rectangles. Every other background (selection included)
    /// keeps the default drawing.
    override func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<NSRect>,
        count rectCount: Int,
        forCharacterRange charRange: NSRange,
        color: NSColor
    ) {
        let chip: (height: CGFloat, radius: CGFloat)? = MainActor.assumeIsolated {
            guard color == Appearance.codeBlockBackground else { return nil }
            // The line-height leading sits above the glyphs, so the chip
            // anchors to the fragment's bottom edge, like the caret.
            let font = Appearance.codeFont()
            return (font.ascender - font.descender + 4, Appearance.codeChipCornerRadius)
        }
        guard let chip else {
            super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
            return
        }
        let height = chip.height
        let origin = backgroundDrawOrigin
        color.setFill()
        for rect in codeChipRects(forCharacterRange: charRange) {
            let placed = rect.offsetBy(dx: origin.x, dy: origin.y)
            NSBezierPath(
                roundedRect: NSRect(
                    x: placed.minX - 2,
                    y: placed.maxY - min(height, placed.height),
                    width: placed.width + 4,
                    height: min(height, placed.height)
                ),
                xRadius: chip.radius,
                yRadius: chip.radius
            ).fill()
        }
    }

    // MARK: - Margin decorations

    private func hasVisibleGlyphs(in range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        for index in range.location..<NSMaxRange(range) {
            switch propertyForGlyph(at: index) {
            case .null, .controlCharacter: continue
            default: return true
            }
        }
        return false
    }

    /// Rects (in text-container coordinates) covering each fenced code
    /// block that intersects `glyphRange`. Fence lines count: concealed off
    /// the active paragraph, they read as the band's vertical padding.
    @MainActor
    func codeBlockRects(forGlyphRange glyphRange: NSRange) -> [NSRect] {
        guard let storage = textStorage else { return [] }
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        var rects: [NSRect] = []
        var measured: [NSRange] = []
        storage.enumerateAttribute(.codeBlock, in: characterRange) { value, partial, _ in
            guard value != nil else { return }
            // As with the quote rule, measure the whole block even when the
            // dirty rect covers one line of it, or partial redraws leave
            // unpainted strips; drawing is clipped to the dirty rect anyway.
            var range = NSRange()
            _ = storage.attribute(.codeBlock, at: partial.location, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length))
            guard !measured.contains(range) else { return }
            measured.append(range)
            let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var top = CGFloat.greatestFiniteMagnitude
            var bottom = -CGFloat.greatestFiniteMagnitude
            enumerateLineFragments(forGlyphRange: glyphs) { fragment, used, _, fragmentGlyphs, _ in
                // A fragment that merely carries attached zero-width glyphs
                // from the block starts outside it; counting it would grow
                // the band over the line above.
                let first = self.characterIndexForGlyph(at: fragmentGlyphs.location)
                guard NSLocationInRange(first, range) else { return }
                top = min(top, fragment.minY)
                // The used rect's bottom excludes the closing fence's
                // paragraph spacing, so the band hugs its last row.
                bottom = max(bottom, used.maxY)
            }
            guard bottom > top else { return }
            rects.append(NSRect(x: 0, y: top, width: 0, height: bottom - top))
        }
        return rects
    }

    /// The band (in text-container coordinates) under each block-image
    /// paragraph intersecting `glyphRange`, with the image file it shows.
    /// The band is the paragraph's spacing: it starts under the line's used
    /// rect and is as tall as the image fits into `width`, so the source
    /// line above stays put whether it is concealed or revealed.
    @MainActor
    func imageBands(forGlyphRange glyphRange: NSRange, width: CGFloat) -> [(rect: NSRect, url: URL)] {
        guard let storage = textStorage else { return [] }
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        var bands: [(rect: NSRect, url: URL)] = []
        var measured: [NSRange] = []
        storage.enumerateAttribute(.imageSource, in: characterRange) { value, partial, _ in
            guard let url = value as? URL else { return }
            var range = NSRange()
            _ = storage.attribute(
                .imageSource, at: partial.location,
                longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length)
            )
            guard !measured.contains(range) else { return }
            measured.append(range)
            guard let dimensions = ImageStore.shared.dimensions(for: url) else { return }
            let size = ImageStore.fit(dimensions.naturalSize, width: width)
            let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var bottom = -CGFloat.greatestFiniteMagnitude
            var padding: CGFloat = 0
            enumerateLineFragments(forGlyphRange: glyphs) { _, used, container, fragmentGlyphs, _ in
                let first = self.characterIndexForGlyph(at: fragmentGlyphs.location)
                guard NSLocationInRange(first, range) else { return }
                bottom = max(bottom, used.maxY)
                // The concealed line's used rect starts at 0, not at the
                // padding the text stands on; the band takes the text's edge.
                padding = container.lineFragmentPadding
            }
            guard bottom > -CGFloat.greatestFiniteMagnitude else { return }
            bands.append((NSRect(x: padding, y: bottom, width: size.width, height: size.height), url))
        }
        return bands
    }

    /// Line-fragment rects (in text-container coordinates) of each concealed
    /// thematic break intersecting `glyphRange`. The active paragraph shows
    /// its source instead, so it yields no rect.
    @MainActor
    func thematicBreakRects(forGlyphRange glyphRange: NSRange) -> [NSRect] {
        guard let storage = textStorage else { return [] }
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        var rects: [NSRect] = []
        var measured: [NSRange] = []
        storage.enumerateAttribute(.thematicBreak, in: characterRange) { value, partial, _ in
            guard value != nil else { return }
            var range = NSRange()
            _ = storage.attribute(
                .thematicBreak, at: partial.location,
                longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length)
            )
            guard !measured.contains(range) else { return }
            measured.append(range)
            guard NSIntersectionRange(range, self.activeRange).length == 0 else { return }
            let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            rects.append(self.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil))
        }
        return rects
    }

    /// Rects (in text-container coordinates) covering each contiguous run of
    /// block-quote lines that intersects `glyphRange`.
    @MainActor
    func quoteRuleRects(forGlyphRange glyphRange: NSRange) -> [NSRect] {
        guard let storage = textStorage else { return [] }
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        var rects: [NSRect] = []
        var measured: [NSRange] = []
        storage.enumerateAttribute(.blockQuote, in: characterRange) { value, partial, _ in
            guard value != nil else { return }
            // Measure the whole quote run even when the dirty rect covers
            // one line of it: the rect is a union of glyph boxes, and a
            // single fragment's box leaves its leading strip unpainted (a
            // slit in the rule) until a full redraw. Drawing is clipped to
            // the dirty rect regardless.
            var range = NSRange()
            _ = storage.attribute(.blockQuote, at: partial.location, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length))
            guard !measured.contains(range) else { return }
            measured.append(range)
            let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            // The line-height leading sits above the glyphs in each fragment,
            // so measure from the glyph box (ascent + descent at the
            // fragment's bottom), as the caret does, or the rule starts a
            // leading's height above the first line.
            let font = Appearance.italicFont()
            let glyphBox = font.ascender - font.descender
            var union = NSRect.null
            enumerateLineFragments(forGlyphRange: glyphs) { _, usedRect, _, fragmentGlyphs, _ in
                // Concealed markers are zero-width glyphs that TextKit can
                // attach to the end of the previous fragment (the blank
                // line above); a fragment counts only if it shows something.
                guard self.hasVisibleGlyphs(in: NSIntersectionRange(fragmentGlyphs, glyphs)) else { return }
                let height = min(usedRect.height, glyphBox)
                union = union.union(NSRect(x: usedRect.minX, y: usedRect.maxY - height, width: usedRect.width, height: height))
            }
            guard !union.isNull else { return }
            if let last = rects.last, abs(last.maxY - union.minY) <= Appearance.paragraphSpacing + 1 {
                rects[rects.count - 1] = last.union(union)
            } else {
                rects.append(union)
            }
        }
        return rects
    }
}
