import AppKit
import Testing
@testable import Papel

/// Heading markers are hidden on every paragraph the selection does not
/// touch. These tests exercise the attribute the styler writes, the glyph
/// properties the layout manager produces, and the selection paths that
/// move the revealed range.
@MainActor
struct ConcealmentTests {
    private static let sample = "# Title\n\nBody text.\n\n## Second\n\nMore body.\n"

    private func makeTextView(_ text: String, selectedAt location: Int) -> (PapelTextView, PapelLayoutManager) {
        let textView = PapelTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        textView.string = text
        textView.syntaxStyler.apply(to: textView)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        let layoutManager = textView.layoutManager as! PapelLayoutManager
        layoutManager.ensureLayout(for: textView.textContainer!)
        return (textView, layoutManager)
    }

    /// Concealed characters are control glyphs with zero advancement: they
    /// stay in their own line fragment (a `.null` glyph at a paragraph start
    /// would attach to the previous line and eat its paragraph spacing) but
    /// draw nothing and take no space.
    private func isNull(_ layoutManager: NSLayoutManager, characterAt index: Int) -> Bool {
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        guard layoutManager.propertyForGlyph(at: glyph).contains(.controlCharacter) else { return false }
        let next = layoutManager.location(forGlyphAt: glyph + 1).x
        return layoutManager.location(forGlyphAt: glyph).x == next
    }

