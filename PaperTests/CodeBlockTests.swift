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
        #expect(storage.attribute(.glyphSubstitute, at: 0, effectiveRange: nil) as? String == " ",
                "the fence's first character stays a real, invisible glyph")
        #expect(storage.attribute(.concealable, at: 1, effectiveRange: nil) != nil, "opening fence")
        #expect(storage.attribute(.concealable, at: 7, effectiveRange: nil) != nil, "info string hides with it")
        let closing = (textView.string as NSString).range(of: "```", options: .backwards)
        #expect(storage.attribute(.glyphSubstitute, at: closing.location, effectiveRange: nil) as? String == " ")
        #expect(storage.attribute(.concealable, at: closing.location + 1, effectiveRange: nil) != nil, "closing fence")
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

    /// A bare fence typed above a paragraph and a real ```sh block stays a
    /// literal line: the sh fence opens its own block instead of sitting
    /// inside the new one, so the paragraph is not swallowed (#39).
    @Test
    func aFenceTypedAboveAnotherBlockDoesNotSwallowIt() throws {
        let source = "## Command line\n```\nInstall it with the command below.\n\n```sh\nbrew install paper\n```\nafter\n"
        let textView = styledView(source)
        let storage = try #require(textView.textStorage)
        let text = textView.string as NSString
        let typed = text.range(of: "```\n").location
        let prose = text.range(of: "Install").location
        let sh = text.range(of: "```sh").location
        let code = text.range(of: "brew").location
        let after = text.range(of: "after").location
        #expect(storage.attribute(.codeBlock, at: typed, effectiveRange: nil) == nil, "the typed fence is prose")
        #expect(storage.attribute(.concealable, at: typed + 1, effectiveRange: nil) == nil, "and shows as typed")
        #expect(storage.attribute(.codeBlock, at: prose, effectiveRange: nil) == nil, "the paragraph is prose")
        #expect(storage.attribute(.codeBlock, at: sh, effectiveRange: nil) != nil, "the sh block is a block")
        #expect(storage.attribute(.concealable, at: sh + 1, effectiveRange: nil) != nil, "whose fence conceals")
        #expect(storage.attribute(.font, at: code, effectiveRange: nil) as? NSFont == Appearance.codeFont())
        #expect(storage.attribute(.codeBlock, at: after, effectiveRange: nil) == nil)
        #expect(MarkdownSyntaxStyler.fencedBlocks(in: source, range: NSRange(location: 0, length: text.length)).count == 1)

        // Once the typed fence gets its own closer, it is a block of its own
        // and the sh block is untouched.
        let closed = styledView("```\nInstall it.\n```\n\n```sh\nbrew install paper\n```\n")
        let closedStorage = try #require(closed.textStorage)
        let closedText = closed.string as NSString
        #expect(closedStorage.attribute(.codeBlock, at: closedText.range(of: "Install").location, effectiveRange: nil) != nil)
        #expect(closedStorage.attribute(.codeBlock, at: closedText.range(of: "brew").location, effectiveRange: nil) != nil)
        #expect(MarkdownSyntaxStyler.fencedBlocks(in: closed.string, range: NSRange(location: 0, length: closedText.length)).count == 2)
    }

    /// The CommonMark ways of showing a fence inside a fence still hold: a
    /// ``` line inside ~~~ is content, and so is ```sh inside ````.
    @Test
    func fencesOfTheOtherCharacterOrShorterAreContent() throws {
        for source in ["~~~\n```sh\necho\n```\n~~~\n", "````\n```sh\necho\n```\n````\n"] {
            let textView = styledView(source)
            let storage = try #require(textView.textStorage)
            let text = textView.string as NSString
            let inner = text.range(of: "```sh").location
            let echo = text.range(of: "echo").location
            #expect(storage.attribute(.codeBlock, at: inner, effectiveRange: nil) != nil)
            #expect(storage.attribute(.concealable, at: inner + 1, effectiveRange: nil) == nil, "the inner fence is literal content")
            #expect(storage.attribute(.font, at: echo, effectiveRange: nil) as? NSFont == Appearance.codeFont())
            #expect(MarkdownSyntaxStyler.fencedBlocks(in: source, range: NSRange(location: 0, length: text.length)).count == 1)
        }
    }

    @Test
    func tildeFencesWorkToo() throws {
        let textView = styledView("~~~\ncode\n~~~")
        let storage = try #require(textView.textStorage)
        let code = (textView.string as NSString).range(of: "code")
        #expect(storage.attribute(.codeBlock, at: code.location, effectiveRange: nil) != nil)
    }

    @Test
    func inlineCodeSpansCarryTheChipColour() throws {
        let textView = styledView("prose `span` more\n```\nblock\n```")
        let storage = try #require(textView.textStorage)
        let text = textView.string as NSString
        let span = text.range(of: "span")
        let chip = storage.attribute(.backgroundColor, at: span.location, effectiveRange: nil) as? NSColor
        #expect(chip == Appearance.codeBlockBackground)
        #expect(storage.attribute(.backgroundColor, at: span.location - 1, effectiveRange: nil) == nil,
                "the backtick sits outside the chip")
        let block = text.range(of: "block")
        #expect(storage.attribute(.backgroundColor, at: block.location, effectiveRange: nil) == nil,
                "the band, not a chip, backs fenced content")
    }

    @Test
    func doubleBacktickSpansPairByRunLength() throws {
        let textView = styledView("- `#`, `*`, `` ` ``, `<u>`, `~~x~~`, and `[a](b)` are concealed")
        let storage = try #require(textView.textStorage)
        let text = textView.string as NSString

        // `` ` `` holds a literal backtick: code font and chip on it, the
        // padding spaces hidden with the delimiters.
        let escaped = text.range(of: "`` ` ``")
        #expect(escaped.location != NSNotFound)
        let literal = escaped.location + 3
        #expect(storage.attribute(.font, at: literal, effectiveRange: nil) as? NSFont == Appearance.codeFont())
        #expect(storage.attribute(.backgroundColor, at: literal, effectiveRange: nil) != nil)
        #expect(storage.attribute(.backgroundColor, at: literal - 1, effectiveRange: nil) == nil)

        // Mispaired runs used to chip the prose between spans.
        let and = text.range(of: " and ")
        for offset in 0..<and.length {
            #expect(storage.attribute(.backgroundColor, at: and.location + offset, effectiveRange: nil) == nil)
            #expect(storage.attribute(.font, at: and.location + offset, effectiveRange: nil) as? NSFont == Appearance.bodyFont())
        }

        // Strikethrough and a link inside a code span stay literal.
        let struck = text.range(of: "~~x~~")
        #expect(storage.attribute(.strikethroughStyle, at: struck.location + 2, effectiveRange: nil) == nil)
        #expect(storage.attribute(.concealable, at: struck.location, effectiveRange: nil) == nil)
        let link = text.range(of: "[a](b)")
        #expect(storage.attribute(.linkDestination, at: link.location + 1, effectiveRange: nil) == nil)
        #expect(storage.attribute(.font, at: link.location, effectiveRange: nil) as? NSFont == Appearance.codeFont())
    }

    @Test
    func concealingFencesDoesNotChangeTheHeight() throws {
        let text = "prose before\n\n```ini\nkey = value\nmore = 1\n```\n\nprose after"
        let textView = styledView(text)
        let layoutManager = try #require(textView.layoutManager as? PaperLayoutManager)
        let container = try #require(textView.textContainer)

        textView.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        layoutManager.ensureLayout(for: container)
        let concealed = layoutManager.usedRect(for: container).height
        var concealedFragments: [NSRect] = []
        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        ) { rect, _, _, _, _ in concealedFragments.append(rect) }

        textView.setSelectedRange(NSRange(location: 0, length: text.utf16.count))
        layoutManager.ensureLayout(for: container)
        let revealed = layoutManager.usedRect(for: container).height
        var revealedFragments: [NSRect] = []
        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        ) { rect, _, _, _, _ in revealedFragments.append(rect) }

        #expect(abs(concealed - revealed) < 0.5, "concealed \(concealed) vs revealed \(revealed)")
        #expect(concealedFragments.count == revealedFragments.count)
        for (hidden, shown) in zip(concealedFragments, revealedFragments) {
            #expect(abs(hidden.minY - shown.minY) < 0.5, "no line shifts on reveal")
        }
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
