import AppKit
import Testing
@testable import Papel

@MainActor
struct PDFExportTests {
    private func styledView(_ text: String, documentURL: URL? = nil, width: CGFloat = 800) -> PapelTextView {
        let textView = PapelTextView()
        textView.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        textView.documentURL = documentURL
        textView.string = text
        textView.syntaxStyler.apply(to: textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        return textView
    }

    @Test
    func pdfDataBeginsWithThePDFHeader() {
        let textView = styledView("# Hello\n\n> A quiet page.\n")
        let data = PDFExport.data(from: textView)
        #expect(data.starts(with: Data("%PDF".utf8)))
        #expect(data.count > 200)
    }

    @Test
    func snapshotConcealsEveryParagraph() throws {
        let textView = styledView("# Title\n\n> quoted\n")
        let page = PDFExport.snapshot(of: textView)
        let layoutManager = try #require(page.layoutManager as? PapelLayoutManager)
        layoutManager.ensureLayout(for: page.textContainer!)
        #expect(layoutManager.activeRange == NSRange(location: 0, length: 0))
        #expect(layoutManager.isConcealed(characterAt: 0), "the heading marker hides")
        let quote = (page.string as NSString).range(of: ">")
        #expect(quote.location != NSNotFound)
        #expect(layoutManager.isConcealed(characterAt: quote.location), "the quote marker hides")
    }

    @Test
    func exportLeavesTheSourceViewSelectionAlone() {
        let textView = styledView("# Title\n\nBody.\n")
        let selection = NSRange(location: 0, length: 0)
        textView.setSelectedRange(selection)
        let layoutManager = textView.layoutManager as! PapelLayoutManager
        let revealed = layoutManager.activeRange
        _ = PDFExport.data(from: textView)
        #expect(textView.selectedRange() == selection)
        #expect(layoutManager.activeRange == revealed)
    }

    @Test
    func suggestedNameUsesTheH1() {
        let textView = styledView("# Hello There\n\nBody.\n", documentURL: URL(fileURLWithPath: "/tmp/notes.md"))
        #expect(PDFExport.suggestedName(for: textView) == "Hello There.pdf")
    }

    @Test
    func suggestedNameSkipsDeeperHeadings() {
        #expect(PDFExport.headingTitle(in: "## Not this\n# This one\n") == "This one")
        #expect(PDFExport.headingTitle(in: "plain\n# Hello There\n") == "Hello There")
        #expect(PDFExport.headingTitle(in: "# Path/Name: Draft\n") == "Path-Name- Draft")
    }

    @Test
    func suggestedNameUsesTheDocumentStem() {
        let textView = styledView("hi", documentURL: URL(fileURLWithPath: "/tmp/notes.md"))
        #expect(PDFExport.suggestedName(for: textView) == "notes.pdf")
    }

    @Test
    func suggestedNameForAnUntitledDocument() {
        let textView = styledView("hi")
        #expect(PDFExport.suggestedName(for: textView) == "Untitled.pdf")
    }

    @Test
    func snapshotFitsTheMeasureAndUsesTheLightAppearance() {
        let textView = styledView("# Hello\n\nA line.\n", width: 1400)
        let page = PDFExport.snapshot(of: textView)
        let expectedWidth = Appearance.maximumMeasure + PDFExport.pageMargin * 2
        #expect(abs(page.bounds.width - expectedWidth) < 0.5)
        #expect(page.textContainerInset.width == PDFExport.pageMargin)
        #expect(page.textContainerInset.height == PDFExport.pageMargin)
        #expect(page.appearance?.name == .aqua)
        #expect(PDFExport.pageMargin == Appearance.minimumHorizontalMargin)
    }

    @Test
    func exportDecodesDocumentImages() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("papel-pdf-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let image = folder.appendingPathComponent("shot.png")
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 32, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        try #require(rep.representation(using: .png, properties: [:])).write(to: image)

        let documentURL = folder.appendingPathComponent("doc.md")
        let textView = styledView("![shot](shot.png)\n", documentURL: documentURL)
        #expect(!ImageStore.shared.isCached(image.standardizedFileURL))
        _ = PDFExport.data(from: textView)
        #expect(ImageStore.shared.isCached(image.standardizedFileURL))
    }
}
