import Foundation

/// Four colours define a theme: canvas and ink for light and dark
/// appearances. Every other tone (muted punctuation, selection, the file
/// label, the quote rule) is derived from the ink by opacity.
struct Palette: Equatable, Sendable {
    var canvas: String
    var ink: String
    var canvasDark: String
    var inkDark: String

    /// The colour keys of a theme file or of the config's overrides: each
    /// value is a `#RRGGBB` string or nil to inherit.
    struct Overrides: Equatable, Sendable {
        var canvas: String?
        var ink: String?
        var canvasDark: String?
        var inkDark: String?

        var isEmpty: Bool { self == Overrides() }
    }

    /// `overrides` layered over this palette; nil values keep the base.
    func applying(_ overrides: Overrides) -> Palette {
        Palette(
            canvas: overrides.canvas ?? canvas,
            ink: overrides.ink ?? ink,
            canvasDark: overrides.canvasDark ?? canvasDark,
            inkDark: overrides.inkDark ?? inkDark
        )
    }

    /// Every value as an override, for writing a palette out as a theme file.
    var overrides: Overrides {
        Overrides(canvas: canvas, ink: ink, canvasDark: canvasDark, inkDark: inkDark)
    }
}

extension Palette.Overrides {
    /// The overrides as `color.*` lines: the content of a theme file.
    var fileText: String {
        Configuration.colorEntries(self)
            .filter { !$0.value.isEmpty }
            .map { "\($0.key) = \($0.value)" }
            .joined(separator: "\n") + "\n"
    }
}

/// A named palette, chosen by the `theme` configuration key. The built-ins
/// ship with the app; user themes are files in `themes/` beside the config,
/// holding the same `color.*` keys, and shadow a built-in of the same name.
struct Theme: Equatable, Sendable, Identifiable {
    /// The stored name: lowercase, the file name for a user theme.
    let name: String
    let title: String
    let palette: Palette
    let isBuiltIn: Bool

    var id: String { name }

    static let paper = Theme(
        name: "paper", title: "Paper",
        palette: Palette(canvas: "#F6F3EC", ink: "#1B1916", canvasDark: "#1B1916", inkDark: "#E8E3D6"),
        isBuiltIn: true
    )

    static let builtIn: [Theme] = [
        paper,
        Theme(name: "slate", title: "Slate",
              palette: Palette(canvas: "#F2F3F5", ink: "#1F2328", canvasDark: "#15181C", inkDark: "#D9DEE5"),
              isBuiltIn: true),
        Theme(name: "mono", title: "Mono",
              palette: Palette(canvas: "#FFFFFF", ink: "#000000", canvasDark: "#000000", inkDark: "#EDEDED"),
              isBuiltIn: true),
        Theme(name: "spatial", title: "Spatial",
              palette: Palette(canvas: "#FFFFFF", ink: "#161819", canvasDark: "#191B1D", inkDark: "#F4F9FA"),
              isBuiltIn: true),
        Theme(name: "apple", title: "Apple",
              palette: Palette(canvas: "#FFFFFF", ink: "#272727", canvasDark: "#212323", inkDark: "#DDDDDD"),
              isBuiltIn: true),
    ]

    static func builtIn(named name: String) -> Theme? {
        builtIn.first { $0.name == name }
    }

    /// The name as stored: trimmed, lowercased, and with the pre-0.2
    /// `spatial-dark` and `apple-dark` spellings mapped to the renamed
    /// themes. Empty for a blank value.
    static func canonicalName(_ text: String) -> String {
        let name = text.trimmingCharacters(in: .whitespaces).lowercased()
        switch name {
        case "spatial-dark": return "spatial"
        case "apple-dark": return "apple"
        default: return name
        }
    }

    /// A user theme parsed from a theme file. Keys the file leaves out fall
    /// back to Paper's values, so a light-only theme still has a dark pair.
    static func user(named name: String, text: String) -> Theme {
        Theme(
            name: canonicalName(name),
            title: name,
            palette: paper.palette.applying(Configuration.parse(text).colorOverrides),
            isBuiltIn: false
        )
    }
}

/// `#RRGGBB` (case-insensitive, `#` optional) to sRGB components and back.
enum HexColor {
    static func components(_ text: String) -> (red: Double, green: Double, blue: Double)? {
        var hex = text.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    static func normalized(_ text: String) -> String? {
        guard let c = components(text) else { return nil }
        return string(red: c.red, green: c.green, blue: c.blue)
    }

    static func string(red: Double, green: Double, blue: Double) -> String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
    }
}
