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

/// How a non-today habit's next occurrence is written. User-selectable in Settings.
enum NextOccurrenceStyle: String, CaseIterable, Identifiable {
    /// Just the weekday, e.g. "Sunday".
    case weekday
    /// Just the date, e.g. "Jun 29".
    case date
    /// Both, e.g. "Sunday · Jun 29".
    case weekdayAndDate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weekday: return "Weekday"
        case .date: return "Date"
        case .weekdayAndDate: return "Weekday + date"
        }
    }

    static let storageKey = "nextOccurrenceStyle"
}
