import WidgetKit
import SwiftUI
import AppIntents
import CommitCore

/// Interactive widget: today's habits with in-place toggles (via `ToggleHabitIntent`).
struct TodayWidget: Widget {
    let kind = "TodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Check off today's habits without opening the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TodayHabitItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let iconName: String
    let colorHex: String
    let done: Bool
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let habits: [TodayHabitItem]
    let accent: Color
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        WidgetData.sampleToday()
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(WidgetData.todayEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = WidgetData.todayEntry()
        completion(Timeline(entries: [entry], policy: .after(WidgetData.nextRefresh())))
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var maxRows: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 4
        default: return 8
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Today").font(.headline)
                Spacer()
                let done = entry.habits.filter { $0.done }.count
                Text("\(done)/\(entry.habits.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if entry.habits.isEmpty {
                Spacer()
                Text("Nothing scheduled")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ForEach(entry.habits.prefix(maxRows)) { item in
                    TodayWidgetRow(item: item, accent: entry.accent)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct TodayWidgetRow: View {
    let item: TodayHabitItem
    let accent: Color

    private var color: Color { Color(hex: item.colorHex) ?? accent }

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleHabitIntent(habitID: item.id)) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.done ? color : Color.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)

            Image(systemName: item.iconName)
                .foregroundStyle(color)
                .frame(width: 18)

            Text(item.name)
                .font(.subheadline)
                .lineLimit(1)
                .strikethrough(item.done, color: .secondary)
                .foregroundStyle(item.done ? .secondary : .primary)

            Spacer()
        }
    }
}
