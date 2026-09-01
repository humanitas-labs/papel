import AppKit
import Testing
@testable import Paper

/// Block images: `![alt](file)` alone on a line reserves a band under the
/// line by paragraph spacing and draws the bitmap there. The source is
/// never edited, the band is constant whether the line is concealed or
/// revealed, and a missing or remote file stands as its alt text.
@MainActor
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
}
