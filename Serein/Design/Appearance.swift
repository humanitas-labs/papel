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
    static let topMargin: CGFloat = 90
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
    static let labelSize: CGFloat = 12
    static let labelInset: CGFloat = 24
    static var labelInk: NSColor { ink.withAlphaComponent(0.34) }

    /// Block-quote rule: a bar in the margin, left of the `>` marker.
    static let quoteRuleWidth: CGFloat = 2
    static let quoteRuleOffset: CGFloat = 14

    /// `#` sits at body + 10 pt; `##` starts at body + 6 pt and each further
    /// level steps down 2 pt, never below body + 2 pt.
    static func headingSize(level: Int) -> CGFloat {
        level == 1 ? bodySize + 10 : max(bodySize + 2, bodySize + 6 - CGFloat(level - 2) * 2)
    }

    /// Canvas and ink come from the configured theme (plus any overrides)
    /// and resolve per appearance. The colour objects are cached per palette
    /// so equal colours are the same object and attribute runs merge; views
    /// re-read them on `Configuration.didChangeNotification`.
    static var canvas: NSColor { colors.canvas }
    static var ink: NSColor { colors.ink }
    static var mutedInk: NSColor { colors.mutedInk }

    /// Selection highlight: a quiet grey made from the ink rather than the
    /// system accent blue, so it sits inside the canvas palette.
    static var selection: NSColor { colors.selection }

    static var palette: Palette { configuration.palette }

    private struct Colors {
        let palette: Palette
        let canvas: NSColor
        let ink: NSColor
        let mutedInk: NSColor
        let selection: NSColor
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
            selection: ink.withAlphaComponent(0.13)
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

    /// The configured family when installed, otherwise the system serif (New
    /// York) so rendering never falls back to a generic face.
    static func bodyFont(size: CGFloat = bodySize) -> NSFont {
        if let preferred = NSFont(
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
    /// Families without that face resolve to the closest installed one.
    static func headingFont(size: CGFloat) -> NSFont {
        guard let family = bodyFont(size: size).familyName,
              let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: headingWeight, size: size)
        else { return bodyFont(size: size) }
        return font
    }

    static func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        style.paragraphSpacing = paragraphSpacing
        return style
    }

    /// Block quotes and list items keep their marker at the margin and hang
    /// wrapped lines under the text, measured from the prefix's rendered
    /// width in the body font.
    static func hangingParagraphStyle(under prefix: String) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        style.paragraphSpacing = paragraphSpacing
        style.headIndent = (prefix as NSString).size(withAttributes: [.font: bodyFont()]).width
        return style
    }

    /// The body font when it has a glyph for `symbol`, otherwise the font the
    /// system would cascade to for it, so rendered list markers never fall
    /// back to the source character.
    static func markerFont(for symbol: String) -> NSFont {
        let body = bodyFont()
        if SereinLayoutManager.glyph(for: symbol.first ?? " ", in: body) != nil { return body }
        let fallback = CTFontCreateForString(body, symbol as CFString, CFRange(location: 0, length: symbol.utf16.count))
        return fallback as NSFont
    }

    static func codeFont(size: CGFloat = bodySize) -> NSFont {
        .monospacedSystemFont(ofSize: size * codeScale, weight: .regular)
    }
}
