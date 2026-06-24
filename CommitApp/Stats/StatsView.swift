import SwiftUI
import SwiftData
import CommitCore

/// Progress screen: the full contribution graph (month or year) plus headline stats.
struct StatsView: View {
    @Query(filter: #Predicate<Habit> { !$0.isArchived }, sort: \Habit.sortOrder)
    private var habits: [Habit]

    @AppStorage(Theme.accentColorHexKey, store: CommitConstants.sharedDefaults)
    private var accentHex = Theme.defaultAccentHex
    private var accent: Color { Color(hex: accentHex) ?? Theme.defaultAccent }

    enum Span: String, CaseIterable, Identifiable {
        case month = "Month"
        case year = "Year"
        var id: String { rawValue }
    }
    @State private var span: Span = .year

    private var contributions: Contributions {
        let range: ContributionGraphRange = span == .month ? .month(Date()) : .year(Date())
        return makeContributions(habits: habits, range: range)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Span", selection: $span) {
                        ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(span == .month ? "This month" : "Past year")
                            .font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            ContributionGraphView(
                                days: contributions.days,
                                cellSize: span == .month ? 22 : 11,
                                accent: accent,
                                showMonthLabels: true
                            )
                            .padding(.vertical, 4)
                        }
                        ContributionLegend(accent: accent)
                    }

                    statsGrid
                }
                .padding()
            }
            .navigationTitle("Progress")
        }
    }

    private var statsGrid: some View {
        let totalCompletions = contributions.days.reduce(0) { $0 + $1.count }
        let activeDays = contributions.days.filter { $0.isInRange && $0.count > 0 }.count
        let bestStreak = habits.map { $0.currentStreak() }.max() ?? 0

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(title: "Active habits", value: "\(habits.count)", accent: accent)
            StatCard(title: "Best streak", value: "\(bestStreak)", accent: accent)
            StatCard(title: "Days with activity", value: "\(activeDays)", accent: accent)
            StatCard(title: "Total check-offs", value: "\(totalCompletions)", accent: accent)
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.title.weight(.semibold))
                .foregroundStyle(accent)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
