import AppKit

final class SereinTextView: NSTextView {
    let syntaxStyler = MarkdownSyntaxStyler()

    init() {
        let storage = NSTextStorage()
        let layoutManager = SereinLayoutManager()
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
        guard let layoutManager = layoutManager as? SereinLayoutManager,
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

    /// Draws block-quote rules in the margin before the text. They must come
    /// first: `NSTextView.draw` leaves the context clipped to the text
    /// container, so anything drawn in the margin afterwards is discarded.
    override func draw(_ dirtyRect: NSRect) {
        drawQuoteRules(in: dirtyRect)
        super.draw(dirtyRect)
    }

    private func drawQuoteRules(in dirtyRect: NSRect) {
        guard let layoutManager = layoutManager as? SereinLayoutManager,
              let container = textContainer else { return }
        let origin = textContainerOrigin
        let containerRect = dirtyRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: container)
        let rects = layoutManager.quoteRuleRects(forGlyphRange: glyphRange)
        guard !rects.isEmpty else { return }

        Appearance.mutedInk.setFill()
        for rect in rects {
            NSRect(
                x: origin.x - Appearance.quoteRuleOffset,
                y: origin.y + rect.minY,
                width: Appearance.quoteRuleWidth,
                height: rect.height
            ).fill(using: .sourceOver)
        }
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
        setFrameSize(frame.size)
        syntaxStyler.apply(to: self)
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
        backgroundColor = Appearance.canvas
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
        textColor = Appearance.ink
        insertionPointColor = Appearance.ink
        selectedTextAttributes = [.backgroundColor: Appearance.selection]
        typingAttributes = MarkdownSyntaxStyler.baseAttributes
    }
}

