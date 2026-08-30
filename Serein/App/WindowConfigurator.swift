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
            window.toolbar = nil
            window.isMovableByWindowBackground = true
            window.backgroundColor = Appearance.canvas
            window.minSize = NSSize(width: 640, height: 520)
        }
    }
}
