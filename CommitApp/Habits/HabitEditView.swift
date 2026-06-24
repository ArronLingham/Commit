import SwiftUI
import SwiftData
import CommitCore

/// Add or edit a habit: name, icon, colour, and schedule.
struct HabitEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// `nil` when creating a new habit.
    let habit: Habit?

    @State private var name: String
    @State private var iconName: String
    @State private var colorHex: String
    @State private var scheduleKind: ScheduleKind
    @State private var selectedWeekdays: Set<Int>
    @State private var timesPerWeek: Int

    private static let iconChoices = [
        "checkmark.circle", "figure.run", "book", "drop", "dumbbell",
        "leaf", "moon.stars", "cup.and.saucer", "pencil", "heart",
        "bed.double", "fork.knife", "pills", "brain.head.profile", "guitars",
        "camera", "music.note", "bicycle", "flame", "sun.max"
    ]

    init(habit: Habit?) {
        self.habit = habit
        _name = State(initialValue: habit?.name ?? "")
        _iconName = State(initialValue: habit?.iconName ?? "checkmark.circle")
        _colorHex = State(initialValue: habit?.colorHex ?? Theme.defaultAccentHex)
        let schedule = habit?.schedule ?? .daily
        _scheduleKind = State(initialValue: schedule.kind)
        if case .weekdays(let days) = schedule {
            _selectedWeekdays = State(initialValue: days)
        } else {
            _selectedWeekdays = State(initialValue: [2, 3, 4, 5, 6]) // Mon–Fri default
        }
        if case .timesPerWeek(let n) = schedule {
            _timesPerWeek = State(initialValue: n)
        } else {
            _timesPerWeek = State(initialValue: 3)
        }
    }

    private var selectedColor: Color { Color(hex: colorHex) ?? Theme.defaultAccent }

    var body: some View {
        NavigationStack {
            Form {
                Section("Habit") {
                    TextField("Name", text: $name)
                    iconPicker
                    colorPicker
                }

                Section("Schedule") {
                    Picker("Repeats", selection: $scheduleKind) {
                        Text("Daily").tag(ScheduleKind.daily)
                        Text("Specific days").tag(ScheduleKind.weekdays)
                        Text("Times per week").tag(ScheduleKind.timesPerWeek)
                    }
                    .pickerStyle(.menu)

                    if scheduleKind == .weekdays {
                        weekdayPicker
                    } else if scheduleKind == .timesPerWeek {
                        Stepper("\(timesPerWeek)× per week", value: $timesPerWeek, in: 1...7)
                    }
                }
            }
            .navigationTitle(habit == nil ? "New Habit" : "Edit Habit")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .frame(minWidth: 360, minHeight: 420)
        }
    }

    private var iconPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
            ForEach(Self.iconChoices, id: \.self) { symbol in
                Image(systemName: symbol)
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(iconName == symbol ? selectedColor.opacity(0.2) : Color.clear)
                    .foregroundStyle(iconName == symbol ? selectedColor : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(iconName == symbol ? selectedColor : Color.clear, lineWidth: 1.5)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { iconName = symbol }
            }
        }
        .padding(.vertical, 4)
    }

    private var colorPicker: some View {
        HStack(spacing: 10) {
            ForEach(Theme.presetAccents, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex) ?? .gray)
                    .frame(width: 26, height: 26)
                    .overlay(
                        Circle().strokeBorder(.primary, lineWidth: colorHex == hex ? 2 : 0)
                    )
                    .onTapGesture { colorHex = hex }
            }
        }
        .padding(.vertical, 4)
    }

    private var weekdayPicker: some View {
        let symbols = Calendar.current.shortWeekdaySymbols // index 0 == Sunday
        return HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { weekday in
                let isOn = selectedWeekdays.contains(weekday)
                Text(symbols[weekday - 1])
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(isOn ? selectedColor.opacity(0.25) : Color.secondary.opacity(0.12))
                    .foregroundStyle(isOn ? selectedColor : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onTapGesture {
                        if isOn { selectedWeekdays.remove(weekday) }
                        else { selectedWeekdays.insert(weekday) }
                    }
            }
        }
    }

    private func currentSchedule() -> Schedule {
        switch scheduleKind {
        case .daily: return .daily
        case .weekdays: return .weekdays(selectedWeekdays.isEmpty ? [2, 3, 4, 5, 6] : selectedWeekdays)
        case .timesPerWeek: return .timesPerWeek(timesPerWeek)
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let habit {
            habit.name = trimmed
            habit.iconName = iconName
            habit.colorHex = colorHex
            habit.schedule = currentSchedule()
            HabitActions.saveEdits(to: habit, in: context)
        } else {
            let new = HabitActions.addHabit(
                name: trimmed,
                iconName: iconName,
                colorHex: colorHex,
                schedule: currentSchedule(),
                in: context
            )
            _ = new
        }
        dismiss()
    }
}