    /// Horizontal offset of a character beyond the container's fragment
    /// padding, so a value of zero means the glyph sits on the margin.
    private func x(_ layoutManager: NSLayoutManager, characterAt index: Int) -> CGFloat {
        let padding = layoutManager.textContainers.first?.lineFragmentPadding ?? 0
        return layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: index)).x - padding
    }

    @Test(arguments: 1...6)
    func stylerMarksTheMarkerAndFollowingWhitespace(level: Int) throws {
        let textView = PapelTextView()
        textView.string = String(repeating: "#", count: level) + "  Heading\n"
        textView.syntaxStyler.apply(to: textView)
        let storage = try #require(textView.textStorage)

        var run = NSRange()
        let marked = storage.attribute(.concealable, at: 0, longestEffectiveRange: &run, in: NSRange(location: 0, length: storage.length))
        #expect(marked != nil)
        #expect(run == NSRange(location: 0, length: level + 2), "marker plus both spaces")
        #expect(storage.attribute(.concealable, at: level + 2, effectiveRange: nil) == nil, "content is never concealable")
    }

    @Test
    func listMarkersAndPlainHashesCarryNoMark() throws {
        let textView = PapelTextView()
        textView.string = "#hashtag\n- item\n"
        textView.syntaxStyler.apply(to: textView)
        let storage = try #require(textView.textStorage)
        storage.enumerateAttribute(.concealable, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            #expect(value == nil)
        }
    }

    @Test
    func quoteMarkersConcealAndTheTextIsInset() throws {
        let text = "Body.\n\n> quoted\n> > nested\n"
        let (textView, layoutManager) = makeTextView(text, selectedAt: 0)
        let storage = try #require(textView.textStorage)

        #expect(storage.attribute(.concealable, at: 7, effectiveRange: nil) != nil)
        #expect(isNull(layoutManager, characterAt: 7), "`>`")
        #expect(isNull(layoutManager, characterAt: 8), "its space")
        #expect(!isNull(layoutManager, characterAt: 9))
        #expect(x(layoutManager, characterAt: 9) == Appearance.quoteIndent, "quoted text inset from the margin")
        for index in 16...19 { #expect(isNull(layoutManager, characterAt: index), "nested `> > ` at \(index)") }
        #expect(x(layoutManager, characterAt: 20) == Appearance.quoteIndent)

        textView.setSelectedRange(NSRange(location: 10, length: 0))
        layoutManager.ensureLayout(for: textView.textContainer!)
        #expect(!isNull(layoutManager, characterAt: 7))
        #expect(x(layoutManager, characterAt: 9) > 0)
        #expect(textView.string == text)
    }

    @Test
    func inlineDelimitersConcealAndTheirContentStaysStyled() throws {
        let text = "Body.\n\nSome **strong** and *em* and `code` here.\n"
        let (textView, layoutManager) = makeTextView(text, selectedAt: 0)
        let storage = try #require(textView.textStorage)

        for index in [12, 13, 20, 21, 27, 30, 36, 41] {
            #expect(storage.attribute(.concealable, at: index, effectiveRange: nil) != nil, "delimiter at \(index)")
            #expect(isNull(layoutManager, characterAt: index), "delimiter at \(index) is hidden")
        }
        for index in [7, 14, 28, 37] {
            #expect(storage.attribute(.concealable, at: index, effectiveRange: nil) == nil, "content at \(index)")
            #expect(!isNull(layoutManager, characterAt: index))
        }
        let strong = storage.attribute(.font, at: 14, effectiveRange: nil) as? NSFont
        #expect(strong?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let hiddenX = x(layoutManager, characterAt: 12)
        #expect(x(layoutManager, characterAt: 14) == hiddenX, "content starts where the hidden delimiter would have")

        textView.setSelectedRange(NSRange(location: 16, length: 0))
        layoutManager.ensureLayout(for: textView.textContainer!)
        #expect(!isNull(layoutManager, characterAt: 12))
        #expect(x(layoutManager, characterAt: 14) > hiddenX, "revealed delimiters push the content right")
        #expect(textView.string == text)
    }

    @Test
    func markersHideOffTheSelectedParagraphAndShowOnIt() {
        let (textView, layoutManager) = makeTextView(Self.sample, selectedAt: 12)

        #expect(isNull(layoutManager, characterAt: 0), "`#` is a null glyph")
        #expect(isNull(layoutManager, characterAt: 1), "the space after it too")
        #expect(!isNull(layoutManager, characterAt: 2))
        #expect(x(layoutManager, characterAt: 2) == 0, "heading text sits on the margin")
        #expect(isNull(layoutManager, characterAt: 21), "second heading `##`")
        #expect(x(layoutManager, characterAt: 24) == 0)

        textView.setSelectedRange(NSRange(location: 3, length: 0))
        layoutManager.ensureLayout(for: textView.textContainer!)

        #expect(!isNull(layoutManager, characterAt: 0))
        #expect(x(layoutManager, characterAt: 2) > 0, "text shifts right by the marker width")
        #expect(isNull(layoutManager, characterAt: 21), "the other heading stays concealed")
    }

    @Test
    func selectionSpanningParagraphsRevealsEachOfThem() {
        let (textView, layoutManager) = makeTextView(Self.sample, selectedAt: 12)
        #expect(isNull(layoutManager, characterAt: 0))
        #expect(isNull(layoutManager, characterAt: 21))

        textView.setSelectedRange(NSRange(location: 4, length: 20))
        layoutManager.ensureLayout(for: textView.textContainer!)

        #expect(!isNull(layoutManager, characterAt: 0))
        #expect(!isNull(layoutManager, characterAt: 21))

        textView.selectAll(nil)
        layoutManager.ensureLayout(for: textView.textContainer!)
        #expect(!isNull(layoutManager, characterAt: 0))
        #expect(!isNull(layoutManager, characterAt: 21))
    }

    /// A click places the caret with `stillSelecting` and the reveal waits
    /// for the final call at mouse up, so the text under the pressed pointer
    /// stays put through AppKit's tracking loop.
    @Test
    func revealWaitsForTheSelectionToSettle() {
        let (textView, layoutManager) = makeTextView(Self.sample, selectedAt: 12)
        #expect(isNull(layoutManager, characterAt: 0))

        let inHeading = [NSValue(range: NSRange(location: 3, length: 0))]
        textView.setSelectedRanges(inHeading, affinity: .downstream, stillSelecting: true)
        layoutManager.ensureLayout(for: textView.textContainer!)
        #expect(textView.selectedRange().location == 3, "the caret moves at once")
        #expect(isNull(layoutManager, characterAt: 0), "the heading stays concealed while the mouse is down")
        #expect(x(layoutManager, characterAt: 2) == 0)

        textView.setSelectedRanges(inHeading, affinity: .downstream, stillSelecting: false)
        layoutManager.ensureLayout(for: textView.textContainer!)
        #expect(!isNull(layoutManager, characterAt: 0), "mouse up reveals it")
        #expect(x(layoutManager, characterAt: 2) > 0)
    }

    @Test
    func dragSettlesOnTheUnionOfItsParagraphs() {
        let (textView, layoutManager) = makeTextView(Self.sample, selectedAt: 12)
        #expect(isNull(layoutManager, characterAt: 0))
        #expect(isNull(layoutManager, characterAt: 21))

        let across = [NSValue(range: NSRange(location: 4, length: 20))]
        textView.setSelectedRanges(across, affinity: .downstream, stillSelecting: true)
        layoutManager.ensureLayout(for: textView.textContainer!)
        #expect(isNull(layoutManager, characterAt: 0))
        #expect(isNull(layoutManager, characterAt: 21))

        textView.setSelectedRanges(across, affinity: .downstream, stillSelecting: false)
        layoutManager.ensureLayout(for: textView.textContainer!)
        #expect(!isNull(layoutManager, characterAt: 0))
        #expect(!isNull(layoutManager, characterAt: 21))
    }

    @Test
    func arrowKeysIntoAndOutOfAHeadingToggleIt() {
        let (textView, layoutManager) = makeTextView(Self.sample, selectedAt: 12)
        #expect(isNull(layoutManager, characterAt: 0))

        textView.moveUp(nil)
        textView.moveUp(nil)
        layoutManager.ensureLayout(for: textView.textContainer!)
        #expect(NSLocationInRange(textView.selectedRange().location, NSRange(location: 0, length: 8)))
        #expect(!isNull(layoutManager, characterAt: 0))

        textView.moveDown(nil)
        textView.moveDown(nil)
        layoutManager.ensureLayout(for: textView.textContainer!)
        #expect(isNull(layoutManager, characterAt: 0))
    }

    @Test
    func concealmentNeverTouchesTheSource() {
        let (textView, layoutManager) = makeTextView(Self.sample, selectedAt: 12)
        #expect(textView.string == Self.sample)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.selectAll(nil)
        textView.setSelectedRange(NSRange(location: 30, length: 0))
        layoutManager.ensureLayout(for: textView.textContainer!)
        #expect(textView.string == Self.sample)
        #expect(textView.textStorage?.string == Self.sample)
    }

    @Test
    func typingAMarkerConcealsOnlyAfterLeavingTheLine() {
        let (textView, layoutManager) = makeTextView("plain\n\nbody\n", selectedAt: 0)
        textView.insertText("# ", replacementRange: NSRange(location: 0, length: 0))
        textView.syntaxStyler.apply(to: textView)
        layoutManager.ensureLayout(for: textView.textContainer!)

        #expect(textView.string == "# plain\n\nbody\n")
        #expect(textView.textStorage?.attribute(.concealable, at: 0, effectiveRange: nil) != nil)
        #expect(!isNull(layoutManager, characterAt: 0), "the cursor is still on the line")

        textView.setSelectedRange(NSRange(location: 10, length: 0))
        layoutManager.ensureLayout(for: textView.textContainer!)
        #expect(isNull(layoutManager, characterAt: 0))
    }

    @Test
    func undoRevealsTheParagraphItLandsOn() throws {
        let (textView, layoutManager) = makeTextView(Self.sample, selectedAt: 12)
        // Undo registration needs an undo manager; the delegate supplies it.
        let host = TestUndoHost()
        host.attach(to: textView)
        let undoManager = try #require(textView.undoManager)
        textView.setSelectedRange(NSRange(location: 7, length: 0))
        textView.insertText("!", replacementRange: NSRange(location: 7, length: 0))
        textView.breakUndoCoalescing()
        textView.syntaxStyler.apply(to: textView)
        textView.setSelectedRange(NSRange(location: 13, length: 0))
        layoutManager.ensureLayout(for: textView.textContainer!)
        #expect(isNull(layoutManager, characterAt: 0))

        undoManager.undo()
        textView.syntaxStyler.apply(to: textView)
        layoutManager.ensureLayout(for: textView.textContainer!)
        #expect(textView.string == Self.sample)
        #expect(NSLocationInRange(textView.selectedRange().location, NSRange(location: 0, length: 8)))
        #expect(!isNull(layoutManager, characterAt: 0))
    }

    /// Revealing a heading in the middle of the document must not change any
    /// line height or the document height; a partial layout invalidation
    /// once double-counted the paragraph spacing and left later lines stale.
    @Test
    func revealingAMiddleHeadingKeepsTheDocumentHeight() {
        let text = "# Title\n\nBody one.\n\n## Second\n\nBody two.\n\n### Third\n\nBody three.\n"
        let (textView, layoutManager) = makeTextView(text, selectedAt: text.utf16.count)
        let container = textView.textContainer!
        let base = layoutManager.usedRect(for: container).height
        let thirdBodyY = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: 45), effectiveRange: nil).minY

        for location in [22, 40, 22, 0] {
            textView.setSelectedRange(NSRange(location: location, length: 0))
            layoutManager.ensureLayout(for: container)
            #expect(layoutManager.usedRect(for: container).height == base, "cursor at \(location)")
        }
        textView.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        layoutManager.ensureLayout(for: container)
        #expect(layoutManager.usedRect(for: container).height == base)
        let after = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: 45), effectiveRange: nil).minY
        #expect(after == thirdBodyY)
    }

    @Test
    func quoteRuleSpansEveryWrappedLineOfASingleMarkerQuote() throws {
        let text = "\n> " + Array(repeating: "quoted words", count: 40).joined(separator: " ") + "\n\nbody\n"
        let (textView, layoutManager) = makeTextView(text, selectedAt: text.utf16.count)
        let container = try #require(textView.textContainer)
        textView.setFrameSize(NSSize(width: 320, height: 800))
        layoutManager.ensureLayout(for: container)
        let quote = NSRange(location: 1, length: text.utf16.count - 8)
        let glyphs = layoutManager.glyphRange(forCharacterRange: quote, actualCharacterRange: nil)
        var fragments = 0
        var last = NSRect.zero
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in fragments += 1; last = used }
        #expect(fragments > 3, "the quote wraps")
        let rects = layoutManager.quoteRuleRects(forGlyphRange: glyphs)
        #expect(rects.count == 1)
        #expect(rects.first?.maxY == last.maxY, "rule reaches the last wrapped line; rects \(rects), last \(last)")

        // A partial redraw of one wrapped line still measures the whole
        // run, so the leading strip above that line is not left as a slit.
        var secondLine = NSRange()
        var glyphIndex = glyphs.location
        var fragments2 = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, range, stop in
            fragments2 += 1
            if fragments2 == 2 { secondLine = range; stop.pointee = true }
        }
        glyphIndex = secondLine.location
        let partial = layoutManager.quoteRuleRects(forGlyphRange: NSRange(location: glyphIndex, length: 1))
        #expect(partial == rects, "partial \(partial) vs full \(rects)")
    }

    @Test
    func quoteRuleSpansOnlyTheVisibleQuoteLines() {
        let text = "# Title\n\n> quoted\n> more\n"
        let (_, layoutManager) = makeTextView(text, selectedAt: text.utf16.count)
        let all = layoutManager.glyphRange(forCharacterRange: NSRange(location: 0, length: text.utf16.count), actualCharacterRange: nil)
        let rects = layoutManager.quoteRuleRects(forGlyphRange: all)
        let firstLine = layoutManager.lineFragmentUsedRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: 11), effectiveRange: nil)
        let lastLine = layoutManager.lineFragmentUsedRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: 20), effectiveRange: nil)
        #expect(rects.count == 1)
        #expect(rects.first!.minY >= firstLine.minY, "does not reach into the blank line above")
        #expect(rects.first!.minY < firstLine.maxY)
        #expect(abs(rects.first!.maxY - lastLine.maxY) < 0.01)
    }
}
