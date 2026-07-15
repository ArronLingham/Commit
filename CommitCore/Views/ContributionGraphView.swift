import SwiftUI

/// The GitHub-style "commit graph": 7 rows (weekdays) × N columns (weeks).
/// Shared by the app's Progress screen and the widget, so it must stay self-contained
/// and size-adaptive.
public struct ContributionGraphView: View {
    public let days: [DayContribution]
    public var cellSize: CGFloat
    public var spacing: CGFloat
    public var accent: Color
    public var scheme: GraphColorScheme
    public var showMonthLabels: Bool
    /// When true, the month label for the current calendar month is omitted (used by the
    /// year view, whose trailing/leading partial month would otherwise crowd the edge).
    public var excludeCurrentMonthLabel: Bool
    /// Optional hover callback: the day under the pointer, or nil when the pointer leaves.
    public var onHoverDay: ((DayContribution?) -> Void)?
    /// The currently selected day — drawn with a highlight ring.
    public var selectedDate: Date?
    /// Optional tap callback: the day the user clicked.
    public var onSelectDay: ((DayContribution) -> Void)?
    /// When true, the informative scheme colours a day green (done) or red (missed) rather than
    /// by miss-count buckets — used for a single habit's own graph.
    public var singleHabit: Bool

    public init(
        days: [DayContribution],
        cellSize: CGFloat = 11,
        spacing: CGFloat = 3,
        accent: Color = Theme.defaultAccent,
        scheme: GraphColorScheme = .githubGreen,
        showMonthLabels: Bool = true,
        excludeCurrentMonthLabel: Bool = false,
        onHoverDay: ((DayContribution?) -> Void)? = nil,
        selectedDate: Date? = nil,
        onSelectDay: ((DayContribution) -> Void)? = nil,
        singleHabit: Bool = false
    ) {
        self.days = days
        self.cellSize = cellSize
        self.spacing = spacing
        self.accent = accent
        self.scheme = scheme
        self.showMonthLabels = showMonthLabels
        self.excludeCurrentMonthLabel = excludeCurrentMonthLabel
        self.onHoverDay = onHoverDay
        self.selectedDate = selectedDate
        self.onSelectDay = onSelectDay
        self.singleHabit = singleHabit
    }

    /// Days grouped into week columns (each column is 7 days, top = first weekday).
    private var weeks: [[DayContribution]] {
        stride(from: 0, to: days.count, by: 7).map { start in
            Array(days[start ..< min(start + 7, days.count)])
        }
    }

    private var cornerRadius: CGFloat { max(2, cellSize * 0.22) }

    /// Total width of the week-column grid, so the month-label row matches the cells and the
    /// view keeps an intrinsic width its container can centre.
    private var gridWidth: CGFloat {
        let n = CGFloat(weeks.count)
        return n * cellSize + max(0, n - 1) * spacing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: spacing * 1.5) {
            if showMonthLabels {
                monthLabels
            }
            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: spacing) {
                        ForEach(week) { day in
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(color(for: day))
                                .frame(width: cellSize, height: cellSize)
                                .overlay {
                                    if isSelected(day) {
                                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                            .strokeBorder(Color.primary, lineWidth: max(1, cellSize * 0.14))
                                    }
                                }
                                .contentShape(Rectangle())
                                .accessibilityLabel(Text(accessibilityLabel(for: day)))
                                .help(day.summary)
                                .onHover { onHoverDay?($0 ? day : nil) }
                                .onTapGesture { if day.isInRange { onSelectDay?(day) } }
                        }
                    }
                }
            }
        }
    }

    private func color(for day: DayContribution) -> Color {
        Theme.cellColor(day: day, scheme: scheme, accent: accent, singleHabit: singleHabit)
    }

    private func isSelected(_ day: DayContribution) -> Bool {
        guard day.isInRange, let selected = selectedDate else { return false }
        return Calendar.current.isDate(selected, inSameDayAs: day.date)
    }

    // MARK: Month labels

    private struct MonthMarker: Identifiable {
        let column: Int
        let label: String
        var id: Int { column }
    }

    private func monthMarkers() -> [MonthMarker] {
        let calendar = Calendar.current
        let currentMonthSymbol = calendar.shortMonthSymbols[calendar.component(.month, from: AppClock.now) - 1]
        var result: [MonthMarker] = []
        for (idx, week) in weeks.enumerated() {
            let label = monthLabel(weekIndex: idx, week: week)
            guard !label.isEmpty else { continue }
            if excludeCurrentMonthLabel && label == currentMonthSymbol { continue }
            result.append(MonthMarker(column: idx, label: label))
        }
        return result
    }

    /// Month abbreviations positioned over the week column where each month begins. Drawn in
    /// a ZStack with horizontal offsets so each label stays on **one line** and can overflow
    /// into the following (empty) columns instead of wrapping.
    private var monthLabels: some View {
        let step = cellSize + spacing
        return ZStack(alignment: .topLeading) {
            ForEach(monthMarkers()) { marker in
                Text(marker.label)
                    .font(.system(size: max(7, cellSize * 0.85)))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .offset(x: CGFloat(marker.column) * step)
            }
        }
        .frame(width: gridWidth, height: max(9, cellSize * 0.9), alignment: .topLeading)
    }

    /// Show a month abbreviation on the first week column that contains that month's start.
    private func monthLabel(weekIndex: Int, week: [DayContribution]) -> String {
        let calendar = Calendar.current
        guard let firstInRange = week.first(where: { $0.isInRange }) ?? week.first else { return "" }
        let month = calendar.component(.month, from: firstInRange.date)

        let previousMonth: Int? = {
            guard weekIndex > 0 else { return nil }
            let prev = weeks[weekIndex - 1]
            guard let prevDay = prev.first(where: { $0.isInRange }) ?? prev.first else { return nil }
            return calendar.component(.month, from: prevDay.date)
        }()

        guard month != previousMonth else { return "" }
        let symbols = calendar.shortMonthSymbols
        return symbols.indices.contains(month - 1) ? symbols[month - 1] : ""
    }

    private func accessibilityLabel(for day: DayContribution) -> String {
        let date = day.date.formatted(date: .abbreviated, time: .omitted)
        return "\(date): \(day.count) completed"
    }
}
