import AppKit
import Testing
@testable import Paper

/// `---`, `***`, and `___` alone on a line conceal into a hairline rule;
/// the active paragraph shows the source instead.
@MainActor
struct ThematicBreakTests {
    private func styledView(_ text: String, selectedAt location: Int) -> (PaperTextView, PaperLayoutManager) {
        let textView = PaperTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        textView.string = text
        textView.syntaxStyler.apply(to: textView)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        let layoutManager = textView.layoutManager as! PaperLayoutManager
        layoutManager.ensureLayout(for: textView.textContainer!)
        return (textView, layoutManager)
    }

    @Test(arguments: ["---", "*****", "___"])
    func runeLinesConcealIntoOneRule(rune: String) throws {
        let text = "above\n\n\(rune)\n\nbelow"
        let (textView, layoutManager) = styledView(text, selectedAt: 0)
        let storage = try #require(textView.textStorage)
        let mark = (text as NSString).range(of: rune)
        #expect(storage.attribute(.thematicBreak, at: mark.location, effectiveRange: nil) != nil)
        #expect(storage.attribute(.concealable, at: mark.location, effectiveRange: nil) != nil)

        let full = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        #expect(layoutManager.thematicBreakRects(forGlyphRange: full).count == 1)
        #expect(textView.string == text, "styling never edits the source")
    }

    @Test
    func theActiveParagraphShowsItsSourceInsteadOfTheRule() throws {
        let text = "above\n\n---\n\nbelow"
        let mark = (text as NSString).range(of: "---")
        let (_, layoutManager) = styledView(text, selectedAt: mark.location + 1)
        let full = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        #expect(layoutManager.thematicBreakRects(forGlyphRange: full).isEmpty)
    }

    @Test
    func shortRunsAndFencedRunesAreNotBreaks() throws {
        let text = "--\n```\n---\n```"
        let (textView, layoutManager) = styledView(text, selectedAt: 0)
        let storage = try #require(textView.textStorage)
        #expect(storage.attribute(.thematicBreak, at: 0, effectiveRange: nil) == nil, "two dashes")
        let fenced = (text as NSString).range(of: "---")
        #expect(storage.attribute(.thematicBreak, at: fenced.location, effectiveRange: nil) == nil,
                "code keeps its source")
        let full = NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        #expect(layoutManager.thematicBreakRects(forGlyphRange: full).isEmpty)
    }
}
