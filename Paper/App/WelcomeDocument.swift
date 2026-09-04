import AppKit
import Foundation

/// The guide Paper opens on its first launch: a real Markdown file, read
/// in the editor itself, that says what the app is, shows the formatting
/// by wearing it, and carries the prompt for an agent. It lives in Application Support,
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

    /// The prompt for an agent: the instruction to add, the check that
    /// the command works, and the terminal notes to give only to someone
    /// who works there.
    static let agentPrompt = """
        Add this to my global instructions:

        > Markdown files are read in Paper, a native macOS editor. To show me a document, open it with `paper <file.md>`. Paper reloads from disk, so after the first open just keep editing the file. Never hard-wrap prose in Markdown: a paragraph is one source line.

        Then check that the `paper` command works by writing a short note to a temporary file and opening it with `paper`. If the command is not found, tell me; it installs from Paper's Settings (⌘,) under CLI.

        If I am someone who works in the terminal, also tell me that `paper <file>` opens any Markdown file from the shell, and that `paper --set-default` makes Paper the app that opens Markdown files when I double-click them. Ask before running that. If I am not, skip this.
        """

    static let text = """
        ![The Paper mark, an ink-brush circle](\(markName))

        # Welcome to Paper!

        > A quiet, native markdown editor for macOS.

        Paper is the simplest markdown editor imaginable. There are no buttons and no panels, only the text. Each document gets its own window so you can focus with no distractions.

        This guide is a Markdown file like any other. Edit it or close it; *Guide* in the welcome window brings it back.

        ## 1. Paper is agent-friendly

        Paper is made to work well with agents.

        Paste this into Claude Code, Codex, or whichever agent you use, and from then on you can have it open docs in Paper for you:

        ```
        \(agentPrompt)
        ```

        ## 2. The basics

        Click into this paragraph and the Markdown shows itself: **bold** is ⌘B, *italic* is ⌘I, `code` is ⌘E, and a [link](https://papel.sh) is ⌘K. Click a link to follow it, ⌘F to find.

        - A dash starts a list
        * A star starts a bullet
        - [ ] A task, with a circle you can click
          - [ ] A nested task, with a square you can click
        - [x] A task that is done

        Paste or drop an image and Paper saves it beside the document. Double-click an image to see it full size.

        ## 3. Configuration

        Settings (⌘,) covers typeface, size, measure, theme, and window size. It edits `~/.config/paper/config`, which you can also edit by hand; changes apply live.

        """

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

    /// Writes the guide and opens it in a document window.
    @MainActor
    static func open(replacing: Bool) async {
        let url = defaultURL
        do {
            try write(to: url, text: text, replacing: replacing)
        } catch {
            NSLog("Paper: could not write the guide: %@", error.localizedDescription)
            return
        }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }
}
