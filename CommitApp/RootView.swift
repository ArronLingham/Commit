import SwiftUI
import CommitCore

/// Top-level navigation. Tabs on iOS; a sidebar split view on macOS.
struct RootView: View {
    #if os(macOS)
    enum Section: String, CaseIterable, Identifiable {
        case today = "Today"
        case progress = "Progress"
        case habits = "Habits"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .today: return "checkmark.circle"
            case .progress: return "square.grid.3x3.fill"
            case .habits: return "list.bullet"
            }
        }
    }

    @State private var selection: Section? = .today

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .navigationTitle("Commit")
        } detail: {
            switch selection ?? .today {
            case .today: TodayView()
            case .progress: StatsView()
            case .habits: ManageHabitsView()
            }
        }
    }
    #else
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "checkmark.circle") }
            StatsView()
                .tabItem { Label("Progress", systemImage: "square.grid.3x3.fill") }
            ManageHabitsView()
                .tabItem { Label("Habits", systemImage: "list.bullet") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
    #endif
}
