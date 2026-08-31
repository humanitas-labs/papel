import AppKit
import Testing
@testable import Paper

/// ⌘B/⌘I/⌘U/⌘E toggle Markdown delimiters around the selection or the
/// word under the caret, in the source, with undo.
struct InlineFormattingTests {
    private func apply(_ format: InlineFormat, to text: String, selection: NSRange) -> (String, NSRange) {
        let edit = format.toggle(in: text as NSString, selection: selection)
        let result = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        return (result, edit.selection)
    }

    @Test
    func wrapsASelectionAndSelectsTheInnerText() {
        let (text, selection) = apply(.bold, to: "make this bold", selection: NSRange(location: 5, length: 4))
        #expect(text == "make **this** bold")
        #expect(selection == NSRange(location: 7, length: 4))
    }

    @Test
    func unwrapsWhenTheDelimitersSurroundTheSelection() {
        let (text, selection) = apply(.bold, to: "make **this** bold", selection: NSRange(location: 7, length: 4))
        #expect(text == "make this bold")
        #expect(selection == NSRange(location: 5, length: 4))
    }

    @Test
    func unwrapsWhenTheSelectionIncludesTheDelimiters() {
        let (text, selection) = apply(.italic, to: "an *emphatic* word", selection: NSRange(location: 3, length: 10))
        #expect(text == "an emphatic word")
        #expect(selection == NSRange(location: 3, length: 8))
    }

    @Test
    func aCaretTakesTheWordUnderIt() {
        let (text, selection) = apply(.italic, to: "one two three", selection: NSRange(location: 5, length: 0))
        #expect(text == "one *two* three")
        #expect(selection == NSRange(location: 5, length: 3))
        let (again, _) = apply(.italic, to: text, selection: NSRange(location: 6, length: 0))
        #expect(again == "one two three", "toggles back from a caret inside the wrapped word")
    }

    @Test
    func aCaretInWhitespaceInsertsAnEmptyPair() {
        let (text, selection) = apply(.bold, to: "one  two", selection: NSRange(location: 4, length: 0))
        #expect(text == "one **** two")
        #expect(selection == NSRange(location: 6, length: 0))
    }

    @Test
    func italicDoesNotStripAStarFromBold() {
        let (text, _) = apply(.italic, to: "**word**", selection: NSRange(location: 2, length: 4))
        #expect(text == "***word***", "adds italic inside bold instead of breaking it")
        let (back, _) = apply(.italic, to: "***word***", selection: NSRange(location: 3, length: 4))
        #expect(back == "**word**")
    }

    @Test
    func underlineAndCodeUseTheirOwnDelimiters() {
        #expect(apply(.underline, to: "a b c", selection: NSRange(location: 2, length: 1)).0 == "a <u>b</u> c")
        #expect(apply(.code, to: "run ls now", selection: NSRange(location: 4, length: 2)).0 == "run `ls` now")
        #expect(apply(.underline, to: "a <u>b</u> c", selection: NSRange(location: 5, length: 1)).0 == "a b c")
    }

    @Test @MainActor
    func underlineTagsRenderAsUnderlineAndConceal() throws {
        let text = "a <u>word</u> here\n"
        let textView = PaperTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        textView.string = text
        textView.syntaxStyler.apply(to: textView)
        let storage = try #require(textView.textStorage)
        #expect(storage.attribute(.underlineStyle, at: 5, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(storage.attribute(.underlineStyle, at: 2, effectiveRange: nil) == nil, "the tag itself is not underlined")
        #expect(storage.attribute(.concealable, at: 2, effectiveRange: nil) as? Bool == true, "<u>")
        #expect(storage.attribute(.concealable, at: 9, effectiveRange: nil) as? Bool == true, "</u>")
        #expect(storage.attribute(.concealable, at: 5, effectiveRange: nil) == nil)
    }

    @Test @MainActor
    func linksRenderUnderlinedWithConcealedSyntax() throws {
        let text = "see [the site](https://example.com/a) and ![img](x.png)\n"
        let textView = PaperTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        textView.string = text
        textView.syntaxStyler.apply(to: textView)
        let storage = try #require(textView.textStorage)
        #expect(storage.attribute(.linkDestination, at: 6, effectiveRange: nil) as? String == "https://example.com/a")
        #expect(storage.attribute(.underlineStyle, at: 6, effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        #expect(storage.attribute(.concealable, at: 4, effectiveRange: nil) as? Bool == true, "[")
        var range = NSRange()
        #expect(storage.attribute(.concealable, at: 13, longestEffectiveRange: &range, in: NSRange(location: 0, length: storage.length)) as? Bool == true, "](…)")
        #expect(range == NSRange(location: 13, length: 24))
        #expect(storage.attribute(.linkDestination, at: 41, effectiveRange: nil) == nil, "images are not links")
    }

    @Test @MainActor
    func insertLinkWrapsTheSelectionAndUsesAURLFromTheClipboard() throws {
        let textView = PaperTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        textView.string = "read this now"
        textView.setSelectedRange(NSRange(location: 5, length: 4))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("not a url", forType: .string)
        textView.insertLink(nil as Any?)
        #expect(textView.string == "read [this]() now")
        #expect(textView.selectedRange() == NSRange(location: 12, length: 0), "caret inside the parentheses")

        textView.string = "read this now"
        textView.setSelectedRange(NSRange(location: 7, length: 0))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("https://example.com", forType: .string)
        textView.insertLink(nil as Any?)
        #expect(textView.string == "read [this](https://example.com) now", "caret takes the word")
        #expect(textView.selectedRange() == NSRange(location: 32, length: 0))
        #expect(PaperTextView.looksLikeURL("mailto:a@b.co"))
        #expect(!PaperTextView.looksLikeURL("plain words"))
    }

    @Test @MainActor
    func typingAnArrowReplacesItInTheSourceWithUndo() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let textView = PaperTextView()
        textView.frame = window.contentView!.bounds
        textView.allowsUndo = true
        window.contentView?.addSubview(textView)
        textView.string = "a -"
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.insertText(">", replacementRange: NSRange(location: 3, length: 0))
        // AppKit closes the keystroke's undo group when the event ends; the
        // test has no event, so close it by hand before the substitution.
        let undoManager = try #require(textView.undoManager)
        if undoManager.groupingLevel > 0 { undoManager.endUndoGrouping() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        #expect(textView.string == "a →")
        #expect(textView.selectedRange() == NSRange(location: 3, length: 0))
        textView.undoManager?.undo()
        #expect(textView.string == "a ->", "undo restores the typed pair")

        textView.string = "a --"
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        textView.insertText(">", replacementRange: NSRange(location: 4, length: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        #expect(textView.string == "a -->", "a longer dash run is not an arrow")

        textView.string = "`x -`"
        textView.syntaxStyler.apply(to: textView)
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        textView.insertText(">", replacementRange: NSRange(location: 4, length: 0))
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        #expect(textView.string == "`x ->`", "inside a code span nothing changes")
    }

    @Test @MainActor
    func textViewAppliesWithUndo() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let textView = PaperTextView()
        textView.frame = window.contentView!.bounds
        textView.allowsUndo = true
        window.contentView?.addSubview(textView)
        textView.string = "plain words"
        textView.setSelectedRange(NSRange(location: 6, length: 5))
        textView.toggleBold(nil as Any?)
        #expect(textView.string == "plain **words**")
        #expect(textView.selectedRange() == NSRange(location: 8, length: 5))
        textView.undoManager?.undo()
        #expect(textView.string == "plain words")
    }
}
