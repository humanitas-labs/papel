import AppKit
import Testing
@testable import Paper

@MainActor
struct WindowCentringTests {
    /// The welcome window sits in the exact middle of the screen's visible
    /// area, not the upward-shifted spot `center()` picks, and never
    /// larger than that area.
    @Test
    func centerExactlyPutsTheWindowInTheMiddleOfTheVisibleArea() throws {
        let screen = try #require(NSScreen.main)
        let visible = screen.visibleFrame
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: visible.height + 300),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.centerExactly()
        let frame = window.frame
        #expect(frame.height <= visible.height, "shrunk to the visible area")
        #expect(abs(frame.midX - visible.midX) < 1, "middle x \(frame.midX) vs \(visible.midX)")
        #expect(abs(frame.midY - visible.midY) < 1, "middle y \(frame.midY) vs \(visible.midY)")
    }
}
