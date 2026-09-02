import AppKit
import Testing
@testable import Paper

/// Block images: `![alt](file)` alone on a line reserves a band under the
/// line by paragraph spacing and draws the bitmap there. The source is
/// never edited, the band is constant whether the line is concealed or
/// revealed, and a missing or remote file stands as its alt text.
@MainActor
@Suite(.serialized)
struct ImageTests {
    /// A folder holding the "document" and the images it references.
    private let folder: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paper-image-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private var documentURL: URL { folder.appendingPathComponent("doc.md") }

    @discardableResult
    private func writePNG(_ name: String, width: Int, height: Int) -> URL {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        let url = folder.appendingPathComponent(name)
        try! rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    private func styledView(_ text: String, documentURL: URL? = nil) -> PaperTextView {
        let textView = PaperTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        textView.documentURL = documentURL
        textView.string = text
        textView.syntaxStyler.apply(to: textView)
        return textView
    }

    private func spacing(at location: Int, in textView: PaperTextView) -> CGFloat {
        (textView.textStorage!.attribute(.paragraphStyle, at: location, effectiveRange: nil) as! NSParagraphStyle).paragraphSpacing
    }

    @Test
    func aWideImageFitsTheMeasureAndReservesItsHeight() throws {
        writePNG("wide.png", width: 1600, height: 400)
        let textView = styledView("before\n![A wide one](wide.png)\nafter", documentURL: documentURL)
        let storage = try #require(textView.textStorage)
        let text = textView.string as NSString
        let line = text.range(of: "![A wide one](wide.png)")

        // The 800 pt frame holds the configured measure with its margins.
        let measure = MarkdownSyntaxStyler.measure(of: textView)
        #expect(measure > 500 && measure < 800)
        let fitted = ImageStore.fit(NSSize(width: 1600, height: 400), width: measure)
        #expect(fitted.width == measure && fitted.height == (measure / 4).rounded(), "1600×400 scales to the measure")
        #expect(spacing(at: line.location, in: textView) == fitted.height + Appearance.paragraphSpacing)
        #expect(storage.attribute(.imageSource, at: line.location, effectiveRange: nil) as? URL == folder.appendingPathComponent("wide.png").standardizedFileURL)
        #expect(storage.attribute(.glyphSubstitute, at: line.location, effectiveRange: nil) as? String == " ", "the `!` keeps the line its own fragment")
        for offset in 1..<line.length {
            #expect(storage.attribute(.concealable, at: line.location + offset, effectiveRange: nil) != nil, "offset \(offset) conceals")
        }
        #expect(spacing(at: 0, in: textView) == Appearance.paragraphSpacing, "the line before is untouched")

        let layoutManager = try #require(textView.layoutManager as? PaperLayoutManager)
        let container = try #require(textView.textContainer)
        layoutManager.ensureLayout(for: container)
        let all = layoutManager.glyphRange(for: container)
        let bands = layoutManager.imageBands(forGlyphRange: all, width: measure)
        let band = try #require(bands.first)
        #expect(bands.count == 1)
        #expect(band.rect.size == fitted)
        #expect(band.rect.minX == container.lineFragmentPadding, "the band's edges are the text's")
        let lineGlyphs = layoutManager.glyphRange(forCharacterRange: line, actualCharacterRange: nil)
        let used = layoutManager.lineFragmentUsedRect(forGlyphAt: lineGlyphs.location, effectiveRange: nil)
        #expect(band.rect.minY == used.maxY, "the band starts under the source line")
        let afterGlyphs = layoutManager.glyphRange(forCharacterRange: text.range(of: "after"), actualCharacterRange: nil)
        let after = layoutManager.lineFragmentRect(forGlyphAt: afterGlyphs.location, effectiveRange: nil)
        #expect(abs(after.minY - (band.rect.maxY + Appearance.paragraphSpacing)) < 1, "the next line follows the band plus the ordinary spacing")
    }

    @Test
    func aSmallImageIsNeverUpscaled() throws {
        writePNG("small.png", width: 200, height: 100)
        let textView = styledView("![](small.png)", documentURL: documentURL)
        #expect(spacing(at: 0, in: textView) == 100 + Appearance.paragraphSpacing)
        let layoutManager = try #require(textView.layoutManager as? PaperLayoutManager)
        let container = try #require(textView.textContainer)
        layoutManager.ensureLayout(for: container)
        let band = try #require(layoutManager.imageBands(forGlyphRange: layoutManager.glyphRange(for: container), width: 640).first)
        #expect(band.rect.size == NSSize(width: 200, height: 100))
    }

    /// The band is paragraph spacing, reserved whether the source line is
    /// concealed or revealed, so the caret entering the image line moves
    /// nothing below it.
    @Test
    func revealingTheImageLineKeepsTheDocumentHeight() throws {
        writePNG("wide.png", width: 1600, height: 400)
        let textView = styledView("# Title\n\n![alt](wide.png)\n\nafter", documentURL: documentURL)
        let layoutManager = try #require(textView.layoutManager as? PaperLayoutManager)
        let container = try #require(textView.textContainer)
        let text = textView.string as NSString
        let line = text.paragraphRange(for: text.range(of: "![alt]"))

        layoutManager.setActiveRange(NSRange(location: 0, length: 0))
        layoutManager.ensureLayout(for: container)
        let concealed = layoutManager.usedRect(for: container).height
        let afterConcealed = layoutManager.lineFragmentRect(
            forGlyphAt: layoutManager.glyphRange(forCharacterRange: text.range(of: "after"), actualCharacterRange: nil).location,
            effectiveRange: nil
        ).minY

        layoutManager.setActiveRange(line)
        layoutManager.ensureLayout(for: container)
        #expect(layoutManager.usedRect(for: container).height == concealed)
        let afterRevealed = layoutManager.lineFragmentRect(
            forGlyphAt: layoutManager.glyphRange(forCharacterRange: text.range(of: "after"), actualCharacterRange: nil).location,
            effectiveRange: nil
        ).minY
        #expect(afterRevealed == afterConcealed)
        #expect(layoutManager.imageBands(forGlyphRange: layoutManager.glyphRange(for: container), width: 640).count == 1, "the band stays while the source shows")
    }

    @Test
    func aMissingFileShowsItsAltTextMuted() throws {
        let textView = styledView("![Lost figure](nowhere.png)", documentURL: documentURL)
        let storage = try #require(textView.textStorage)
        let alt = (textView.string as NSString).range(of: "Lost figure")
        #expect(storage.attribute(.imageSource, at: 0, effectiveRange: nil) == nil)
        #expect(spacing(at: 0, in: textView) == Appearance.paragraphSpacing)
        #expect(storage.attribute(.font, at: alt.location, effectiveRange: nil) as? NSFont == Appearance.italicFont())
        #expect(storage.attribute(.foregroundColor, at: alt.location, effectiveRange: nil) as? NSColor == Appearance.mutedInk)
        #expect(storage.attribute(.concealable, at: alt.location, effectiveRange: nil) == nil, "the alt text shows")
        #expect(storage.attribute(.concealable, at: 0, effectiveRange: nil) != nil, "`![` conceals")
        #expect(storage.attribute(.concealable, at: NSMaxRange(alt), effectiveRange: nil) != nil, "`](…)` conceals")
    }

    /// No request leaves the machine when a document opens: a remote image
    /// stands as its alt text.
    @Test
    func aRemoteImageIsNotFetched() throws {
        #expect(MarkdownResource.localURL(for: "https://example.com/a.png", relativeTo: documentURL) == nil)
        let textView = styledView("![Remote](https://example.com/a.png)", documentURL: documentURL)
        let storage = try #require(textView.textStorage)
        #expect(storage.attribute(.imageSource, at: 0, effectiveRange: nil) == nil)
        let alt = (textView.string as NSString).range(of: "Remote")
        #expect(storage.attribute(.font, at: alt.location, effectiveRange: nil) as? NSFont == Appearance.italicFont())
    }

    @Test
    func anUnsavedDocumentResolvesNoRelativeImage() throws {
        writePNG("wide.png", width: 1600, height: 400)
        #expect(MarkdownResource.localURL(for: "wide.png", relativeTo: nil) == nil)
        let textView = styledView("![alt](wide.png)", documentURL: nil)
        #expect(textView.textStorage?.attribute(.imageSource, at: 0, effectiveRange: nil) == nil)
        #expect(textView.linkURL(for: "wide.png") == nil, "links share the resolver: nothing to open until the document is saved")
        #expect(textView.linkURL(for: "https://example.com")?.absoluteString == "https://example.com")
        textView.documentURL = documentURL
        #expect(textView.textStorage?.attribute(.imageSource, at: 0, effectiveRange: nil) != nil, "a Save As restyles against the new base")
        #expect(textView.linkURL(for: "wide.png") == folder.appendingPathComponent("wide.png").standardizedFileURL)
    }

    @Test
    func pathsResolveAgainstTheDocumentFolder() {
        let doc = URL(fileURLWithPath: "/Users/me/notes/sub/doc.md")
        #expect(MarkdownResource.localURL(for: "a.png", relativeTo: doc)?.path == "/Users/me/notes/sub/a.png")
        #expect(MarkdownResource.localURL(for: "../img/a%20b.png", relativeTo: doc)?.path == "/Users/me/notes/img/a b.png")
        #expect(MarkdownResource.localURL(for: "/tmp/a.png", relativeTo: doc)?.path == "/tmp/a.png")
        #expect(MarkdownResource.localURL(for: "mailto:x@y.z", relativeTo: doc) == nil)
    }

    @Test
    func anImageInsideASentenceStaysAsTyped() throws {
        writePNG("wide.png", width: 1600, height: 400)
        let textView = styledView("see ![alt](wide.png) here", documentURL: documentURL)
        let storage = try #require(textView.textStorage)
        let bang = (textView.string as NSString).range(of: "!")
        #expect(storage.attribute(.imageSource, at: bang.location, effectiveRange: nil) == nil)
        #expect(storage.attribute(.concealable, at: bang.location, effectiveRange: nil) == nil)
        #expect(spacing(at: 0, in: textView) == Appearance.paragraphSpacing)
    }

    @Test
    func anImageInsideAFenceIsLiteral() throws {
        writePNG("wide.png", width: 1600, height: 400)
        let textView = styledView("```\n![alt](wide.png)\n```", documentURL: documentURL)
        let storage = try #require(textView.textStorage)
        let bang = (textView.string as NSString).range(of: "!")
        #expect(storage.attribute(.imageSource, at: bang.location, effectiveRange: nil) == nil)
        #expect(spacing(at: bang.location, in: textView) == 0, "the fence's flush style wins")
    }

    /// An image file rewritten on disk is decoded again on the next restyle.
    @Test
    func aRewrittenImageReloadsOnRestyle() throws {
        let url = writePNG("changing.png", width: 200, height: 100)
        let textView = styledView("![alt](changing.png)", documentURL: documentURL)
        #expect(spacing(at: 0, in: textView) == 100 + Appearance.paragraphSpacing)
        writePNG("changing.png", width: 200, height: 300)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
        textView.syntaxStyler.apply(to: textView)
        #expect(spacing(at: 0, in: textView) == 300 + Appearance.paragraphSpacing)
    }

    /// The view watches the image files it shows: a file replaced by another
    /// program reloads and resizes its band with no restyle asked for, the way
    /// the document reloads when it changes on disk.
    @Test
    func aReplacedImageReloadsOnItsOwn() async throws {
        writePNG("watched.png", width: 200, height: 100)
        let textView = styledView("![alt](watched.png)", documentURL: documentURL)
        #expect(spacing(at: 0, in: textView) == 100 + Appearance.paragraphSpacing)

        // An atomic replacement, as an image editor saves: a new inode at the path.
        let staging = writePNG("staging.png", width: 200, height: 300)
        _ = try FileManager.default.replaceItemAt(folder.appendingPathComponent("watched.png"), withItemAt: staging)
        for _ in 0..<100 where spacing(at: 0, in: textView) != 300 + Appearance.paragraphSpacing {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(spacing(at: 0, in: textView) == 300 + Appearance.paragraphSpacing)
    }

    /// An image-looking line inside a fenced code block is literal text: it
    /// must not resolve, decode, or watch the file it names (#24).
    @Test
    func anImageInsideAFenceIsNeitherDecodedNorWatched() throws {
        let url = writePNG("fenced.png", width: 200, height: 100)
        ImageStore.shared.forget(url)
        let textView = styledView("```\n![alt](fenced.png)\n```\n", documentURL: documentURL)
        let storage = try #require(textView.textStorage)
        var found = false
        storage.enumerateAttribute(.imageSource, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if value != nil { found = true }
        }
        #expect(!found)
        #expect(!ImageStore.shared.isCached(url))
    }

    /// The store drops its least recently used bitmaps past the byte
    /// budget; a document naming many images cannot grow memory without
    /// bound (#23). The evicted file simply decodes again when asked.
    @Test
    func theStoreEvictsLeastRecentlyUsedPastItsBudget() throws {
        let first = writePNG("lru-one.png", width: 100, height: 100)
        let second = writePNG("lru-two.png", width: 100, height: 100)
        let budget = ImageStore.shared.byteBudget
        defer { ImageStore.shared.byteBudget = budget }

        #expect(ImageStore.shared.entry(for: first) != nil)
        // Room for exactly one of them.
        ImageStore.shared.byteBudget = ImageStore.shared.residentBytes + 1
        #expect(ImageStore.shared.entry(for: second) != nil)
        #expect(!ImageStore.shared.isCached(first))
        #expect(ImageStore.shared.isCached(second))
    }

    // MARK: - Demand-driven decoding

    private func until(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// A decoder the test holds shut; the store's real decoder runs once
    /// the gate opens. Installed for one test, restored after.
    private final class Gate: Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        func open() { semaphore.signal() }
        func wait() { semaphore.wait() }
    }

    private func holdDecodes() -> Gate {
        let gate = Gate()
        let real = ImageStore.shared.decode
        ImageStore.shared.decode = { url in
            gate.wait()
            return real(url)
        }
        return gate
    }

    private func restoreDecoder() {
        ImageStore.shared.decode = ImageStore.load
    }

    /// Demand owners stand in for text views; any object identity does.
    private let ownerToken = NSObject()
    private let otherToken = NSObject()
    private var owner: ObjectIdentifier { ObjectIdentifier(ownerToken) }

    /// Styling reserves the band from the file header alone, and neither
    /// styling nor drawing decodes a pixel: the cache-only lookup drawing
    /// uses returns nil and queues nothing (#30).
    @Test
    func stylingAndDrawingReserveTheBandWithoutDecoding() throws {
        let url = writePNG("lazy.png", width: 200, height: 150)
        ImageStore.shared.forget(url)
        let starts = ImageStore.shared.decodeStarts.count
        let textView = styledView("![alt](lazy.png)", documentURL: documentURL)
        #expect(spacing(at: 0, in: textView) == 150 + Appearance.paragraphSpacing)
        #expect(!ImageStore.shared.isCached(url))

        #expect(ImageStore.shared.residentImage(for: url) == nil)
        #expect(!ImageStore.shared.isQueued(url))
        #expect(!ImageStore.shared.isDecoding(url))
        #expect(ImageStore.shared.decodeStarts.count == starts, "nothing drawn or styled starts a decode")
    }

    /// Demand is what decodes: a visible file arrives off the main actor
    /// and announces itself; a file nobody demands never starts.
    @Test
    func demandDecodesAndAnUndemandedFileNeverStarts() async throws {
        let wanted = writePNG("wanted.png", width: 200, height: 150)
        let unwanted = writePNG("unwanted.png", width: 200, height: 150)
        ImageStore.shared.forget(wanted)
        ImageStore.shared.forget(unwanted)
        defer { ImageStore.shared.removeDemand(for: owner) }

        ImageStore.shared.updateDemand(for: owner, visible: [wanted], prefetch: [])
        try await until { ImageStore.shared.isCached(wanted) }
        let entry = try #require(ImageStore.shared.residentImage(for: wanted))
        #expect(entry.naturalSize == NSSize(width: 200, height: 150))
        #expect(!ImageStore.shared.isCached(unwanted))
        #expect(!ImageStore.shared.decodeStarts.contains(unwanted))
    }

    /// Demand withdrawn from a queued file removes it before it starts;
    /// withdrawn from the file in flight, its result is discarded rather
    /// than admitted.
    @Test
    func withdrawnDemandLeavesTheQueueAndDiscardsTheActiveDecode() async throws {
        let active = writePNG("active.png", width: 100, height: 100)
        let queued = writePNG("queued.png", width: 100, height: 100)
        ImageStore.shared.forget(active)
        ImageStore.shared.forget(queued)
        let gate = holdDecodes()
        defer { restoreDecoder(); ImageStore.shared.removeDemand(for: owner) }

        ImageStore.shared.updateDemand(for: owner, visible: [active, queued], prefetch: [])
        #expect(ImageStore.shared.isDecoding(active))
        #expect(ImageStore.shared.isQueued(queued))

        ImageStore.shared.updateDemand(for: owner, visible: [], prefetch: [])
        #expect(!ImageStore.shared.isQueued(queued))
        let discards = ImageStore.shared.discards
        gate.open()
        try await until { ImageStore.shared.discards > discards }
        #expect(!ImageStore.shared.isCached(active), "the finished decode nobody wants is dropped")
        #expect(!ImageStore.shared.decodeStarts.contains(queued))
    }

    /// Visible files decode before prefetch files, whichever was named
    /// first; two owners naming one file share one decode.
    @Test
    func visibleDemandOutranksPrefetchAndOwnersShareADecode() async throws {
        let first = writePNG("order-first.png", width: 100, height: 100)
        let near = writePNG("order-near.png", width: 100, height: 100)
        let seen = writePNG("order-seen.png", width: 100, height: 100)
        for url in [first, near, seen] { ImageStore.shared.forget(url) }
        let gate = holdDecodes()
        let other = ObjectIdentifier(otherToken)
        defer {
            restoreDecoder()
            ImageStore.shared.removeDemand(for: owner)
            ImageStore.shared.removeDemand(for: other)
        }

        ImageStore.shared.updateDemand(for: owner, visible: [first], prefetch: [near])
        ImageStore.shared.updateDemand(for: owner, visible: [first, seen], prefetch: [near])
        ImageStore.shared.updateDemand(for: other, visible: [seen], prefetch: [near])
        let before = ImageStore.shared.decodeStarts.count
        gate.open(); gate.open(); gate.open()
        try await until { ImageStore.shared.isCached(near) }
        let starts = Array(ImageStore.shared.decodeStarts.dropFirst(before - 1))
        #expect(starts == [first, seen, near], "visible first, then prefetch, each once")
    }

    /// A visible image is never evicted, even over budget; once it is no
    /// longer visible the cache returns under budget (#23).
    @Test
    func aVisibleImageSurvivesEvictionUntilItScrollsAway() async throws {
        let first = writePNG("pin-one.png", width: 100, height: 100)
        let second = writePNG("pin-two.png", width: 100, height: 100)
        ImageStore.shared.forget(first)
        ImageStore.shared.forget(second)
        let budget = ImageStore.shared.byteBudget
        defer {
            ImageStore.shared.byteBudget = budget
            ImageStore.shared.removeDemand(for: owner)
        }
        ImageStore.shared.byteBudget = 100 * 100 * 4 + 1

        ImageStore.shared.updateDemand(for: owner, visible: [first, second], prefetch: [])
        try await until { ImageStore.shared.isCached(first) && ImageStore.shared.isCached(second) }
        #expect(ImageStore.shared.isCached(first), "both visible: over budget rather than flashing")
        #expect(ImageStore.shared.isCached(second))

        ImageStore.shared.updateDemand(for: owner, visible: [second], prefetch: [first])
        #expect(!ImageStore.shared.isCached(first), "unpinned, the older one goes")
        #expect(ImageStore.shared.isCached(second))
    }

    /// A prefetch that lands into a budget full of visible images evicts
    /// itself once and then waits: it is not decoded again until room
    /// frees or it becomes visible. Without this the store decodes and
    /// evicts it in a loop.
    @Test
    func aPrefetchThatCannotFitWaitsInsteadOfLooping() async throws {
        let shown = writePNG("fit-shown.png", width: 100, height: 100)
        let near = writePNG("fit-near.png", width: 100, height: 100)
        ImageStore.shared.forget(shown)
        ImageStore.shared.forget(near)
        let budget = ImageStore.shared.byteBudget
        defer {
            ImageStore.shared.byteBudget = budget
            ImageStore.shared.removeDemand(for: owner)
        }
        ImageStore.shared.byteBudget = 100 * 100 * 4 + 1

        ImageStore.shared.updateDemand(for: owner, visible: [shown], prefetch: [near])
        try await until { ImageStore.shared.decodeStarts.filter { $0 == near }.count == 1 && !ImageStore.shared.isDecoding(near) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(ImageStore.shared.isCached(shown))
        #expect(!ImageStore.shared.isCached(near), "no room beside the pinned one")
        #expect(ImageStore.shared.decodeStarts.filter { $0 == near }.count == 1, "decoded once, then parked")
        #expect(!ImageStore.shared.isQueued(near))

        ImageStore.shared.updateDemand(for: owner, visible: [near], prefetch: [shown])
        try await until { ImageStore.shared.isCached(near) }
        #expect(ImageStore.shared.isCached(near), "visible, it is decoded again and pinned")
        #expect(!ImageStore.shared.isCached(shown))
    }

    /// A file forgotten while decoding — rewritten on disk — has its stale
    /// result rejected; still demanded, it decodes again.
    @Test
    func aStaleResultIsRejectedAfterForget() async throws {
        let url = writePNG("stale.png", width: 100, height: 100)
        ImageStore.shared.forget(url)
        let gate = holdDecodes()
        defer { restoreDecoder(); ImageStore.shared.removeDemand(for: owner) }

        ImageStore.shared.updateDemand(for: owner, visible: [url], prefetch: [])
        #expect(ImageStore.shared.isDecoding(url))
        let discards = ImageStore.shared.discards
        ImageStore.shared.forget(url)
        gate.open()
        try await until { ImageStore.shared.discards > discards }
        #expect(!ImageStore.shared.isCached(url), "the result that started before forget is dropped")
        #expect(ImageStore.shared.isDecoding(url), "still demanded, it decodes again")
        gate.open()
        try await until { ImageStore.shared.isCached(url) }
        #expect(ImageStore.shared.residentImage(for: url) != nil)
    }

    /// The view's demand comes from the real viewport: a band in it is
    /// visible, a band within a viewport of it is prefetch, a band further
    /// away is neither. A file shown twice is named once.
    @Test
    func demandFollowsTheViewportAndNamesARepeatedFileOnce() throws {
        let url = writePNG("twice.png", width: 100, height: 100)
        ImageStore.shared.forget(url)
        let filler = String(repeating: "line\n", count: 60)
        let textView = styledView("![a](twice.png)\n\n" + filler + "![b](twice.png)\n", documentURL: documentURL)
        let layoutManager = try #require(textView.layoutManager as? PaperLayoutManager)
        let container = try #require(textView.textContainer)
        layoutManager.ensureLayout(for: container)
        let bands = layoutManager.imageBands(forGlyphRange: layoutManager.glyphRange(for: container), width: 640)
        #expect(bands.count == 2)
        let origin = textView.textContainerOrigin
        let top = bands[0].rect.offsetBy(dx: origin.x, dy: origin.y)
        let bottom = bands[1].rect.offsetBy(dx: origin.x, dy: origin.y)
        let width = textView.bounds.width

        let onTop = textView.imageDemand(in: NSRect(x: 0, y: 0, width: width, height: top.maxY + 10))
        #expect(onTop.visible == [url] && onTop.prefetch.isEmpty, "the top band is visible; the same file below is not named again")

        let between = NSRect(x: 0, y: top.maxY + 10, width: width, height: 50)
        let nearTop = textView.imageDemand(in: between)
        #expect(nearTop.visible.isEmpty && nearTop.prefetch == [url], "just under the band: a prefetch")

        let far = NSRect(x: 0, y: top.maxY + 100, width: width, height: 50)
        #expect(far.maxY + 50 < bottom.minY)
        let nothing = textView.imageDemand(in: far)
        #expect(nothing.visible.isEmpty && nothing.prefetch.isEmpty, "a viewport height from either band: nothing")
        #expect(!ImageStore.shared.isCached(url), "asking for demand decodes nothing by itself")
    }
}
