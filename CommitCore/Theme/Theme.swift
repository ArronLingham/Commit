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

    // MARK: Graph colour scheme

    /// The currently selected informative palette variant, from shared defaults (default `.soft`).
    public static func informativePalette() -> InformativePalette {
        let raw = CommitConstants.sharedDefaults.string(forKey: InformativePalette.storageKey) ?? ""
        return InformativePalette(rawValue: raw) ?? .soft
    }

    /// Colour for a day's cell under the chosen scheme.
    ///
    /// - `.githubGreen`: intensity by how much of the day was completed, all in the accent hue.
    /// - `.informative`: blunt read by how many scheduled habits were **missed** that day —
    ///   0 → brightest green, 1 → a step-down green, 2–3 → yellow, 4+ → red, using the selected
    ///   palette variant. Days with nothing scheduled, and future days, stay neutral.
    public static func cellColor(day: DayContribution, scheme: GraphColorScheme, accent: Color) -> Color {
        guard day.isInRange else { return emptyCell.opacity(0.25) }

        switch scheme {
        case .githubGreen:
            return cellColor(level: day.level, accent: accent)

        case .informative:
            // Nothing assessed that day (no habits due, or a future day) → neutral, never red.
            guard day.scheduled > 0 else { return emptyCell.opacity(0.5) }

            let colors = informativePalette().colors
            switch day.missed {
            case 0: return colors.none
            case 1: return colors.one
            case 2...3: return colors.few
            default: return colors.many
            }
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

/// How the contribution graph colours its cells. User-selectable in Settings.
public enum GraphColorScheme: String, CaseIterable, Identifiable, Sendable {
    /// All-green, intensity by how much of the day was completed (classic GitHub look).
    case githubGreen
    /// Green → yellow → red by how many scheduled habits were missed that day.
    case informative

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .githubGreen: return "GitHub style"
        case .informative: return "Green · yellow · red"
        }
    }

    public static let storageKey = "graphColorScheme"
}

/// A shade/style variant for the informative (green·yellow·red) scheme. User-selectable in
/// Settings when that scheme is active.
public enum InformativePalette: String, CaseIterable, Identifiable, Sendable {
    case soft, deep, vivid

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .soft: return "Soft"
        case .deep: return "Deep"
        case .vivid: return "Vivid"
        }
    }

    /// Hex for the "all done" green — also used as the app accent when this palette is chosen.
    public var allDoneHex: String {
        switch self {
        case .soft: return "#4CAF6E"
        case .deep: return "#2E7D46"
        case .vivid: return "#2FB457"
        }
    }

    /// The four cell colours: none (all done) → one → few (2–3) → many (4+ missed).
    public var colors: (none: Color, one: Color, few: Color, many: Color) {
        func c(_ hex: String) -> Color { Color(hex: hex) ?? .gray }
        switch self {
        case .soft: return (c("#4CAF6E"), c("#8BC28A"), c("#E0B152"), c("#D06B62"))
        case .deep: return (c("#2E7D46"), c("#5C9A5E"), c("#C99A3B"), c("#B4453F"))
        case .vivid: return (c("#2FB457"), c("#7DCB6B"), c("#F2C14E"), c("#EF5350"))
        }
    }

    public static let storageKey = "informativePalette"
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
