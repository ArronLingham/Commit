import SwiftUI

/// Minimalist palette + the GitHub-style 5-step intensity scale.
public enum Theme {
    public static let defaultAccentHex = "#39D353"
    public static let accentColorHexKey = "accentColorHex"

    public static var defaultAccent: Color { Color(hex: defaultAccentHex) ?? .green }

    /// A few calm presets for the accent picker.
    public static let presetAccents: [String] = [
        "#39D353", // green (default, GitHub-like)
        "#2F81F7", // blue
        "#A371F7", // purple
        "#F778BA", // pink
        "#FB8500", // orange
        "#E5534B", // red
        "#3FB950", // emerald
        "#8B949E", // graphite
    ]

    /// Empty-cell colour for the contribution graph (subtle, theme-aware).
    public static var emptyCell: Color {
        #if os(macOS)
        Color(nsColor: .quaternaryLabelColor)
        #else
        Color(uiColor: .quaternaryLabel)
        #endif
    }

    /// Colour for a contribution cell at `level` (0…4) given the chosen `accent`.
    public static func cellColor(level: Int, accent: Color) -> Color {
        switch level {
        case 0: return emptyCell.opacity(0.5)
        case 1: return accent.opacity(0.30)
        case 2: return accent.opacity(0.50)
        case 3: return accent.opacity(0.75)
        default: return accent
        }
    }

    /// The user's chosen accent, read from the shared App Group defaults so the widget
    /// matches the app.
    public static func currentAccent() -> Color {
        let hex = CommitConstants.sharedDefaults.string(forKey: accentColorHexKey) ?? defaultAccentHex
        return Color(hex: hex) ?? defaultAccent
    }

    public static func setAccent(hex: String) {
        CommitConstants.sharedDefaults.set(hex, forKey: accentColorHexKey)
    }
}

public extension Color {
    /// Create a colour from a `#RRGGBB` or `#RRGGBBAA` hex string.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let value = UInt64(s, radix: 16) else { return nil }

        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((value & 0xFF0000) >> 16) / 255
            g = Double((value & 0x00FF00) >> 8) / 255
            b = Double(value & 0x0000FF) / 255
            a = 1
        case 8:
            r = Double((value & 0xFF000000) >> 24) / 255
            g = Double((value & 0x00FF0000) >> 16) / 255
            b = Double((value & 0x0000FF00) >> 8) / 255
            a = Double(value & 0x000000FF) / 255
        default:
            return nil
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
