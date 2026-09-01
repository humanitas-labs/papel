import AppKit

/// Single source of visual tokens. User-tunable values come from the live
/// `Configuration`; everything else is fixed here.
@MainActor
enum Appearance {
    static var configuration: Configuration { ConfigurationStore.shared.current }

    static var bodySize: CGFloat { CGFloat(configuration.fontSize) }
    static var preferredFamily: String { configuration.fontFamily }
    static var maximumMeasure: CGFloat { CGFloat(configuration.measure) }
    static var lineHeightMultiple: CGFloat { CGFloat(configuration.lineHeight) }
    static var paragraphSpacing: CGFloat { CGFloat(configuration.paragraphSpacing) }
    static var letterSpacing: CGFloat { CGFloat(configuration.letterSpacing) }
    static var headingWeight: Int { configuration.headingWeight.fontManagerWeight }

    static let minimumHorizontalMargin: CGFloat = 64
    static let topMargin: CGFloat = 80
    static let codeScale: CGFloat = 0.88

    /// The insertion point is a rounded bar sized to the glyph box of the
    /// current font rather than the full line fragment, so extra leading does
    /// not stretch it.
    static let caretWidth: CGFloat = 2
    static let caretOvershoot: CGFloat = 1

    /// Vertical padding added to every redraw rect so fractional line metrics
    /// cannot leave sub-pixel selection streaks behind.
    static let invalidationPadding: CGFloat = 2

    /// File-name label: system sans, light beige-grey, evenly inset from the
    /// top-left corner below the traffic lights, in and out of full screen.

    /// List items are inset from the margin by this much, scaled with the
    /// body size so the marker sits like an Apple Notes bullet.
    static var listIndent: CGFloat { (bodySize * 1.4).rounded() }

    /// Extra space after a list marker, beyond the source's single space,
    /// so the text sits clear of the bullet as in Apple Notes.
    static var listMarkerGap: CGFloat { (bodySize * 0.5).rounded() }

    /// How far each nesting level steps a list item's marker. The source's
    /// two spaces per level are far narrower than a legible step, so the
    /// paragraph indent makes up the difference.
    static var listNestIndent: CGFloat { bodySize.rounded() }

    /// Block-quote rule: a bar in the margin, left of the `>` marker.
    static let windowCornerRadius: CGFloat = 16
    static let quoteRuleWidth: CGFloat = 2
    /// A thematic break (`---`) draws as a hairline across the measure, in
    /// a whisper of the ink so it reads as a fold in the page, not a line
    /// of text.
    static let thematicBreakThickness: CGFloat = 1
    static var thematicBreakInk: NSColor { colors.hairline }

    /// Fenced code blocks: content inset from the band's edge and the
    /// band's corner rounding. The band itself spans the text container.
    static var codeBlockInset: CGFloat { (bodySize * 0.75).rounded() }
    static let codeBlockCornerRadius: CGFloat = 12
    static let codeChipCornerRadius: CGFloat = 4
    /// Block images are clipped to this radius; the default matches the
    /// code band, and Settings can change it.
    static var imageCornerRadius: CGFloat { CGFloat(configuration.imageCornerRadius) }
    /// One cached instance per palette: the chip drawing in the layout
    /// manager recognises spans by this exact colour.
    static var codeBlockBackground: NSColor { colors.codeBackground }
    /// Quote text is inset from the margin by the list indent; the rule
    /// stands on the margin itself, aligned with the surrounding text.
    static var quoteIndent: CGFloat { listIndent }

    /// `#` sits at body + 12 pt; `##` starts at body + 6 pt and each further
    /// level steps down 2 pt, never below body + 2 pt.
    static func headingSize(level: Int) -> CGFloat {
        level == 1 ? bodySize + 12 : max(bodySize + 2, bodySize + 6 - CGFloat(level - 2) * 2)
    }

    /// Canvas and ink come from the configured theme (plus any overrides)
    /// and resolve per appearance. The colour objects are cached per palette
    /// so equal colours are the same object and attribute runs merge; views
    /// re-read them on `Configuration.didChangeNotification`.
    static var canvas: NSColor { colors.canvas }
    static var ink: NSColor { colors.ink }
    static var mutedInk: NSColor { colors.mutedInk }
    /// Quoted text: softer than body ink, well above punctuation.
    static var quoteInk: NSColor { colors.quoteInk }

    /// Selection highlight: a quiet grey made from the ink rather than the
    /// system accent blue, so it sits inside the canvas palette.
    static var selection: NSColor { colors.selection }

    static var palette: Palette { configuration.palette }

    private struct Colors {
        let palette: Palette
        let canvas: NSColor
        let ink: NSColor
        let mutedInk: NSColor
        let quoteInk: NSColor
        let selection: NSColor
        let codeBackground: NSColor
        let hairline: NSColor
    }

