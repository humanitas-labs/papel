import AppKit
import Testing
@testable import Paper

/// The layout is identical whether a heading's marker is concealed or
/// revealed — including when an empty line precedes the heading, where
/// null glyphs used to attach to the empty line's fragment and eat its
/// paragraph spacing (the "highlight shifts the heading" bug).
@MainActor
struct HeadingRevealTests {
    @Test
    func revealingAHeadingAfterAnEmptyLineShiftsNothing() throws {
        let text = "para one\n\n## Tweet draft\n\nbody line"
        let textView = PaperTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        textView.string = text
        textView.syntaxStyler.apply(to: textView)
        let layoutManager = try #require(textView.layoutManager as? PaperLayoutManager)
        let container = try #require(textView.textContainer)

        func fragments() -> [NSRect] {
            layoutManager.ensureLayout(for: container)
            var rects: [NSRect] = []
            layoutManager.enumerateLineFragments(
                forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)
            ) { rect, _, _, _, _ in rects.append(rect) }
            return rects
        }

        textView.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        let concealed = fragments()

        let start = (text as NSString).range(of: "\n\n##").location
        let end = (text as NSString).range(of: "draft").location + 5
        textView.setSelectedRange(NSRange(location: start, length: end - start))
        let revealed = fragments()

        #expect(concealed.count == revealed.count)
        for (hidden, shown) in zip(concealed, revealed) {
            #expect(abs(hidden.minY - shown.minY) < 0.5, "no line shifts on reveal")
            #expect(abs(hidden.height - shown.height) < 0.5)
        }

        // The concealed heading text still sits on the margin: its first
        // visible glyph starts where the body text starts.
        textView.setSelectedRange(NSRange(location: text.utf16.count, length: 0))
        layoutManager.ensureLayout(for: container)
        let head = (text as NSString).range(of: "Tweet")
        let headX = layoutManager.location(
            forGlyphAt: layoutManager.glyphIndexForCharacter(at: head.location)
        ).x
        let bodyX = layoutManager.location(forGlyphAt: 0).x
        #expect(abs(headX - bodyX) < 0.5, "concealed heading text on the margin")
    }
}
