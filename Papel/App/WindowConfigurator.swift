import AppKit
import SwiftUI

/// Applies Mac window behavior that SwiftUI does not expose. The host view
/// configures its window every time it is attached, so the setup is idempotent
/// and does not depend on the window existing when the view is created.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> HostView {
        HostView(frame: .zero)
    }

    func updateNSView(_ view: HostView, context: Context) {
        view.configureWindow()
    }

    final class HostView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindow()
        }

        func configureWindow() {
            window?.applyPapelChrome(minSize: NSSize(width: 640, height: 520))
        }
    }
}

extension NSWindow {
    static let chromeToolbarIdentifier = NSToolbar.Identifier("org.humanitas.papel.chrome")

    /// The Papel window: hidden title, transparent title bar, the content
    /// under it, and corners rounder than the system default. Idempotent.
    func applyPapelChrome(minSize: NSSize) {
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        styleMask.insert(.fullSizeContentView)
        // An empty unified toolbar is the supported way to a taller
        // title area: the traffic lights sit further in and down, as in
        // Spatial, without repositioning the buttons by hand.
        if toolbar?.identifier != Self.chromeToolbarIdentifier {
            let chrome = NSToolbar(identifier: Self.chromeToolbarIdentifier)
            chrome.allowsUserCustomization = false
            toolbar = chrome
        }
        toolbarStyle = .unified
        isMovableByWindowBackground = true
        self.minSize = minSize
        applyCorners()
    }

    /// Places the window in the exact middle of its screen's visible area,
    /// shrunk to fit it if need be. `center()` sits a window somewhat
    /// above the middle by design, which reads as too high when the
    /// window nearly fills the screen.
    func centerExactly() {
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { center(); return }
        var size = frame.size
        size.width = min(size.width, visible.width)
        size.height = min(size.height, visible.height)
        let origin = NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2)
        setFrame(NSRect(origin: origin, size: size), display: false)
    }

    /// The window rounds more than the system default: the content view
    /// is masked with a continuous corner and the window itself is
    /// clear, so the shadow follows the mask.
    private func applyCorners() {
        guard let content = contentView else { return }
        backgroundColor = .clear
        isOpaque = false
        content.wantsLayer = true
        content.layer?.backgroundColor = Appearance.canvas.cgColor
        content.layer?.cornerRadius = Appearance.windowCornerRadius
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
        invalidateShadow()
    }
}