    private static var cachedColors: Colors?

    private static var colors: Colors {
        let palette = self.palette
        if let cachedColors, cachedColors.palette == palette { return cachedColors }
        let ink = dynamic(light: palette.ink, dark: palette.inkDark)
        let colors = Colors(
            palette: palette,
            canvas: dynamic(light: palette.canvas, dark: palette.canvasDark),
            ink: ink,
            mutedInk: ink.withAlphaComponent(0.28),
            quoteInk: ink.withAlphaComponent(0.62),
            selection: ink.withAlphaComponent(0.13),
            codeBackground: ink.withAlphaComponent(0.055),
            hairline: ink.withAlphaComponent(0.10)
        )
        cachedColors = colors
        return colors
    }

    static func color(hex: String) -> NSColor {
        guard let c = HexColor.components(hex) else { return .textColor }
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    private static func dynamic(light: String, dark: String) -> NSColor {
        let lightColor = color(hex: light)
        let darkColor = color(hex: dark)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor
        }
    }

    /// The shipped default: the system serif, which has no user-installable
    /// family and resolves through the `.serif` design instead.
    static let systemSerifFamily = "New York"

    /// The configured family when installed, otherwise the system serif (New
    /// York) so rendering never falls back to a generic face.
    static func bodyFont(size: CGFloat = bodySize) -> NSFont {
        if preferredFamily != systemSerifFamily, let preferred = NSFont(
            descriptor: NSFontDescriptor(fontAttributes: [.family: preferredFamily]),
            size: size
        ), preferred.familyName == preferredFamily {
            return preferred
        }
        let system = NSFont.systemFont(ofSize: size)
        let descriptor = system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor
        return NSFont(descriptor: descriptor, size: size) ?? system
    }

    static func italicFont(size: CGFloat = bodySize) -> NSFont {
        let descriptor = bodyFont(size: size).fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: descriptor, size: size) ?? bodyFont(size: size)
    }

    static func boldFont(size: CGFloat = bodySize) -> NSFont {
        let descriptor = bodyFont(size: size).fontDescriptor.withSymbolicTraits(.bold)
        return NSFont(descriptor: descriptor, size: size) ?? bodyFont(size: size)
    }

    /// Headings use the family's face nearest to the configured weight.
    /// Families without that face resolve to the closest installed one. The
    /// system serif has no family `NSFontManager` can weight, so it takes
    /// the system font at the configured weight in the serif design.
    static func headingFont(size: CGFloat) -> NSFont {
        let body = bodyFont(size: size)
        if let family = body.familyName, family == preferredFamily,
           let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: headingWeight, size: size) {
            return font
        }
        let weighted = NSFont.systemFont(ofSize: size, weight: systemWeight)
        let descriptor = weighted.fontDescriptor.withDesign(.serif) ?? weighted.fontDescriptor
        return NSFont(descriptor: descriptor, size: size) ?? body
    }

    private static var systemWeight: NSFont.Weight {
        switch configuration.headingWeight {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
    }

    static func paragraphStyle(spacing: CGFloat? = nil) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        style.paragraphSpacing = spacing ?? paragraphSpacing
        return style
    }

    /// Block quotes and list items start their marker at `indent` and hang
    /// wrapped lines under the text, measured from the prefix's rendered
    /// width in the body font.
    static func hangingParagraphStyle(
        under prefix: String, indent: CGFloat = 0, gap: CGFloat = 0, spacing: CGFloat? = nil
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        style.paragraphSpacing = spacing ?? paragraphSpacing
        style.firstLineHeadIndent = indent
        style.headIndent = indent + gap + (prefix as NSString).size(withAttributes: [.font: bodyFont()]).width
        return style
    }

    /// A paragraph whose every line starts at `indent`: the continuation of
    /// a hard-wrapped list item, aligned under the item's text.
    static func flushParagraphStyle(indent: CGFloat, spacing: CGFloat? = nil) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        style.paragraphSpacing = spacing ?? paragraphSpacing
        style.firstLineHeadIndent = indent
        style.headIndent = indent
        return style
    }

    /// The body font when it has a glyph for `symbol`, otherwise the font the
    /// system would cascade to for it, so rendered list markers never fall
    /// back to the source character.
    static func markerFont(for symbol: String) -> NSFont {
        let body = bodyFont()
        if PaperLayoutManager.glyph(for: symbol.first ?? " ", in: body) != nil { return body }
        let fallback = CTFontCreateForString(body, symbol as CFString, CFRange(location: 0, length: symbol.utf16.count))
        return fallback as NSFont
    }

    static func codeFont(size: CGFloat = bodySize) -> NSFont {
        .monospacedSystemFont(ofSize: size * codeScale, weight: .regular)
    }
}
