import SwiftUI
import SwiftData
import CommitCore
#if canImport(AppKit)
import AppKit
#endif

#if os(macOS)
/// Compact menu-bar popover: today's habits with quick toggles, a mini graph, and
/// shortcuts to open the app or quit.
struct MenuBarView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Query(filter: #Predicate<Habit> { !$0.isArchived && !$0.isDeleted }, sort: \Habit.sortOrder)
    private var habits: [Habit]

    @AppStorage(Theme.accentColorHexKey, store: CommitConstants.sharedDefaults)
    private var accentHex = Theme.defaultAccentHex
    private var accent: Color { Color(hex: accentHex) ?? Theme.defaultAccent }

    private var todaysHabits: [Habit] {
        habits.filter { $0.schedule.isScheduled(on: Date()) }
    }
    private var completedToday: Int {
        todaysHabits.filter { $0.isCompleted(on: Date()) }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Commit").font(.headline)
                Spacer()
                Text("\(completedToday)/\(todaysHabits.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let contributions = makeContributions(habits: habits, range: .trailingWeeks(14))
            ContributionGraphView(
                days: contributions.days,
                cellSize: 9,
                spacing: 2,
                accent: accent,
                showMonthLabels: false
            )

            Divider()

            if todaysHabits.isEmpty {
                Text("Nothing scheduled today")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(todaysHabits) { habit in
                        MenuBarHabitRow(habit: habit, accent: accent) {
                            _ = HabitActions.toggleCompletion(for: habit, in: context)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Open Commit") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .font(.subheadline)
        }
        .padding(14)
    }
}

private struct MenuBarHabitRow: View {
    let habit: Habit
    let accent: Color
    let toggle: () -> Void

    private var habitColor: Color { Color(hex: habit.colorHex) ?? accent }
    private var done: Bool { habit.isCompleted(on: Date()) }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? habitColor : Color.secondary.opacity(0.6))
                Image(systemName: habit.iconName)
                    .foregroundStyle(habitColor)
                    .frame(width: 18)
                Text(habit.name.isEmpty ? "Untitled" : habit.name)
                    .foregroundStyle(.primary)
                Spacer()
                let streak = habit.currentStreak()
                if streak > 0 {
                    Text("🔥\(streak)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
