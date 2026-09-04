import AppKit
import UniformTypeIdentifiers

/// File > Export > PDF. The PDF is the document as a page: the configured
/// measure, decorations, and concealed punctuation, on the light canvas,
/// with the window's extra side slack stripped off. The Markdown file is
/// not rewritten.
enum PDFExport {
    /// Side and vertical inset on the exported page. Matches
    /// `Appearance.minimumHorizontalMargin` so the column is the measure,
    /// not the window.
    static let pageMargin: CGFloat = 64

    /// Offers a save panel and writes the front document. Does nothing when
    /// the key window is not a Papel document.
    @MainActor
    static func present() {
        // DocumentGroup's key window is sometimes the chrome, not the
        // document, so search every window for the editor.
        guard let textView = NSApp.windows.lazy.compactMap({ papelTextView(in: $0) }).first else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedName(for: textView)
        Task { @MainActor in
            let response: NSApplication.ModalResponse
            if let window = textView.window ?? NSApp.keyWindow {
                response = await panel.beginSheetModal(for: window)
            } else {
                response = panel.runModal()
            }
            guard response == .OK, let url = panel.url else { return }
            do {
                try data(from: textView).write(to: url, options: .atomic)
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    /// Suggested save-panel name: the first `#` heading, else the
    /// document's stem, else `Untitled.pdf`.
    @MainActor
    static func suggestedName(for textView: PapelTextView) -> String {
        let stem = headingTitle(in: textView.string)
            ?? textView.documentURL?.deletingPathExtension().lastPathComponent
        let name = (stem?.isEmpty == false) ? stem! : "Untitled"
        return "\(name).pdf"
    }

    /// The text of the first ATX H1 (`# Title`), with characters that
    /// cannot live in a filename replaced. `##` and deeper are skipped.
    static func headingTitle(in source: String) -> String? {
        for raw in source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("#") else { continue }
            let rest = line.drop(while: { $0 == "#" })
            guard line.count - rest.count == 1 else { continue }
            let title = rest.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            return filename(from: title)
        }
        return nil
    }

    /// `/`, `:`, and control characters become `-`; empty after that is nil.
    private static func filename(from title: String) -> String? {
        let banned = CharacterSet(charactersIn: "/:\\")
            .union(.newlines)
            .union(.controlCharacters)
        let cleaned = title
            .components(separatedBy: banned)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// PDF bytes for `source`. Builds an offscreen copy so the live window
    /// keeps its selection, scroll, and revealed paragraph.
    @MainActor
    static func data(from source: PapelTextView) -> Data {
        let page = snapshot(of: source)
        let light = NSAppearance(named: .aqua)!
        var pdf = Data()
        light.performAsCurrentDrawingAppearance {
            pdf = page.dataWithPDF(inside: page.bounds)
        }
        return pdf
    }

    /// A detached text view laid out to the measure plus page margins,
    /// forced to the light appearance, every block image decoded, and no
    /// paragraph revealed. Drawing this view is what the PDF captures.
    @MainActor
    static func snapshot(of source: PapelTextView) -> PapelTextView {
        let light = NSAppearance(named: .aqua)!
        let width = Appearance.maximumMeasure + pageMargin * 2
        let copy = PapelTextView()
        copy.appearance = light
        copy.frame = NSRect(x: 0, y: 0, width: width, height: 600)
        copy.documentURL = source.documentURL
        copy.string = source.string
        light.performAsCurrentDrawingAppearance {
            copy.syntaxStyler.apply(to: copy)
        }
        // Setting the string places the caret at 0, which would reveal the
        // first paragraph. Export is the reading view: nothing revealed.
        if let layoutManager = copy.layoutManager as? PapelLayoutManager {
            layoutManager.setActiveRange(NSRange(location: 0, length: 0))
        }
        prepareImages(in: copy)
        layoutToDocumentHeight(copy)
        return copy
    }

    /// The PapelTextView editing the document in `window`, if any.
    @MainActor
    static func papelTextView(in window: NSWindow) -> PapelTextView? {
        func search(_ view: NSView) -> PapelTextView? {
            if let textView = view as? PapelTextView { return textView }
            if let scroll = view as? NSScrollView,
               let textView = scroll.documentView as? PapelTextView {
                return textView
            }
            for child in view.subviews {
                if let found = search(child) { return found }
            }
            return nil
        }
        return window.contentView.flatMap(search)
    }

    /// Drawing looks only in the image cache. Demand is viewport-scoped, so
    /// an export would otherwise paint placeholder bands for every image
    /// that has not scrolled into view. `entry(for:)` decodes on this
    /// thread, which is what a save-panel action can wait for.
    @MainActor
    private static func prepareImages(in textView: PapelTextView) {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        storage.enumerateAttribute(
            .imageSource,
            in: NSRange(location: 0, length: storage.length)
        ) { value, _, _ in
            guard let url = value as? URL else { return }
            _ = ImageStore.shared.entry(for: url)
        }
    }

    @MainActor
    private static func layoutToDocumentHeight(_ textView: PapelTextView) {
        guard let layoutManager = textView.layoutManager as? PapelLayoutManager,
              let container = textView.textContainer else { return }
        layoutManager.ensureLayout(for: container)
        // setFrameSize uses the window top inset (traffic lights). The
        // PDF has no chrome, so both axes use the page margin.
        textView.textContainerInset = NSSize(width: pageMargin, height: pageMargin)
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        let height = used.height + pageMargin * 2
        textView.setFrameSize(NSSize(width: textView.frame.width, height: max(height, 1)))
        textView.textContainerInset = NSSize(width: pageMargin, height: pageMargin)
        layoutManager.ensureLayout(for: container)
    }
}
