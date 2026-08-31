import AppKit
import Testing
@testable import Paper

/// Fenced code blocks: mono font, literal content (no Markdown styling
/// inside), concealed fences, and one background band per block.
@MainActor
struct CodeBlockTests {
    private func styledView(_ text: String) -> PaperTextView {
        let textView = PaperTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        textView.string = text
        textView.syntaxStyler.apply(to: textView)
        return textView
    }

    @Test
    func fencedContentIsMonoAndLiteral() throws {
        let textView = styledView("before\n```swift\nlet **x** = 1\n```\nafter")
        let storage = try #require(textView.textStorage)
        let text = textView.string as NSString

        let inside = text.range(of: "**x**")
        let font = try #require(storage.attribute(.font, at: inside.location, effectiveRange: nil) as? NSFont)
        #expect(font == Appearance.codeFont())
        #expect(!font.fontDescriptor.symbolicTraits.contains(.bold), "stars are literal inside a fence")
        #expect(storage.attribute(.concealable, at: inside.location, effectiveRange: nil) == nil)
        #expect(storage.attribute(.codeBlock, at: inside.location, effectiveRange: nil) != nil)

        let before = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(before == Appearance.bodyFont())
        let after = text.range(of: "after")
        #expect(storage.attribute(.codeBlock, at: after.location, effectiveRange: nil) == nil)
    }

    @Test
    func fenceLinesConcealAndDim() throws {
        let textView = styledView("```swift\ncode\n```")
        let storage = try #require(textView.textStorage)
        #expect(storage.attribute(.concealable, at: 0, effectiveRange: nil) != nil, "opening fence")
        #expect(storage.attribute(.concealable, at: 7, effectiveRange: nil) != nil, "info string hides with it")
        let closing = (textView.string as NSString).range(of: "```", options: .backwards)
        #expect(storage.attribute(.concealable, at: closing.location, effectiveRange: nil) != nil, "closing fence")
    }

    @Test
    func listMarkersInsideAFenceStayLiteral() throws {
        let textView = styledView("```\n- not a list\n```")
        let storage = try #require(textView.textStorage)
        let dash = (textView.string as NSString).range(of: "-")
        #expect(storage.attribute(.glyphSubstitute, at: dash.location, effectiveRange: nil) == nil)
    }

    @Test
    func anUnterminatedFenceStaysProse() throws {
        let textView = styledView("```swift\nstill typing")
        let storage = try #require(textView.textStorage)
        #expect(storage.attribute(.codeBlock, at: 0, effectiveRange: nil) == nil)
        #expect(storage.attribute(.concealable, at: 0, effectiveRange: nil) == nil)
    }

    @Test
    func tildeFencesWorkToo() throws {
        let textView = styledView("~~~\ncode\n~~~")
        let storage = try #require(textView.textStorage)
        let code = (textView.string as NSString).range(of: "code")
        #expect(storage.attribute(.codeBlock, at: code.location, effectiveRange: nil) != nil)
    }

    @Test
    func oneBandPerBlockEvenFromAPartialRange() throws {
        let textView = styledView("prose\n```\nline one\nline two\n```\nprose")
        let layoutManager = try #require(textView.layoutManager as? PaperLayoutManager)
        let full = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        let rects = layoutManager.codeBlockRects(forGlyphRange: full)
        #expect(rects.count == 1)
        let band = try #require(rects.first)
        #expect(band.height > 0)

        // A dirty rect covering one line of the block still measures the
        // whole block, so partial redraws never paint a shorter band.
        let text = textView.string as NSString
        let oneLine = layoutManager.glyphRange(
            forCharacterRange: text.range(of: "line one"), actualCharacterRange: nil
        )
        #expect(layoutManager.codeBlockRects(forGlyphRange: oneLine) == rects)
    }
}
