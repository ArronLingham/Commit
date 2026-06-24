import WidgetKit
import SwiftUI
import SwiftData
import CommitCore

/// Home-screen / desktop widget showing the aggregate contribution graph.
struct ContributionWidget: Widget {
    let kind = "ContributionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ContributionProvider()) { entry in
            ContributionWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Contribution Graph")
        .description("Your habit progress, like a commit graph.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ContributionEntry: TimelineEntry {
    let date: Date
    let days: [DayContribution]
    let accent: Color
    let completedToday: Int
    let totalToday: Int
}

struct ContributionProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContributionEntry {
        WidgetData.sampleContribution(family: context.family)
    }

    func getSnapshot(in context: Context, completion: @escaping (ContributionEntry) -> Void) {
        completion(WidgetData.contributionEntry(family: context.family))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContributionEntry>) -> Void) {
        let entry = WidgetData.contributionEntry(family: context.family)
        completion(Timeline(entries: [entry], policy: .after(WidgetData.nextRefresh())))
    }
}

struct ContributionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ContributionEntry

    private var cellSize: CGFloat {
        switch family {
        case .systemLarge: return 13
        default: return 11
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if family != .systemSmall {
                HStack {
                    Text("Commit").font(.headline)
                    Spacer()
                    Text("\(entry.completedToday)/\(entry.totalToday) today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ContributionGraphView(
                days: entry.days,
                cellSize: cellSize,
                spacing: 3,
                accent: entry.accent,
                showMonthLabels: family == .systemLarge
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
