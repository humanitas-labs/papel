import AppKit
import Testing
@testable import Paper

/// The copy control over each fenced block: what it copies and where it sits.
@MainActor
struct CodeCopyTests {
    private func styledView(_ text: String) -> PaperTextView {
        let textView = PaperTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        textView.string = text
        textView.syntaxStyler.apply(to: textView)
        return textView
    }

    @Test
    func contentIsTheLinesBetweenTheFences() {
        let source = "before\n```swift\nlet x = 1\n\n  indented\n```\nafter"
        let block = (source as NSString).range(of: "```swift\nlet x = 1\n\n  indented\n```\n")
        #expect(CodeBlockCopy.content(of: block, in: source) == "let x = 1\n\n  indented")
    }

    @Test
    func emptyBlockAndTildeFencesAtTheEnd() {
        let empty = "~~~\n~~~"
        #expect(CodeBlockCopy.content(of: NSRange(location: 0, length: empty.utf16.count), in: empty) == "")
        let last = "text\n~~~py\nprint(1)\n~~~"
        let block = (last as NSString).range(of: "~~~py\nprint(1)\n~~~")
        #expect(CodeBlockCopy.content(of: block, in: last) == "print(1)")
    }

    @Test
    func oneButtonPerVisibleBlockOverItsBand() throws {
        let textView = styledView("a\n```\none\n```\nb\n```\ntwo\nthree\n```\nc")
        let layoutManager = try #require(textView.layoutManager as? PaperLayoutManager)
        let container = try #require(textView.textContainer)
        layoutManager.ensureLayout(for: container)

        textView.syncCodeCopyButtons()
        #expect(textView.codeCopyButtons.count == 2)
        let origin = textView.textContainerOrigin
        let bands = layoutManager.codeBlockRects(forGlyphRange: layoutManager.glyphRange(for: container))
        for (button, band) in zip(textView.codeCopyButtons, bands) {
            #expect(button.superview === textView)
            #expect(button.frame.minY == origin.y + band.minY)
            #expect(button.frame.height == band.height)
            #expect(button.alphaValue == 0, "hidden until the pointer is over the band")
        }

        // The second block's button copies the second block, fences excluded.
        let pasteboard = NSPasteboard.withUniqueName()
        let second = textView.codeCopyButtons[1]
        second.pasteboard = pasteboard
        second.copyBlock()
        #expect(pasteboard.string(forType: .string) == "two\nthree")

        // Removing a block drops its button.
        textView.string = "a\n```\none\n```\nb"
        textView.syntaxStyler.apply(to: textView)
        layoutManager.ensureLayout(for: container)
        textView.syncCodeCopyButtons()
        #expect(textView.codeCopyButtons.count == 1)
        #expect(textView.subviews.compactMap { $0 as? CodeCopyButton }.count == 1)
    }

    @Test
    func onlyTheIconTakesClicks() throws {
        let textView = styledView("```\nx\n```")
        let layoutManager = try #require(textView.layoutManager as? PaperLayoutManager)
        layoutManager.ensureLayout(for: try #require(textView.textContainer))
        textView.syncCodeCopyButtons()
        let button = try #require(textView.codeCopyButtons.first)
        let icon = button.iconRect
        let onIcon = NSPoint(x: button.frame.minX + icon.midX, y: button.frame.minY + icon.midY)
        let onText = NSPoint(x: button.frame.minX + 4, y: button.frame.minY + icon.midY)
        // `hitTest` takes a point in the superview's coordinates, so the
        // text view needs one to be asked at all.
        let container = NSView(frame: textView.frame)
        container.addSubview(textView)
        #expect(container.hitTest(textView.convert(onIcon, to: container)) === button)
        #expect(container.hitTest(textView.convert(onText, to: container)) === textView)
    }
}
