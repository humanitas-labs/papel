import AppKit
import Quartz

/// A double-click on a block image opens it in the system Quick Look panel,
/// the way Messages opens a photo: zoomed out of the band, with ← → across
/// the document's images and Open with Preview one click away. The panel
/// is the system's; Paper adds nothing to it. Only files the document
/// resolves on disk take part: a remote image has no file to show.
extension PaperTextView: @preconcurrency QLPreviewPanelDataSource, @preconcurrency QLPreviewPanelDelegate {
    /// Every image band on the page in document order, in view coordinates.
    var imageBands: [(rect: NSRect, url: URL)] {
        guard let layoutManager = layoutManager as? PaperLayoutManager,
              let storage = textStorage, storage.length > 0 else { return [] }
        let origin = textContainerOrigin
        let all = layoutManager.glyphRange(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
        return layoutManager.imageBands(forGlyphRange: all, width: MarkdownSyntaxStyler.measure(of: self))
            .filter(\.url.isFileURL)
            .map { (rect: $0.rect.offsetBy(dx: origin.x, dy: origin.y), url: $0.url) }
    }

    /// The I-beam belongs to text; over an image the plain arrow, as in Messages.
    /// The text view sets its cursor on every mouse move, over any cursor
    /// rects, so the move itself is where the hand goes in.
    override func mouseMoved(with event: NSEvent) {
        if imageURL(at: event) != nil {
            NSCursor.arrow.set()
        } else {
            super.mouseMoved(with: event)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if imageURL(at: event) != nil {
            NSCursor.arrow.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    /// A click that lands on an image is the image's: the caret stays where
    /// it was, so the source line is not revealed and the band does not
    /// jump under the pointer. A double-click released on the same image
    /// opens it, as in Messages; a single click or a drag does nothing.
    func clickImage(with event: NSEvent) -> Bool {
        guard let image = imageURL(at: event), let window else { return false }
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            guard next.type == .leftMouseUp else { continue }
            if event.clickCount == 2, imageURL(at: next) == image { preview(image) }
            break
        }
        return true
    }

    /// The image file drawn under `event`'s point, if any.
    func imageURL(at event: NSEvent) -> URL? {
        let point = convert(event.locationInWindow, from: nil)
        return imageBands.first { $0.rect.contains(point) }?.url
    }

    /// Shows the panel on `url`, which becomes the current item among the
    /// page's images. The panel asks up the responder chain for a data
    /// source; the text view is first responder, so it answers.
    func preview(_ url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        window?.makeFirstResponder(self)
        panel.makeKeyAndOrderFront(nil)
        if let index = imageBands.firstIndex(where: { $0.url == url }) {
            panel.currentPreviewItemIndex = index
        }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = self
            panel.delegate = self
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            panel.delegate = nil
        }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        imageBands.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        let bands = imageBands
        guard bands.indices.contains(index) else { return nil }
        return bands[index].url as NSURL
    }

    /// The band's place on screen, so the panel zooms out of the page and
    /// back into it. A band scrolled out of view zooms from the centre.
    func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: QLPreviewItem!) -> NSRect {
        guard let url = item.previewItemURL,
              let band = imageBands.first(where: { $0.url == url }),
              band.rect.intersects(visibleRect),
              let window else { return .zero }
        return window.convertToScreen(convert(band.rect, to: nil))
    }
}
