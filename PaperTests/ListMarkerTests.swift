import AppKit
import Testing
@testable import Paper

/// Unordered list markers render as Apple Notes' two list kinds off the
/// active paragraph: `-` as an en dash, `*` and `+` as a bullet. The source
/// characters never change.
@MainActor
struct ListMarkerTests {
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

    private func glyph(_ layoutManager: NSLayoutManager, characterAt index: Int) -> CGGlyph {
        layoutManager.cgGlyph(at: layoutManager.glyphIndexForCharacter(at: index))
    }

    @Test
    func dashAndStarRenderAsDashAndBulletOffTheActiveParagraph() throws {
        let text = "- dash\n* star\n+ plus\n1. one\n\nbody\n"
        let (textView, layoutManager) = makeTextView(text, selectedAt: text.utf16.count)
        let storage = try #require(textView.textStorage)
        // Marker characters carry a font that has the rendered glyph, which
        // may be a cascade fallback when the body face lacks it.
        let dashFont = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let bulletFont = try #require(storage.attribute(.font, at: 7, effectiveRange: nil) as? NSFont)
        let dash = try #require(PaperLayoutManager.glyph(for: "–", in: dashFont))
        let bullet = try #require(PaperLayoutManager.glyph(for: "•", in: bulletFont))
        let hyphen = try #require(PaperLayoutManager.glyph(for: "-", in: dashFont))

        #expect(storage.attribute(.listMarker, at: 0, effectiveRange: nil) as? String == "–")
        #expect(storage.attribute(.listMarker, at: 7, effectiveRange: nil) as? String == "•")
        #expect(storage.attribute(.listMarker, at: 14, effectiveRange: nil) as? String == "•")
        #expect(storage.attribute(.listMarker, at: 21, effectiveRange: nil) == nil, "ordered markers are untouched")
        #expect(glyph(layoutManager, characterAt: 0) == dash)
        #expect(glyph(layoutManager, characterAt: 7) == bullet)
        #expect(glyph(layoutManager, characterAt: 14) == bullet)
        #expect(glyph(layoutManager, characterAt: 2) != dash, "content glyphs are not substituted")

        textView.setSelectedRange(NSRange(location: 3, length: 0))
        layoutManager.ensureLayout(for: textView.textContainer!)
        #expect(glyph(layoutManager, characterAt: 0) == hyphen, "the active paragraph shows its source")
        #expect(glyph(layoutManager, characterAt: 7) == bullet)
        #expect(textView.string == text)
    }

    @Test
    func listItemsHangUnderTheirTextAndQuotesKeepTheirOwnIndent() throws {
        let (textView, _) = makeTextView("- item\n\nplain\n\n> - quoted item\n", selectedAt: 0)
        let storage = try #require(textView.textStorage)
        let item = storage.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
        let plain = storage.attribute(.paragraphStyle, at: 9, effectiveRange: nil) as? NSParagraphStyle
        let quoted = storage.attribute(.paragraphStyle, at: 18, effectiveRange: nil) as? NSParagraphStyle
        let expected = ("– " as NSString).size(withAttributes: [.font: Appearance.bodyFont()]).width

        #expect(item?.firstLineHeadIndent == Appearance.listIndent)
        #expect(item?.headIndent == Appearance.listIndent + Appearance.listMarkerGap + expected)
        #expect(storage.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat == Appearance.letterSpacing + Appearance.listMarkerGap)
        #expect(storage.attribute(.kern, at: 2, effectiveRange: nil) as? CGFloat == Appearance.letterSpacing)
        #expect(plain?.headIndent == 0)
        #expect(quoted?.firstLineHeadIndent == 0)
        #expect(quoted?.headIndent == 0)
        #expect(storage.attribute(.listMarker, at: 17, effectiveRange: nil) as? String == "–", "a list inside a quote still gets its marker")
    }

