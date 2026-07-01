import SwiftUI
import CommitCore

/// Accent colour and about info.
struct SettingsView: View {
    @AppStorage(Theme.accentColorHexKey, store: CommitConstants.sharedDefaults)
    private var accentHex = Theme.defaultAccentHex
    private var accent: Color { Color(hex: accentHex) ?? Theme.defaultAccent }

    @AppStorage(ReminderScheduler.enabledKey, store: CommitConstants.sharedDefaults)
    private var reminderEnabled = false
    @State private var reminderTime = Date()

    @AppStorage(OtherHabitsStyle.storageKey, store: CommitConstants.sharedDefaults)
    private var otherHabitsStyle: OtherHabitsStyle = .upcoming
    @AppStorage(NextOccurrenceStyle.storageKey, store: CommitConstants.sharedDefaults)
    private var nextOccurrenceStyle: NextOccurrenceStyle = .weekdayAndDate
    @AppStorage(showMenuBarIconKey, store: CommitConstants.sharedDefaults)
    private var showMenuBarIcon = true

    @AppStorage(AppClock.enabledKey, store: CommitConstants.sharedDefaults)
    private var testerModeEnabled = false
    @State private var testerDate = AppClock.overrideDate

    var body: some View {
        Form {
            accentSection
            reminderSection
            layoutSection
            menuBarSection
            testerSection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            reminderTime = Calendar.current.date(
                bySettingHour: ReminderScheduler.hour,
                minute: ReminderScheduler.minute,
                second: 0,
                of: Date()
            ) ?? Date()
        }
    }

    // MARK: Reminder

    private var reminderSection: some View {
        Section {
            Toggle("Daily reminder", isOn: $reminderEnabled)
                .onChange(of: reminderEnabled) { _, _ in
                    ReminderScheduler.refresh()
                }
            if reminderEnabled {
                DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .onChange(of: reminderTime) { _, newValue in
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                        ReminderScheduler.hour = comps.hour ?? 22
                        ReminderScheduler.minute = comps.minute ?? 0
                        ReminderScheduler.refresh()
                    }
            }
        } header: {
            Text("Reminder")
        } footer: {
            Text("A daily notification nudging you to check off your habits.")
        }
    }

    // MARK: Layout

    private var layoutSection: some View {
        Section {
            Picker("Other habits", selection: $otherHabitsStyle) {
                ForEach(OtherHabitsStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            Picker("Next occurrence", selection: $nextOccurrenceStyle) {
                ForEach(NextOccurrenceStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
        } header: {
            Text("Layout")
        } footer: {
            Text("How habits that aren't due today appear on the main page, and how each one's next occurrence is written.")
        }
    }

    // MARK: Menu bar

    private var menuBarSection: some View {
        Section {
            Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
        } header: {
            Text("Menu Bar")
        } footer: {
            Text("Hide the checkmark from the menu bar. You can still open Commit from the Dock or Applications.")
        }
    }

    // MARK: Tester mode

    private var testerSection: some View {
        Section {
            Toggle("Tester mode", isOn: $testerModeEnabled)
                .onChange(of: testerModeEnabled) { _, on in
                    // Seed the override with the current picker value when switched on.
                    if on { AppClock.overrideDate = testerDate }
                }
            if testerModeEnabled {
                DatePicker("Simulated date", selection: $testerDate, displayedComponents: .date)
                    .onChange(of: testerDate) { _, newValue in
                        AppClock.overrideDate = newValue
                    }
                HStack {
                    Button("−1 day") { shiftTesterDate(by: -1) }
                    Spacer()
                    Button("Today") { setTesterDate(Date()) }
                    Spacer()
                    Button("+1 day") { shiftTesterDate(by: 1) }
                }
                LabeledContent("App thinks it's",
                               value: testerDate.formatted(date: .complete, time: .omitted))
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        } header: {
            Text("Tester Mode")
        } footer: {
            Text("Overrides the app's current date so you can test schedules, streaks, and weekly / monthly targets. Turn it off to return to the real date. Completions you check off are still recorded on the simulated date.")
        }
    }

    private func shiftTesterDate(by days: Int) {
        let shifted = Calendar.current.date(byAdding: .day, value: days, to: testerDate) ?? testerDate
        setTesterDate(shifted)
    }

    private func setTesterDate(_ date: Date) {
        testerDate = date
        AppClock.overrideDate = date
    }

    // MARK: Accent

    private var accentSection: some View {
        Section("Accent") {
            HStack(spacing: 12) {
                ForEach(Theme.presetAccents, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex) ?? .gray)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(.primary, lineWidth: accentHex == hex ? 2.5 : 0))
                        .onTapGesture {
                            accentHex = hex
                            Theme.setAccent(hex: hex)
                        }
                }
            }
            .padding(.vertical, 4)
            ContributionLegend(accent: accent, cellSize: 14)
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("App", value: "Commit")
            LabeledContent("Version", value: appVersion)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
