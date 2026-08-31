import Foundation

/// Everything the user can tune, read from `~/.config/paper/config`.
/// Values are validated and clamped on parse so a typo in the file degrades
/// to the default for that key rather than breaking the window.
struct Configuration: Equatable, Sendable {
    enum HeadingWeight: String, CaseIterable, Sendable {
        case regular, medium, semibold, bold

        /// `NSFontManager` weight on its 0–15 scale.
        var fontManagerWeight: Int {
            switch self {
            case .regular: 5
            case .medium: 6
            case .semibold: 8
            case .bold: 9
            }
        }
    }

    var fontFamily = "Test Family"
    var fontSize: Double = 14
    var lineHeight: Double = 1.38
    var paragraphSpacing: Double = 13
    var measure: Double = 640
    /// Tracking in points added between characters; negative tightens.
    var letterSpacing: Double = 0
    var headingWeight: HeadingWeight = .medium
    var theme: Theme = .paper
    /// Size of a newly opened window in points; macOS restores each window's
    /// last size after that.
    var windowWidth: Double = 1120
    var windowHeight: Double = 800
    /// Hex overrides for the theme's colours; nil inherits the theme.
    var canvas: String?
    var ink: String?
    var canvasDark: String?
    var inkDark: String?

    /// The theme's palette with any overrides applied.
    var palette: Palette {
        var palette = theme.palette
        if let canvas { palette.canvas = canvas }
        if let ink { palette.ink = ink }
        if let canvasDark { palette.canvasDark = canvasDark }
        if let inkDark { palette.inkDark = inkDark }
        return palette
    }

    static let fontSizeRange: ClosedRange<Double> = 8...40
    static let lineHeightRange: ClosedRange<Double> = 1...2.5
    static let paragraphSpacingRange: ClosedRange<Double> = 0...60
    static let measureRange: ClosedRange<Double> = 320...1200
    static let letterSpacingRange: ClosedRange<Double> = -1...3
    static let windowWidthRange: ClosedRange<Double> = 640...4000
    static let windowHeightRange: ClosedRange<Double> = 520...3000

    static let didChangeNotification = Notification.Name("paper.configuration.didChange")

    /// The file Paper writes on first launch: every key, its default, and
    /// what it does. Parsing this text yields `Configuration()`.
    static let template = """
    # Paper configuration. Edits apply to open windows as you save.
    # Lines starting with # are comments. Unknown keys are ignored; invalid
    # values fall back to the default shown here. Presets are files in the
    # presets/ directory beside this one, in the same format; Settings can
    # save, apply, and delete them.

    # Body typeface (an installed family name) and size in points.
    font.family = Test Family
    font.size = 14

    # Line height as a multiple of the font size, and space after a paragraph
    # in points.
    line.height = 1.38
    paragraph.spacing = 13

    # Maximum text width in points.
    measure = 640

    # Letter spacing in points added between characters (negative tightens).
    letter.spacing = 0

    # Heading weight: regular, medium, semibold, or bold. The nearest installed
    # face is used.
    heading.weight = medium

    # Theme: paper, sepia, slate, mono, spatial-dark, or apple-dark (the last
    # two are dark in both appearances; the others have light and dark
    # colours).
    theme = paper

    # Size of new windows in points. Each window remembers its own size
    # after that.
    window.width = 1120
    window.height = 800

    # Colour overrides as #RRGGBB. Leave a value empty to use the theme's.
    color.canvas =
    color.ink =
    color.canvas.dark =
    color.ink.dark =

    """

    /// Parses `key = value` lines. Whitespace around keys and values is
    /// trimmed; a value may be wrapped in single or double quotes.
    static func parse(_ text: String) -> Configuration {
        var config = Configuration()
        for rawLine in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            let value = unquote(line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces))
            config.apply(key: key, value: value)
        }
        return config
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

    private mutating func apply(key: String, value: String) {
        switch key {
        case "font.family":
            if !value.isEmpty { fontFamily = value }
        case "font.size":
            fontSize = Self.number(value, in: Self.fontSizeRange) ?? fontSize
        case "line.height":
            lineHeight = Self.number(value, in: Self.lineHeightRange) ?? lineHeight
        case "paragraph.spacing":
            paragraphSpacing = Self.number(value, in: Self.paragraphSpacingRange) ?? paragraphSpacing
        case "measure":
            measure = Self.number(value, in: Self.measureRange) ?? measure
        case "letter.spacing":
            letterSpacing = Self.number(value, in: Self.letterSpacingRange) ?? letterSpacing
        case "heading.weight":
            headingWeight = HeadingWeight(rawValue: value.lowercased()) ?? headingWeight
        case "window.width":
            windowWidth = Self.number(value, in: Self.windowWidthRange) ?? windowWidth
        case "window.height":
            windowHeight = Self.number(value, in: Self.windowHeightRange) ?? windowHeight
        case "theme":
            theme = Theme(rawValue: value.lowercased()) ?? theme
        case "color.canvas":
            canvas = HexColor.normalized(value)
        case "color.ink":
            ink = HexColor.normalized(value)
        case "color.canvas.dark":
            canvasDark = HexColor.normalized(value)
        case "color.ink.dark":
            inkDark = HexColor.normalized(value)
        default:
            break
        }
    }

    /// Every key with its current value, in template order.
    var entries: [(key: String, value: String)] {
        [
            ("font.family", fontFamily),
            ("font.size", Self.format(fontSize)),
            ("line.height", Self.format(lineHeight)),
            ("paragraph.spacing", Self.format(paragraphSpacing)),
            ("measure", Self.format(measure)),
            ("letter.spacing", Self.format(letterSpacing)),
            ("heading.weight", headingWeight.rawValue),
            ("theme", theme.rawValue),
            ("window.width", Self.format(windowWidth)),
            ("window.height", Self.format(windowHeight)),
            ("color.canvas", canvas ?? ""),
            ("color.ink", ink ?? ""),
            ("color.canvas.dark", canvasDark ?? ""),
            ("color.ink.dark", inkDark ?? ""),
        ]
    }

    /// Writes this configuration into existing file text, keeping comments,
    /// order, and unknown keys. Keys already present are updated in place;
    /// missing keys are appended.
    func merged(into text: String) -> String {
        var remaining = Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value) })
        var lines = text.components(separatedBy: "\n")
        for index in lines.indices {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            guard let value = remaining.removeValue(forKey: key) else { continue }
            lines[index] = value.isEmpty ? "\(key) =" : "\(key) = \(value)"
        }
        if !remaining.isEmpty {
            if let last = lines.last, !last.isEmpty { lines.append("") }
            for entry in entries where remaining[entry.key] != nil {
                lines.append(entry.value.isEmpty ? "\(entry.key) =" : "\(entry.key) = \(entry.value)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private static func format(_ number: Double) -> String {
        number == number.rounded() ? String(Int(number)) : String(format: "%.2f", number)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
    }

    private static func number(_ value: String, in range: ClosedRange<Double>) -> Double? {
        guard let parsed = Double(value), parsed.isFinite else { return nil }
        return min(max(parsed, range.lowerBound), range.upperBound)
    }
}
