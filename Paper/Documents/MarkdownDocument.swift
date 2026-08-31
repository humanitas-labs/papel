import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Markdown as declared by the system-registered `net.daringfireball.markdown`
    /// identifier. The SDK ships no `UTType.markdown` static, so the type is
    /// imported and declared in `Info.plist` under `UTImportedTypeDeclarations`.
    static let markdown = UTType(
        importedAs: "net.daringfireball.markdown",
        conformingTo: .plainText
    )
}

/// The document is the file's UTF-8 source string and nothing else.
///
/// Decoding and encoding are exposed as `init(data:)` and `data` so the
/// byte-preservation invariant can be tested without SwiftUI's read and write
/// configuration types, which have no public initializers.
struct MarkdownDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.markdown, .plainText]
    static let writableContentTypes: [UTType] = [.markdown, .plainText]

    var text: String

    init(text: String = "") {
        self.text = text
    }

    /// Decodes UTF-8 exactly. A leading byte-order mark is retained as U+FEFF so
    /// the file round-trips byte-for-byte. Invalid UTF-8 is rejected rather than
    /// repaired.
    init(data: Data) throws {
        guard let text = String(validating: data, as: UTF8.self) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.text = text
    }

    init(fileWrapper: FileWrapper) throws {
        guard fileWrapper.isRegularFile, let data = fileWrapper.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try self.init(data: data)
    }

    init(configuration: ReadConfiguration) throws {
        try self.init(fileWrapper: configuration.file)
    }

    /// The exact bytes written to disk.
    var data: Data {
        Data(text.utf8)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
