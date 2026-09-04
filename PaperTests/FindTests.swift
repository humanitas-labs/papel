import AppKit
import Testing
@testable import Paper

/// Find (#21): matching over the source, stepping from the selection, and
/// the pill the scroll view floats at its top right.
@MainActor
@Suite(.serialized)
struct FindTests {
    // MARK: - Matching

    @Test
    func matchesAreLiteralCaseInsensitiveAndNonOverlapping() {
        let text = "Aa aa AA aaa" as NSString
        #expect(FindSession.matches(of: "aa", in: text) == [
            NSRange(location: 0, length: 2), NSRange(location: 3, length: 2),
            NSRange(location: 6, length: 2), NSRange(location: 9, length: 2),
        ])
        #expect(FindSession.matches(of: "", in: text).isEmpty)
        #expect(FindSession.matches(of: "zz", in: text).isEmpty)
        #expect(FindSession.matches(of: "**", in: "**bold** and **more**" as NSString).count == 4, "the source, syntax included")
    }

    @Test
    func nextAndPreviousStepFromTheSelectionAndWrap() {
        let matches = [NSRange(location: 2, length: 3), NSRange(location: 10, length: 3), NSRange(location: 20, length: 3)]
        #expect(FindSession.next(from: NSRange(location: 0, length: 0), in: matches) == 0)
        #expect(FindSession.next(from: NSRange(location: 2, length: 0), in: matches) == 0, "a caret at a match finds it")
        #expect(FindSession.next(from: NSRange(location: 2, length: 3), in: matches, after: true) == 1, "⌘G on a found match moves on")
        #expect(FindSession.next(from: NSRange(location: 21, length: 0), in: matches) == 0, "wraps to the top")
        #expect(FindSession.previous(from: NSRange(location: 21, length: 0), in: matches) == 2)
        #expect(FindSession.previous(from: NSRange(location: 20, length: 3), in: matches) == 1)
        #expect(FindSession.previous(from: NSRange(location: 0, length: 0), in: matches) == 2, "wraps to the bottom")
        #expect(FindSession.next(from: NSRange(location: 0, length: 0), in: []) == nil)
    }

    // MARK: - In the view

    private func host(_ text: String) -> (PaperScrollView, PaperTextView) {
        let scrollView = PaperScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let textView = PaperTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        textView.string = text
        textView.syntaxStyler.apply(to: textView)
        scrollView.documentView = textView
        return (scrollView, textView)
    }

    @Test
    func findOpensThePillInTheTopRightCornerSeededWithTheSelection() {
        let (scrollView, textView) = host("one two one three")
        textView.setSelectedRange(NSRange(location: 4, length: 3))
        scrollView.showFind(nil)
        let pill = try! #require(scrollView.pill)
        #expect(pill.superview === scrollView)
        #expect(pill.query == "two")
        #expect(pill.count == "1 of 1")
        #expect(pill.frame.maxX == 800 - FindPill.margin.right)
        #expect(scrollView.isFlipped ? pill.frame.minY == FindPill.margin.top : pill.frame.maxY == 600 - FindPill.margin.top, "the top, whichever way the scroll view counts")
        #expect(scrollView.contentView.frame.height == 600, "the text keeps its room")

        scrollView.closeFind()
        #expect(scrollView.pill == nil)
        #expect(textView.selectedRange() == NSRange(location: 4, length: 3), "the selection stays")
    }

    @Test
    func findNextAndPreviousWalkTheMatchesAndTintThemAll() {
        let (scrollView, textView) = host("one two one three one")
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        scrollView.showFind(nil)
        let pill = try! #require(scrollView.pill)
        pill.query = "one"
        pill.onChange?("one")
        #expect(textView.selectedRange() == NSRange(location: 0, length: 3), "typing selects the match at the caret")
        #expect(pill.count == "1 of 3")

        scrollView.findNext(nil)
        #expect(textView.selectedRange() == NSRange(location: 8, length: 3))
        #expect(pill.count == "2 of 3")
        scrollView.findNext(nil)
        scrollView.findNext(nil)
        #expect(textView.selectedRange() == NSRange(location: 0, length: 3), "wraps")
        scrollView.findPrevious(nil)
        #expect(textView.selectedRange() == NSRange(location: 18, length: 3))
        #expect(pill.count == "3 of 3")

        let layoutManager = try! #require(textView.layoutManager)
        var range = NSRange()
        #expect(layoutManager.temporaryAttribute(.backgroundColor, atCharacterIndex: 8, effectiveRange: &range) != nil)
        #expect(range == NSRange(location: 8, length: 3))
        #expect(layoutManager.temporaryAttribute(.backgroundColor, atCharacterIndex: 4, effectiveRange: nil) == nil)

        scrollView.closeFind()
        #expect(layoutManager.temporaryAttribute(.backgroundColor, atCharacterIndex: 8, effectiveRange: nil) == nil, "the tint goes with the pill")
    }

    @Test
    func useSelectionForFindSetsTheQueryWithoutOpeningAndFindNextOpensWhenEmpty() {
        let (scrollView, textView) = host("alpha beta alpha")
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        scrollView.useSelectionForFind(nil)
        #expect(scrollView.pill == nil)
        scrollView.findNext(nil)
        #expect(textView.selectedRange() == NSRange(location: 11, length: 5))

        let (empty, _) = host("nothing yet")
        empty.findNext(nil)
        #expect(empty.pill != nil, "⌘G with no query asks for one")
    }

    @Test
    func aMultiLineSelectionDoesNotSeedTheQuery() {
        let (scrollView, textView) = host("one\ntwo")
        textView.setSelectedRange(NSRange(location: 0, length: 7))
        scrollView.showFind(nil)
        #expect(scrollView.pill?.query == "")
    }
}
