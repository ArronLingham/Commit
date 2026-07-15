import SwiftUI
import CommitCore

/// A single habit's progress: its own contribution graph plus streak, completion-rate and
/// total stats. Opened by tapping a habit's name on the home page.
struct HabitDetailView: View {
    let habit: Habit

    @Environment(\.dismiss) private var dismiss

    @AppStorage(Theme.accentColorHexKey, store: CommitConstants.sharedDefaults)
    private var accentHex = Theme.defaultAccentHex
    private var accent: Color { Color(hex: accentHex) ?? Theme.defaultAccent }
    @AppStorage(GraphColorScheme.storageKey, store: CommitConstants.sharedDefaults)
    private var colorScheme: GraphColorScheme = .githubGreen

    private enum Span: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", year = "Year"
        var id: String { rawValue }
    }
    @State private var span: Span = .month

    private var habitColor: Color { Color(hex: habit.colorHex) ?? accent }

    private var contributions: Contributions {
        let range: ContributionGraphRange
        switch span {
        case .week:  range = .week(AppClock.now)
        case .month: range = .month(AppClock.now)
        case .year:  range = .calendarYear(AppClock.now)
        }
        return makeContributions(habits: [habit], range: range)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    Picker("Span", selection: $span) {
                        ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    graph
                        .frame(maxWidth: .infinity, alignment: .center)
                    statsGrid
                }
                .padding(20)
            }
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 560)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: habit.iconName)
                .font(.largeTitle)
                .foregroundStyle(habitColor)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name.isEmpty ? "Untitled" : habit.name)
                    .font(.title2.weight(.semibold))
                Text(habit.schedule.shortDescription())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: Graph

    @ViewBuilder
    private var graph: some View {
        switch span {
        case .week:  weekRow
        case .month: monthGrid
        case .year:  yearGrid
        }
    }

    private var weekRow: some View {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        return HStack(spacing: 10) {
            ForEach(contributions.days) { day in
                let weekdayIndex = calendar.component(.weekday, from: day.date) - 1
                VStack(spacing: 6) {
                    Text(symbols.indices.contains(weekdayIndex) ? symbols[weekdayIndex] : "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.cellColor(day: day, scheme: colorScheme, accent: accent))
                        .frame(width: 34, height: 34)
                        .help(day.summary)
                }
            }
        }
    }

    private var monthGrid: some View {
        ContributionGraphView(
            days: contributions.days,
            cellSize: 26,
            spacing: 4,
            accent: accent,
            scheme: colorScheme,
            showMonthLabels: false
        )
    }

    private var yearGrid: some View {
        let cols = max(1, Int((Double(contributions.days.count) / 7).rounded(.up)))
        let spacing: CGFloat = 2
        let usable: CGFloat = 480 - 40
        let cell = max(6, ((usable - spacing * CGFloat(cols - 1)) / CGFloat(cols)).rounded(.down))
        return ContributionGraphView(
            days: contributions.days,
            cellSize: cell,
            spacing: spacing,
            accent: accent,
            scheme: colorScheme,
            showMonthLabels: true
        )
    }

    // MARK: Stats

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(value: "🔥 \(habit.currentStreak())", label: "Current streak", accent: habitColor)
            StatTile(value: "\(habit.longestStreak())", label: "Longest streak", accent: habitColor)
            StatTile(value: "\(Int((habit.completionRate() * 100).rounded()))%", label: "Completion rate", accent: habitColor)
            StatTile(value: "\(habit.totalCompletions)", label: "Total completions", accent: habitColor)
            periodTile
        }
    }

    @ViewBuilder
    private var periodTile: some View {
        if case .timesPerWeek(let target) = habit.schedule {
            StatTile(value: "\(habit.weeklyCompletionCount())/\(target)", label: "This week", accent: habitColor)
        } else if case .timesPerMonth(let target) = habit.schedule {
            StatTile(value: "\(habit.monthlyCompletionCount())/\(target)", label: "This month", accent: habitColor)
        }
    }
}

/// A single labelled stat box.
private struct StatTile: View {
    let value: String
    let label: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2.weight(.semibold))
                .foregroundStyle(accent)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
