import Foundation

/// A fresh `UserDefaults` suite for one test, removed when the test ends.
/// The suite is a plist under `~/Library/Preferences`, so one left behind
/// is a file on the developer's machine (#60): make it here and `defer`
/// `remove()`, so a failing test cleans up too.
struct TestDefaults {
    let suite: String
    let defaults: UserDefaults

    init(_ label: String) {
        suite = "paper.tests.\(label).\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    /// Removing the domain empties it, but cfprefsd leaves the empty plist
    /// on disk, still listed by `defaults domains`; so the file goes too.
    func remove() {
        defaults.removePersistentDomain(forName: suite)
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suite).plist")
        try? FileManager.default.removeItem(at: plist)
    }
}
