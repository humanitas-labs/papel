import Foundation

/// What the welcome window lists: the recent documents that still exist,
/// newest first, at most five, each with its name and the folder it sits
/// in. Pure, so the listing is testable without a window.
enum WelcomeModel {
    struct Recent: Identifiable, Equatable, Sendable {
        let url: URL
        /// The file name, extension included.
        let name: String
        /// The enclosing folder, `~`-abbreviated, for telling like names apart.
        let folder: String
        var id: URL { url }
    }

    static let maximumRecents = 5

    /// The greeting, the same at every hour.
    static let greeting = "Welcome back"

    static func recents(
        from urls: [URL],
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> [Recent] {
        var seen: Set<URL> = []
        var recents: [Recent] = []
        for url in urls {
            let standardized = url.standardizedFileURL
            guard !seen.contains(standardized), exists(standardized) else { continue }
            seen.insert(standardized)
            recents.append(Recent(
                url: standardized,
                name: standardized.lastPathComponent,
                folder: (standardized.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
            ))
            if recents.count == maximumRecents { break }
        }
        return recents
    }
}
