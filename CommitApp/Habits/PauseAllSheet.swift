import SwiftUI
import CommitCore

/// Pick a date to pause **every** habit until — vacation mode.
///
/// Mirrors `PauseSheet` deliberately: same `tomorrow...` floor (a window ending today would
/// cover no days), same Form-in-NavigationStack shape, same Cancel / confirm pairing.
struct PauseAllSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private static func day(offset: Int) -> Date {
        let calendar = Calendar.current
        return calendar.date(
            byAdding: .day, value: offset, to: calendar.startOfDay(for: AppClock.now)
        ) ?? AppClock.now
    }

    /// A week away is the common case for the trip this feature exists for.
    @State private var until: Date = PauseAllSheet.day(offset: 7)

    private var tomorrow: Date { Self.day(offset: 1) }

    private var nights: Int {
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: AppClock.now),
            to: calendar.startOfDay(for: until)
        ).day ?? 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Resume on", selection: $until, in: tomorrow..., displayedComponents: .date)
                } footer: {
                    Text(
                        """
                        Every habit is hidden until this day, then comes back automatically. \
                        The \(nights) day\(nights == 1 ? "" : "s") in between stay neutral — \
                        they won't count as missed or break your streaks.
                        """
                    )
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Pause All Habits")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pause All") {
                        HabitActions.pauseAll(until: until, in: context)
                        // Silence the nightly reminder for the trip; `resumeAll` re-arms it.
                        ReminderScheduler.refresh()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 260)
    }
}
