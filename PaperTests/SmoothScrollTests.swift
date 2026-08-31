import AppKit
import Testing
@testable import Paper

/// Mouse-wheel notches ease the viewport toward an accumulated target;
/// trackpad deltas are not touched. The animation is stepped by hand: the
/// document-based test host cannot safely pump the run loop.
@MainActor
struct SmoothScrollTests {
    private func makeScrollView() -> PaperScrollView {
        let scrollView = PaperScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 3000))
        scrollView.documentView = document
        return scrollView
    }

    @Test
    func wheelNotchesAccumulateAndSettleOnTheTarget() {
        let scrollView = makeScrollView()
        scrollView.scroll(by: 120)
        scrollView.scroll(by: 120)
        scrollView.step(at: scrollView.startTime + 0.05)
        let midway = scrollView.contentView.bounds.origin.y
        #expect(midway > 0 && midway < 240, "moving, not jumped: \(midway)")
        scrollView.step(at: scrollView.startTime + 1)
        #expect(scrollView.contentView.bounds.origin.y == 240)
    }

    @Test
    func targetsClampToTheDocument() {
        let scrollView = makeScrollView()
        scrollView.scroll(by: 100_000)
        scrollView.step(at: scrollView.startTime + 1)
        #expect(scrollView.contentView.bounds.origin.y == 2700, "document height minus the viewport")
        scrollView.scroll(by: -100_000)
        scrollView.step(at: scrollView.startTime + 1)
        #expect(scrollView.contentView.bounds.origin.y == 0)
    }
}
