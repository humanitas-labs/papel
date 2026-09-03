import AppKit
import Foundation

/// The guide Papel opens on its first launch: a real Markdown file, read
/// in the editor itself, that says what the app is, lists the shortcuts,
/// and carries the prompt for an agent. It lives in Application Support,
/// out of the user's folders, and the welcome window's Guide item brings
/// it back whenever it is gone.
enum WelcomeDocument {
    static let fileName = "welcome.md"
    /// The mark, copied from the bundle beside the guide so the image link resolves.
    static let markName = "enso.png"
    static let bundledMark = Bundle.main.url(forResource: "enso-wide", withExtension: "png")

    /// `~/Library/Application Support/Papel/welcome.md`.
    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Papel", isDirectory: true).appendingPathComponent(fileName)
    }

    /// The README's prompt, with the instruction on its own line so the
    /// two paragraphs read as such in the fence.
    static let agentPrompt = """
        Add the following to my global instructions:

        Markdown files are read in Papel (a native macOS editor). To show me a document, open it with `papel <file.md>`. Papel reloads clean documents from disk automatically, so after the first open just keep editing the file. Never hard-wrap prose in Markdown — a paragraph is one source line; fixed-width wrapping renders as broken mid-paragraph lines.
        """

    /// The command-line paragraph, from what the launch-time install found.
    static func commandLineNote(_ status: CommandLineTool.Status) -> String {
        let usage = "`papel notes.md` opens a document from the terminal, creating it first when it doesn't exist yet."
        switch status {
        case .installed(let link):
            return "The `papel` command is installed at `\(Self.abbreviated(link))`. \(usage)"
        case .notInstalled:
            return "\(usage) The command is not installed yet; install it from Settings (⌘,) under CLI."
        case .broken(let link), .stale(let link, _):
            return "\(usage) The command at `\(Self.abbreviated(link))` points at another copy of Papel; Settings (⌘,) under CLI repairs it."
        case .foreign(let link):
            return "\(usage) Something else named `papel` is at `\(Self.abbreviated(link))`, so Papel left it alone."
        }
    }

    private static func abbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    static func text(commandLine status: CommandLineTool.Status) -> String {
        """
        ![The Papel mark, an ink-brush circle](\(markName))

        # Welcome to Papel!

        > A quiet, native markdown editor for macOS.

        Papel is the simplest markdown editor imaginable. There are no buttons and no panels, only the text. Each document gets its own window so you can focus without distractions. Everything is a file on your computer, and you own it.

        This guide is a Markdown file like any other. Read it here, edit it, or close it; the welcome window's Guide item brings it back.

        ## 1. Prompt your agent

        Give this prompt to your agent of choice:

        ```
        \(agentPrompt)
        ```

        ## 2. CLI

        \(commandLineNote(status))

        ## 3. Default app for Markdown

        To make double-clicking a `.md` file open Papel: select any Markdown file in Finder, press ⌘I (Get Info), choose Papel under *Open with*, and click *Change All…*. Repeat once for `.markdown` if you use that extension.

        ## 4. Shortcuts

        - ⌘B, ⌘I, ⌘U, ⌘⇧X, ⌘E: toggle `**bold**`, `*italic*`, `<u>underline</u>`, `~~strikethrough~~`, `` `code` `` around the selection or word
        - ⌘K: add a link, destination from the clipboard when it holds a URL
        - Click or ⌘-click: open a link
        - Double-click an image: open it in Quick Look
        - ⌘N, ⌘O: new document, open a document
        - ⌘,: settings

        ## 5. Configuration

        Everything lives in `~/.config/papel/config`: typeface, size, measure, theme, window size. It is written as a commented template on first launch and applied live to open windows whenever it is saved. Settings (⌘,) edits the same file.

        """
    }

    /// Writes the guide at `url`, and the mark beside it from `mark`. An
    /// existing guide is kept unless `replacing`, so a user's edits survive
    /// the Guide item; the mark is refreshed either way.
    @discardableResult
    static func write(to url: URL = defaultURL, text: String, mark: URL? = bundledMark, replacing: Bool) throws -> Bool {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if let mark {
            let copy = directory.appendingPathComponent(markName)
            if fileManager.fileExists(atPath: copy.path) { try fileManager.removeItem(at: copy) }
            try fileManager.copyItem(at: mark, to: copy)
        }
        if !replacing, fileManager.fileExists(atPath: url.path) { return false }
        try text.write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    /// Writes the guide from the command's current status and opens it in
    /// a document window.
    @MainActor
    static func open(replacing: Bool) async {
        let tool = CommandLineTool.shared
        if tool.quietOutcome == nil { await tool.refresh() }
        let url = defaultURL
        do {
            try write(to: url, text: text(commandLine: tool.status), replacing: replacing)
        } catch {
            NSLog("Papel: could not write the guide: %@", error.localizedDescription)
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }
}
