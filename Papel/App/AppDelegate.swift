import AppKit

/// Launch behaviour the document group leaves to AppKit. SwiftUI answers a
/// launch with nothing to open by running an Open panel before the app
/// finishes launching and never forwards the untitled-file hooks, so the
/// panel is the signal: when it is up at launch, it is dismissed for the
/// welcome window. A launch with a file, or with restored windows, has no
/// panel and is untouched.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let panel = NSApp.windows.first(where: { $0 is NSOpenPanel }) as? NSOpenPanel else { return }
        panel.cancel(nil)
        WelcomeWindow.show()
    }

    /// A Dock click while no window is open.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if hasVisibleWindows { return true }
        WelcomeWindow.show()
        return false
    }
}
