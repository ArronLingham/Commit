import SwiftUI
import CommitCore

/// Accent colour and about info.
struct SettingsView: View {
    @Environment(\.modelContext) private var context

    @AppStorage(Theme.accentColorHexKey, store: CommitConstants.sharedDefaults)
    private var accentHex = Theme.defaultAccentHex

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

    @AppStorage(GraphColorScheme.storageKey, store: CommitConstants.sharedDefaults)
    private var colorScheme: GraphColorScheme = .githubGreen
    @AppStorage(InformativePalette.storageKey, store: CommitConstants.sharedDefaults)
    private var informativePaletteRaw = InformativePalette.soft.rawValue
    private var informativePalette: InformativePalette {
        InformativePalette(rawValue: informativePaletteRaw) ?? .soft
    }

    var body: some View {
        Form {
            appearanceSection
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
                    if on {
                        // Seed the override with the current picker value and snapshot the real
                        // data so everything checked off while testing can be reverted.
                        AppClock.overrideDate = testerDate
                        HabitActions.beginTesterSession(in: context)
                    } else {
                        // Undo every completion change made during the tester session.
                        HabitActions.endTesterSession(in: context)
                    }
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
            Text("Overrides the app's current date so you can test schedules, streaks, and weekly / monthly targets. Any habits you check or uncheck while Tester Mode is on are reverted when you turn it off, so your real history is left untouched.")
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

    // MARK: Appearance

    private var appearanceSection: some View {
        Section {
            Picker("Style", selection: $colorScheme) {
                ForEach(GraphColorScheme.allCases) { scheme in
                    Text(scheme.label).tag(scheme)
                }
            }
            if colorScheme == .githubGreen {
                accentSwatches
            } else {
                paletteChoices
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text(colorScheme == .githubGreen
                 ? "GitHub style shades each day by how much you completed, in the accent colour you pick."
                 : "Green · yellow · red colours each day by how many habits you missed. Pick a palette style for the graph.")
        }
    }

    /// GitHub-style: pick the single accent hue used across the app and the green graph.
    private var accentSwatches: some View {
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
    }

    /// Informative scheme: pick a shade/style of the green·yellow·red palette.
    private var paletteChoices: some View {
        ForEach(InformativePalette.allCases) { palette in
            let selected = palette == informativePalette
            HStack(spacing: 12) {
                let colors = palette.colors
                HStack(spacing: 4) {
                    ForEach([colors.none, colors.one, colors.few, colors.many], id: \.self) { swatch in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(swatch)
                            .frame(width: 18, height: 18)
                    }
                }
                Text(palette.label)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                informativePaletteRaw = palette.rawValue
                // Keep the app's accent (checkmarks, buttons) coherent with the green graph.
                accentHex = palette.allDoneHex
                Theme.setAccent(hex: palette.allDoneHex)
            }
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