    @Test
    func hardWrappedItemsContinueUnderTheirText() throws {
        let text = "- first line of an item\nsecond line\nthird line\n\nplain\n- next\n"
        let (textView, _) = makeTextView(text, selectedAt: 0)
        let storage = try #require(textView.textStorage)
        func style(_ index: Int) -> NSParagraphStyle? {
            storage.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle
        }
        let item = try #require(style(2))
        let second = try #require(style(26))
        let third = try #require(style(38))
        let plain = try #require(style(50))
        let next = try #require(style(58))

        #expect(item.paragraphSpacing == 0, "no gap before its continuation")
        #expect(second.firstLineHeadIndent == item.headIndent)
        #expect(second.headIndent == item.headIndent)
        #expect(second.paragraphSpacing == 0)
        #expect(third.firstLineHeadIndent == item.headIndent)
        #expect(third.paragraphSpacing == Appearance.paragraphSpacing, "last continuation keeps the gap")
        #expect(plain.headIndent == 0)
        #expect(next.paragraphSpacing == Appearance.paragraphSpacing, "an item followed by another item has no continuation")
        #expect(storage.attribute(.listMarker, at: 24, effectiveRange: nil) == nil)
        #expect(textView.string == text)
    }

    @Test
    func indentedContinuationsConcealTheirLeadingWhitespace() throws {
        let text = "- first line of an item\n  second line\n\tthird line\nfourth\n"
        let (textView, layoutManager) = makeTextView(text, selectedAt: text.utf16.count)
        let storage = try #require(textView.textStorage)
        var range = NSRange()
        #expect(storage.attribute(.concealable, at: 24, effectiveRange: &range) as? Bool == true)
        #expect(range == NSRange(location: 24, length: 2), "both leading spaces")
        #expect(storage.attribute(.concealable, at: 38, effectiveRange: &range) as? Bool == true)
        #expect(range == NSRange(location: 38, length: 1), "a leading tab")
        #expect(storage.attribute(.concealable, at: 50, effectiveRange: nil) == nil, "an unindented continuation has nothing to hide")

        // Off the active paragraph the continuation's text starts where the
        // item's text does; on it, the source whitespace shows.
        let itemX = layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: 2)).x
        let concealedX = layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: 26)).x
        #expect(abs(itemX - concealedX) < 0.5, "item text at \(itemX), continuation at \(concealedX)")
        textView.setSelectedRange(NSRange(location: 30, length: 0))
        layoutManager.ensureLayout(for: textView.textContainer!)
        let revealedX = layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: 26)).x
        #expect(revealedX > itemX + 1)
        #expect(textView.string == text)
    }

    @Test
    func wrappedLinesStartExactlyUnderTheFirstLinesText() throws {
        let text = "- " + Array(repeating: "wrapping words", count: 40).joined(separator: " ") + "\n"
        let (textView, layoutManager) = makeTextView(text, selectedAt: text.utf16.count)
        let container = try #require(textView.textContainer)
        textView.setFrameSize(NSSize(width: 320, height: 600))
        layoutManager.ensureLayout(for: container)

        // x of the first content glyph on line 1 versus the first glyph on line 2.
        let firstContent = layoutManager.glyphIndexForCharacter(at: 2)
        let firstLine = layoutManager.lineFragmentRect(forGlyphAt: firstContent, effectiveRange: nil)
        var secondLineRange = NSRange()
        _ = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.numberOfGlyphs - 2, effectiveRange: nil)
        var glyphIndex = firstContent
        while glyphIndex < layoutManager.numberOfGlyphs {
            let rect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &secondLineRange)
            if rect.minY > firstLine.minY { break }
            glyphIndex = NSMaxRange(secondLineRange)
        }
        #expect(glyphIndex < layoutManager.numberOfGlyphs, "the item wraps")
        let firstX = layoutManager.location(forGlyphAt: firstContent).x
        let secondX = layoutManager.location(forGlyphAt: glyphIndex).x
        #expect(abs(firstX - secondX) < 0.5, "first line text at \(firstX), wrapped line at \(secondX)")
    }

    @Test
    func markersNeedContentAndAreNotMatchedMidLine() throws {
        let (textView, _) = makeTextView("-\n- \na - b\n  - nested\n", selectedAt: 30)
        let storage = try #require(textView.textStorage)
        #expect(storage.attribute(.listMarker, at: 0, effectiveRange: nil) == nil, "bare dash")
        #expect(storage.attribute(.listMarker, at: 2, effectiveRange: nil) == nil, "dash with only trailing space")
        #expect(storage.attribute(.listMarker, at: 7, effectiveRange: nil) == nil, "mid-line dash")
        #expect(storage.attribute(.listMarker, at: 13, effectiveRange: nil) as? String == "–", "nested item")
    }
}
