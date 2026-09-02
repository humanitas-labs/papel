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
            guard let window else { return }

            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            // An empty unified toolbar is the supported way to a taller
            // title area: the traffic lights sit further in and down, as in
            // Spatial, without repositioning the buttons by hand.
            if window.toolbar?.identifier != Self.chromeToolbarIdentifier {
                let toolbar = NSToolbar(identifier: Self.chromeToolbarIdentifier)
                toolbar.allowsUserCustomization = false
                window.toolbar = toolbar
            }
            window.toolbarStyle = .unified
            window.isMovableByWindowBackground = true
            window.minSize = NSSize(width: 640, height: 520)
            applyCorners(to: window)
        }

        static let chromeToolbarIdentifier = NSToolbar.Identifier("org.humanitas.papel.chrome")

        /// The window rounds more than the system default: the content view
        /// is masked with a continuous corner and the window itself is
        /// clear, so the shadow follows the mask.
        private func applyCorners(to window: NSWindow) {
            guard let content = window.contentView else { return }
            window.backgroundColor = .clear
            window.isOpaque = false
            content.wantsLayer = true
            content.layer?.backgroundColor = Appearance.canvas.cgColor
            content.layer?.cornerRadius = Appearance.windowCornerRadius
            content.layer?.cornerCurve = .continuous
            content.layer?.masksToBounds = true
            window.invalidateShadow()
        }
    }
}
