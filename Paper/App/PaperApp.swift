import SwiftUI

@main
struct PaperApp: App {
    /// Observed so scene-level values such as the default window size
    /// follow the configuration.
    @ObservedObject private var store = ConfigurationStore.shared
    init() {
        ConfigurationStore.shared.start()
    }

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { configuration in
            DocumentView(document: configuration.$document, fileURL: configuration.fileURL)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: store.current.windowWidth, height: store.current.windowHeight)
        .commands {
            // Replacing the toolbar group empties SwiftUI's View menu, which
            // also drops AppKit's Enter Full Screen item and its ⌃⌘F shortcut.
            // Provide the toggle explicitly so the shortcut keeps working.
            // Markdown emphasis in the Format menu; AppKit's rich-text
            // items would set font traits the document cannot keep.
            CommandGroup(replacing: .textFormatting) {
                Button("Bold") { NSApp.sendAction(#selector(PaperTextView.toggleBold(_:)), to: nil, from: nil) }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Italic") { NSApp.sendAction(#selector(PaperTextView.toggleItalic(_:)), to: nil, from: nil) }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Underline") { NSApp.sendAction(#selector(PaperTextView.toggleUnderline(_:)), to: nil, from: nil) }
                    .keyboardShortcut("u", modifiers: .command)
                Button("Code") { NSApp.sendAction(#selector(PaperTextView.toggleCode(_:)), to: nil, from: nil) }
                    .keyboardShortcut("e", modifiers: .command)
            }
            CommandGroup(replacing: .toolbar) {
                Button("Toggle Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
            }
        }

        Settings {
            SettingsView()
        }
    }
}

private struct DocumentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?
    /// Observed so the SwiftUI canvas and label follow theme changes.
    @ObservedObject private var store = ConfigurationStore.shared

    var body: some View {
        MarkdownEditor(text: $document.text)
            .background(Color(nsColor: Appearance.canvas))
            .background(WindowConfigurator())
            .frame(minWidth: 640, minHeight: 520)
            .ignoresSafeArea()
    }
}
