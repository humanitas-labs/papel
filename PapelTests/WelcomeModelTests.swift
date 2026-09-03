import Foundation
import Testing
@testable import Papel

struct WelcomeModelTests {
    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test func listsExistingFilesNewestFirstUpToFive() {
        let urls = (1...7).map { url("/tmp/notes/\($0).md") }
        let recents = WelcomeModel.recents(from: urls) { _ in true }
        #expect(recents.map(\.name) == ["1.md", "2.md", "3.md", "4.md", "5.md"])
    }

    @Test func dropsMissingFilesAndDuplicates() {
        let urls = [url("/tmp/a.md"), url("/tmp/gone.md"), url("/tmp/./a.md"), url("/tmp/b.md")]
        let recents = WelcomeModel.recents(from: urls) { $0.lastPathComponent != "gone.md" }
        #expect(recents.map(\.name) == ["a.md", "b.md"])
    }

    @Test func folderIsTildeAbbreviated() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let recents = WelcomeModel.recents(from: [home.appendingPathComponent("Documents/notes.md")]) { _ in true }
        #expect(recents.first?.folder == "~/Documents")
        #expect(recents.first?.name == "notes.md")
    }

    @Test func greetingFollowsTheHour() {
        #expect(WelcomeModel.greeting(hour: 8) { _ in 0 } == "Good morning")
        #expect(WelcomeModel.greeting(hour: 14) { _ in 0 } == "Good afternoon")
        #expect(WelcomeModel.greeting(hour: 20) { _ in 0 } == "Good evening")
        #expect(WelcomeModel.greeting(hour: 2) { _ in 0 } == "Welcome back", "the small hours have no timed greeting")
    }

    @Test func greetingPoolIncludesTheAnytimeGreetingsAndClampsThePick() {
        let count = WelcomeModel.timedGreetings(hour: 8).count
        #expect(WelcomeModel.greeting(hour: 8) { _ in count } == "Welcome back")
        #expect(WelcomeModel.greeting(hour: 8) { _ in 999 } == WelcomeModel.anytimeGreetings.last)
    }
}
