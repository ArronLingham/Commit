import Foundation

/// The overall look-and-feel of the app window. User-selectable in Settings.
///
/// - `.minimalist`: the original clean single page — a centred content column with flat,
///   low-contrast surfaces.
/// - `.macOS`: an Apple-style layout with a translucent sidebar (à la System Settings / Music),
///   frosted material cards, and Finder-style hover highlights.
///
/// Stored in the shared App Group defaults (like the other appearance keys) so any surface that
/// wants to react — or a future widget — reads the same value.
public enum AppearanceStyle: String, CaseIterable, Identifiable, Sendable {
    case minimalist
    case macOS

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .minimalist: return "Minimalist"
        case .macOS: return "macOS"
        }
    }

    /// A one-line description shown under the picker in Settings.
    public var blurb: String {
        switch self {
        case .minimalist:
            return "A clean single page with a centred column."
        case .macOS:
            return "A sidebar and frosted materials, matching System Settings."
        }
    }

    public static let storageKey = "appearanceStyle"

    /// The user's chosen style, read from the shared defaults. Defaults to `.minimalist` so
    /// existing installs are left exactly as they were.
    public static var current: AppearanceStyle {
        let raw = CommitConstants.sharedDefaults.string(forKey: storageKey) ?? ""
        return AppearanceStyle(rawValue: raw) ?? .minimalist
    }
}
