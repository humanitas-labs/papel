import AppKit
import Testing
@testable import Papel

/// In-document anchors: a `[text](#fragment)` link jumps to the heading
/// whose GitHub-style slug matches the fragment, repeated headings take
/// `-1`, `-2`… suffixes, and a fragment naming no heading does nothing.
@MainActor
struct AnchorTests {
    private let source = """
    # Papel

    intro

    ## System boundaries

    text

    ## System boundaries

    again

    ### Fancy *stuff* & things!

    See [one](#system-boundaries) and [two](#system-boundaries-1).
    """

    @Test
    func slugsFollowTheGitHubConvention() {
        #expect(MarkdownSyntaxStyler.slug("System boundaries") == "system-boundaries")
        #expect(MarkdownSyntaxStyler.slug("Fancy *stuff* & things!") == "fancy-stuff--things")
        #expect(MarkdownSyntaxStyler.slug("ADR-003 :: Resolution") == "adr-003--resolution")
    }

    @Test
    func aFragmentFindsItsHeadingAndDuplicatesCount() throws {
        let text = source as NSString
        let first = MarkdownSyntaxStyler.fragmentRange("#system-boundaries", in: source)
        #expect(first == text.range(of: "System boundaries"))

        let second = try #require(MarkdownSyntaxStyler.fragmentRange("#system-boundaries-1", in: source))
        #expect(second.location > text.range(of: "System boundaries").location)
        #expect(text.substring(with: second) == "System boundaries")

        let decoded = MarkdownSyntaxStyler.fragmentRange("#system%20boundaries".replacingOccurrences(of: "%20", with: "-"), in: source)
        #expect(decoded == first)
        #expect(MarkdownSyntaxStyler.fragmentRange("#no-such-heading", in: source) == nil)
    }

    @Test
    func jumpingPlacesTheCaretOnTheHeading() {
        let textView = PapelTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        textView.string = source
        textView.syntaxStyler.apply(to: textView)

        textView.jump(toFragment: "#system-boundaries-1")
        let text = source as NSString
        let firstLocation = text.range(of: "System boundaries").location
        let second = text.range(of: "System boundaries", options: .backwards)
        #expect(textView.selectedRange().location == second.location)
        #expect(textView.selectedRange().location > firstLocation)

        // A fragment naming no heading moves nothing.
        textView.jump(toFragment: "#missing")
        #expect(textView.selectedRange().location == second.location)
    }
}
