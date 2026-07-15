import SwiftUI
import SwiftData
import UniformTypeIdentifiers
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
    enum Scope: String, CaseIterable, Identifiable {
        case today = "Today", all = "All"
        var id: String { rawValue }
    }
    @State private var span: Span = .month
    @State private var scope: Scope = .today
    @State private var newHabitName = ""
    @State private var editing: Habit?
    @State private var hoveredDay: DayContribution?
    @State private var selectedDay: Date?
    @State private var isEditing = false
    @State private var draggingHabit: Habit?
    @State private var detailHabit: Habit?
    @AppStorage(OtherHabitsStyle.storageKey, store: CommitConstants.sharedDefaults)
    private var otherHabitsStyle: OtherHabitsStyle = .upcoming
    @AppStorage(NextOccurrenceStyle.storageKey, store: CommitConstants.sharedDefaults)
    private var nextOccurrenceStyle: NextOccurrenceStyle = .weekdayAndDate
    @AppStorage(GraphColorScheme.storageKey, store: CommitConstants.sharedDefaults)
    private var colorScheme: GraphColorScheme = .githubGreen
    // Observed only so the graph re-renders when the informative palette variant changes.
    @AppStorage(InformativePalette.storageKey, store: CommitConstants.sharedDefaults)
    private var informativePaletteRaw = InformativePalette.soft.rawValue
    // Observed only so the page re-renders when Tester Mode changes the simulated date.
    @AppStorage(AppClock.enabledKey, store: CommitConstants.sharedDefaults)
    private var testerEnabled = false
    @AppStorage(AppClock.overrideKey, store: CommitConstants.sharedDefaults)
    private var testerOverride = 0.0

    /// Width of the centred content column; also drives the year graph's fit-to-width sizing.
    private let contentWidth: CGFloat = 660
    private var horizontalPadding: CGFloat { 20 }

    private var todaysHabits: [Habit] {
        // Hide times-per-week / month habits once the target is met — but not on the day you
        // checked off the last one (see Habit.isDueForList).
        habits.filter { $0.isDueForList() }
    }

    private var upcomingHabits: [Habit] {
        habits.filter { !$0.schedule.isScheduled(on: AppClock.now) }
            .sorted { ($0.schedule.nextDate() ?? .distantFuture) < ($1.schedule.nextDate() ?? .distantFuture) }
    }

    private var contributions: Contributions {
        let range: ContributionGraphRange
        switch span {
        case .week: range = .week(AppClock.now)
        case .month: range = .month(AppClock.now)
        case .year: range = .calendarYear(AppClock.now)
        }
        return makeContributions(habits: habits, range: range)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    graphSection
                    if selectedDay != nil { dayDetail }
                    Divider()
                    habitsArea
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
            .navigationDestination(isPresented: Binding(
                get: { detailHabit != nil },
                set: { if !$0 { detailHabit = nil } }
            )) {
                if let habit = detailHabit {
                    HabitDetailView(habit: habit)
                }
            }
        }
    }

    // MARK: Graph

    private var graphSection: some View {
        VStack(spacing: 12) {
            graph
            // Updates as you hover a cell (also shown as a native tooltip via .help).
            Text(hoveredDay?.summary ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 14)
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
                    Text(symbols.indices.contains(weekdayIndex) ? symbols[weekdayIndex] : "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.cellColor(day: day, scheme: colorScheme, accent: accent))
                        .frame(width: 36, height: 36)
                        .overlay {
                            if isSelected(day) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.primary, lineWidth: 2.5)
                            }
                        }
                        .contentShape(Rectangle())
                        .help(day.summary)
                        .onHover { hovering in
                            if hovering { hoveredDay = day }
                            else if hoveredDay == day { hoveredDay = nil }
                        }
                        .onTapGesture { if day.isInRange { selectDay(day.date) } }
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
            Text(AppClock.now.formatted(.dateTime.month(.wide).year()))
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
                    monthDayCell(day, size: cell)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func monthDayCell(_ day: DayContribution, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(day.isInRange ? Theme.cellColor(day: day, scheme: colorScheme, accent: accent) : Color.clear)
            .frame(width: size, height: size)
            .overlay {
                if isSelected(day) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary, lineWidth: 2.5)
                }
            }
            .contentShape(Rectangle())
            .help(day.isInRange ? day.summary : "")
            .onHover { hovering in
                guard day.isInRange else { return }
                if hovering { hoveredDay = day }
                else if hoveredDay == day { hoveredDay = nil }
            }
            .onTapGesture { if day.isInRange { selectDay(day.date) } }
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
            scheme: colorScheme,
            showMonthLabels: true,
            onHoverDay: { hoveredDay = $0 },
            selectedDate: selectedDay,
            onSelectDay: { selectDay($0.date) }
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func isSelected(_ day: DayContribution) -> Bool {
        guard day.isInRange, let selected = selectedDay else { return false }
        return Calendar.current.isDate(selected, inSameDayAs: day.date)
    }

    /// Toggle the selected day: clicking the same cell again closes the detail card.
    private func selectDay(_ date: Date) {
        withAnimation(.snappy) {
            if let current = selectedDay, Calendar.current.isDate(current, inSameDayAs: date) {
                selectedDay = nil
            } else {
                selectedDay = date
            }
        }
    }

    // MARK: Day detail

    /// The habits scheduled on `date`, in the same order as the main list.
    private func habitsScheduled(on date: Date) -> [Habit] {
        habits.filter { $0.schedule.isScheduled(on: date) }
    }

    /// Inline card shown under the graph when a day is selected: that day's habits with a
    /// per-day completion toggle (so you can backfill a missed day) and a per-habit edit button.
    @ViewBuilder
    private var dayDetail: some View {
        if let day = selectedDay {
            let isFuture = Calendar.current.startOfDay(for: day) > Calendar.current.startOfDay(for: AppClock.now)
            let dayHabits = habitsScheduled(on: day)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    Text(day.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                        .font(.headline)
                    Spacer(minLength: 16)
                    Button {
                        withAnimation(.snappy) { selectedDay = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close")
                }

                if dayHabits.isEmpty {
                    Text("No habits scheduled this day.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dayHabits) { habit in
                        dayDetailRow(habit, on: day, locked: isFuture)
                    }
                    if isFuture {
                        Text("Future day — check-offs are disabled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)   // hug content width
            .padding(14)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// A row inside the day-detail card: completion toggle for the selected day + an Edit button.
    private func dayDetailRow(_ habit: Habit, on day: Date, locked: Bool) -> some View {
        let habitColor = Color(hex: habit.colorHex) ?? accent
        let done = habit.isCompleted(on: day)
        return HStack(spacing: 12) {
            Button {
                let nowDone = withAnimation(.snappy) {
                    HabitActions.toggleCompletion(for: habit, on: day, in: context)
                }
                if nowDone { SoundEffects.playCheck() }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(done ? habitColor : Color.secondary.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .disabled(locked)

            Image(systemName: habit.iconName)
                .foregroundStyle(habitColor)
                .frame(width: 24)
            Text(habit.name.isEmpty ? "Untitled" : habit.name)
                .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
        .contextMenu { editDeleteMenu(habit) }
    }

    // MARK: Habits

    /// Today's habits plus, depending on the user's Settings choice, the habits that aren't
    /// due today (an Upcoming section, a Today/All toggle, or a collapsible list).
    private var habitsArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            habitsHeader
            if isEditing {
                editList
                quickAdd
            } else {
                habitsContent
            }
        }
    }

    /// Row under the graph: the Today/All scope toggle (in that layout) on the left, and the
    /// notepad button on the right — across from the scope — that toggles inline edit mode.
    private var habitsHeader: some View {
        HStack(spacing: 12) {
            if isEditing {
                Text("Edit habits")
                    .font(.headline)
            } else if otherHabitsStyle == .toggle {
                Picker("Scope", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            Spacer()
            Button {
                withAnimation(.snappy) { isEditing.toggle() }
            } label: {
                Image(systemName: isEditing ? "checkmark.circle.fill" : "square.and.pencil")
                    .font(.title3)
                    .foregroundStyle(isEditing ? accent : .secondary)
            }
            .buttonStyle(.plain)
            .help(isEditing ? "Done" : "Edit habits")
        }
    }

    @ViewBuilder
    private var habitsContent: some View {
        switch otherHabitsStyle {
        case .upcoming:
            todaySectionView
            if !upcomingHabits.isEmpty { upcomingSection }
        case .toggle:
            if scope == .today { todayRows } else { allHabitsRows }
        case .collapsible:
            todaySectionView
            if !upcomingHabits.isEmpty {
                DisclosureGroup("Other habits (\(upcomingHabits.count))") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(upcomingHabits) { infoRow($0) }
                    }
                }
            }
        }
    }

    // MARK: Edit mode

    /// A flat, drag-reorderable list of every habit shown while editing.
    @ViewBuilder
    private var editList: some View {
        if habits.isEmpty {
            ContentUnavailableView(
                "No habits yet",
                systemImage: "leaf",
                description: Text("Add your first habit below.")
            )
        } else {
            VStack(spacing: 6) {
                ForEach(habits) { habit in
                    editRow(habit)
                        .opacity(draggingHabit?.id == habit.id ? 0.4 : 1)
                        .onDrag {
                            draggingHabit = habit
                            return NSItemProvider(object: habit.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [.text],
                            delegate: HabitReorderDropDelegate(
                                target: habit,
                                habits: habits,
                                dragging: $draggingHabit,
                                context: context
                            )
                        )
                }
            }
        }
    }

    /// A habit row in edit mode: drag handle, delete, name/schedule, and a pencil to edit fields.
    private func editRow(_ habit: Habit) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            Button {
                withAnimation(.snappy) { HabitActions.softDelete(habit, in: context) }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Delete habit")

            Image(systemName: habit.iconName)
                .foregroundStyle(Color(hex: habit.colorHex) ?? accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(habit.name.isEmpty ? "Untitled" : habit.name)
                    .foregroundStyle(.primary)
                Text(habit.schedule.shortDescription())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                editing = habit
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit habit")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }

    private var todaySectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            todayRows
        }
    }

    @ViewBuilder
    private var todayRows: some View {
        if todaysHabits.isEmpty {
            ContentUnavailableView(
                "Nothing scheduled",
                systemImage: "leaf",
                description: Text("Add a habit below to start your streak.")
            )
        } else {
            ForEach(todaysHabits) { habit in checkableRow(habit) }
        }
    }

    @ViewBuilder
    private var allHabitsRows: some View {
        if habits.isEmpty {
            ContentUnavailableView(
                "No habits yet",
                systemImage: "leaf",
                description: Text("Add a habit below to get started.")
            )
        } else {
            ForEach(habits) { habit in
                if habit.schedule.isScheduled(on: AppClock.now) {
                    checkableRow(habit)
                } else {
                    infoRow(habit)
                }
            }
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Upcoming")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(upcomingHabits) { infoRow($0) }
        }
    }

    /// A checkable habit row (today's habits). Tapping the name opens progress; the circle toggles.
    private func checkableRow(_ habit: Habit) -> some View {
        HabitRow(habit: habit, accent: accent, now: AppClock.now, openDetail: {
            detailHabit = habit
        }, toggle: {
            let nowDone = withAnimation(.snappy) {
                HabitActions.toggleCompletion(for: habit, in: context)
            }
            if nowDone { SoundEffects.playCheck() }
        })
        .contextMenu { editDeleteMenu(habit) }
    }

    /// A non-checkable row for habits not due today: shows the next occurrence. Tap opens progress.
    private func infoRow(_ habit: Habit) -> some View {
        Button {
            detailHabit = habit
        } label: {
            HStack(spacing: 12) {
                Image(systemName: habit.iconName)
                    .font(.title3)
                    .foregroundStyle(Color(hex: habit.colorHex) ?? accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name.isEmpty ? "Untitled" : habit.name)
                        .foregroundStyle(.primary)
                    Text(nextText(habit))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { editDeleteMenu(habit) }
    }

    @ViewBuilder
    private func editDeleteMenu(_ habit: Habit) -> some View {
        Button("Edit…") { editing = habit }
        Button("Delete", role: .destructive) {
            HabitActions.softDelete(habit, in: context)
        }
    }

    /// "Next: Sunday · Jun 29" — the habit's next scheduled day, weekday + date.
    private func nextText(_ habit: Habit) -> String {
        guard let date = habit.schedule.nextDate() else {
            return habit.schedule.shortDescription()
        }
        let weekday = date.formatted(.dateTime.weekday(.wide))
        let day = date.formatted(.dateTime.month(.abbreviated).day())
        switch nextOccurrenceStyle {
        case .weekday: return "Next: \(weekday)"
        case .date: return "Next: \(day)"
        case .weekdayAndDate: return "Next: \(weekday) · \(day)"
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

/// A single habit row: tapping the name/icon opens the habit's progress, while the circle on
/// the right checks it off for today (tap again to un-check).
struct HabitRow: View {
    let habit: Habit
    let accent: Color
    /// The app's current date (from AppClock) — passed in so the row refreshes under Tester Mode.
    let now: Date
    let openDetail: () -> Void
    let toggle: () -> Void

    private var habitColor: Color { Color(hex: habit.colorHex) ?? accent }
    private var done: Bool { habit.isCompleted(on: now) }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: openDetail) {
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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("View progress")

            Button(action: toggle) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(done ? habitColor : Color.secondary.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(done ? "Mark not done" : "Mark done")
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        var parts: [String] = []
        let streak = habit.currentStreak(asOf: now)
        if streak > 0 { parts.append("🔥 \(streak)") }
        if case .timesPerWeek(let target) = habit.schedule {
            parts.append("\(habit.weeklyCompletionCount(asOf: now))/\(target) this week")
        } else if case .timesPerMonth(let target) = habit.schedule {
            parts.append("\(habit.monthlyCompletionCount(asOf: now))/\(target) this month")
        } else {
            parts.append(habit.schedule.shortDescription())
        }
        return parts.joined(separator: " · ")
    }
}

/// Live drag-to-reorder for the edit-mode habit list: as the dragged habit hovers over a row,
/// it's moved to that row's position and the new order is persisted via `HabitActions.reorder`.
private struct HabitReorderDropDelegate: DropDelegate {
    let target: Habit
    let habits: [Habit]
    @Binding var dragging: Habit?
    let context: ModelContext

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging.id != target.id,
              let from = habits.firstIndex(where: { $0.id == dragging.id }),
              let to = habits.firstIndex(where: { $0.id == target.id })
        else { return }

        var reordered = habits
        reordered.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        HabitActions.reorder(reordered, in: context)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
