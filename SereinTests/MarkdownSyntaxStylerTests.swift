import AppKit
import Testing
@testable import Serein

@MainActor
struct MarkdownSyntaxStylerTests {
    nonisolated static let sources: [String] = [
        "",
        "# Heading\n\nParagraph with **strong**, *emphasis*, and `code`.\n\n- item\n1. item\n",
        "unmatched **strong and *emphasis and `code\n",
        "***nested*** **adjacent****markers** *a**b**c*\n",
        "# 日本語 — 👩‍👩‍👧‍👦 — e\u{301} **café** `naïve`\n",
        "\u{FEFF}## BOM heading\n",
        "> quoted *line*\n>\n> > nested\n>no space\n",
    ]

    @Test(arguments: sources)
    func stylingLeavesSourceUnchanged(source: String) {
        let textView = SereinTextView()
        textView.string = source

        textView.syntaxStyler.apply(to: textView)

        #expect(textView.string == source)
        #expect(textView.textStorage?.string == source)
    }

    @Test
    func stylingPreservesSelection() {
        let textView = SereinTextView()
        textView.string = "Some **strong** text\n"
        let selection = NSRange(location: 7, length: 6)
        textView.setSelectedRange(selection)

        textView.syntaxStyler.apply(to: textView)

        #expect(textView.selectedRange() == selection)
    }

    @Test
    func stylingResetsTypingAttributesToBody() {
        let textView = SereinTextView()
        textView.string = "# Heading\n"
        textView.setSelectedRange(NSRange(location: 9, length: 0))

        textView.syntaxStyler.apply(to: textView)

        let font = textView.typingAttributes[.font] as? NSFont
        #expect(font?.pointSize == Appearance.bodySize)
    }

    @Test
    func stylingDifferentiatesConstructs() {
        let textView = SereinTextView()
        textView.string = "# Heading\n**strong** *em* `code`\n"
        textView.syntaxStyler.apply(to: textView)
        let storage = try! #require(textView.textStorage)

        let headingFont = storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        let markerColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let strongFont = storage.attribute(.font, at: 12, effectiveRange: nil) as? NSFont
        let emFont = storage.attribute(.font, at: 22, effectiveRange: nil) as? NSFont
        let codeFont = storage.attribute(.font, at: 27, effectiveRange: nil) as? NSFont

        #expect(headingFont?.pointSize == Appearance.headingSize(level: 1))
        #expect(markerColor == Appearance.mutedInk)
        #expect(strongFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(emFont?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        #expect(codeFont?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
    }
}

extension MarkdownSyntaxStylerTests {
    @Test
    func stylingMarksBlockQuotes() {
        let textView = SereinTextView()
        textView.string = "> quoted text\n>\nplain\n"
        textView.syntaxStyler.apply(to: textView)
        let storage = try! #require(textView.textStorage)

        let markerColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let quoteFont = storage.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
        let quoteStyle = storage.attribute(.paragraphStyle, at: 3, effectiveRange: nil) as? NSParagraphStyle
        let plainFont = storage.attribute(.font, at: 17, effectiveRange: nil) as? NSFont
        let plainStyle = storage.attribute(.paragraphStyle, at: 17, effectiveRange: nil) as? NSParagraphStyle

        #expect(markerColor == Appearance.mutedInk)
        #expect(quoteFont?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        #expect((quoteStyle?.headIndent ?? 0) > 0)
        #expect(plainFont?.fontDescriptor.symbolicTraits.contains(.italic) == false)
        #expect(plainStyle?.headIndent == 0)

        var runRange = NSRange()
        let marked = storage.attribute(
            .blockQuote, at: 0, longestEffectiveRange: &runRange, in: NSRange(location: 0, length: storage.length)
        )
        #expect(marked != nil)
        #expect(runRange == NSRange(location: 0, length: 16), "both quote lines and their newlines form one run")
        #expect(storage.attribute(.blockQuote, at: 17, effectiveRange: nil) == nil)
    }

    @Test
    func inlineTraitsCompose() {
        let textView = SereinTextView()
        textView.string = "> **bold in quote** and ***both***\n"
        textView.syntaxStyler.apply(to: textView)
        let storage = try! #require(textView.textStorage)

        let quoteBold = (storage.attribute(.font, at: 5, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits
        let both = (storage.attribute(.font, at: 27, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits

        #expect(quoteBold?.contains(.bold) == true)
        #expect(quoteBold?.contains(.italic) == true)
        #expect(both?.contains(.bold) == true)
        #expect(both?.contains(.italic) == true)
    }
}

struct SelectionClampingTests {
    @Test
    func clampsLocationAndLengthIntoText() {
        #expect(NSRange(location: 3, length: 4).clamped(to: 10) == NSRange(location: 3, length: 4))
        #expect(NSRange(location: 8, length: 4).clamped(to: 10) == NSRange(location: 8, length: 2))
        #expect(NSRange(location: 12, length: 4).clamped(to: 10) == NSRange(location: 10, length: 0))
        #expect(NSRange(location: 0, length: 0).clamped(to: 0) == NSRange(location: 0, length: 0))
    }
}

@MainActor
struct ConfigurationDrivenAppearanceTests {
    private func withConfiguration<T>(_ configuration: Configuration, _ body: () throws -> T) rethrows -> T {
        let store = ConfigurationStore.shared
        let saved = store.current
        defer { store.apply(saved) }
        store.apply(configuration)
        return try body()
    }

    @Test
    func configurationDrivesBodyFontAndHeadings() {
        var config = Configuration()
        config.fontFamily = "Georgia"
        config.fontSize = 20
        config.lineHeight = 1.5
        config.paragraphSpacing = 20
        config.measure = 700
        config.headingWeight = .bold
        config.letterSpacing = 0.5
        withConfiguration(config) {
            #expect(Appearance.letterSpacing == 0.5)
            #expect(MarkdownSyntaxStyler.baseAttributes[.kern] as? CGFloat == 0.5)
            #expect(Appearance.bodySize == 20)
            #expect(Appearance.bodyFont().familyName == "Georgia")
            #expect(Appearance.headingSize(level: 1) == 30)
            #expect(Appearance.headingSize(level: 2) == 26)
            #expect(Appearance.headingSize(level: 6) == 22)
            #expect(Appearance.paragraphStyle().lineHeightMultiple == 1.5)
            #expect(Appearance.paragraphStyle().paragraphSpacing == 20)
            #expect(Appearance.maximumMeasure == 700)
            #expect(Appearance.headingFont(size: 30).fontDescriptor.symbolicTraits.contains(.bold))
        }

        config.fontFamily = "No Such Family"
        withConfiguration(config) {
            #expect(Appearance.bodyFont().familyName != "No Such Family")
        }
    }

}
