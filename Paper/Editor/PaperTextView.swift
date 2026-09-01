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
        let height = font.ascender - font.descender + Appearance.caretOvershoot * 2
        // The empty document's caret stands in the ghost title, which is
        // drawn from the fragment's top and is taller than the body-sized
        // fragment AppKit proposes — so anchor to the top and keep the
        // title's full height.
        if string.isEmpty {
            // The caret stands where the first letter will land — after
            // the ghost's `# `, which the keystroke inserts — so it does
            // not hop when typing starts.
            let markerWidth = ("# " as NSString).size(withAttributes: [.font: Appearance.bodyFont()]).width
            return NSRect(
                x: proposed.minX + markerWidth,
                y: proposed.minY + ghostTitleTopInset,
                width: Appearance.caretWidth,
                height: height
            )
        }
        let clamped = min(proposed.height, height)
        return NSRect(
            x: proposed.minX,
            y: proposed.maxY - clamped,
            width: Appearance.caretWidth,
            height: clamped
        )
    }

    /// The tallest font on the caret's paragraph. Typing attributes are always
    /// the body font (the styler resets them), so a caret sized from them is
    /// too short on headings; sizing from the paragraph keeps it matched to
    /// the line's text.
    private func caretFont() -> NSFont {
        let body = Appearance.bodyFont()
        // An empty document shows the ghost title, and the first letter
        // typed starts one, so the caret takes the H1 face.
        guard let storage = textStorage, storage.length > 0 else {
            return Appearance.headingFont(size: Appearance.headingSize(level: 1))
        }
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
        // The empty document's caret is drawn shifted into the ghost title
        // — right of the marker, lower, and taller than the body-sized rect
        // AppKit invalidates — so the invalidation grows to reach it, or
        // the blink is clipped away and the caret never appears.
        let font = caretFont()
        let dx = string.isEmpty
            ? -(("# " as NSString).size(withAttributes: [.font: Appearance.bodyFont()]).width + Appearance.caretWidth)
            : -Appearance.caretWidth
        let dy = string.isEmpty
            ? -(ghostTitleTopInset + font.ascender - font.descender + Appearance.invalidationPadding)
            : -Appearance.invalidationPadding
        let padded = rect.insetBy(dx: dx, dy: dy).integral
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
        drawThematicBreaks(in: rect)
        drawPlaceholder()
    }

    /// An empty document ghosts a title where the first line will land, so
    /// a fresh page reads as a page and not a blank canvas. The first
    /// keystroke clears it. The ghost carries the exact attributes a
    /// revealed `# Untitled` line would — marker in the body font at the
    /// syntax ink, word in the H1 face — and sits where TextKit would set
    /// the line (extra line-height leading goes above the glyphs), so the
    /// real title replaces it without anything moving.
    static let placeholderTitle = "Untitled"
    private var placeholderVisible = false

    private static var ghostTitle: NSAttributedString {
        let title = NSMutableAttributedString(
            string: "# ",
            attributes: [.font: Appearance.bodyFont(), .foregroundColor: Appearance.mutedInk]
        )
        title.append(NSAttributedString(
            string: placeholderTitle,
            attributes: [
                .font: Appearance.headingFont(size: Appearance.headingSize(level: 1)),
                .foregroundColor: Appearance.mutedInk,
            ]
        ))
        return title
    }

    /// TextKit places the line-height multiple's extra space above the
    /// glyphs; the ghost (and the caret standing in it) drops by the same
    /// amount to land where the typed title will.
    private var ghostTitleTopInset: CGFloat {
        let font = Appearance.headingFont(size: Appearance.headingSize(level: 1))
        let natural = layoutManager?.defaultLineHeight(for: font)
            ?? (font.ascender - font.descender + font.leading)
        return max(0, (Appearance.lineHeightMultiple - 1) * natural)
    }

    private func drawPlaceholder() {
        guard string.isEmpty, let container = textContainer else {
            placeholderVisible = false
            return
        }
        placeholderVisible = true
        let origin = textContainerOrigin
        Self.ghostTitle.draw(
            at: NSPoint(x: origin.x + container.lineFragmentPadding, y: origin.y + ghostTitleTopInset)
        )
    }

    override func didChangeText() {
        super.didChangeText()
        if placeholderVisible != string.isEmpty { needsDisplay = true }
    }

    /// A concealed `---`/`***`/`___` line draws as a hairline across the
    /// measure, vertically centred on its (empty-looking) line fragment.
    private func drawThematicBreaks(in dirtyRect: NSRect) {
        guard let layoutManager = layoutManager as? PaperLayoutManager,
              let container = textContainer else { return }
        let origin = textContainerOrigin
        let containerRect = dirtyRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: container)
        let rects = layoutManager.thematicBreakRects(forGlyphRange: glyphRange)
        guard !rects.isEmpty else { return }

        Appearance.thematicBreakInk.setFill()
        for fragment in rects {
            NSRect(
                x: origin.x + container.lineFragmentPadding,
                y: origin.y + fragment.midY - Appearance.thematicBreakThickness / 2,
                width: container.size.width - 2 * container.lineFragmentPadding,
                height: Appearance.thematicBreakThickness
            ).fill()
        }
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

    /// Tab in a list item indents the whole item a level; Shift-Tab takes
    /// one back. Anywhere else both keep their ordinary meaning.
    override func insertTab(_ sender: Any?) {
        guard applyListIndent(outdent: false) else { return super.insertTab(sender) }
    }

    override func insertBacktab(_ sender: Any?) {
        guard applyListIndent(outdent: true) else { return super.insertBacktab(sender) }
    }

    private func applyListIndent(outdent: Bool) -> Bool {
        guard isEditable, !hasMarkedText(),
              let edit = ListContinuation.indent(in: string as NSString, selection: selectedRange(), outdent: outdent)
        else { return false }
        breakUndoCoalescing()
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return true }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
        return true
    }

    // MARK: - Typed substitutions

    /// Typing `>` after `-` replaces the pair with `→`; a word or space
    /// after `--` replaces the pair with `—` (Paper's own smart dashes —
    /// the system's are disabled because they eat `---`). ⌘Z restores the
    /// typed pair. `-->`, `<->`, `---`, and code spans are left as typed.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        var string = string
        // The first letter typed into an empty document starts the title
        // the placeholder promises: it lands as `# ` plus the letter, one
        // undo step, visible in the source. Syntax starters (`#`, `-`,
        // `>`, a backtick, a digit…) are left alone so lists, quotes, and
        // hand-typed headings begin as typed.
        if self.string.isEmpty, !hasMarkedText(),
           let typed = string as? String ?? (string as? NSAttributedString)?.string,
           typed.count == 1, let scalar = typed.unicodeScalars.first,
           CharacterSet.letters.contains(scalar) {
            string = "# " + typed
        }
        super.insertText(string, replacementRange: replacementRange)
        guard let typed = string as? String ?? (string as? NSAttributedString)?.string,
              typed.utf16.count == 1, !hasMarkedText() else { return }
        let isDashTrigger = typed == " " || typed.rangeOfCharacter(from: .alphanumerics) != nil
        guard typed == ">" || isDashTrigger else { return }
        // On the next pass of the run loop, after the keystroke's undo group
        // has closed, so the substitution is its own undo step.
        pendingSubstitution?.invalidate()
        pendingSubstitution = Timer.scheduledTimer(withTimeInterval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.replaceTypedArrow()
                self?.replaceTypedDashes()
            }
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

    /// `--` becomes `—` when the character after it lands — never a third
    /// `-` (so `---` rules and front-matter fences survive), never after a
    /// `-`, `|`, `:`, `<` or `>` (runs, tables, arrows), never in code.
    private func replaceTypedDashes() {
        guard selectedRange().length == 0 else { return }
        let caret = selectedRange().location
        let text = self.string as NSString
        guard caret >= 3,
              // The trigger is the just-typed word character or space — a
              // third `-` keeps a rule typeable and `>` keeps `-->` literal.
              ![0x2D, 0x3E].contains(text.character(at: caret - 1)),
              text.character(at: caret - 2) == 0x2D,
              text.character(at: caret - 3) == 0x2D else { return }
        if caret >= 4 {
            let before = text.character(at: caret - 4)
            if [0x2D, 0x7C, 0x3A, 0x3C, 0x3E].contains(before) { return }
        }
        if let font = textStorage?.attribute(.font, at: caret - 2, effectiveRange: nil) as? NSFont,
           font == Appearance.codeFont() { return }
        let pair = NSRange(location: caret - 3, length: 2)
        breakUndoCoalescing()
        guard shouldChangeText(in: pair, replacementString: "—") else { return }
        textStorage?.replaceCharacters(in: pair, with: "—")
        didChangeText()
        setSelectedRange(NSRange(location: caret - 1, length: 0))
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

    /// A clean click on link text opens its destination — the caret goes in
    /// by clicking beside the link or dragging across it. ⌘-click opens too.
    /// `super.mouseDown` runs the whole tracking loop, so afterwards a drag
    /// shows up as a non-empty selection and the click is left alone.
    override func mouseDown(with event: NSEvent) {
        let destination = linkDestination(at: event)
        if event.modifierFlags.contains(.command), let destination {
            open(destination)
            return
        }
        let plainClick = event.clickCount == 1
            && event.modifierFlags.intersection([.shift, .control, .option]).isEmpty
        super.mouseDown(with: event)
        if plainClick, let destination, selectedRange().length == 0,
           let up = NSApp.currentEvent, up.type == .leftMouseUp,
           linkDestination(at: up) == destination {
            open(destination)
        }
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
        // The system's dash substitution is syntax-blind: it eats the second
        // `-` of a thematic break or front-matter fence. Paper does its own,
        // Markdown-aware, in the typed-substitution path.
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = true
        isAutomaticSpellingCorrectionEnabled = false

        font = Appearance.bodyFont()
        applyColors()
        typingAttributes = MarkdownSyntaxStyler.baseAttributes
    }
}

