import AppKit
import Combine

/// The once-a-day look at GitHub for a newer release. When one is out, the
/// welcome window shows a download icon that opens the DMG link, the same
/// path as the site; nothing appears when the app is current, offline, or
/// the request fails, and the check never blocks launch. No framework, no
/// keys, no in-app install.
enum UpdateCheck {
    struct Release: Equatable, Sendable {
        /// The version without a leading `v`.
        let version: String
        /// The download: the stable `releases/latest/download/Papel.dmg`
        /// rather than the asset's own URL, so it survives a renamed asset.
        let url: URL
    }

    static let repository = "humanitas-labs/papel"
    static let latestURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    static let downloadURL = URL(string: "https://github.com/\(repository)/releases/latest/download/Papel.dmg")!
    static let interval: TimeInterval = 24 * 60 * 60

    static let lastCheckKey = "papel.update.lastCheck"
    static let availableKey = "papel.update.available"

    /// What the welcome window observes.
    @MainActor
    final class Observed: ObservableObject {
        @Published var available: Release?
    }

    @MainActor static let observed = Observed()

    // MARK: - Pure parts

    /// The release in a `releases/latest` body: `tag_name` with any leading
    /// `v` dropped. nil for anything that is not a release.
    static func release(from data: Data) -> Release? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = object["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard !version.isEmpty, components(of: version) != nil else { return nil }
        return Release(version: version, url: downloadURL)
    }

    /// Whether `latest` is newer than `current`, comparing dotted numeric
    /// components; a missing component is 0. Either side unparsable is
    /// false: never nag on a bad tag.
    static func isNewer(_ latest: String, than current: String) -> Bool {
        guard let a = components(of: latest), let b = components(of: current) else { return false }
        let count = max(a.count, b.count)
        for index in 0..<count {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Whether a check should run now: never checked, or a day or more ago.
    static func isDue(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    private static func components(of version: String) -> [Int]? {
        let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        return numbers
    }

    // MARK: - Runner

    /// The bundle's marketing version.
    static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Shows a release found earlier today, then asks again when due. Off
    /// under `update.check = off`; the caller keeps it off under tests.
    @MainActor
    static func runIfDue(
        configuration: Configuration,
        defaults: UserDefaults = .standard,
        current: String = bundleVersion,
        now: Date = Date()
    ) {
        guard configuration.updateCheck else { return }
        if let known = defaults.string(forKey: availableKey) {
            if isNewer(known, than: current) {
                observed.available = Release(version: known, url: downloadURL)
            } else {
                defaults.removeObject(forKey: availableKey)
            }
        }
        guard isDue(lastCheck: defaults.object(forKey: lastCheckKey) as? Date, now: now) else { return }
        // Recorded before the request so a flaky network does not retry
        // every launch.
        defaults.set(now, forKey: lastCheckKey)
        // The request runs off the main actor inside URLSession; only the
        // result comes back here.
        Task {
            guard let data = await fetchLatest() else { return }
            record(release(from: data), current: current, defaults: defaults)
        }
    }

    @MainActor
    private static func record(_ release: Release?, current: String, defaults: UserDefaults) {
        guard let release, isNewer(release.version, than: current) else {
            defaults.removeObject(forKey: availableKey)
            observed.available = nil
            return
        }
        defaults.set(release.version, forKey: availableKey)
        observed.available = release
    }

    private static func fetchLatest() async -> Data? {
        var request = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Papel/\(bundleVersion)", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral)
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// Opens the download in the browser.
    static func download(_ release: Release) {
        NSWorkspace.shared.open(release.url)
    }
}
