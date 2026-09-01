import AppKit
import Testing
@testable import Paper

/// A plain text view over a `PaperLayoutManager`, recording every display
/// invalidation it receives. `PaperTextView` is final, so the layout
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

    private func makeStack(width: CGFloat) -> (NSTextStorage, PaperLayoutManager, NSTextContainer, RecordingTextView) {
        let storage = NSTextStorage()
        let layoutManager = PaperLayoutManager()
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
}
