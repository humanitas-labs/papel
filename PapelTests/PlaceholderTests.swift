import AppKit
import Testing
@testable import Papel

/// An empty document ghosts a title placeholder; any content clears it.
@MainActor
struct PlaceholderTests {
    private func render(_ text: String) throws -> NSBitmapImageRep {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let textView = PapelTextView()
        scrollView.documentView = textView
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Appearance.canvas
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        textView.string = text
        textView.syntaxStyler.apply(to: textView)
        scrollView.layoutSubtreeIfNeeded()
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let rep = try #require(scrollView.bitmapImageRepForCachingDisplay(in: scrollView.bounds))
        scrollView.cacheDisplay(in: scrollView.bounds, to: rep)
        return rep
    }

    /// A lone space draws no glyphs, so it renders the bare canvas; the
    /// empty document must differ from it — the ghost title.
    @Test
    func anEmptyDocumentDrawsAGhostTitleAndContentClearsIt() throws {
        let empty = try render("")
        let blank = try render(" ")
        #expect(empty.size == blank.size)

        var differing = 0
        for x in stride(from: 0, to: Int(empty.pixelsWide), by: 2) {
            for y in stride(from: 0, to: empty.pixelsHigh, by: 2) {
                if empty.colorAt(x: x, y: y) != blank.colorAt(x: x, y: y) { differing += 1 }
            }
        }
        #expect(differing > 0, "the empty page shows the placeholder")
    }

    /// The first letter typed into an empty document starts the title the
    /// placeholder promises; syntax starters and later typing do not.
    @Test
    func theFirstTypedLetterStartsTheTitle() {
        let textView = PapelTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)

        textView.insertText("N", replacementRange: NSRange(location: 0, length: 0))
        #expect(textView.string == "# N")
        #expect(textView.selectedRange() == NSRange(location: 3, length: 0))

        textView.insertText("o", replacementRange: NSRange(location: 3, length: 0))
        #expect(textView.string == "# No", "only the first keystroke converts")

        for starter in ["#", "-", "*", ">", "`", "1", " "] {
            textView.string = ""
            textView.insertText(starter, replacementRange: NSRange(location: 0, length: 0))
            #expect(textView.string == starter, "\(starter.debugDescription) begins as typed")
        }
    }
}
