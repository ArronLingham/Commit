import SwiftUI
import SwiftData
import CommitCore

/// Today's habits + a compact recent contribution graph at the top.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: \Habit.sortOrder)
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
        NavigationStack {
            List {
                Section {
                    header
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }

                Section("Today") {
                    if todaysHabits.isEmpty {
                        ContentUnavailableView(
                            "Nothing scheduled",
                            systemImage: "leaf",
                            description: Text("Add a habit to start your streak.")
                        )
                    } else {
                        ForEach(todaysHabits) { habit in
                            HabitRow(habit: habit, accent: accent) {
                                withAnimation(.snappy) {
                                    _ = HabitActions.toggleCompletion(for: habit, in: context)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Commit")
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
        }
    }

    private var header: some View {
        let contributions = makeContributions(habits: habits, range: .trailingWeeks(18))
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(completedToday) of \(todaysHabits.count)")
                        .font(.title2.weight(.semibold))
                    Text("completed today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                ContributionGraphView(
                    days: contributions.days,
                    cellSize: 11,
                    accent: accent,
                    showMonthLabels: false
                )
            }
            ContributionLegend(accent: accent)
        }
    }
}

/// A single habit row with an inline complete/incomplete toggle.
struct HabitRow: View {
    let habit: Habit
    let accent: Color
    let toggle: () -> Void

    private var habitColor: Color { Color(hex: habit.colorHex) ?? accent }
    private var done: Bool { habit.isCompleted(on: Date()) }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: habit.iconName)
                    .font(.title3)
                    .foregroundStyle(habitColor)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name.isEmpty ? "Untitled" : habit.name)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? habitColor : Color.secondary.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        var parts: [String] = []
        let streak = habit.currentStreak()
        if streak > 0 { parts.append("🔥 \(streak)") }
        if case .timesPerWeek(let target) = habit.schedule {
            parts.append("\(habit.weeklyCompletionCount())/\(target) this week")
        } else {
            parts.append(habit.schedule.shortDescription())
        }
        return parts.joined(separator: " · ")
    }
}
