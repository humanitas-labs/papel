import AppKit
import ImageIO

/// Loads the images a document embeds and remembers them for the session.
/// Only local files load: a remote destination makes a network request the
/// moment a document opens, which Paper does not do on the author's behalf,
/// so it stands as its alt text like a missing file.
///
/// Two caches. Pixel dimensions are read from the file header on the main
/// actor — cheap, and needed at style time so the band under an image line
/// is reserved before any bitmap exists. Bitmaps decode lazily, when a band
/// is first drawn, on a serial background queue: a document naming forty
/// large images opens at once and paints them as they arrive, and images
/// that never scroll into view never decode. The decoded bitmap is
/// downsampled to what the measure can show, so a 6000-pixel screenshot
/// does not become a 6000-pixel texture.
@MainActor
final class ImageStore {
    static let shared = ImageStore()

    /// Posted on the main actor, with the file URL as `object`, when a
    /// bitmap has decoded; a view showing it redraws.
    static let didLoadNotification = Notification.Name("org.humanitas.paper.ImageStore.didLoad")

    struct Entry {
        let image: NSImage
        /// The natural size in points, taken as the pixel size the way a
        /// browser shows it, before any fit to the measure.
        let naturalSize: NSSize
    }

    struct Dimensions {
        let naturalSize: NSSize
    }

    /// What the decoder hands back across the actor boundary.
    private struct Decoded: Sendable {
        let cgImage: CGImage
        let naturalSize: NSSize
    }

    private struct Cached {
        let entry: Entry?
        let modified: Date?
        let bytes: Int
    }

    private struct CachedDimensions {
        let dimensions: Dimensions?
        let modified: Date?
    }

    private var cache: [URL: Cached] = [:]
    private var dimensionCache: [URL: CachedDimensions] = [:]
    /// Least recently used first; eviction order for the byte budget.
    private var recency: [URL] = []
    private var totalBytes = 0
    /// URLs with a decode in flight, so a band redrawn while it waits
    /// does not queue a second one.
    private var decoding: Set<URL> = []
    /// Serial: one decode at a time keeps the transient memory of a
    /// forty-image document to one bitmap, not forty.
    private let decoder = DispatchQueue(label: "org.humanitas.paper.image-decode", qos: .userInitiated)

    /// The longest edge the decoded bitmap keeps, in pixels: twice the
    /// widest measure Settings allows, for Retina.
    nonisolated static let maximumPixelEdge: CGFloat = 2 * 1200

    /// The decoded bitmaps the cache may hold at once; the least recently
    /// used are dropped past it and decode again on their next draw.
    /// A variable so tests can shrink it.
    var byteBudget = 256 << 20
    /// Bounds the entry count too: missing files cache a nil at zero bytes,
    /// and a document can name any number of those.
    var entryLimit = 512

    // MARK: - Dimensions

    /// The pixel dimensions of the image at `url` from its header, or nil
    /// when it is remote, missing, or unreadable. Synchronous and cheap: no
    /// pixel is decoded. A file edited since it was cached is read again.
    func dimensions(for url: URL) -> Dimensions? {
        guard url.isFileURL else { return nil }
        let modified = Self.modificationDate(of: url)
        if let cached = dimensionCache[url], cached.modified == modified {
            return cached.dimensions
        }
        let dimensions = Self.readDimensions(url).map { Dimensions(naturalSize: $0) }
        if dimensionCache.count >= entryLimit * 4 { dimensionCache.removeAll() }
        dimensionCache[url] = CachedDimensions(dimensions: dimensions, modified: modified)
        return dimensions
    }

    // MARK: - Bitmaps

    /// The decoded bitmap at `url` if it is resident. Otherwise nil, and a
    /// decode starts (once) off the main actor; `didLoadNotification`
    /// follows when it lands. A file edited since it was cached decodes
    /// again the same way.
    func image(for url: URL) -> Entry? {
        guard url.isFileURL else { return nil }
        let modified = Self.modificationDate(of: url)
        if let cached = cache[url], cached.modified == modified {
            touch(url)
            return cached.entry
        }
        guard !decoding.contains(url) else { return nil }
        decoding.insert(url)
        decoder.async {
            let decoded = Self.load(url)
            Task { @MainActor in
                self.decoding.remove(url)
                self.store(decoded.map(Self.entry), for: url, modified: modified)
                NotificationCenter.default.post(name: Self.didLoadNotification, object: url)
            }
        }
        return nil
    }

    /// The decoded bitmap at `url`, decoding on the caller's thread when it
    /// is not resident. For callers that must have the bitmap now — the
    /// tests and render probes; the drawing path uses `image(for:)`.
    func entry(for url: URL) -> Entry? {
        guard url.isFileURL else { return nil }
        let modified = Self.modificationDate(of: url)
        if let cached = cache[url], cached.modified == modified {
            touch(url)
            return cached.entry
        }
        let entry = Self.load(url).map(Self.entry)
        store(entry, for: url, modified: modified)
        return entry
    }

    func forget(_ url: URL) {
        dimensionCache[url] = nil
        guard let cached = cache.removeValue(forKey: url) else { return }
        totalBytes -= cached.bytes
        recency.removeAll { $0 == url }
    }

    /// Whether `url`'s bitmap is decoded and resident (tests).
    func isCached(_ url: URL) -> Bool {
        cache[url] != nil
    }

    private func store(_ entry: Entry?, for url: URL, modified: Date?) {
        if let cached = cache.removeValue(forKey: url) {
            totalBytes -= cached.bytes
            recency.removeAll { $0 == url }
        }
        let bytes = entry.map { Int($0.image.representations.first.map { $0.pixelsWide * $0.pixelsHigh * 4 } ?? 0) } ?? 0
        cache[url] = Cached(entry: entry, modified: modified, bytes: bytes)
        recency.append(url)
        totalBytes += bytes
        evictIfNeeded()
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

    private static func entry(_ decoded: Decoded) -> Entry {
        Entry(image: NSImage(cgImage: decoded.cgImage, size: decoded.naturalSize), naturalSize: decoded.naturalSize)
    }

    // MARK: - File access

    nonisolated private static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// The upright pixel size from the header alone. EXIF orientations 5–8
    /// rotate a quarter turn, so their width and height swap.
    nonisolated private static func readDimensions(_ url: URL) -> NSSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0, height > 0
        else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return orientation >= 5 ? NSSize(width: height, height: width) : NSSize(width: width, height: height)
    }

    nonisolated private static func load(_ url: URL) -> Decoded? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let natural = readDimensions(url)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelEdge,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return Decoded(cgImage: cgImage, naturalSize: natural)
    }

    /// The size an image draws at inside `width`: its natural size, scaled
    /// down to fit the measure and never up past it.
    static func fit(_ natural: NSSize, width: CGFloat) -> NSSize {
        guard natural.width > width, natural.width > 0 else { return natural }
        let scale = width / natural.width
        return NSSize(width: width, height: (natural.height * scale).rounded())
    }
}
