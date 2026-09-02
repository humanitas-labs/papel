import Foundation

/// Where a Markdown destination points, for links and images alike
/// (ADR-003). The saved document's folder is the base for every relative
/// path; an unsaved document has no base, so its relative destinations
/// stay unresolved rather than falling back to the home folder or the
/// working directory. `~` is not expanded and no project root is inferred.
enum MarkdownResource {
    /// An absolute URL with a scheme and host, or a `mailto:` address —
    /// opened by the system, never read by Papel.
    static func isRemote(_ destination: String) -> Bool {
        guard !destination.isEmpty, !destination.contains(" "), let url = URL(string: destination) else { return false }
        return url.scheme != nil && url.host != nil || destination.hasPrefix("mailto:")
    }

    /// The local file a destination names, or nil for a remote destination
    /// or a relative path with no document to resolve it against.
    static func localURL(for destination: String, relativeTo documentURL: URL?) -> URL? {
        if isRemote(destination) { return nil }
        let path = destination.removingPercentEncoding ?? destination
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        guard let base = documentURL?.deletingLastPathComponent() else { return nil }
        return base.appendingPathComponent(path).standardizedFileURL
    }
}
