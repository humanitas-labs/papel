import SwiftUI

@main
struct PapelApp: App {
    /// Observed so scene-level values such as the default window size
    /// follow the configuration.
    @ObservedObject private var store = ConfigurationStore.shared
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
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
                Button("Bold") { NSApp.sendAction(#selector(PapelTextView.toggleBold(_:)), to: nil, from: nil) }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Italic") { NSApp.sendAction(#selector(PapelTextView.toggleItalic(_:)), to: nil, from: nil) }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Underline") { NSApp.sendAction(#selector(PapelTextView.toggleUnderline(_:)), to: nil, from: nil) }
                    .keyboardShortcut("u", modifiers: .command)
                Button("Strikethrough") { NSApp.sendAction(#selector(PapelTextView.toggleStrikethrough(_:)), to: nil, from: nil) }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                Button("Code") { NSApp.sendAction(#selector(PapelTextView.toggleCode(_:)), to: nil, from: nil) }
                    .keyboardShortcut("e", modifiers: .command)
                Divider()
                Button("Add Link") { NSApp.sendAction(#selector(PapelTextView.insertLink(_:)), to: nil, from: nil) }
                    .keyboardShortcut("k", modifiers: .command)
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
    @State private var watcher: FileWatcher?

    var body: some View {
        MarkdownEditor(text: $document.text, fileURL: fileURL)
            .background(Color(nsColor: Appearance.canvas))
            .background(WindowConfigurator())
            .frame(minWidth: 640, minHeight: 520)
            .ignoresSafeArea()
            .onChange(of: fileURL, initial: true) { _, url in
                watcher?.cancel()
                watcher = url.map { url in
                    FileWatcher(url: url) { reload(from: url) }
                }
            }
            .onDisappear {
                watcher?.cancel()
                watcher = nil
            }
    }

    /// Follows edits other programs save to the open file. A buffer with
    /// unsaved changes keeps them and surfaces the conflict on save, as
    /// before; a clean buffer adopts the disk content in place.
    private func reload(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let fresh = try? MarkdownDocument(data: data),
              fresh.text != document.text else { return }
        let nsDocument = NSDocumentController.shared.document(for: url)
        if nsDocument?.isDocumentEdited == true { return }
        document.text = fresh.text
        // The binding write marks the document edited; it now matches the
        // disk, so clear the change count and adopt the file's modification
        // date, keeping the next save quiet about the external edit.
        DispatchQueue.main.async {
            // A keystroke landing between the adoption above and this
            // deferred reset is a real edit; clearing then would mark it
            // clean and close without the unsaved-change protection. Only
            // a buffer still matching what was adopted is clean.
            guard document.text == fresh.text else { return }
            nsDocument?.updateChangeCount(.changeCleared)
            if let date = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate {
                nsDocument?.fileModificationDate = date
            }
        }
    }
}
