import AppKit
import Testing
@testable import Serein

/// Unordered list markers render as Apple Notes' two list kinds off the
/// active paragraph: `-` as an en dash, `*` and `+` as a bullet. The source
/// characters never change.
@MainActor
struct ListMarkerTests {
    private func makeTextView(_ text: String, selectedAt location: Int) -> (SereinTextView, SereinLayoutManager) {
        let textView = SereinTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        textView.string = text
        textView.syntaxStyler.apply(to: textView)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        let layoutManager = textView.layoutManager as! SereinLayoutManager
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
        let dash = try #require(SereinLayoutManager.glyph(for: "–", in: dashFont))
        let bullet = try #require(SereinLayoutManager.glyph(for: "•", in: bulletFont))
        let hyphen = try #require(SereinLayoutManager.glyph(for: "-", in: dashFont))

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
    func markersNeedContentAndAreNotMatchedMidLine() throws {
        let (textView, _) = makeTextView("-\n- \na - b\n  - nested\n", selectedAt: 30)
        let storage = try #require(textView.textStorage)
        #expect(storage.attribute(.listMarker, at: 0, effectiveRange: nil) == nil, "bare dash")
        #expect(storage.attribute(.listMarker, at: 2, effectiveRange: nil) == nil, "dash with only trailing space")
        #expect(storage.attribute(.listMarker, at: 7, effectiveRange: nil) == nil, "mid-line dash")
        #expect(storage.attribute(.listMarker, at: 13, effectiveRange: nil) as? String == "–", "nested item")
    }
}
