import AppKit

extension NSAttributedString.Key {
    /// Marks block-quote paragraphs so the text view can draw their rule.
    static let blockQuote = NSAttributedString.Key("serein.blockQuote")

    /// Marks Markdown punctuation that is hidden whenever the selection is
    /// not on its paragraph. A pure annotation: the characters stay in
    /// storage and in the saved file.
    static let concealable = NSAttributedString.Key("serein.concealable")
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
    /// the old and new ranges that carry concealable punctuation. Paragraphs
    /// without markers cost nothing to enter or leave.
    func setActiveRange(_ range: NSRange) {
        let previous = activeRange
        guard range != previous else { return }
        activeRange = range

        for stale in [previous, range] {
            guard let clipped = clip(stale), containsConcealable(clipped) else { continue }
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

    private func containsConcealable(_ range: NSRange) -> Bool {
        guard let storage = textStorage else { return false }
        var found = false
        storage.enumerateAttribute(.concealable, in: range) { value, _, stop in
            if value != nil {
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
        var runConcealable = storage.attribute(
            .concealable, at: characterIndexes[0], effectiveRange: &runRange
        ) != nil
        if !runConcealable, NSMaxRange(runRange) > characterIndexes[glyphRange.length - 1] {
            return 0
        }

        var replaced: [NSLayoutManager.GlyphProperty]?
        for offset in 0..<glyphRange.length {
            let index = characterIndexes[offset]
            if !NSLocationInRange(index, runRange) {
                // One lookup per attribute run. `effectiveRange` (not the
                // longest) matters: merging unmarked runs would scan the
                // document to the next heading for every batch of glyphs.
                runConcealable = storage.attribute(
                    .concealable, at: index, effectiveRange: &runRange
                ) != nil
            }
            guard runConcealable, !NSLocationInRange(index, activeRange) else { continue }

            if replaced == nil {
                replaced = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
            }
            replaced?[offset] = .null
        }

        guard let replaced else { return 0 }
        replaced.withUnsafeBufferPointer { buffer in
            layoutManager.setGlyphs(
                glyphs,
                properties: buffer.baseAddress!,
                characterIndexes: characterIndexes,
                font: font,
                forGlyphRange: glyphRange
            )
        }
        return glyphRange.length
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
