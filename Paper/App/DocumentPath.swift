import AppKit

/// Getting the open file's path out of the app. The window hides its
/// title bar, so there is no proxy icon; these stand in for it.
enum DocumentPath {
    /// The absolute path as plain text: `/Users/you/notes/today.md`, no
    /// `file://`, no quoting. Spaces stay; the shell quoting is the
    /// paster's business.
    static func copy(_ url: URL, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    static func copyName(_ url: URL?, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(FileBadge.title(for: url), forType: .string)
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
