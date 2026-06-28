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

    var body: some View {
        Form {
            accentSection
            reminderSection
            layoutSection
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
        } header: {
            Text("Layout")
        } footer: {
            Text("How habits that aren't due today appear on the main page.")
        }
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
