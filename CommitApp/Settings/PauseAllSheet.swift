import SwiftUI
import SwiftData
import CommitCore

/// Pick a date to pause (snooze) all habits until. They hide from the Today list until then.
struct PauseAllSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Habit> { !$0.isArchived && !$0.isDeleted })
    private var habits: [Habit]

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
                    DatePicker("Pause all until", selection: $until, in: tomorrow..., displayedComponents: .date)
                } footer: {
                    Text("All your habits will be hidden from your list until this day, then reappear automatically.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Vacation Mode")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pause All") {
                        for habit in habits {
                            HabitActions.pause(habit, until: until, in: context)
                        }
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 360, minHeight: 240)
    }
}
