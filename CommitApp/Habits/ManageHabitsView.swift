import SwiftUI
import SwiftData
import CommitCore

/// The full habit manager: list every habit, add, edit, delete, and reorder in one place.
/// Opened from the button under the graph on the home page.
struct ManageHabitsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Habit> { !$0.isArchived && !$0.isDeleted }, sort: \Habit.sortOrder)
    private var habits: [Habit]

    @AppStorage(Theme.accentColorHexKey, store: CommitConstants.sharedDefaults)
    private var accentHex = Theme.defaultAccentHex
    private var accent: Color { Color(hex: accentHex) ?? Theme.defaultAccent }

    @State private var editing: Habit?
    @State private var newHabitName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if habits.isEmpty {
                        Text("No habits yet. Add one below.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(habits) { habit in
                            habitRow(habit)
                        }
                        .onDelete(perform: delete)
                        .onMove(perform: move)
                    }
                } footer: {
                    Text("Drag to reorder. Tap a habit to edit it, or swipe to delete.")
                }

                Section("Add a habit") {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(accent)
                        TextField("Name…", text: $newHabitName)
                            .textFieldStyle(.plain)
                            .onSubmit(addHabit)
                        Button("Add", action: addHabit)
                            .disabled(newHabitName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("Edit Habits")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { habit in
                HabitEditView(habit: habit)
            }
        }
        .frame(minWidth: 420, minHeight: 480)
    }

    private func habitRow(_ habit: Habit) -> some View {
        Button {
            editing = habit
        } label: {
            HStack(spacing: 12) {
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
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            HabitActions.softDelete(habits[index], in: context)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = habits
        reordered.move(fromOffsets: source, toOffset: destination)
        HabitActions.reorder(reordered, in: context)
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
