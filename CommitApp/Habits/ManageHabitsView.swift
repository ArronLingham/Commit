import SwiftUI
import SwiftData
import CommitCore

/// List of all habits with add / edit / reorder / archive / delete.
struct ManageHabitsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Habit.sortOrder) private var habits: [Habit]

    @AppStorage(Theme.accentColorHexKey, store: CommitConstants.sharedDefaults)
    private var accentHex = Theme.defaultAccentHex
    private var accent: Color { Color(hex: accentHex) ?? Theme.defaultAccent }

    @State private var editing: Habit?
    @State private var creatingNew = false

    private var active: [Habit] { habits.filter { !$0.isArchived } }
    private var archived: [Habit] { habits.filter { $0.isArchived } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(active) { habit in
                        row(for: habit)
                    }
                    .onMove(perform: move)
                    .onDelete { offsets in delete(active, at: offsets) }

                    if active.isEmpty {
                        ContentUnavailableView(
                            "No habits yet",
                            systemImage: "plus.circle",
                            description: Text("Tap + to add your first habit.")
                        )
                    }
                }

                if !archived.isEmpty {
                    Section("Archived") {
                        ForEach(archived) { habit in
                            row(for: habit)
                                .swipeActions {
                                    Button("Restore") { habit.isArchived = false; save() }
                                        .tint(.green)
                                }
                        }
                        .onDelete { offsets in delete(archived, at: offsets) }
                    }
                }
            }
            .navigationTitle("Habits")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { creatingNew = true } label: { Image(systemName: "plus") }
                }
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                #endif
            }
            .sheet(item: $editing) { habit in
                HabitEditView(habit: habit)
            }
            .sheet(isPresented: $creatingNew) {
                HabitEditView(habit: nil)
            }
        }
    }

    private func row(for habit: Habit) -> some View {
        Button {
            editing = habit
        } label: {
            HStack(spacing: 12) {
                Image(systemName: habit.iconName)
                    .foregroundStyle(Color(hex: habit.colorHex) ?? accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(habit.name.isEmpty ? "Untitled" : habit.name)
                        .foregroundStyle(.primary)
                    Text(habit.schedule.shortDescription())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            if !habit.isArchived {
                Button("Archive") { habit.isArchived = true; save() }
                    .tint(.orange)
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = active
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, habit) in reordered.enumerated() {
            habit.sortOrder = index
        }
        save()
    }

    private func delete(_ list: [Habit], at offsets: IndexSet) {
        for index in offsets { context.delete(list[index]) }
        save()
    }

    private func save() {
        try? context.save()
        HabitActions.reloadWidgets()
    }
}
