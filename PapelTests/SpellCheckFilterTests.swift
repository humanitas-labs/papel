import AppKit
import Testing
@testable import Papel

/// Spelling marks on tokens that are not words are dropped by shape;
/// misspellings keep theirs, and grammar marks are never touched.
struct SpellCheckFilterTests {
    private func keeps(_ needle: String, in text: String) -> Bool {
        let nsText = text as NSString
        return SpellCheckFilter.keepsMark(at: nsText.range(of: needle), in: nsText)
    }

    @Test
    func tokensThatAreNotWordsLoseTheirMark() {
        #expect(!keeps("ae", in: "fixed in (50ae103) yesterday"), "a hash, judged with its neighbours")
        #expect(!keeps("50ae103", in: "fixed in 50ae103 yesterday"))
        #expect(!keeps("v0", in: "since v0.3.1 the"), "a version")
        #expect(!keeps("T4H3QX65LN", in: "team T4H3QX65LN signs"))
        #expect(!keeps("ABCDEF", in: "ink #ABCDEF here"), "a hex colour")
        #expect(!keeps("abcdef", in: "ink #abcdef here"))
        #expect(!keeps("NOTARY", in: "set NOTARY_KEY first"), "an identifier with an underscore")
        #expect(!keeps("dmg", in: "run scripts/make-dmg.sh now"), "a path")
        #expect(!keeps("buld", in: "see docs/buld.md and"))
        #expect(!keeps("exmaple", in: "mail me@exmaple.com please"), "an email")
        #expect(!keeps("DMG", in: "open the DMG and"), "an acronym of three or more capitals")
        #expect(!keeps("PDF", in: "as PDF."))
    }

    @Test
    func misspellingsKeepTheirMark() {
        #expect(keeps("teh", in: "teh cat sat"))
        #expect(keeps("mispeled", in: "a (mispeled) word."), "wrapping punctuation is not the token's")
        #expect(keeps("Recieve", in: "Recieve it"), "a capitalised word is still a word")
        #expect(keeps("OK", in: "it is OK"), "two capitals are not an acronym")
        #expect(keeps("dont", in: "they dont know"), "no digit, no separator")
        #expect(keeps("Ryōanji", in: "at Ryōanji today"), "proper nouns are not guessed at")
    }

    @Test
    func theRunAroundATokenStopsAtSpacesAndDropsWrappingPunctuation() {
        let text = "see (docs/buld.md), then" as NSString
        let run = SpellCheckFilter.run(around: text.range(of: "buld"), in: text)
        #expect(text.substring(with: run) == "docs/buld.md")
    }

    @MainActor
    @Test
    func theTextViewDropsSuchSpellingResultsButKeepsGrammarOnes() {
        let textView = PapelTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        textView.string = "teh fix is 50ae103 and them is here"
        textView.syntaxStyler.apply(to: textView)
        let text = textView.string as NSString
        let kept = textView.proseResults([
            .spellCheckingResult(range: text.range(of: "teh")),
            .spellCheckingResult(range: text.range(of: "50ae103")),
            .grammarCheckingResult(range: text.range(of: "them is"), details: []),
        ]).map(\.range)
        #expect(kept == [text.range(of: "teh"), text.range(of: "them is")])
    }

    @MainActor
    @Test
    func theLayoutManagerRefusesSuchMarksAtEverySetter() {
        let textView = PapelTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        textView.string = "teh fix is 50ae103 and NOTARY_KEY"
        textView.syntaxStyler.apply(to: textView)
        let layoutManager = textView.layoutManager!
        let text = textView.string as NSString
        let flag = NSNumber(value: NSAttributedString.SpellingState.spelling.rawValue)
        func mark(_ needle: String) -> Any? {
            layoutManager.temporaryAttribute(.spellingState, atCharacterIndex: text.range(of: needle).location, effectiveRange: nil)
        }
        layoutManager.addTemporaryAttribute(.spellingState, value: flag, forCharacterRange: text.range(of: "teh"))
        layoutManager.addTemporaryAttribute(.spellingState, value: flag, forCharacterRange: text.range(of: "50ae103"))
        layoutManager.addTemporaryAttributes([.spellingState: flag], forCharacterRange: text.range(of: "NOTARY"))
        #expect(mark("teh") != nil)
        #expect(mark("50ae103") == nil)
        #expect(mark("NOTARY") == nil)

        let grammar = NSNumber(value: NSAttributedString.SpellingState.grammar.rawValue)
        layoutManager.setTemporaryAttributes([.spellingState: grammar], forCharacterRange: text.range(of: "is 50ae103"))
        #expect(mark("50ae103") != nil, "a grammar mark is not judged by token shape")
    }
}
