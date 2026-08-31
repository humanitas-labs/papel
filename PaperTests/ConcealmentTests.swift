import AppKit
import Testing
@testable import Paper

/// Heading markers are hidden on every paragraph the selection does not
/// touch. These tests exercise the attribute the styler writes, the glyph
/// properties the layout manager produces, and the selection paths that
/// move the revealed range.
@MainActor
struct ConcealmentTests {
    private static let sample = "# Title\n\nBody text.\n\n## Second\n\nMore body.\n"

    private func makeTextView(_ text: String, selectedAt location: Int) -> (PaperTextView, PaperLayoutManager) {
        let textView = PaperTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        textView.string = text
        textView.syntaxStyler.apply(to: textView)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        let layoutManager = textView.layoutManager as! PaperLayoutManager
        layoutManager.ensureLayout(for: textView.textContainer!)
        return (textView, layoutManager)
    }

    private func isNull(_ layoutManager: NSLayoutManager, characterAt index: Int) -> Bool {
        let glyph = layoutManager.glyphIndexForCharacter(at: index)
        return layoutManager.propertyForGlyph(at: glyph) == .null
    }

    /// Horizontal offset of a character beyond the container's fragment
    /// padding, so a value of zero means the glyph sits on the margin.
    private func x(_ layoutManager: NSLayoutManager, characterAt index: Int) -> CGFloat {
        let padding = layoutManager.textContainers.first?.lineFragmentPadding ?? 0
        return layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: index)).x - padding
    }

    @Test(arguments: 1...6)
    func stylerMarksTheMarkerAndFollowingWhitespace(level: Int) throws {
        let textView = PaperTextView()
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
        let textView = PaperTextView()
        textView.string = "#hashtag\n- item\n"
        textView.syntaxStyler.apply(to: textView)
        let storage = try #require(textView.textStorage)
        storage.enumerateAttribute(.concealable, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            #expect(value == nil)
        }
    }

    @Test
    func quoteMarkersConcealAndTheTextSitsOnTheMargin() throws {
        let text = "Body.\n\n> quoted\n> > nested\n"
        let (textView, layoutManager) = makeTextView(text, selectedAt: 0)
        let storage = try #require(textView.textStorage)

        #expect(storage.attribute(.concealable, at: 7, effectiveRange: nil) != nil)
        #expect(isNull(layoutManager, characterAt: 7), "`>`")
        #expect(isNull(layoutManager, characterAt: 8), "its space")
        #expect(!isNull(layoutManager, characterAt: 9))
        #expect(x(layoutManager, characterAt: 9) == 0, "quoted text on the margin")
        for index in 16...19 { #expect(isNull(layoutManager, characterAt: index), "nested `> > ` at \(index)") }
        #expect(x(layoutManager, characterAt: 20) == 0)

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
        // Undo registration needs a responder chain with an undo manager.
        let window = NSWindow(contentRect: textView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = textView
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
        #expect(rects.first!.maxY == lastLine.maxY)
    }
}
