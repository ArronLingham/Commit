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
    @State private var timesPerMonth: Int
    @State private var selectedDaysOfMonth: Set<Int>
    @State private var yearlyMonth: Int
    @State private var yearlyDay: Int
    @State private var intervalDays: Int

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
        if case .timesPerMonth(let n) = schedule {
            _timesPerMonth = State(initialValue: n)
        } else {
            _timesPerMonth = State(initialValue: 10)
        }
        if case .monthly(let days) = schedule {
            _selectedDaysOfMonth = State(initialValue: days)
        } else {
            _selectedDaysOfMonth = State(initialValue: [1])
        }
        if case .yearly(let m, let d) = schedule {
            _yearlyMonth = State(initialValue: m)
            _yearlyDay = State(initialValue: d)
        } else {
            let now = Calendar.current.dateComponents([.month, .day], from: Date())
            _yearlyMonth = State(initialValue: now.month ?? 1)
            _yearlyDay = State(initialValue: now.day ?? 1)
        }
        if case .everyNDays(let n) = schedule {
            _intervalDays = State(initialValue: max(2, n))
        } else {
            _intervalDays = State(initialValue: 2)
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
                        Text("Times per month").tag(ScheduleKind.timesPerMonth)
                        Text("Monthly").tag(ScheduleKind.monthly)
                        Text("Yearly").tag(ScheduleKind.yearly)
                        Text("Every N days").tag(ScheduleKind.everyNDays)
                    }
                    .pickerStyle(.menu)

                    if scheduleKind == .weekdays {
                        weekdayPicker
                    } else if scheduleKind == .timesPerWeek {
                        Stepper("\(timesPerWeek)× per week", value: $timesPerWeek, in: 1...7)
                    } else if scheduleKind == .timesPerMonth {
                        Stepper("\(timesPerMonth)× per month", value: $timesPerMonth, in: 1...31)
                    } else if scheduleKind == .monthly {
                        dayOfMonthPicker
                    } else if scheduleKind == .yearly {
                        yearlyPicker
                    } else if scheduleKind == .everyNDays {
                        Stepper("Every \(intervalDays) days", value: $intervalDays, in: 2...365)
                    }
                }
            }
            .formStyle(.grouped)
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
            .frame(minWidth: 440, minHeight: 560)
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

    private var dayOfMonthPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(1...31, id: \.self) { day in
                let isOn = selectedDaysOfMonth.contains(day)
                Text("\(day)")
                    .font(.caption)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(isOn ? selectedColor.opacity(0.25) : Color.secondary.opacity(0.12))
                    .foregroundStyle(isOn ? selectedColor : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isOn { selectedDaysOfMonth.remove(day) } else { selectedDaysOfMonth.insert(day) }
                    }
            }
        }
        .padding(.vertical, 4)
    }

    private var yearlyPicker: some View {
        let months = Calendar.current.monthSymbols
        return Group {
            Picker("Month", selection: $yearlyMonth) {
                ForEach(1...12, id: \.self) { m in
                    Text(months.indices.contains(m - 1) ? months[m - 1] : "\(m)").tag(m)
                }
            }
            .pickerStyle(.menu)
            Stepper("Day: \(yearlyDay)", value: $yearlyDay, in: 1...31)
        }
    }

    private func currentSchedule() -> Schedule {
        switch scheduleKind {
        case .daily: return .daily
        case .weekdays: return .weekdays(selectedWeekdays.isEmpty ? [2, 3, 4, 5, 6] : selectedWeekdays)
        case .timesPerWeek: return .timesPerWeek(timesPerWeek)
        case .timesPerMonth: return .timesPerMonth(timesPerMonth)
        case .monthly: return .monthly(selectedDaysOfMonth.isEmpty ? [1] : selectedDaysOfMonth)
        case .yearly: return .yearly(month: yearlyMonth, day: yearlyDay)
        case .everyNDays: return .everyNDays(max(2, intervalDays))
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
