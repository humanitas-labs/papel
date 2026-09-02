import AppKit
import Testing
@testable import Papel

/// Text-checking results (spelling, grammar, substitutions) that touch
/// code are dropped before they annotate the document; prose keeps them.
@MainActor
struct SpellCheckingTests {
    private func makeView(_ text: String) -> PapelTextView {
        let textView = PapelTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        textView.string = text
        textView.syntaxStyler.apply(to: textView)
        return textView
    }

    private func range(of needle: String, in textView: PapelTextView) -> NSRange {
        (textView.string as NSString).range(of: needle)
    }

    @Test
    func codeSpansAndFencedBlocksAreCode() {
        let textView = makeView("prose `spanword` more\n\n```\nblockword\n```\n\ntail")
        #expect(textView.touchesCode(range(of: "spanword", in: textView)))
        #expect(textView.touchesCode(range(of: "blockword", in: textView)))
        #expect(!textView.touchesCode(range(of: "prose", in: textView)))
        #expect(!textView.touchesCode(range(of: "tail", in: textView)))
        #expect(
            textView.touchesCode(range(of: "more\n\n```", in: textView)),
            "a result overlapping code at either end counts as code"
        )
    }

    /// A mark laid down before styling (the checker beat the styler to a
    /// fresh document) comes off on the next restyle; prose keeps its own.
    @Test
    func restyleClearsMarksLeftInCode() {
        let textView = makeView("teh `mispeled` word")
        let layoutManager = textView.layoutManager!
        let flag = NSNumber(value: NSAttributedString.SpellingState.spelling.rawValue)
        layoutManager.addTemporaryAttribute(.spellingState, value: flag, forCharacterRange: range(of: "teh", in: textView))
        layoutManager.addTemporaryAttribute(.spellingState, value: flag, forCharacterRange: range(of: "mispeled", in: textView))
        textView.syntaxStyler.apply(to: textView)
        #expect(layoutManager.temporaryAttribute(.spellingState, atCharacterIndex: range(of: "mispeled", in: textView).location, effectiveRange: nil) == nil)
        #expect(layoutManager.temporaryAttribute(.spellingState, atCharacterIndex: range(of: "teh", in: textView).location, effectiveRange: nil) != nil)
    }

    /// On current macOS the checker writes `.spellingState` straight into
    /// the layout manager, so the mark is refused there for code and kept
    /// for prose, on every setter.
    @Test
    func layoutManagerRefusesMarksInCode() {
        let textView = makeView("teh `mispeled` word [x](http://exmaple.com)\n\n```\nblokc\n```")
        let layoutManager = textView.layoutManager!
        let flag = NSNumber(value: NSAttributedString.SpellingState.spelling.rawValue)
        let whole = NSRange(location: 0, length: textView.string.utf16.count)
        func mark(at needle: String) -> Any? {
            layoutManager.temporaryAttribute(.spellingState, atCharacterIndex: range(of: needle, in: textView).location, effectiveRange: nil)
        }

        layoutManager.addTemporaryAttribute(.spellingState, value: flag, forCharacterRange: whole)
        #expect(mark(at: "teh") != nil && mark(at: "word") != nil)
        #expect(mark(at: "mispeled") == nil && mark(at: "exmaple") == nil && mark(at: "blokc") == nil)

        layoutManager.removeTemporaryAttribute(.spellingState, forCharacterRange: whole)
        layoutManager.setTemporaryAttributes([.spellingState: flag, .toolTip: "t"], forCharacterRange: whole)
        #expect(mark(at: "teh") != nil && mark(at: "mispeled") == nil && mark(at: "blokc") == nil)
        #expect(layoutManager.temporaryAttribute(.toolTip, atCharacterIndex: range(of: "mispeled", in: textView).location, effectiveRange: nil) != nil, "other temporary attributes still land in code")

        layoutManager.removeTemporaryAttribute(.spellingState, forCharacterRange: whole)
        layoutManager.addTemporaryAttributes([.spellingState: flag], forCharacterRange: range(of: "mispeled", in: textView))
        #expect(mark(at: "mispeled") == nil)
    }

    /// The override hands `super` only the results that touch no code; the
    /// filter is observed directly, since annotation needs a live window.
    @Test
    func resultsInsideCodeAreDroppedAndProseOnesKept() {
        let textView = makeView("teh `mispeled` word \"quoted\" `\"literal\"`\n\n```\nblokc\n```")
        let prose = range(of: "teh", in: textView)
        let span = range(of: "mispeled", in: textView)
        let proseQuote = range(of: "\"", in: textView)
        let spanQuote = NSRange(location: range(of: "`\"literal", in: textView).location + 1, length: 1)
        let block = range(of: "blokc", in: textView)

        let kept = textView.proseResults([
            .spellCheckingResult(range: prose),
            .spellCheckingResult(range: span),
            .replacementCheckingResult(range: proseQuote, replacementString: "“"),
            .replacementCheckingResult(range: spanQuote, replacementString: "“"),
            .spellCheckingResult(range: block),
        ]).map(\.range)

        #expect(kept == [prose, proseQuote], "prose keeps its spelling and quote results; code loses both")
    }

    @Test
    func linkAndImageAddressesAreNotChecked() {
        let textView = makeView("see [the docz](docs/buld.md) and\n\n![a pictur](assets/pictur-here.png)\n")
        let linkText = range(of: "docz", in: textView)
        let linkAddress = range(of: "buld", in: textView)
        let alt = range(of: "pictur", in: textView)
        let imageAddress = range(of: "pictur-here", in: textView)

        let kept = textView.proseResults([
            .spellCheckingResult(range: linkText),
            .spellCheckingResult(range: linkAddress),
            .spellCheckingResult(range: alt),
            .spellCheckingResult(range: imageAddress),
        ]).map(\.range)

        #expect(kept == [linkText, alt], "link text and alt text are prose; the addresses are not")
    }
}
