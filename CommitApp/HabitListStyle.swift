import Foundation

/// How the home page presents habits that aren't due today. User-selectable in Settings.
enum OtherHabitsStyle: String, CaseIterable, Identifiable {
    /// A second "Upcoming" section under Today.
    case upcoming
    /// A Today / All segmented switch above the list.
    case toggle
    /// A collapsible "Other habits" disclosure under Today.
    case collapsible

    var id: String { rawValue }

    var label: String {
        switch self {
        case .upcoming: return "Upcoming section"
        case .toggle: return "Today / All toggle"
        case .collapsible: return "Collapsible list"
        }
    }

    static let storageKey = "otherHabitsStyle"
}
