import SwiftUI

/// The GitHub-style "commit graph": 7 rows (weekdays) × N columns (weeks).
/// Shared by the app's Progress screen and the widget, so it must stay self-contained
/// and size-adaptive.
public struct ContributionGraphView: View {
    public let days: [DayContribution]
    public var cellSize: CGFloat
    public var spacing: CGFloat
    public var accent: Color
    public var showMonthLabels: Bool

    public init(
        days: [DayContribution],
        cellSize: CGFloat = 11,
        spacing: CGFloat = 3,
        accent: Color = Theme.defaultAccent,
        showMonthLabels: Bool = true
    ) {
        self.days = days
        self.cellSize = cellSize
        self.spacing = spacing
        self.accent = accent
        self.showMonthLabels = showMonthLabels
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
                                .accessibilityLabel(Text(accessibilityLabel(for: day)))
                        }
                    }
                }
            }
        }
    }

    private func color(for day: DayContribution) -> Color {
        guard day.isInRange else { return Theme.emptyCell.opacity(0.25) }
        return Theme.cellColor(level: day.level, accent: accent)
    }

    // MARK: Month labels

    private struct MonthMarker: Identifiable {
        let column: Int
        let label: String
        var id: Int { column }
    }

    private func monthMarkers() -> [MonthMarker] {
        var result: [MonthMarker] = []
        for (idx, week) in weeks.enumerated() {
            let label = monthLabel(weekIndex: idx, week: week)
            if !label.isEmpty { result.append(MonthMarker(column: idx, label: label)) }
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

/// Compact horizontal legend ("Less ▢▢▢▢ More") matching the cell scale.
public struct ContributionLegend: View {
    public var accent: Color
    public var cellSize: CGFloat

    public init(accent: Color = Theme.defaultAccent, cellSize: CGFloat = 10) {
        self.accent = accent
        self.cellSize = cellSize
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text("Less").font(.caption2).foregroundStyle(.secondary)
            ForEach(0...4, id: \.self) { level in
                RoundedRectangle(cornerRadius: max(2, cellSize * 0.22), style: .continuous)
                    .fill(Theme.cellColor(level: level, accent: accent))
                    .frame(width: cellSize, height: cellSize)
            }
            Text("More").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
