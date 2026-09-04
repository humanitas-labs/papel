import AppKit
import Testing
@testable import Paper

/// Pasting or dropping an image writes it beside the document and inserts
/// a block image line with a relative path (#36).
@MainActor
@Suite(.serialized)
struct ImagePasteTests {
    private let folder: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("paper-image-paste-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private var documentURL: URL { folder.appendingPathComponent("My notes.md") }

    private func png(width: Int = 4, height: Int = 4) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        return rep.representation(using: .png, properties: [:])!
    }

    private let noon = Calendar(identifier: .gregorian).date(from: DateComponents(
        timeZone: TimeZone.current, year: 2026, month: 9, day: 3, hour: 14, minute: 12, second: 5
    ))!

    // MARK: - Naming

    @Test
    func fileNameIsDocumentStampAndExtensionWithWhitespaceDashed() {
        let name = ImagePaste.fileName(for: documentURL, extension: "png", date: noon) { _ in false }
        #expect(name == "My-notes-20260903-141205.png")
    }

    @Test
    func fileNameAppendsACounterWhenTaken() {
        let taken: Set<String> = ["a-20260903-141205.png", "a-20260903-141205-2.png"]
        let name = ImagePaste.fileName(for: folder.appendingPathComponent("a.md"), extension: "png", date: noon) { taken.contains($0) }
        #expect(name == "a-20260903-141205-3.png")
    }

    // MARK: - Directory

    @Test
    func directoryMustStayInsideTheDocumentsFolder() {
        #expect(ImagePaste.isAcceptableDirectory(""))
        #expect(ImagePaste.isAcceptableDirectory("assets"))
        #expect(ImagePaste.isAcceptableDirectory("assets/images/"))
        #expect(!ImagePaste.isAcceptableDirectory("/tmp"))
        #expect(!ImagePaste.isAcceptableDirectory("~/Pictures"))
        #expect(!ImagePaste.isAcceptableDirectory("../elsewhere"))
        #expect(!ImagePaste.isAcceptableDirectory("assets/../../x"))
    }

    @Test
    func configRejectsAnEscapingDirectoryAndKeepsARelativeOne() {
        #expect(Configuration.parse("image.paste.directory = assets").imagePasteDirectory == "assets")
        #expect(Configuration.parse("image.paste.directory = /tmp").imagePasteDirectory == "")
        #expect(Configuration.parse("image.paste.directory = ../x").imagePasteDirectory == "")
        #expect(Configuration().imagePasteDirectory == "")
        #expect(Configuration.parse("image.paste.directory = assets").entries.contains { $0.key == "image.paste.directory" && $0.value == "assets" })
    }

    // MARK: - Writing

    @Test
    func aPastedBitmapIsWrittenAsPNGBesideTheDocument() throws {
        let destination = try ImagePaste.write(.png(png()), beside: documentURL, directory: "", date: noon)
        #expect(destination == "My-notes-20260903-141205.png")
        let written = folder.appendingPathComponent("My-notes-20260903-141205.png")
        #expect(FileManager.default.fileExists(atPath: written.path))
        #expect(NSImage(contentsOf: written)?.size == NSSize(width: 4, height: 4))
    }

    @Test
    func aSubfolderIsCreatedOnDemandAndNamedInTheDestination() throws {
        let destination = try ImagePaste.write(.png(png()), beside: documentURL, directory: "assets/img", date: noon)
        #expect(destination == "assets/img/My-notes-20260903-141205.png")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("assets/img/My-notes-20260903-141205.png").path))
        #expect(MarkdownResource.localURL(for: destination, relativeTo: documentURL) == folder.appendingPathComponent("assets/img/My-notes-20260903-141205.png").standardizedFileURL)
    }

    @Test
    func twoPastesInTheSameSecondGetDistinctNames() throws {
        let first = try ImagePaste.write(.png(png()), beside: documentURL, directory: "", date: noon)
        let second = try ImagePaste.write(.png(png()), beside: documentURL, directory: "", date: noon)
        #expect(first == "My-notes-20260903-141205.png")
        #expect(second == "My-notes-20260903-141205-2.png")
    }

    @Test
    func aCopiedFileIsCopiedKeepingItsFormat() throws {
        let original = folder.appendingPathComponent("shot.jpeg")
        try Data([0xFF, 0xD8, 0xFF, 0xD9]).write(to: original)
        let destination = try ImagePaste.write(.file(original), beside: documentURL, directory: "", date: noon)
        #expect(destination == "My-notes-20260903-141205.jpeg")
        #expect(FileManager.default.fileExists(atPath: original.path), "the original stays where it was")
        #expect(try Data(contentsOf: folder.appendingPathComponent(destination)) == Data([0xFF, 0xD8, 0xFF, 0xD9]))
    }

    @Test
    func aSpaceInTheSubfolderIsPercentEncodedForTheMarkdown() throws {
        let destination = try ImagePaste.write(.png(png()), beside: documentURL, directory: "my assets", date: noon)
        #expect(destination == "my%20assets/My-notes-20260903-141205.png")
        #expect(MarkdownResource.localURL(for: destination, relativeTo: documentURL) == folder.appendingPathComponent("my assets/My-notes-20260903-141205.png").standardizedFileURL)
    }

