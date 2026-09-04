import AppKit
import Foundation

/// The guide Paper opens on its first launch: a real Markdown file, read
/// in the editor itself, that says what the app is, lists the shortcuts,
/// and carries the prompt for an agent. It lives in Application Support,
/// out of the user's folders, and the welcome window's Guide item brings
/// it back whenever it is gone.
enum WelcomeDocument {
    static let fileName = "welcome.md"
    /// The mark, copied from the bundle beside the guide so the image link resolves.
    static let markName = "enso.png"
    static let bundledMark = Bundle.main.url(forResource: "enso-wide", withExtension: "png")

    /// `~/Library/Application Support/Paper/welcome.md`.
    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("Paper", isDirectory: true).appendingPathComponent(fileName)
    }

    /// The README's prompt: the quoted paragraph to add, then a check that the
    /// command works, then the offer to make Paper the default app, each
    /// its own paragraph so they read as such in the fence.
    static let agentPrompt = """
        Add the following to my global instructions:

        > Markdown files are read in Paper (a native macOS editor). To show me a document, open it with `paper <file.md>`. Paper reloads clean documents from disk automatically, so after the first open just keep editing the file. Never hard-wrap prose in Markdown — a paragraph is one source line; fixed-width wrapping renders as broken mid-paragraph lines.

        Then check that the `paper` command works: write a short Markdown note to a temporary file and open it with `paper`. If the command is not found, tell me; it installs from Paper's Settings (⌘,) under CLI.

        Finally, ask me explicitly whether I want Paper to be the default app for Markdown files, and explain what that means: double-clicking a .md file in Finder would open it in Paper instead of the current app. Do not change anything until I answer. Only if I say yes, run `paper --set-default`.
        """

    /// The command-line paragraph, from what the launch-time install found.
    static func commandLineNote(_ status: CommandLineTool.Status) -> String {
        let usage = "`paper notes.md` opens a document from the terminal, creating it first when it doesn't exist yet."
        switch status {
        case .installed(let link):
            return "The `paper` command is installed at `\(Self.abbreviated(link))`. \(usage)"
        case .notInstalled:
            return "\(usage) The command is not installed yet; install it from Settings (⌘,) under CLI."
        case .broken(let link), .stale(let link, _):
            return "\(usage) The command at `\(Self.abbreviated(link))` points at another copy of Paper; Settings (⌘,) under CLI repairs it."
        case .foreign(let link):
            return "\(usage) Something else named `paper` is at `\(Self.abbreviated(link))`, so Paper left it alone."
        }
    }

    private static func abbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    static func text(commandLine status: CommandLineTool.Status) -> String {
        """
        ![The Paper mark, an ink-brush circle](\(markName))

        # Welcome to Paper!

        > A quiet, native markdown editor for macOS.

        Paper is the simplest markdown editor imaginable. There are no buttons and no panels, only the text. Each document gets its own window so you can focus without distractions. Everything is a file on your computer, and you own it.

        This guide is a Markdown file like any other. Read it here, edit it, or close it; the welcome window's Guide item brings it back.

        ## 1. Prompt your agent

        Give this prompt to your agent of choice:

        ```
        \(agentPrompt)
        ```

        ## 2. CLI

        \(commandLineNote(status))

        ## 3. Default app for Markdown

        `paper --set-default` makes double-clicking a `.md` or `.markdown` file open Paper; so does *Make Default* in Settings (⌘,) under CLI. By hand: select any Markdown file in Finder, press ⌘I (Get Info), choose Paper under *Open with*, and click *Change All…*.

        ## 4. Shortcuts

        - ⌘B, ⌘I, ⌘U, ⌘⇧X, ⌘E: toggle `**bold**`, `*italic*`, `<u>underline</u>`, `~~strikethrough~~`, `` `code` `` around the selection or word
        - ⌘K: add a link, destination from the clipboard when it holds a URL
        - ⌘F, ⌘G, ⇧⌘G: find; next and previous match. Return and ⇧Return step from the field, Esc closes
        - Click or ⌘-click: open a link
        - Double-click an image: open it in Quick Look
        - Paste or drop an image: save a copy beside the document and insert its Markdown reference
        - ⌘N, ⌘O: new document, open a document
        - ⌘,: settings

        Pasting or dropping an image into an unsaved document asks you to save first. Images go beside the document by default; set `image.paste.directory = assets` to use a relative subfolder instead. Undo removes the inserted Markdown, but keeps the image file.

        ## 5. Configuration

        Settings live in `$XDG_CONFIG_HOME/paper/config` when set, otherwise `~/.config/paper/config`: typeface, size, measure, theme, window size. The file is written as a commented template on first launch and applied live to open windows whenever it is saved. Settings (⌘,) edits the same file.

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
            NSLog("Paper: could not write the guide: %@", error.localizedDescription)
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }
}
