import AppKit
import Testing
@testable import Paper

/// Text-checking results (spelling, grammar, substitutions) that touch
/// code are dropped before they annotate the document; prose keeps them.
@MainActor
struct SpellCheckingTests {
    private func makeView(_ text: String) -> PaperTextView {
        let textView = PaperTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        textView.string = text
        textView.syntaxStyler.apply(to: textView)
        return textView
    }

    private func range(of needle: String, in textView: PaperTextView) -> NSRange {
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
}
