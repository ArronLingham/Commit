import SwiftUI
import SwiftData
import CommitCore

/// The app's single page: a centered GitHub-style contribution graph with a Week / Month /
/// Year switcher (top-right), today's checkable habits, and an inline quick-add field.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Habit> { !$0.isArchived && !$0.isDeleted }, sort: \Habit.sortOrder)
    private var habits: [Habit]

    @AppStorage(Theme.accentColorHexKey, store: CommitConstants.sharedDefaults)
    private var accentHex = Theme.defaultAccentHex
    private var accent: Color { Color(hex: accentHex) ?? Theme.defaultAccent }

    enum Span: String, CaseIterable, Identifiable {
        case week = "Week", month = "Month", year = "Year"
        var id: String { rawValue }
    }
    @State private var span: Span = .month
    @State private var newHabitName = ""
    @State private var editing: Habit?

    /// Width of the centred content column; also drives the year graph's fit-to-width sizing.
    private let contentWidth: CGFloat = 660
    private var horizontalPadding: CGFloat { 20 }

    private var todaysHabits: [Habit] {
        habits.filter { $0.schedule.isScheduled(on: Date()) }
    }

    private var contributions: Contributions {
        let range: ContributionGraphRange
        switch span {
        case .week: range = .week(Date())
        case .month: range = .month(Date())
        case .year: range = .year(Date())
        }
        return makeContributions(habits: habits, range: range)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    graphSection
                    Divider()
                    todaySection
                    quickAdd
                }
                .padding(horizontalPadding)
                .frame(maxWidth: contentWidth)
                .frame(maxWidth: .infinity)   // centre the content column
            }
            .navigationTitle("Commit")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Span", selection: $span) {
                        ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
            }
            .sheet(item: $editing) { habit in
                HabitEditView(habit: habit)
            }
        }
    }

    // MARK: Graph

    private var graphSection: some View {
        VStack(spacing: 12) {
            graph
            ContributionLegend(accent: accent)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var graph: some View {
        switch span {
        case .week:  weekRow
        case .month: monthCalendar
        case .year:  yearGraph
        }
    }

    /// Week: the 7 days of the current week as a centred row with weekday initials.
    private var weekRow: some View {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols // index 0 == Sunday
        return HStack(spacing: 10) {
            ForEach(contributions.days) { day in
                let weekdayIndex = calendar.component(.weekday, from: day.date) - 1
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(day.isInRange
                              ? Theme.cellColor(level: day.level, accent: accent)
                              : Theme.emptyCell.opacity(0.25))
                        .frame(width: 36, height: 36)
                    Text(symbols.indices.contains(weekdayIndex) ? symbols[weekdayIndex] : "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Month: a standard calendar grid (weeks as rows, weekday columns) with the full month
    /// name on one line, weekday headers, and a day number in each in-range cell.
    private var monthCalendar: some View {
        let calendar = Calendar.current
        let cell: CGFloat = 40
        let spacing: CGFloat = 8
        let first = calendar.firstWeekday                 // 1 == Sunday
        let shortSymbols = calendar.veryShortWeekdaySymbols
        let orderedSymbols = (0..<7).map { shortSymbols[(first - 1 + $0) % 7] }
        let columns = Array(repeating: GridItem(.fixed(cell), spacing: spacing), count: 7)

        return VStack(spacing: 10) {
            Text(Date().formatted(.dateTime.month(.wide).year()))
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: spacing) {
                ForEach(orderedSymbols.indices, id: \.self) { i in
                    Text(orderedSymbols[i])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: cell)
                }
            }

            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(contributions.days) { day in
                    monthDayCell(day, size: cell, calendar: calendar)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func monthDayCell(_ day: DayContribution, size: CGFloat, calendar: Calendar) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(day.isInRange ? Theme.cellColor(level: day.level, accent: accent) : Color.clear)
            .frame(width: size, height: size)
            .overlay {
                if day.isInRange {
                    Text("\(calendar.component(.day, from: day.date))")
                        .font(.caption2)
                        .foregroundStyle(day.level >= 3 ? Color.white : Color.secondary)
                }
            }
    }

    /// Year: the full ~52-week graph sized to fit the content width — no horizontal scroll.
    private var yearGraph: some View {
        let cols = max(1, Int((Double(contributions.days.count) / 7).rounded(.up)))
        let spacing: CGFloat = 2
        let usable = contentWidth - horizontalPadding * 2
        let cell = max(7, ((usable - spacing * CGFloat(cols - 1)) / CGFloat(cols)).rounded(.down))
        return ContributionGraphView(
            days: contributions.days,
            cellSize: cell,
            spacing: spacing,
            accent: accent,
            showMonthLabels: true
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: Today

    @ViewBuilder
    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            if todaysHabits.isEmpty {
                ContentUnavailableView(
                    "Nothing scheduled",
                    systemImage: "leaf",
                    description: Text("Add a habit below to start your streak.")
                )
            } else {
                ForEach(todaysHabits) { habit in
                    HabitRow(habit: habit, accent: accent) {
                        withAnimation(.snappy) {
                            HabitActions.complete(habit, in: context)
                        }
                    }
                    .contextMenu {
                        Button("Edit…") { editing = habit }
                        Button("Delete", role: .destructive) {
                            HabitActions.softDelete(habit, in: context)
                        }
                    }
                }
            }
        }
    }

    // MARK: Quick add

    private var quickAdd: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").foregroundStyle(accent)
            TextField("Add a habit…", text: $newHabitName)
                .textFieldStyle(.plain)
                .onSubmit(addHabit)
            Button("Add", action: addHabit)
                .disabled(newHabitName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func addHabit() {
        let trimmed = newHabitName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        _ = HabitActions.addHabit(
            name: trimmed,
            iconName: "checkmark.circle",
            colorHex: accentHex,
            schedule: .daily,
            in: context
        )
        newHabitName = ""
    }
}

/// A single habit row with an inline complete toggle. Tapping **completes** the habit;
/// completions can't be undone here (`HabitActions.complete` is idempotent).
struct HabitRow: View {
    let habit: Habit
    let accent: Color
    let complete: () -> Void

    private var habitColor: Color { Color(hex: habit.colorHex) ?? accent }
    private var done: Bool { habit.isCompleted(on: Date()) }

    var body: some View {
        Button(action: complete) {
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
            .padding(.vertical, 4)
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
