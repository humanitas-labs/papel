import AppKit
import ImageIO

/// Loads the images a document embeds and remembers them for the session.
/// Only local files load: a remote destination makes a network request the
/// moment a document opens, which Paper does not do on the author's behalf,
/// so it stands as its alt text like a missing file. Loading is synchronous
/// — a local read is cheap next to a restyle — and the decoded bitmap is
/// downsampled to what the measure can show, so a 6000-pixel screenshot
/// does not become a 6000-pixel texture.
@MainActor
final class ImageStore {
    static let shared = ImageStore()

    struct Entry {
        let image: NSImage
        /// The natural size in points, taken as the pixel size the way a
        /// browser shows it, before any fit to the measure.
        let naturalSize: NSSize
    }

    private struct Cached {
        let entry: Entry?
        let modified: Date?
    }

    private var cache: [URL: Cached] = [:]

    /// The longest edge the decoded bitmap keeps, in pixels: twice the
    /// widest measure Settings allows, for Retina.
    static let maximumPixelEdge: CGFloat = 2 * 1200

    /// The image at `url`, or nil when it is remote, missing, or unreadable.
    /// A file edited since it was cached is decoded again.
    func entry(for url: URL) -> Entry? {
        guard url.isFileURL else { return nil }
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let cached = cache[url], cached.modified == modified {
            return cached.entry
        }
        let entry = Self.load(url)
        cache[url] = Cached(entry: entry, modified: modified)
        return entry
    }

    func forget(_ url: URL) {
        cache[url] = nil
    }

    private static func load(_ url: URL) -> Entry? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelEdge,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        // EXIF orientation may swap the edges; the thumbnail is already
        // upright, so its aspect is the truth and the natural width is
        // the source's longest matching edge.
        let upright = (cgImage.width >= cgImage.height) == (width >= height)
        let natural = upright ? NSSize(width: width, height: height) : NSSize(width: height, height: width)
        return Entry(image: NSImage(cgImage: cgImage, size: natural), naturalSize: natural)
    }

    /// The size an image draws at inside `width`: its natural size, scaled
    /// down to fit the measure and never up past it.
    static func fit(_ natural: NSSize, width: CGFloat) -> NSSize {
        guard natural.width > width, natural.width > 0 else { return natural }
        let scale = width / natural.width
        return NSSize(width: width, height: (natural.height * scale).rounded())
    }

    /// The image file a Markdown destination names, relative to the
    /// document's folder; nil for a remote destination.
    static func resolve(_ destination: String, relativeTo documentURL: URL?) -> URL? {
        if PaperTextView.looksLikeURL(destination) { return nil }
        let path = destination.removingPercentEncoding ?? destination
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        guard let base = documentURL?.deletingLastPathComponent() else { return nil }
        return base.appendingPathComponent(path).standardizedFileURL
    }
}
