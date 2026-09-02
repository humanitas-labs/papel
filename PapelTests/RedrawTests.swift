import AppKit
import Testing
@testable import Papel

/// A plain text view over a `PapelLayoutManager`, recording every display
/// invalidation it receives. `PapelTextView` is final, so the layout
/// manager's view-facing behaviour is observed through the stack it serves.
@MainActor
private final class RecordingTextView: NSTextView {
    var recorded: [NSRect] = []

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        recorded.append(rect)
        super.setNeedsDisplay(rect, avoidAdditionalLayout: flag)
    }
}

@MainActor
struct RedrawTests {
    private let styler = MarkdownSyntaxStyler()

    private func makeStack(width: CGFloat) -> (NSTextStorage, PapelLayoutManager, NSTextContainer, RecordingTextView) {
        let storage = NSTextStorage()
        let layoutManager = PapelLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        let textView = RecordingTextView(frame: NSRect(x: 0, y: 0, width: width, height: 600), textContainer: container)
        return (storage, layoutManager, container, textView)
    }

    /// Deleting a newline shortens the layout; the strip the text vacated
    /// below the new bottom holds no characters, so only an explicit
    /// invalidation repaints it — without one the old last line survives
    /// there as stale pixels (issue #16).
    @Test
    func aShorteningEditInvalidatesTheVacatedStripBelowTheText() {
        let (storage, layoutManager, container, textView) = makeStack(width: 400)
        textView.string = "## Heading\n\nfirst paragraph\n\nlast paragraph"
        styler.apply(to: textView)
        layoutManager.ensureLayout(for: container)
        let bottomBefore = layoutManager.usedRect(for: container).maxY

        textView.recorded = []
        let blankLine = (textView.string as NSString).range(of: "\n\nlast")
        storage.replaceCharacters(in: NSRange(location: blankLine.location, length: 1), with: "")
        styler.apply(to: textView)
        layoutManager.ensureLayout(for: container)
        let bottomAfter = layoutManager.usedRect(for: container).maxY
        #expect(bottomAfter < bottomBefore, "the edit shortens the layout")

        let originY = textView.textContainerOrigin.y
        let vacated = textView.recorded.contains {
            $0.minY <= originY + bottomAfter + 1 && $0.maxY >= originY + bottomBefore - 1
        }
        #expect(vacated, "the strip between the new and old bottoms is redrawn")
    }

    /// An inline code span that wraps gets one chip rect per line fragment,
    /// clamped to its glyphs — never TextKit's selection-shaped background
    /// rects, whose first line runs to the trailing edge (issue #19).
    @Test
    func aWrappedCodeSpanChipsPerFragmentClampedToItsGlyphs() {
        let (_, layoutManager, container, textView) = makeStack(width: 220)
        textView.string = "start `alpha beta gamma deltadelta` end"
        styler.apply(to: textView)
        layoutManager.ensureLayout(for: container)

        var span = NSRange(location: NSNotFound, length: 0)
        textView.textStorage?.enumerateAttribute(
            .backgroundColor, in: NSRange(location: 0, length: textView.textStorage!.length)
        ) { value, range, stop in
            guard value != nil else { return }
            span = range
            stop.pointee = true
        }
        #expect(span.location != NSNotFound, "the span carries the chip background")

        let rects = layoutManager.codeChipRects(forCharacterRange: span)
        #expect(rects.count >= 2, "the span wraps, so it chips per fragment")
        let trailingEdge = container.size.width - container.lineFragmentPadding
        #expect(
            rects.allSatisfy { $0.maxX < trailingEdge - 10 },
            "every chip stops at its last glyph, short of the trailing edge"
        )
        for pair in zip(rects, rects.dropFirst()) {
            #expect(pair.0.maxY <= pair.1.minY + 1, "fragments stack; no chip spans two lines")
        }
    }

    /// An unwrapped span keeps a single chip over its glyphs.
    @Test
    func anUnwrappedCodeSpanKeepsASingleChip() {
        let (_, layoutManager, container, textView) = makeStack(width: 400)
        textView.string = "start `code` end"
        styler.apply(to: textView)
        layoutManager.ensureLayout(for: container)

        var span = NSRange(location: NSNotFound, length: 0)
        textView.textStorage?.enumerateAttribute(
            .backgroundColor, in: NSRange(location: 0, length: textView.textStorage!.length)
        ) { value, range, stop in
            guard value != nil else { return }
            span = range
            stop.pointee = true
        }
        let rects = layoutManager.codeChipRects(forCharacterRange: span)
        #expect(rects.count == 1)
    }
}
