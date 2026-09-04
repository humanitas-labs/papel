import AppKit
import Testing
@testable import Papel

/// The indent of a hard-wrapped list item's continuation is one unit for
/// the caret: it stays concealed on the active paragraph, so the caret
/// never stands inside it, and the keys that would eat into it act on the
/// newline and the indent together.
@MainActor
struct ContinuationIndentTests {
    /// "- first line of an item\n" is 24 characters; the indent is 24–25
    /// and the continuation's text starts at 26.
    private let text = "- first line of an item\n  second line\nafter\n"

    private func makeTextView(selectedAt location: Int) -> PapelTextView {
        let textView = PapelTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        textView.string = text
        textView.syntaxStyler.apply(to: textView)
        textView.setSelectedRange(NSRange(location: location, length: 0))
        return textView
    }

    @Test
    func theCaretNeverStandsInsideTheIndent() {
        let textView = makeTextView(selectedAt: 38)
        textView.setSelectedRange(NSRange(location: 24, length: 0))
        #expect(textView.selectedRange() == NSRange(location: 26, length: 0), "after the newline lands at the text's start")
        textView.setSelectedRange(NSRange(location: 38, length: 0))
        textView.setSelectedRange(NSRange(location: 25, length: 0))
        #expect(textView.selectedRange() == NSRange(location: 26, length: 0), "inside the indent lands at the text's start")
        textView.setSelectedRange(NSRange(location: 25, length: 5))
        #expect(textView.selectedRange() == NSRange(location: 24, length: 6), "a selection takes the indent whole")
    }

    @Test
    func leftFromTheTextStartLandsBeforeTheNewlineAndRightComesBack() {
        let textView = makeTextView(selectedAt: 26)
        textView.moveLeft(nil)
        #expect(textView.selectedRange() == NSRange(location: 23, length: 0), "before the newline, on the line above")
        textView.moveRight(nil)
        #expect(textView.selectedRange() == NSRange(location: 26, length: 0), "back at the text's start")
    }

    @Test
    func backspaceAtTheTextStartJoinsTheLines() throws {
        let textView = makeTextView(selectedAt: 26)
        let host = TestUndoHost()
        host.attach(to: textView)
        let undoManager = try #require(textView.undoManager)
        textView.deleteBackward(nil)
        #expect(textView.string == "- first line of an itemsecond line\nafter\n")
        #expect(textView.selectedRange() == NSRange(location: 23, length: 0))
        undoManager.undo()
        #expect(textView.string == text, "one undo restores the newline and the indent")
    }

    @Test
    func deleteBeforeTheNewlineJoinsTheLinesToo() {
        let textView = makeTextView(selectedAt: 23)
        textView.deleteForward(nil)
        #expect(textView.string == "- first line of an itemsecond line\nafter\n")
        #expect(textView.selectedRange() == NSRange(location: 23, length: 0))
    }

    @Test
    func aPlainParagraphIsUntouched() {
        let textView = makeTextView(selectedAt: 38)
        #expect(textView.selectedRange() == NSRange(location: 38, length: 0), "the start of 'after' is a plain position")
        textView.deleteBackward(nil)
        #expect(textView.string == "- first line of an item\n  second lineafter\n", "an ordinary Backspace eats one newline")
    }
}
