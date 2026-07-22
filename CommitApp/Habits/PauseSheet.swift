import SwiftUI
import CommitCore

/// Pick a date to pause (snooze) a habit until. The habit hides from the Today list until then.
struct PauseSheet: View {
    let habit: Habit

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var until: Date = Calendar.current.date(
        byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: AppClock.now)
    ) ?? AppClock.now

    private var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: AppClock.now)) ?? AppClock.now
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Pause until", selection: $until, in: tomorrow..., displayedComponents: .date)
                } footer: {
                    Text("\(habit.name.isEmpty ? "This habit" : habit.name) will be hidden from your list until this day, then reappear automatically.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Pause Habit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pause") {
                        HabitActions.pause(habit, until: until, in: context)
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 240)
    }
}
