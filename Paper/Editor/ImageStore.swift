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
        let bytes: Int
    }

    private var cache: [URL: Cached] = [:]
    /// Least recently used first; eviction order for the byte budget.
    private var recency: [URL] = []
    private var totalBytes = 0

    /// The longest edge the decoded bitmap keeps, in pixels: twice the
    /// widest measure Settings allows, for Retina.
    static let maximumPixelEdge: CGFloat = 2 * 1200

    /// The decoded bitmaps the cache may hold at once; the least recently
    /// used are dropped past it and decode again on their next restyle.
    /// A variable so tests can shrink it.
    var byteBudget = 256 << 20
    /// Bounds the entry count too: missing files cache a nil at zero bytes,
    /// and a document can name any number of those.
    var entryLimit = 512

    /// The image at `url`, or nil when it is remote, missing, or unreadable.
    /// A file edited since it was cached is decoded again.
    func entry(for url: URL) -> Entry? {
        guard url.isFileURL else { return nil }
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let cached = cache[url], cached.modified == modified {
            touch(url)
            return cached.entry
        }
        forget(url)
        let entry = Self.load(url)
        let bytes = entry.map { Int($0.image.representations.first.map { $0.pixelsWide * $0.pixelsHigh * 4 } ?? 0) } ?? 0
        cache[url] = Cached(entry: entry, modified: modified, bytes: bytes)
        recency.append(url)
        totalBytes += bytes
        evictIfNeeded()
        return entry
    }

    func forget(_ url: URL) {
        guard let cached = cache.removeValue(forKey: url) else { return }
        totalBytes -= cached.bytes
        recency.removeAll { $0 == url }
    }

    /// Whether `url` is decoded and resident (tests).
    func isCached(_ url: URL) -> Bool {
        cache[url] != nil
    }

    private func touch(_ url: URL) {
        guard recency.last != url else { return }
        recency.removeAll { $0 == url }
        recency.append(url)
    }

    /// Drops least recently used entries past the budgets. The newest entry
    /// always stays, even alone over budget: it is the one being drawn.
    private func evictIfNeeded() {
        while (totalBytes > byteBudget || cache.count > entryLimit),
              recency.count > 1,
              let oldest = recency.first {
            forget(oldest)
        }
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
}
