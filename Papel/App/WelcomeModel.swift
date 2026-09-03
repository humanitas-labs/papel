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

    /// Greetings that fit any hour.
    static let anytimeGreetings = ["Welcome back", "Hello again", "Hello there"]

    /// Greetings for the time of day: morning before noon, afternoon until
    /// six, evening until eleven; the small hours get only the anytime pool.
    static func timedGreetings(hour: Int) -> [String] {
        switch hour {
        case 5..<12: return ["Good morning"]
        case 12..<18: return ["Good afternoon"]
        case 18..<23: return ["Good evening"]
        default: return []
        }
    }

    /// A greeting for `hour`: the timed and anytime pools together, chosen
    /// by `pick` in the pool's range. Timed greetings are listed first, so
    /// a pick within their count is time-aware.
    static func greeting(hour: Int, pick: (Int) -> Int = { Int.random(in: 0..<$0) }) -> String {
        let pool = timedGreetings(hour: hour) + anytimeGreetings
        return pool[min(max(pick(pool.count), 0), pool.count - 1)]
    }

    static func greeting(at date: Date = Date()) -> String {
        greeting(hour: Calendar.current.component(.hour, from: date))
    }

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
