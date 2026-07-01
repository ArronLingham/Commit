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
    // Observed only so the popover re-renders when Tester Mode changes the simulated date.
    @AppStorage(AppClock.enabledKey, store: CommitConstants.sharedDefaults)
    private var testerEnabled = false
    @AppStorage(AppClock.overrideKey, store: CommitConstants.sharedDefaults)
    private var testerOverride = 0.0

    private var todaysHabits: [Habit] {
        // Hide times-per-week / times-per-month habits once this period's target is met.
        habits.filter { $0.schedule.isScheduled(on: AppClock.now) && !$0.isPeriodTargetMet() }
    }
    private var completedToday: Int {
        todaysHabits.filter { $0.isCompleted(on: AppClock.now) }.count
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
            let cols = CGFloat(max(1, Int((Double(contributions.days.count) / 7).rounded(.up))))
            let menuSpacing: CGFloat = 2
            // Popover is fixed at 320pt wide; subtract the view's own padding on both sides.
            let menuCell = max(7, ((320 - 14 * 2 - menuSpacing * (cols - 1)) / cols).rounded(.down))
            ContributionGraphView(
                days: contributions.days,
                cellSize: menuCell,
                spacing: menuSpacing,
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
                        MenuBarHabitRow(habit: habit, accent: accent, now: AppClock.now) {
                            if HabitActions.toggleCompletion(for: habit, in: context) {
                                SoundEffects.playCheck()
                            }
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
    let now: Date
    let toggle: () -> Void

    private var habitColor: Color { Color(hex: habit.colorHex) ?? accent }
    private var done: Bool { habit.isCompleted(on: now) }

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
                let streak = habit.currentStreak(asOf: now)
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
