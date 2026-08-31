import AppKit

extension NSAttributedString.Key {
    /// Marks block-quote paragraphs so the text view can draw their rule.
    static let blockQuote = NSAttributedString.Key("serein.blockQuote")

    /// Marks Markdown punctuation that is hidden whenever the selection is
    /// not on its paragraph. A pure annotation: the characters stay in
    /// storage and in the saved file.
    static let concealable = NSAttributedString.Key("serein.concealable")

    /// Marks an unordered list marker character. The value is the single
    /// character to draw in its place off the active paragraph (`–` for `-`,
    /// `•` for `*` and `+`); the source character is untouched.
    static let listMarker = NSAttributedString.Key("serein.listMarker")
}

/// TextKit 1 layout manager that computes margin decorations and conceals
/// marked punctuation. It does not draw decorations: `NSTextView` clips
/// layout-manager drawing to the text container, and the block-quote rule
/// sits in the margin outside it, so `SereinTextView` draws the rects this
/// returns.
///
/// Concealment is a glyph-generation decision. Every `.concealable`
/// character outside `activeRange` gets a `.null` glyph property, which lays
/// out with zero advance and draws nothing. Storage, undo, find, and copy
/// never see the difference.
final class SereinLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
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
            if attributes[.concealable] != nil || attributes[.listMarker] != nil {
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
                replacedProperties?[offset] = .null
            } else if let rendered = run.listMarker, let glyph = Self.glyph(for: rendered, in: font) {
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

    /// The rendering marks on the attribute run at `index`.
    private struct Marks {
        var concealable = false
        var listMarker: Character?
        var isEmpty: Bool { !concealable && listMarker == nil }
        func contains(_ key: NSAttributedString.Key) -> Bool { key == .concealable && concealable }
    }

    private func markers(at index: Int, in storage: NSTextStorage, effectiveRange: NSRangePointer) -> Marks {
        let attributes = storage.attributes(at: index, effectiveRange: effectiveRange)
        var marks = Marks()
        marks.concealable = attributes[.concealable] != nil
        marks.listMarker = (attributes[.listMarker] as? String)?.first
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

    // MARK: - Margin decorations

    /// Rects (in text-container coordinates) covering each contiguous run of
    /// block-quote lines that intersects `glyphRange`.
    @MainActor
    func quoteRuleRects(forGlyphRange glyphRange: NSRange) -> [NSRect] {
        guard let storage = textStorage else { return [] }
        let characterRange = self.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        var rects: [NSRect] = []
        storage.enumerateAttribute(.blockQuote, in: characterRange) { value, range, _ in
            guard value != nil else { return }
            let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var union = NSRect.null
            enumerateLineFragments(forGlyphRange: glyphs) { _, usedRect, _, _, _ in
                union = union.union(usedRect)
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
