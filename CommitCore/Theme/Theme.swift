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

    /// Colour for a day's cell under the chosen scheme.
    ///
    /// - `.githubGreen`: intensity by how much of the day was completed, all in the accent hue.
    /// - `.informative` (aggregate): read by how many scheduled habits were **missed** that day.
    ///   The yellow and red cutoffs are configurable in Settings. Days
    ///   with nothing scheduled, and future days, stay neutral.
    /// - `.informative` with `singleHabit`: one habit can only be done or missed, so it's binary —
    ///   done → green, missed → red — with today-not-yet-done left neutral.
    public static func cellColor(
        day: DayContribution,
        scheme: GraphColorScheme,
        accent: Color,
        singleHabit: Bool = false
    ) -> Color {
        guard day.isInRange else { return emptyCell.opacity(0.25) }

        switch scheme {
        case .githubGreen:
            return cellColor(level: day.level, accent: accent)

        case .informative:
            // Nothing assessed that day (no habits due, or a future day) → neutral, never red.
            guard day.scheduled > 0 else { return emptyCell.opacity(0.5) }

            if singleHabit {
                // Don't flag an in-progress today red before it's had a chance to be done.
                if day.missed > 0 && Calendar.current.isDate(day.date, inSameDayAs: AppClock.now) {
                    return emptyCell.opacity(0.5)
                }
                return day.missed == 0 ? InformativeThresholds.allDoneColor : InformativeThresholds.redColor
            }

            switch InformativeThresholds.current.category(forMissed: day.missed) {
            case .green:
                return day.missed == 0 ? InformativeThresholds.allDoneColor : InformativeThresholds.greenColor
            case .yellow: return InformativeThresholds.yellowColor
            case .red: return InformativeThresholds.redColor
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

/// Miss-count cutoffs for the aggregate green/yellow/red graph. Existing installs keep
/// the former 0–1 green, 2–3 yellow, 4+ red behavior until the user changes them.
public struct InformativeThresholds: Sendable {
    public enum Category: Equatable, Sendable { case green, yellow, red }

    public static let yellowKey = "informativeYellowStartsAt"
    public static let redKey = "informativeRedStartsAt"
    public static let defaultYellow = 2
    public static let defaultRed = 4

    public let yellowStartsAt: Int
    public let redStartsAt: Int

    public init(yellowStartsAt: Int = defaultYellow, redStartsAt: Int = defaultRed) {
        self.yellowStartsAt = min(99, max(1, yellowStartsAt))
        self.redStartsAt = min(100, max(self.yellowStartsAt + 1, redStartsAt))
    }

    public static var current: Self {
        let defaults = CommitConstants.sharedDefaults
        return Self(
            yellowStartsAt: defaults.object(forKey: yellowKey) as? Int ?? defaultYellow,
            redStartsAt: defaults.object(forKey: redKey) as? Int ?? defaultRed
        )
    }

    public func category(forMissed missed: Int) -> Category {
        if missed >= redStartsAt { return .red }
        if missed >= yellowStartsAt { return .yellow }
        return .green
    }

    public static var allDoneColor: Color { Color(hex: "#4CAF6E")! }
    public static var greenColor: Color { Color(hex: "#8BC28A")! }
    public static var yellowColor: Color { Color(hex: "#E0B152")! }
    public static var redColor: Color { Color(hex: "#D06B62")! }
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
