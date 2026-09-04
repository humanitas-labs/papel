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

    @Test func carriesTheAgentPromptInAFence() {
        let text = WelcomeDocument.text
        #expect(text.contains("```\n\(WelcomeDocument.agentPrompt)\n```"))
        #expect(text.hasPrefix("![The Paper mark, an ink-brush circle](enso.png)\n\n# Welcome to Paper!\n"))
    }

    @Test func promptChecksTheCommandAndLeavesTheTerminalToTheAgent() {
        let prompt = WelcomeDocument.agentPrompt
        #expect(prompt.hasPrefix("Add this to my global instructions:\n\n> Markdown files are read in Paper"))
        #expect(prompt.contains("one source line.\n\nThen check that the `paper` command works"))
        #expect(prompt.contains("If I am someone who works in the terminal"))
        #expect(prompt.contains("Ask before running that. If I am not, skip this."))
        let text = WelcomeDocument.text
        #expect(!text.contains("## 2. CLI"), "the terminal is the agent's to mention")
    }

    @Test func wearsItsOwnFormatting() {
        let text = WelcomeDocument.text
        #expect(text.contains("**bold** is ⌘B, *italic* is ⌘I, `code` is ⌘E"))
        #expect(text.contains("- [ ] A task, with a circle you can click\n  - [ ] A nested task"))
        #expect(text.contains("- [x] A task that is done"))
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
