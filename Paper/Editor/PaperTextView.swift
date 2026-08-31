import AppKit

final class PaperTextView: NSTextView {
    let syntaxStyler = MarkdownSyntaxStyler()

    init() {
        let storage = NSTextStorage()
        let layoutManager = PaperLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))

        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)

        configure()
        observeSettings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    /// Every selection setter funnels through this primitive, so it is the one
    /// place that decides which paragraphs show their Markdown punctuation:
    /// those the selection touches. While an input method holds marked text
    /// the revealed range is frozen, as restyling already is.
    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard !hasMarkedText() else { return }
        revealSelectedParagraphs()
    }

    /// The union of the paragraphs touched by the selection. Disjoint
    /// selections reveal everything between them as well, which is rare and
    /// harmless.
    private func revealSelectedParagraphs() {
        guard let layoutManager = layoutManager as? PaperLayoutManager,
              let storage = textStorage else { return }
        let text = storage.string as NSString
        var active: NSRange?
        for value in selectedRanges {
            let paragraph = text.paragraphRange(for: value.rangeValue.clamped(to: text.length))
            active = active.map { NSUnionRange($0, paragraph) } ?? paragraph
        }
        layoutManager.setActiveRange(active ?? NSRange(location: 0, length: 0))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)

        let margin = max(
            Appearance.minimumHorizontalMargin,
            (newSize.width - Appearance.maximumMeasure) / 2
        )
        textContainerInset = NSSize(width: margin, height: Appearance.topMargin)
    }

    /// The rect AppKit proposes spans the whole line fragment, including the
    /// leading added by the line-height multiple. TextKit 1 places that extra
    /// space above the glyphs, so the caret keeps the fragment's bottom edge and
    /// shrinks to the font's ascent plus descent.
    private func caretRect(for proposed: NSRect) -> NSRect {
        let font = caretFont()
        let height = min(
            proposed.height,
            font.ascender - font.descender + Appearance.caretOvershoot * 2
        )
        return NSRect(
            x: proposed.minX,
            y: proposed.maxY - height,
            width: Appearance.caretWidth,
            height: height
        )
    }

    /// The tallest font on the caret's paragraph. Typing attributes are always
    /// the body font (the styler resets them), so a caret sized from them is
    /// too short on headings; sizing from the paragraph keeps it matched to
    /// the line's text.
    private func caretFont() -> NSFont {
        let body = Appearance.bodyFont()
        guard let storage = textStorage, storage.length > 0 else { return body }
        let location = min(selectedRange().location, storage.length)
        let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
        guard paragraph.length > 0 else { return body }

        var tallest = body
        storage.enumerateAttribute(.font, in: paragraph) { value, _, _ in
            if let font = value as? NSFont, font.pointSize > tallest.pointSize {
                tallest = font
            }
        }
        return tallest
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        guard flag else { return }
        color.setFill()
        NSBezierPath(
            roundedRect: caretRect(for: rect),
            xRadius: Appearance.caretWidth / 2,
            yRadius: Appearance.caretWidth / 2
        ).fill()
    }

    /// Two reasons to enlarge every invalidation: AppKit invalidates only the
    /// 1 pt caret it expects, so the wider bar would leave a trail; and with
    /// fractional line metrics (any non-integer size, line height, or
    /// spacing) the selection highlight and its later erase rect round to
    /// different pixels, leaving thin streaks at fragment edges. Padding by a
    /// pixel each way and snapping to whole pixels covers both.
    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        let padded = rect
            .insetBy(dx: -Appearance.caretWidth, dy: -Appearance.invalidationPadding)
            .integral
        super.setNeedsDisplay(padded, avoidAdditionalLayout: flag)
    }

    /// Draws block-quote rules in the margin right after the canvas fill and
    /// before the glyphs. Drawing them in `draw(_:)` fails both ways: before
    /// `super` the background fill covers them, after it the context is
    /// clipped to the text container and the margin is discarded.
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        drawCodeBlockBands(in: rect)
        drawQuoteRules(in: rect)
    }

    private func drawCodeBlockBands(in dirtyRect: NSRect) {
        guard let layoutManager = layoutManager as? PaperLayoutManager,
              let container = textContainer else { return }
        let origin = textContainerOrigin
        let containerRect = dirtyRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: container)
        let rects = layoutManager.codeBlockRects(forGlyphRange: glyphRange)
        guard !rects.isEmpty else { return }

        Appearance.codeBlockBackground.setFill()
        for rect in rects {
            NSBezierPath(
                roundedRect: NSRect(
                    x: origin.x,
                    y: origin.y + rect.minY,
                    width: container.size.width,
                    height: rect.height
                ),
                xRadius: Appearance.codeBlockCornerRadius,
                yRadius: Appearance.codeBlockCornerRadius
            ).fill()
        }
    }

    private func drawQuoteRules(in dirtyRect: NSRect) {
        guard let layoutManager = layoutManager as? PaperLayoutManager,
              let container = textContainer else { return }
        let origin = textContainerOrigin
        let containerRect = dirtyRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: container)
        let rects = layoutManager.quoteRuleRects(forGlyphRange: glyphRange)
        guard !rects.isEmpty else { return }

        Appearance.mutedInk.setFill()
        for rect in rects {
            NSRect(
                x: origin.x + container.lineFragmentPadding,
                y: origin.y + rect.minY,
                width: Appearance.quoteRuleWidth,
                height: rect.height
            ).fill(using: .sourceOver)
        }
    }

    // MARK: - List continuation

    /// Return inside a list item starts the next item; Return on an empty
    /// item removes its marker; shift-Return hard-wraps without a marker.
    /// Everything else is an ordinary newline.
    override func insertNewline(_ sender: Any?) {
        guard isEditable, !hasMarkedText(),
              NSApp.currentEvent?.modifierFlags.contains(.shift) != true,
              let edit = ListContinuation.edit(in: string as NSString, selection: selectedRange())
        else {
            super.insertNewline(sender)
            return
        }
        breakUndoCoalescing()
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
    }

    // MARK: - Typed substitutions

    /// Typing `>` after `-` replaces the pair with `→` in the source, the
    /// way smart dashes turn `--` into `—`; ⌘Z restores `->`. `-->`, `<->`,
    /// and code spans are left as typed.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        super.insertText(string, replacementRange: replacementRange)
        guard let typed = string as? String ?? (string as? NSAttributedString)?.string, typed == ">",
              !hasMarkedText() else { return }
        // On the next pass of the run loop, after the keystroke's undo group
        // has closed, so the substitution is its own undo step.
        pendingSubstitution?.invalidate()
        pendingSubstitution = Timer.scheduledTimer(withTimeInterval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.replaceTypedArrow() }
        }
    }

    private var pendingSubstitution: Timer?

    /// Runs a scheduled substitution now. Tests use it instead of pumping
    /// the run loop, which is not safe inside the document-based test host.
    func flushPendingSubstitution() {
        guard let pendingSubstitution else { return }
        pendingSubstitution.fire()
        pendingSubstitution.invalidate()
        self.pendingSubstitution = nil
    }

    private func replaceTypedArrow() {
        pendingSubstitution = nil
        guard selectedRange().length == 0 else { return }
        let caret = selectedRange().location
        let text = self.string as NSString
        guard caret >= 2, text.character(at: caret - 1) == 0x3E, text.character(at: caret - 2) == 0x2D else { return }
        if caret >= 3 {
            let before = text.character(at: caret - 3)
            if before == 0x2D || before == 0x3C { return }
        }
        if let font = textStorage?.attribute(.font, at: caret - 2, effectiveRange: nil) as? NSFont, font == Appearance.codeFont() { return }
        let pair = NSRange(location: caret - 2, length: 2)
        // Typing is coalesced into one undo action; close it on both sides
        // so ⌘Z after the substitution gives back the typed pair.
        breakUndoCoalescing()
        guard shouldChangeText(in: pair, replacementString: "→") else { return }
        textStorage?.replaceCharacters(in: pair, with: "→")
        didChangeText()
        setSelectedRange(NSRange(location: pair.location + 1, length: 0))
        breakUndoCoalescing()
    }

    // MARK: - Inline formatting (Format menu, ⌘B ⌘I ⌘U ⌘E)

    @objc func toggleBold(_ sender: Any?) { toggle(.bold) }
    @objc func toggleItalic(_ sender: Any?) { toggle(.italic) }
    @objc func toggleUnderline(_ sender: Any?) { toggle(.underline) }
    @objc func toggleCode(_ sender: Any?) { toggle(.code) }

    /// ⌘K: the selection (or word) becomes link text; the destination is
    /// the clipboard when it holds a URL, otherwise the caret waits inside
    /// the parentheses.
    @objc func insertLink(_ sender: Any?) {
        guard isEditable, !hasMarkedText() else { return }
        let text = string as NSString
        var range = selectedRange()
        if range.length == 0 { range = InlineFormat.wordRange(at: range.location, in: text) }
        let label = text.substring(with: range)
        let clipboard = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let destination = Self.looksLikeURL(clipboard) ? clipboard : ""
        let replacement = "[\(label)](\(destination))"
        let selection: NSRange
        if destination.isEmpty {
            selection = NSRange(location: range.location + label.utf16.count + 3, length: 0)
        } else if label.isEmpty {
            selection = NSRange(location: range.location + 1, length: 0)
        } else {
            selection = NSRange(location: range.location + replacement.utf16.count, length: 0)
        }
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(selection)
    }

    static func looksLikeURL(_ string: String) -> Bool {
        guard !string.isEmpty, !string.contains(" "), let url = URL(string: string) else { return false }
        return url.scheme != nil && url.host != nil || string.hasPrefix("mailto:")
    }

    /// ⌘-click on link text opens its destination; every other click is
    /// ordinary caret placement.
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), let destination = linkDestination(at: event) {
            open(destination)
            return
        }
        super.mouseDown(with: event)
    }

    private func linkDestination(at event: NSEvent) -> String? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        guard index < storage.length else { return nil }
        return storage.attribute(.linkDestination, at: index, effectiveRange: nil) as? String
    }

    /// Absolute URLs open as they are; anything else is a path relative to
    /// the document.
    private func open(_ destination: String) {
        if Self.looksLikeURL(destination) || destination.hasPrefix("mailto:"), let url = URL(string: destination) {
            NSWorkspace.shared.open(url)
            return
        }
        let base = window?.representedURL?.deletingLastPathComponent() ?? URL(fileURLWithPath: NSHomeDirectory())
        let path = (destination.removingPercentEncoding ?? destination)
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path)
        NSWorkspace.shared.open(url)
    }

    private func toggle(_ format: InlineFormat) {
        guard isEditable, !hasMarkedText() else { return }
        let edit = format.toggle(in: string as NSString, selection: selectedRange())
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        insertionPointColor = Appearance.ink
        syntaxStyler.apply(to: self)
    }

    /// Configuration changes apply to every open window as soon as the file
    /// is saved. Selector observers are unregistered automatically on
    /// deallocation.
    private func observeSettings() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: Configuration.didChangeNotification,
            object: nil
        )
    }

    @objc private func settingsDidChange() {
        font = Appearance.bodyFont()
        applyColors()
        setFrameSize(frame.size)
        syntaxStyler.apply(to: self)
        needsDisplay = true
    }

    private func applyColors() {
        backgroundColor = Appearance.canvas
        textColor = Appearance.ink
        insertionPointColor = Appearance.ink
        selectedTextAttributes = [.backgroundColor: Appearance.selection]
        enclosingScrollView?.backgroundColor = Appearance.canvas
    }

    private func configure() {
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true

        // Drawing the canvas here keeps the view opaque, so scrolling can
        // blit the existing pixels instead of redrawing every visible line.
        drawsBackground = true
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isContinuousSpellCheckingEnabled = true
        isGrammarCheckingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = true
        isAutomaticDashSubstitutionEnabled = true
        isAutomaticTextReplacementEnabled = true
        isAutomaticSpellingCorrectionEnabled = false

        font = Appearance.bodyFont()
        applyColors()
        typingAttributes = MarkdownSyntaxStyler.baseAttributes
    }
}

