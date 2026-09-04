import AppKit
import Testing
@testable import Paper

/// The file name badge and File ▸ Copy Path: what the pill says, what
/// lands on the pasteboard, and when the command is available.
@MainActor
struct FileBadgeTests {
    @Test
    func thePillSaysTheFileNameOrUntitled() {
        #expect(FileBadge.title(for: URL(fileURLWithPath: "/Users/you/notes/today.md")) == "today.md")
        #expect(FileBadge.title(for: URL(fileURLWithPath: "/tmp/a note with spaces.md")) == "a note with spaces.md")
        #expect(FileBadge.title(for: nil) == "Untitled")
    }

    @Test
    func copyPathLeavesAPlainAbsolutePath() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("paper-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        DocumentPath.copy(URL(fileURLWithPath: "/Users/you/my notes/today.md"), to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "/Users/you/my notes/today.md", "no scheme, no quoting")
        DocumentPath.copyName(URL(fileURLWithPath: "/Users/you/my notes/today.md"), to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "today.md")
        DocumentPath.copyName(nil, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "Untitled")
    }

    @Test
    func theCommandIsAvailableOnlyWithAFile() {
        let textView = PaperTextView()
        let item = NSMenuItem(title: "Copy Path", action: #selector(PaperTextView.copyPath(_:)), keyEquivalent: "")
        #expect(!textView.validateUserInterfaceItem(item))
        textView.documentURL = URL(fileURLWithPath: "/tmp/paper-file-badge-test.md")
        #expect(textView.validateUserInterfaceItem(item))
        let unrelated = NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "")
        #expect(textView.validateUserInterfaceItem(unrelated), "other items keep the text view's answer")
    }
}
