import Foundation

/// Four colours define a theme: canvas and ink for light and dark
/// appearances. Every other tone (muted punctuation, selection, the file
/// label, the quote rule) is derived from the ink by opacity.
struct Palette: Equatable, Sendable {
    var canvas: String
    var ink: String
    var canvasDark: String
    var inkDark: String
}

/// Built-in themes, chosen by the `theme` configuration key.
enum Theme: String, CaseIterable, Sendable {
    case paper, sepia, slate, mono
    /// Dark in both appearances.
    case spatialDark = "spatial-dark"
    case appleDark = "apple-dark"

    var palette: Palette {
        switch self {
        case .paper: Palette(canvas: "#F6F3EC", ink: "#1B1916", canvasDark: "#1B1916", inkDark: "#E8E3D6")
        case .sepia: Palette(canvas: "#F4ECD8", ink: "#3B2F1E", canvasDark: "#2A241B", inkDark: "#E6D9BF")
        case .slate: Palette(canvas: "#F2F3F5", ink: "#1F2328", canvasDark: "#15181C", inkDark: "#D9DEE5")
        case .mono: Palette(canvas: "#FFFFFF", ink: "#000000", canvasDark: "#000000", inkDark: "#EDEDED")
        case .spatialDark: Palette(canvas: "#191B1D", ink: "#F4F9FA", canvasDark: "#191B1D", inkDark: "#F4F9FA")
        case .appleDark: Palette(canvas: "#212323", ink: "#DDDDDD", canvasDark: "#212323", inkDark: "#DDDDDD")
        }
    }

    var title: String {
        switch self {
        case .paper: "Paper"
        case .sepia: "Sepia"
        case .slate: "Slate"
        case .mono: "Mono"
        case .spatialDark: "Spatial Dark"
        case .appleDark: "Apple Dark"
        }
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
