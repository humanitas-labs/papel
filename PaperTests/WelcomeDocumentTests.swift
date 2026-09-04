import Foundation
import Testing
@testable import Paper

struct WelcomeDocumentTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paper-welcome-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func namesTheLinkWhenInstalled() {
        let link = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/paper")
        let text = WelcomeDocument.text(commandLine: .installed(link))
        #expect(text.contains("installed at `~/.local/bin/paper`"))
        #expect(!text.contains("The command is not installed yet"))
    }

    @Test func pointsAtSettingsWhenNotInstalled() {
        let text = WelcomeDocument.text(commandLine: .notInstalled)
        #expect(text.contains("not installed yet; install it from Settings (⌘,) under CLI"))
        #expect(!text.contains("installed at"))
    }

    @Test func offersRepairForAnotherCopysLink() {
        let link = URL(fileURLWithPath: "/usr/local/bin/paper")
        for status in [CommandLineTool.Status.broken(link), .stale(link, target: URL(fileURLWithPath: "/x/Paper.app/Contents/Resources/paper"))] {
            let text = WelcomeDocument.text(commandLine: status)
            #expect(text.contains("The command at `/usr/local/bin/paper` points at another copy of Paper"))
        }
        #expect(WelcomeDocument.text(commandLine: .foreign(link)).contains("Something else named `paper` is at `/usr/local/bin/paper`"))
    }

    @Test func carriesTheAgentPromptInAFence() {
        let text = WelcomeDocument.text(commandLine: .notInstalled)
        #expect(text.contains("```\n\(WelcomeDocument.agentPrompt)\n```"))
        #expect(text.hasPrefix("![The Paper mark, an ink-brush circle](enso.png)\n\n# Welcome to Paper!\n"))
    }

    @Test func promptChecksTheCommandAndOffersTheDefault() {
        let prompt = WelcomeDocument.agentPrompt
        #expect(prompt.hasPrefix("Add the following to my global instructions:\n\n> Markdown files are read in Paper"))
        #expect(prompt.contains("mid-paragraph lines.\n\nThen check that"))
        #expect(prompt.contains("check that the `paper` command works"))
        #expect(prompt.contains("ask me explicitly whether I want Paper to be the default app for Markdown files"))
        #expect(prompt.contains("Do not change anything until I answer. Only if I say yes, run `paper --set-default`."))
        #expect(prompt.contains("run `paper --set-default`"))
        let text = WelcomeDocument.text(commandLine: .notInstalled)
        #expect(text.contains("## 3. Default app for Markdown\n\n`paper --set-default`"))
    }

    @Test func keepsAnExistingFileUnlessReplacing() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Paper/welcome.md")
        let mark = directory.appendingPathComponent("mark.png")
        try Data([1, 2, 3]).write(to: mark)
        #expect(try WelcomeDocument.write(to: url, text: "first", mark: mark, replacing: false))
        #expect(try !WelcomeDocument.write(to: url, text: "second", mark: mark, replacing: false))
        #expect(try String(contentsOf: url, encoding: .utf8) == "first")
        #expect(try WelcomeDocument.write(to: url, text: "third", mark: mark, replacing: true))
        #expect(try String(contentsOf: url, encoding: .utf8) == "third")
        #expect(try Data(contentsOf: directory.appendingPathComponent("Paper/enso.png")) == Data([1, 2, 3]))
        #expect(WelcomeDocument.bundledMark != nil, "the mark ships in the bundle")
    }

    @Test @MainActor func storeReportsFirstLaunchOnlyWhenItCreatesTheFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config")
        let first = ConfigurationStore(fileURL: url)
        first.ensureFileExists()
        #expect(first.isFirstLaunch)
        let second = ConfigurationStore(fileURL: url)
        second.ensureFileExists()
        #expect(!second.isFirstLaunch)
    }
}
