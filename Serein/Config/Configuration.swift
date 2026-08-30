import Foundation

/// Everything the user can tune, read from `~/.config/serein/config`.
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
    var headingWeight: HeadingWeight = .medium

    static let fontSizeRange: ClosedRange<Double> = 8...40
    static let lineHeightRange: ClosedRange<Double> = 1...2.5
    static let paragraphSpacingRange: ClosedRange<Double> = 0...60
    static let measureRange: ClosedRange<Double> = 320...1200

    static let didChangeNotification = Notification.Name("serein.configuration.didChange")

    /// The file Serein writes on first launch: every key, its default, and
    /// what it does. Parsing this text yields `Configuration()`.
    static let template = """
    # Serein configuration. Edits apply to open windows as you save.
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

    # Heading weight: regular, medium, semibold, or bold. The nearest installed
    # face is used.
    heading.weight = medium

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
        case "heading.weight":
            headingWeight = HeadingWeight(rawValue: value.lowercased()) ?? headingWeight
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
            ("heading.weight", headingWeight.rawValue),
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
            lines[index] = "\(key) = \(value)"
        }
        if !remaining.isEmpty {
            if let last = lines.last, !last.isEmpty { lines.append("") }
            for entry in entries where remaining[entry.key] != nil {
                lines.append("\(entry.key) = \(entry.value)")
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