    // MARK: - Pasteboard

    @Test
    func pasteboardSourcePrefersAFileThenPNGThenTIFF() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("paper-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        pasteboard.clearContents()
        pasteboard.setString("hello", forType: .string)
        #expect(ImagePaste.source(on: pasteboard) == nil, "text is not an image")

        pasteboard.clearContents()
        let tiff = try #require(NSBitmapImageRep(data: png())?.tiffRepresentation)
        pasteboard.setData(tiff, forType: .tiff)
        guard case .png(let data)? = ImagePaste.source(on: pasteboard) else { Issue.record("TIFF becomes PNG"); return }
        #expect(NSBitmapImageRep(data: data) != nil)

        pasteboard.clearContents()
        let file = folder.appendingPathComponent("on-disk.png")
        try png().write(to: file)
        pasteboard.writeObjects([file as NSURL])
        guard case .file(let url)? = ImagePaste.source(on: pasteboard) else { Issue.record("a file URL is copied"); return }
        #expect(url.standardizedFileURL == file.standardizedFileURL)

        pasteboard.clearContents()
        let text = folder.appendingPathComponent("notes.txt")
        try Data("x".utf8).write(to: text)
        pasteboard.writeObjects([text as NSURL])
        #expect(ImagePaste.source(on: pasteboard) == nil, "a file that is not an image pastes as its path, as before")
    }

    // MARK: - Insertion

    @Test
    func insertionPutsTheImageOnItsOwnLineAndTheCaretUnderIt() {
        let empty = ImagePaste.insertion(of: "a.png", replacing: NSRange(location: 0, length: 0), in: "")
        #expect(empty.replacement == "![](a.png)\n")
        #expect(empty.selection == NSRange(location: 11, length: 0))

        let atEnd = ImagePaste.insertion(of: "a.png", replacing: NSRange(location: 5, length: 0), in: "hello")
        #expect(atEnd.replacement == "\n\n![](a.png)\n")
        #expect(atEnd.selection == NSRange(location: 5 + 13, length: 0))

        let afterBlankLine = ImagePaste.insertion(of: "a.png", replacing: NSRange(location: 7, length: 0), in: "hello\n\nworld")
        #expect(afterBlankLine.replacement == "![](a.png)\n\n", "prose following directly gets a blank line")
        #expect(afterBlankLine.selection == NSRange(location: 7 + 11, length: 0))

        let midParagraph = ImagePaste.insertion(of: "a.png", replacing: NSRange(location: 5, length: 1), in: "hello world")
        #expect(midParagraph.replacement == "\n\n![](a.png)\n\n", "the paragraph splits around the image")

        let onEmptyLine = ImagePaste.insertion(of: "a.png", replacing: NSRange(location: 6, length: 0), in: "hello\n\nworld")
        #expect(onEmptyLine.replacement == "\n![](a.png)\n", "one newline before, since the line break after `hello` is there already")
    }

    // MARK: - In the view

    private func styledView(_ text: String) -> PaperTextView {
        let textView = PaperTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        textView.documentURL = documentURL
        textView.string = text
        textView.syntaxStyler.apply(to: textView)
        return textView
    }

    @Test
    func pastingIntoASavedDocumentWritesTheFileAndInsertsABlockImage() throws {
        let host = TestUndoHost()
        let textView = styledView("hello")
        host.attach(to: textView)
        textView.imagePasteDirectory = "assets"
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("paper-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setData(png(), forType: .png)

        #expect(textView.pasteImage(from: pasteboard, at: textView.selectedRange()))
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("assets").path)
        let name = try #require(files.first { $0.hasSuffix(".png") })
        #expect(name.hasPrefix("My-notes-"))
        #expect(textView.string == "hello\n\n![](assets/\(name))\n")
        #expect(textView.selectedRange() == NSRange(location: textView.string.utf16.count, length: 0))

        textView.syntaxStyler.apply(to: textView)
        let line = (textView.string as NSString).range(of: "![](assets/\(name))")
        let source = textView.textStorage?.attribute(.imageSource, at: line.location, effectiveRange: nil) as? URL
        #expect(source == folder.appendingPathComponent("assets/\(name)").standardizedFileURL, "the line renders as a block image")

        host.undoManager.undo()
        #expect(textView.string == "hello", "⌘Z takes the line out")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("assets/\(name)").path), "the file stays")
    }

    @Test
    func imageTypesAreReadableSoPasteIsEnabledForAScreenshot() {
        let textView = styledView("")
        let types = textView.readablePasteboardTypes
        #expect(types.contains(.png) && types.contains(.tiff) && types.contains(.fileURL))
        let item = NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "")
        let saved = NSPasteboard.general.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        defer {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(saved)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png(), forType: .png)
        #expect(textView.validateUserInterfaceItem(item), "Paste stays enabled with only an image on the clipboard")
    }

    @Test
    func aPasteboardWithoutAnImageIsLeftToTextPasting() {
        let textView = styledView("hello")
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("paper-test-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("world", forType: .string)
        #expect(!textView.pasteImage(from: pasteboard, at: NSRange(location: 5, length: 0)))
        #expect(textView.string == "hello")
    }
}
