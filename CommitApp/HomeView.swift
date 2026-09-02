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
    /// Sidebar destinations for the macOS (System Settings-style) layout.
    enum MacSection: String, CaseIterable, Identifiable {
        case today, all, paused
        var id: String { rawValue }
        var title: String {
            switch self {
            case .today:  return "Today"
            case .all:    return "All Habits"
            case .paused: return "Paused"
            }
        }
        var icon: String {
            switch self {
            case .today:  return "calendar"
            case .all:    return "checklist"
            case .paused: return "pause.circle"
            }
        }
    }
    @State private var span: Span = .month
    @State private var scope: Scope = .today
    @State private var newHabitName = ""
    @State private var editing: Habit?
    @State private var hoveredDay: DayContribution?
    /// The day the whole page is scoped to. `nil` means "follow the app's today", which is what
    /// makes the page roll over at midnight, keeps a 23:59 check-off landing on the right day,
    /// and tracks Tester Mode — none of which a stored `Date` would do.
    @State private var viewDate: Date?
    @State private var showingPauseAll = false
    @State private var isEditing = false
    @State private var draggingHabit: Habit?
    @State private var detailHabit: Habit?
    @State private var pausingHabit: Habit?
    @State private var macSection: MacSection = .today
    @AppStorage(OtherHabitsStyle.storageKey, store: CommitConstants.sharedDefaults)
    private var otherHabitsStyle: OtherHabitsStyle = .upcoming
    @AppStorage(NextOccurrenceStyle.storageKey, store: CommitConstants.sharedDefaults)
    private var nextOccurrenceStyle: NextOccurrenceStyle = .weekdayAndDate
    @AppStorage(GraphColorScheme.storageKey, store: CommitConstants.sharedDefaults)
    private var colorScheme: GraphColorScheme = .githubGreen
    // Observed only so the graph re-renders when the informative palette variant changes.
    @AppStorage(InformativePalette.storageKey, store: CommitConstants.sharedDefaults)
    private var informativePaletteRaw = InformativePalette.soft.rawValue
    // The overall window look — minimalist single page vs. macOS sidebar layout.
    @AppStorage(AppearanceStyle.storageKey, store: CommitConstants.sharedDefaults)
    private var appearanceRaw = AppearanceStyle.minimalist.rawValue
    private var appearance: AppearanceStyle { AppearanceStyle(rawValue: appearanceRaw) ?? .minimalist }
    // Observed only so the page re-renders when Tester Mode changes the simulated date.
    @AppStorage(AppClock.enabledKey, store: CommitConstants.sharedDefaults)
    private var testerEnabled = false
    @AppStorage(AppClock.overrideKey, store: CommitConstants.sharedDefaults)
    private var testerOverride = 0.0

    /// Width of the centred content column; also drives the year graph's fit-to-width sizing.
    private let contentWidth: CGFloat = 660
    private var horizontalPadding: CGFloat { 20 }

    // MARK: Viewing date

    /// The day being shown. Recomputed on every body pass, so "today" is never stale.
    private var viewingDate: Date { viewDate ?? Calendar.current.startOfDay(for: AppClock.now) }

    // Always compared against `AppClock.now` — `Calendar.isDateInToday` reads the real system
    // clock and would ignore Tester Mode.
    private var isViewingToday: Bool {
        Calendar.current.isDate(viewingDate, inSameDayAs: AppClock.now)
    }
    private var isViewingFuture: Bool {
        let calendar = Calendar.current
        return calendar.startOfDay(for: viewingDate) > calendar.startOfDay(for: AppClock.now)
    }

    /// Scope the page to `date`. Landing on the app's today stores `nil` so the page goes back to
    /// following today — that invariant is what keeps `isViewingToday` honest.
    private func setViewDate(_ date: Date) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        withAnimation(.snappy) {
            viewDate = calendar.isDate(day, inSameDayAs: AppClock.now) ? nil : day
        }
    }

    private func stepViewDate(by days: Int) {
        hoveredDay = nil   // the summary line would otherwise name a cell from another month
        let calendar = Calendar.current
        setViewDate(calendar.date(byAdding: .day, value: days, to: viewingDate) ?? viewingDate)
    }

    private func goToToday() {
        hoveredDay = nil
        withAnimation(.snappy) { viewDate = nil }
    }

    /// The habits listed for the day being viewed. `@Query`'s `sortOrder` ordering survives the
    /// filter, so a past day lists habits in exactly the same order as today.
    private var visibleHabits: [Habit] {
        habits.filter { $0.belongsOnList(for: viewingDate) }
    }

    private var upcomingHabits: [Habit] {
        habits.filter { !$0.isPaused() && !$0.schedule.isScheduled(on: AppClock.now) }
            .sorted { ($0.schedule.nextDate() ?? .distantFuture) < ($1.schedule.nextDate() ?? .distantFuture) }
    }

    /// Habits currently snoozed — shown only in the collapsed "Paused" section.
    private var pausedHabits: [Habit] {
        habits.filter { $0.isPaused() }
            .sorted { ($0.pausedUntil ?? .distantFuture) < ($1.pausedUntil ?? .distantFuture) }
    }

    private var contributions: Contributions {
        let range: ContributionGraphRange
        switch span {
        // Anchored to the viewed day, so stepping back past the 1st re-renders the previous
        // month and the selected cell stays on screen. This also gives the graph its first way
        // to show anything but the current month/week/year.
        case .week: range = .week(viewingDate)
        case .month: range = .month(viewingDate)
        case .year: range = .calendarYear(viewingDate)
        }
        // `referenceDate` deliberately stays at the real today: it gates `assess`'s
        // `day <= today` check, so passing the viewed date would paint every later day as missed.
        return makeContributions(habits: habits, range: range)
    }

    var body: some View {
        switch appearance {
        case .minimalist: minimalistBody
        case .macOS:      macBody
        }
    }

    // MARK: Minimalist layout (the original single page)

    private var minimalistBody: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    graphSection
                    Divider()
                    vacationBanner
                    habitsArea
                }
                .padding(horizontalPadding)
                .frame(maxWidth: contentWidth)
                .frame(maxWidth: .infinity)   // centre the content column
            }
            .navigationTitle("Commit")
            .toolbar { spanToolbar }
            .navigationDestination(isPresented: detailHabitBinding) {
                if let habit = detailHabit { HabitDetailView(habit: habit) }
            }
        }
        .sheet(item: $editing) { HabitEditView(habit: $0) }
        .sheet(item: $pausingHabit) { PauseSheet(habit: $0) }
        .sheet(isPresented: $showingPauseAll) { PauseAllSheet() }
        // When "today" itself moves, an off-today view can flip from past to future (silently
        // locking check-offs) or land on the new today while `viewDate` is still set. Snapping
        // back is the only unambiguous answer.
        .onChange(of: testerEnabled) { _, _ in viewDate = nil }
        .onChange(of: testerOverride) { _, _ in viewDate = nil }
    }

    // MARK: macOS layout (System Settings-style sidebar)

    private var macBody: some View {
        NavigationSplitView {
            List(selection: macSelectionBinding) {
                ForEach(MacSection.allCases) { section in
                    Label(section.title, systemImage: section.icon).tag(section)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 212, max: 260)
            .navigationTitle("Commit")
        } detail: {
            NavigationStack {
                ScrollView {
                    macDetail
                        .padding(24)
                        .frame(maxWidth: 720, alignment: .leading)
                        .frame(maxWidth: .infinity)
                }
                .navigationTitle(macSection == .today && !isViewingToday ? dayLabel : macSection.title)
                .toolbar {
                    spanToolbar
                    vacationToolbar
                    macEditToolbar
                }
                .navigationDestination(isPresented: detailHabitBinding) {
                    if let habit = detailHabit { HabitDetailView(habit: habit) }
                }
            }
        }
        .sheet(item: $editing) { HabitEditView(habit: $0) }
        .sheet(item: $pausingHabit) { PauseSheet(habit: $0) }
        .sheet(isPresented: $showingPauseAll) { PauseAllSheet() }
        // When "today" itself moves, an off-today view can flip from past to future (silently
        // locking check-offs) or land on the new today while `viewDate` is still set. Snapping
        // back is the only unambiguous answer.
        .onChange(of: testerEnabled) { _, _ in viewDate = nil }
        .onChange(of: testerOverride) { _, _ in viewDate = nil }
    }

    /// The detail pane for the macOS layout, driven by the sidebar selection. Reuses the same
    /// graph, rows, and quick-add as the minimalist page — only the surrounding chrome differs.
    @ViewBuilder
    private var macDetail: some View {
        switch macSection {
        case .today:
            VStack(alignment: .leading, spacing: 20) {
                graphSection
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .surface(appearance, cornerRadius: 16)
                vacationBanner
                daySectionView
                quickAdd
            }
        case .all:
            VStack(alignment: .leading, spacing: 12) {
                if isEditing {
                    editList
                    quickAdd
                } else {
                    allHabitsRows
                    quickAdd
                }
            }
        case .paused:
            if pausedHabits.isEmpty {
                ContentUnavailableView(
                    "Nothing paused",
                    systemImage: "pause.circle",
                    description: Text("Habits you snooze will appear here.")
                )
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(pausedHabits) { pausedRow($0) }
                }
            }
        }
    }

    /// Single-selection binding for the sidebar (List wants an optional selection).
    private var macSelectionBinding: Binding<MacSection?> {
        Binding(get: { macSection }, set: { if let value = $0 { macSection = value } })
    }

    private var detailHabitBinding: Binding<Bool> {
        Binding(get: { detailHabit != nil }, set: { if !$0 { detailHabit = nil } })
    }

    @ToolbarContentBuilder
    private var spanToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Picker("Span", selection: $span) {
                ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
        }
    }

    /// The macOS layout never renders `habitsHeader`, so without this the sidebar layout would
    /// have no way to *start* a vacation except Settings.
    @ToolbarContentBuilder
    private var vacationToolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) { vacationButton }
    }

    /// Edit toggle for the macOS "All Habits" pane (minimalist keeps its in-content pencil).
    @ToolbarContentBuilder
    private var macEditToolbar: some ToolbarContent {
        if macSection == .all {
            ToolbarItem(placement: .automatic) {
                Button {
                    // Edit mode manages every habit and has no per-day meaning, so entering it
                    // snaps back to today rather than leaving a stale date scoping the page.
                    withAnimation(.snappy) { isEditing.toggle(); if isEditing { viewDate = nil } }
                } label: {
                    Image(systemName: isEditing ? "checkmark.circle.fill" : "square.and.pencil")
                }
                .help(isEditing ? "Done editing" : "Edit habits")
            }
        }
    }

    // MARK: Graph

    private var graphSection: some View {
        VStack(spacing: 12) {
            // One insertion point serves both layouts: minimalist renders it bare above the
            // centred graph, macOS gets it as the title bar of the existing graph card.
            dateStepper
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
                        .onTapGesture { if day.isInRange { setViewDate(day.date) } }
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
            // The month title now lives in the date stepper's caption line, where it follows the
            // viewed date — keeping a second one here would desynchronise the moment you stepped
            // into another month.
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
            .onTapGesture { if day.isInRange { setViewDate(day.date) } }
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
            selectedDate: viewingDate,
            onSelectDay: { setViewDate($0.date) }
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func isSelected(_ day: DayContribution) -> Bool {
        day.isInRange && Calendar.current.isDate(viewingDate, inSameDayAs: day.date)
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

    // MARK: Date stepper

    /// `‹ Today ›` — the day being viewed, with arrows to step through days and a "Today" chip
    /// that **only exists when you're off today**. That absence/presence is the off-today signal:
    /// it costs nothing while you're on today, and when it appears it's both the indicator and
    /// the way back. Deliberately not a tint, wash, or dimmed list — those punish you for browsing.
    private var dateStepper: some View {
        HStack(spacing: 12) {
            stepButton(days: -1, symbol: "chevron.left", label: "Previous day")

            VStack(spacing: 2) {
                Text(dayLabel)
                    .font(.headline)
                    .contentTransition(.numericText())
                Text(spanLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 230)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibleDateLabel)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: stepViewDate(by: 1)
                case .decrement: stepViewDate(by: -1)
                @unknown default: break
                }
            }

            stepButton(days: 1, symbol: "chevron.right", label: "Next day")
        }
        .frame(maxWidth: .infinity)
        // An overlay rather than a sibling, so the chip appearing never shifts the date label.
        .overlay(alignment: .trailing) { todayChip }
        .animation(.snappy, value: viewingDate)
    }

    private func stepButton(days: Int, symbol: String, label: String) -> some View {
        Button { stepViewDate(by: days) } label: {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)     // a real hit target, not just the glyph
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var todayChip: some View {
        if !isViewingToday {
            Button { goToToday() } label: {
                Label("Today", systemImage: "calendar")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(accent)
            .help("Back to today")
            .accessibilityLabel("Back to today")
            .accessibilityHint("Returns the graph and habit list to today")
            .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .trailing)))
        }
    }

    /// "Today" / "Yesterday" / "Sat 23 Aug" — the year is only shown when it isn't the current
    /// one. Built with `.dateTime` so field order follows the locale.
    private var dayLabel: String {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: viewingDate)
        let today = calendar.startOfDay(for: AppClock.now)
        if day == today { return "Today" }
        if calendar.date(byAdding: .day, value: -1, to: today) == day { return "Yesterday" }
        if calendar.date(byAdding: .day, value: 1, to: today) == day { return "Tomorrow" }
        if calendar.component(.year, from: day) == calendar.component(.year, from: today) {
            return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }

    /// The graph's range, under the day label — this absorbs the standalone month title the
    /// month grid used to carry.
    private var spanLabel: String {
        let calendar = Calendar.current
        switch span {
        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: viewingDate) else { return "" }
            let last = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
            let from = interval.start.formatted(.dateTime.day().month(.abbreviated))
            let to = last.formatted(.dateTime.day().month(.abbreviated))
            return "\(from) – \(to)"
        case .month:
            return viewingDate.formatted(.dateTime.month(.wide).year())
        case .year:
            return viewingDate.formatted(.dateTime.year())
        }
    }

    /// The off-today state is conveyed visually by the *absence* of a chip, which says nothing to
    /// VoiceOver — so it has to be spoken here.
    private var accessibleDateLabel: String {
        let full = viewingDate.formatted(date: .complete, time: .omitted)
        if isViewingToday { return "Today, \(full)" }
        if isViewingFuture { return "\(full). Viewing a future day — check-offs are disabled." }
        return "\(full). Viewing a past day. Use the Today button to return."
    }

    /// Row under the graph: the Today/All scope toggle (in that layout) on the left, and the
    /// notepad button on the right — across from the scope — that toggles inline edit mode.
    private var habitsHeader: some View {
        HStack(spacing: 12) {
            if isEditing {
                Text("Edit habits")
                    .font(.headline)
            } else if otherHabitsStyle == .toggle && appearance == .minimalist && isViewingToday {
                // Hidden off-today: `Scope.today` would mean "the viewed day's habits", two
                // different axes sharing the word Today. `scope` is left untouched, so it comes
                // back exactly as it was.
                Picker("Scope", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            Spacer()

            if !isEditing { vacationButton }

            Button {
                // Edit mode manages every habit and has no per-day meaning, so entering it
                // snaps back to today rather than leaving a stale date scoping the page.
                withAnimation(.snappy) { isEditing.toggle(); if isEditing { viewDate = nil } }
            } label: {
                Image(systemName: isEditing ? "checkmark.circle.fill" : "square.and.pencil")
                    .font(.title3)
                    .foregroundStyle(isEditing ? accent : .secondary)
            }
            .buttonStyle(.plain)
            .help(isEditing ? "Done" : "Edit habits")
        }
    }

    // MARK: Pause all (vacation)

    /// Going away: pause everything at once, or come back early. Disabled under Tester Mode —
    /// `endTesterSession` only rewinds completions, so a pause-all made while testing would be
    /// permanent real data, and moving the simulated date mid-vacation corrupts the window.
    @ViewBuilder
    private var vacationButton: some View {
        if Vacation.isActive() {
            Button {
                withAnimation(.snappy) { HabitActions.resumeAll(in: context) }
                ReminderScheduler.refresh()
            } label: {
                Image(systemName: "moon.zzz.fill")
                    .font(.title3)
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            .help(Vacation.statusText() ?? "Resume all habits")
            .accessibilityLabel("Resume all habits")
        } else {
            Button {
                showingPauseAll = true
            } label: {
                Image(systemName: "moon.zzz")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(testerEnabled)
            .help(testerEnabled ? "Unavailable while Tester Mode is on" : "Pause all habits…")
            .accessibilityLabel("Pause all habits")
        }
    }

    /// A quiet strip naming the running vacation, so an empty list is never unexplained.
    @ViewBuilder
    private var vacationBanner: some View {
        if let status = Vacation.statusText() {
            HStack(spacing: 10) {
                Image(systemName: "moon.zzz.fill")
                    .foregroundStyle(accent)
                Text(status)
                    .font(.subheadline)
                Spacer(minLength: 12)
                Button("Resume All") {
                    withAnimation(.snappy) { HabitActions.resumeAll(in: context) }
                    ReminderScheduler.refresh()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .surface(appearance, cornerRadius: 10, minimalOpacity: 0.10)
        }
    }

    @ViewBuilder
    private var habitsContent: some View {
        if !isViewingToday {
            // A past or future day is one day's record: no Upcoming (whose "next" dates would
            // already be behind the viewed day) and no Paused section (whose Resume button and
            // "paused until" text are both statements about *now*). The header stays, though —
            // "Yesterday" above the list is what makes these check-offs unambiguous.
            daySectionView
        } else {
            switch otherHabitsStyle {
            case .upcoming:
                daySectionView
                if !upcomingHabits.isEmpty || !pausedHabits.isEmpty { upcomingSection }
            case .toggle:
                if scope == .today { dayRows } else { allHabitsRows }
            case .collapsible:
                daySectionView
                if !upcomingHabits.isEmpty || !pausedHabits.isEmpty {
                    DisclosureGroup("Other habits (\(upcomingHabits.count + pausedHabits.count))") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(upcomingHabits) { infoRow($0) }
                            ForEach(pausedHabits) { pausedRow($0) }
                        }
                    }
                }
            }
        }
    }

    /// A snoozed habit row: greyed out in place, showing when it resumes, with a Resume button.
    /// Never appears under Today — only in the All / Upcoming / Other lists.
    private func pausedRow(_ habit: Habit) -> some View {
        HStack(spacing: 12) {
            Button {
                detailHabit = habit
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: habit.iconName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(habit.name.isEmpty ? "Untitled" : habit.name)
                            .foregroundStyle(.primary)
                        Text(habit.pauseStatusText() ?? "Paused")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button("Resume") {
                withAnimation(.snappy) { HabitActions.resume(habit, in: context) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .opacity(0.7)
        .contextMenu { editDeleteMenu(habit) }
        .rowHover(appearance == .macOS)
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
        .surface(appearance, cornerRadius: 8)
        .contentShape(Rectangle())
    }

    private var daySectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Reads "Today" on today and "Yesterday" / "Sat 23 Aug" otherwise — the same string
            // the stepper shows, restated where the list actually begins.
            Text(dayLabel)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            dayRows
        }
    }

    @ViewBuilder
    private var dayRows: some View {
        if visibleHabits.isEmpty {
            emptyDayState
        } else {
            ForEach(visibleHabits) { habit in checkableRow(habit) }
        }
    }

    /// The empty list, explained for the day you're actually looking at. The paused branch
    /// matters most: during a vacation "everything is paused" is the normal state for a week at
    /// a time, and "Add a habit below to start your streak" would be actively wrong copy.
    @ViewBuilder
    private var emptyDayState: some View {
        let calendar = Calendar.current
        let pausedCount = habits.filter {
            calendar.startOfDay(for: $0.createdAt) <= calendar.startOfDay(for: viewingDate)
                && $0.isPausedDay(viewingDate, calendar: calendar)
        }.count
        if pausedCount > 0 {
            ContentUnavailableView(
                "Paused",
                systemImage: "pause.circle",
                description: Text(
                    pausedCount == 1
                        ? (isViewingToday ? "1 habit is snoozed." : "1 habit was snoozed on this day.")
                        : (isViewingToday ? "\(pausedCount) habits are snoozed." : "\(pausedCount) habits were snoozed on this day.")
                )
            )
        } else if isViewingToday {
            ContentUnavailableView(
                "Nothing scheduled",
                systemImage: "leaf",
                description: Text("Add a habit below to start your streak.")
            )
        } else if isViewingFuture {
            ContentUnavailableView(
                "Nothing scheduled",
                systemImage: "leaf",
                description: Text("Nothing is scheduled for this day yet.")
            )
        } else {
            ContentUnavailableView(
                "Nothing scheduled",
                systemImage: "leaf",
                description: Text("No habits were scheduled on this day.")
            )
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
                if habit.isPaused() {
                    pausedRow(habit)
                } else if habit.schedule.isScheduled(on: AppClock.now) {
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
            ForEach(pausedHabits) { pausedRow($0) }
        }
    }

    /// A checkable habit row for the day being viewed. Tapping the name opens progress; the
    /// circle toggles that day's completion, which is what makes backfilling a missed day work.
    private func checkableRow(_ habit: Habit) -> some View {
        HabitRow(
            habit: habit,
            accent: accent,
            day: viewingDate,
            now: AppClock.now,
            locked: isViewingFuture,
            openDetail: { detailHabit = habit },
            toggle: {
                guard !isViewingFuture else { return }   // belt and braces behind .disabled
                let nowDone = withAnimation(.snappy) {
                    // `on: viewingDate` is load-bearing: without it, checking off a row while
                    // browsing June 3 would silently stamp the completion on today instead.
                    HabitActions.toggleCompletion(for: habit, on: viewingDate, in: context)
                }
                if nowDone { SoundEffects.playCheck() }
            }
        )
        .contextMenu { editDeleteMenu(habit) }
        .rowHover(appearance == .macOS)
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
        .rowHover(appearance == .macOS)
    }

    @ViewBuilder
    private func editDeleteMenu(_ habit: Habit) -> some View {
        Button("Edit…") { editing = habit }
        // Pause and Resume always act from *now*, which a row on a past day can't express
        // without a relabel that raises more questions than it answers. Off-today the menu is
        // Edit / Delete only; pausing stays one click away from today's list.
        if !isViewingToday {
            EmptyView()
        } else if habit.isPaused() {
            Button("Resume") {
                withAnimation(.snappy) { HabitActions.resume(habit, in: context) }
            }
        } else {
            Menu("Pause") {
                Button("For 1 day") { pause(habit, days: 1) }
                Button("For 3 days") { pause(habit, days: 3) }
                Button("For 1 week") { pause(habit, days: 7) }
                Button("Until a date…") { pausingHabit = habit }
            }
        }
        Divider()
        Button("Delete", role: .destructive) {
            HabitActions.softDelete(habit, in: context)
        }
    }

    /// Pause a habit for `days` starting today (resumes on the day after the window).
    private func pause(_ habit: Habit, days: Int) {
        let until = Calendar.current.date(
            byAdding: .day, value: days, to: Calendar.current.startOfDay(for: AppClock.now)
        ) ?? AppClock.now
        withAnimation(.snappy) { HabitActions.pause(habit, until: until, in: context) }
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
        .surface(appearance, cornerRadius: 10, minimalOpacity: 0.10)
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
        // A new habit's `createdAt` is today, so it would fail `belongsOnList`'s createdAt guard
        // and vanish from a past day the instant it was created. Snap to today so it lands
        // somewhere the user can see it.
        goToToday()
    }
}

/// A single habit row: tapping the name/icon opens the habit's progress, while the circle on
/// the right checks it off for today (tap again to un-check).
struct HabitRow: View {
    let habit: Habit
    let accent: Color
    /// The day this row represents — drives the checkbox and the period counters.
    let day: Date
    /// The app's current date (from AppClock) — passed in so the row refreshes under Tester Mode,
    /// and so the streak badge can mean "right now" rather than "as of the day you're looking at".
    let now: Date
    /// True for a future day: the row renders normally but its toggle is disabled.
    var locked: Bool = false
    let openDetail: () -> Void
    let toggle: () -> Void

    private var habitColor: Color { Color(hex: habit.colorHex) ?? accent }
    private var isToday: Bool { Calendar.current.isDate(day, inSameDayAs: now) }
    private var done: Bool { habit.isCompleted(on: day) }

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
            .disabled(locked)
            .help(toggleHelp)
        }
        .padding(.vertical, 4)
    }

    private var toggleHelp: String {
        if locked { return "Future day — check-offs are disabled" }
        if isToday { return done ? "Mark not done" : "Mark done" }
        let label = day.formatted(.dateTime.month(.abbreviated).day())
        return done ? "Mark not done on \(label)" : "Mark done on \(label)"
    }

    private var subtitle: String {
        var parts: [String] = []
        // The streak is shown only on today. Re-anchoring it to a past day makes it visibly
        // shrink as you step back (which reads as damage), while leaving it at `now` would put
        // "🔥 12" beside a row labelled June 3 — a claim about June 3. Omitting it is the honest
        // option; the habit's own detail view still has the full picture.
        if isToday {
            let streak = habit.currentStreak(asOf: now)
            if streak > 0 { parts.append("🔥 \(streak)") }
        }
        let sameWeek = Calendar.current.isDate(day, equalTo: now, toGranularity: .weekOfYear)
        let sameMonth = Calendar.current.isDate(day, equalTo: now, toGranularity: .month)
        if case .timesPerWeek(let target) = habit.schedule {
            parts.append("\(habit.weeklyCompletionCount(asOf: day))/\(target) \(sameWeek ? "this" : "that") week")
        } else if case .timesPerMonth(let target) = habit.schedule {
            parts.append("\(habit.monthlyCompletionCount(asOf: day))/\(target) \(sameMonth ? "this" : "that") month")
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
