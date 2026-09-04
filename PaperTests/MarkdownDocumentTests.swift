import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Paper

struct MarkdownDocumentTests {
    /// Sources that must survive a read and write byte-for-byte.
    static let fixtures: [String] = [
        "",
        "# Paper\n\nA quiet place to write.\n",
        "no trailing newline",
        "\n\n\nblank lines first\n\n\n",
        "tabs\there\t\ttrailing spaces   \nand more  \n",
        "café — naïve — 日本語 — 👩‍👩‍👧‍👦 — e\u{301}\n",
        "\u{FEFF}# Byte-order mark retained\n",
        "windows\r\nline\r\nendings\r\n",
        "1. **Keep** the source.\n2. Preserve `syntax`.\n   - nested *item*\n",
    ]

    @Test(arguments: fixtures)
    func roundTripsBytesExactly(source: String) throws {
        let original = Data(source.utf8)
        let document = try MarkdownDocument(data: original)

        #expect(document.text == source)
        #expect(document.data == original)
    }

    @Test(arguments: fixtures)
    func fileWrapperRoundTripsBytesExactly(source: String) throws {
        let original = Data(source.utf8)
        let wrapper = FileWrapper(regularFileWithContents: original)
        let document = try MarkdownDocument(fileWrapper: wrapper)

        #expect(document.data == original)
    }

    @Test
    func retainsUnicodeScalarsWithoutNormalization() throws {
        let composed = "e\u{301}"
        let precomposed = "\u{E9}"
        let document = try MarkdownDocument(data: Data(composed.utf8))

        #expect(document.text.unicodeScalars.count == 2)
        #expect(document.data != Data(precomposed.utf8))
    }

    @Test
    func rejectsInvalidUTF8() {
        let invalid = Data([0x23, 0x20, 0xFF, 0xFE, 0x0A])

        #expect(throws: CocoaError.self) {
            try MarkdownDocument(data: invalid)
        }
    }

    @Test
    func rejectsWrappersWithoutRegularFileContents() {
        let directory = FileWrapper(directoryWithFileWrappers: [:])

        #expect(throws: CocoaError.self) {
            try MarkdownDocument(fileWrapper: directory)
        }
    }

    @Test
    func writesSourceWithoutTransformation() {
        let source = "1. **Keep** the source.\n2. Preserve `syntax`.\n"
        let document = MarkdownDocument(text: source)

        #expect(document.data == Data(source.utf8))
    }

    @Test
    func startsAsAnEmptyDocument() {
        let document = MarkdownDocument()

        #expect(document.text.isEmpty)
        #expect(document.data.isEmpty)
        #expect(MarkdownDocument.readableContentTypes.contains(.markdown))
        #expect(MarkdownDocument.readableContentTypes.contains(.plainText))
        #expect(MarkdownDocument.writableContentTypes == MarkdownDocument.readableContentTypes)
    }

    @Test
    func markdownTypeIsRegisteredWithExpectedIdentifier() {
        #expect(UTType.markdown.identifier == "net.daringfireball.markdown")
        #expect(UTType.markdown.conforms(to: .plainText))
    }
}
