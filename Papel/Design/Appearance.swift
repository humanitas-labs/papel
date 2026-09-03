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
    static var fontSmoothing: Bool { configuration.fontSmoothing }
    static var bodyWeight: CGFloat { CGFloat(configuration.fontWeight) }
    static var headingWeight: CGFloat { CGFloat(configuration.headingWeight) }

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

    static var palette: Palette { ConfigurationStore.shared.palette }

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
        let lightInk = color(hex: palette.ink)
        let darkInk = color(hex: palette.inkDark)
        /// A tone from the theme when it names one, else the ink at `alpha`.
        func tone(_ light: String?, _ dark: String?, alpha: CGFloat) -> NSColor {
            dynamic(
                light: light.map(color(hex:)) ?? lightInk.withAlphaComponent(alpha),
                dark: dark.map(color(hex:)) ?? darkInk.withAlphaComponent(alpha)
            )
        }
        let colors = Colors(
            palette: palette,
            canvas: dynamic(light: color(hex: palette.canvas), dark: color(hex: palette.canvasDark)),
            ink: dynamic(light: lightInk, dark: darkInk),
            mutedInk: tone(palette.inkMuted, palette.inkMutedDark, alpha: 0.28),
            quoteInk: tone(palette.inkQuote, palette.inkQuoteDark, alpha: 0.62),
            selection: tone(palette.selection, palette.selectionDark, alpha: 0.13),
            codeBackground: tone(palette.codeBackground, palette.codeBackgroundDark, alpha: 0.055),
            hairline: tone(palette.rule, palette.ruleDark, alpha: 0.10)
        )
        cachedColors = colors
        return colors
    }

    static func color(hex: String) -> NSColor {
        guard let c = HexColor.components(hex) else { return .textColor }
        return NSColor(srgbRed: c.red, green: c.green, blue: c.blue, alpha: 1)
    }

    private static func dynamic(light lightColor: NSColor, dark darkColor: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor
        }
    }

    /// The shipped default: the system serif, which has no user-installable
    /// family and resolves through the `.serif` design instead.
    static let systemSerifFamily = "New York"

    /// Whether the configured family is installed; otherwise the system
    /// serif (New York) stands in, so rendering never falls back to a
    /// generic face.
    private static var preferredFamilyIsInstalled: Bool {
        preferredFamily != systemSerifFamily
            && NSFontManager.shared.availableFontFamilies.contains(preferredFamily)
    }

    /// The body face at the configured weight.
    static func bodyFont(size: CGFloat = bodySize) -> NSFont {
        font(size: size, weight: bodyWeight, italic: false)
    }

    static func italicFont(size: CGFloat = bodySize) -> NSFont {
        font(size: size, weight: bodyWeight, italic: true)
    }

    /// Bold is the body weight plus three hundred, at least the bold face.
    static func boldFont(size: CGFloat = bodySize) -> NSFont {
        font(size: size, weight: max(bodyWeight + 300, 700), italic: false)
    }

    /// Headings use the configured heading weight.
    static func headingFont(size: CGFloat) -> NSFont {
        font(size: size, weight: headingWeight, italic: false)
    }

    /// A face at `weight` on the CSS scale. The system serif takes the
    /// weight through `NSFont.Weight`, which is continuous. An installed
    /// family with a variable weight axis takes the exact value on that
    /// axis; a static family takes its nearest face through the font
    /// manager.
    static func font(size: CGFloat, weight: CGFloat, italic: Bool) -> NSFont {
        let weight = min(max(weight, 100), 900)
        guard preferredFamilyIsInstalled else {
            let system = NSFont.systemFont(ofSize: size, weight: systemWeight(weight))
            var descriptor = system.fontDescriptor.withDesign(.serif) ?? system.fontDescriptor
            if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
            return NSFont(descriptor: descriptor, size: size) ?? system
        }
        let base = NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: preferredFamily]), size: size)
            ?? NSFont.systemFont(ofSize: size)
        if let axis = weightAxis(of: base) {
            let value = min(max(weight, axis.minimum), axis.maximum)
            var descriptor = base.fontDescriptor.addingAttributes([.variation: [NSNumber(value: axis.identifier): value]])
            if italic { descriptor = descriptor.withSymbolicTraits(.italic) }
            if let font = NSFont(descriptor: descriptor, size: size) { return font }
        }
        let traits: NSFontTraitMask = italic ? .italicFontMask : []
        if let font = NSFontManager.shared.font(withFamily: preferredFamily, traits: traits, weight: managerWeight(weight), size: size) {
            return font
        }
        let descriptor = italic ? base.fontDescriptor.withSymbolicTraits(.italic) : base.fontDescriptor
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    /// The `wght` axis of a variable face, if it has one.
    private static func weightAxis(of font: NSFont) -> (identifier: Int, minimum: CGFloat, maximum: CGFloat)? {
        guard let axes = CTFontCopyVariationAxes(font) as? [[String: Any]] else { return nil }
        for axis in axes {
            guard let identifier = axis[kCTFontVariationAxisIdentifierKey as String] as? Int,
                  identifier == 0x77676874,
                  let minimum = axis[kCTFontVariationAxisMinimumValueKey as String] as? CGFloat,
                  let maximum = axis[kCTFontVariationAxisMaximumValueKey as String] as? CGFloat
            else { continue }
            return (identifier, minimum, maximum)
        }
        return nil
    }

    /// CSS weight to `NSFont.Weight`, interpolated between Apple's named
    /// stops so the system's variable faces take any value.
    static func systemWeight(_ css: CGFloat) -> NSFont.Weight {
        let stops: [(CGFloat, CGFloat)] = [
            (100, NSFont.Weight.ultraLight.rawValue), (200, NSFont.Weight.thin.rawValue),
            (300, NSFont.Weight.light.rawValue), (400, NSFont.Weight.regular.rawValue),
            (500, NSFont.Weight.medium.rawValue), (600, NSFont.Weight.semibold.rawValue),
            (700, NSFont.Weight.bold.rawValue), (800, NSFont.Weight.heavy.rawValue),
            (900, NSFont.Weight.black.rawValue),
        ]
        return NSFont.Weight(rawValue: interpolate(css, stops))
    }

    /// CSS weight to the font manager's 0–15 scale, for static families.
    static func managerWeight(_ css: CGFloat) -> Int {
        let stops: [(CGFloat, CGFloat)] = [(100, 1), (200, 2), (300, 3), (400, 5), (500, 6), (600, 8), (700, 9), (800, 10), (900, 12)]
        return Int(interpolate(css, stops).rounded())
    }

    private static func interpolate(_ x: CGFloat, _ stops: [(CGFloat, CGFloat)]) -> CGFloat {
        if x <= stops[0].0 { return stops[0].1 }
        for (a, b) in zip(stops, stops.dropFirst()) where x <= b.0 {
            let t = (x - a.0) / (b.0 - a.0)
            return a.1 + (b.1 - a.1) * t
        }
        return stops[stops.count - 1].1
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
        if PapelLayoutManager.glyph(for: symbol.first ?? " ", in: body) != nil { return body }
        let fallback = CTFontCreateForString(body, symbol as CFString, CFRange(location: 0, length: symbol.utf16.count))
        return fallback as NSFont
    }

    static func codeFont(size: CGFloat = bodySize) -> NSFont {
        .monospacedSystemFont(ofSize: size * codeScale, weight: .regular)
    }
}
