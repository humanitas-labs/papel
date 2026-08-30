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

    static let canvas = NSColor(
        name: nil,
        dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(srgbRed: 0.105, green: 0.098, blue: 0.086, alpha: 1)
            }
            return NSColor(srgbRed: 0.965, green: 0.951, blue: 0.925, alpha: 1)
        }
    )

    static let ink = NSColor(
        name: nil,
        dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(srgbRed: 0.91, green: 0.89, blue: 0.84, alpha: 1)
            }
            return NSColor(srgbRed: 0.105, green: 0.098, blue: 0.086, alpha: 1)
        }
    )

    static let mutedInk = ink.withAlphaComponent(0.28)

    /// Selection highlight: a quiet warm grey made from the ink rather than
    /// the system accent blue, so it sits inside the canvas palette.
    static let selection = ink.withAlphaComponent(0.13)

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

    /// Block quotes keep the marker at the margin and hang wrapped lines under
    /// the quoted text, measured from the marker's rendered width.
    static func quoteParagraphStyle(hangingUnder marker: String) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeightMultiple
        style.paragraphSpacing = paragraphSpacing
        style.headIndent = (marker as NSString).size(withAttributes: [.font: bodyFont()]).width
        return style
    }

    static func codeFont(size: CGFloat = bodySize) -> NSFont {
        .monospacedSystemFont(ofSize: size * codeScale, weight: .regular)
    }
}
