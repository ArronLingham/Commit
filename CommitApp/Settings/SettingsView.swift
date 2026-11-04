import SwiftUI
import CommitCore
import UserNotifications
import AppKit

/// Everyday preferences for the app and its contribution graph.
struct SettingsView: View {
    @Environment(\.modelContext) private var context

    @AppStorage(Theme.accentColorHexKey, store: CommitConstants.sharedDefaults)
    private var accentHex = Theme.defaultAccentHex

    @AppStorage(ReminderScheduler.enabledKey, store: CommitConstants.sharedDefaults)
    private var reminderEnabled = false
    @State private var reminderTime = Date()
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined

    @AppStorage(OtherHabitsStyle.storageKey, store: CommitConstants.sharedDefaults)
    private var otherHabitsStyle: OtherHabitsStyle = .upcoming
    @AppStorage(showMenuBarIconKey, store: CommitConstants.sharedDefaults)
    private var showMenuBarIcon = true

    @AppStorage(AppClock.enabledKey, store: CommitConstants.sharedDefaults)
    private var testerModeEnabled = false
    @State private var testerDate = AppClock.overrideDate

    @AppStorage(PhoneSyncService.enabledKey, store: CommitConstants.sharedDefaults)
    private var phoneSyncEnabled = false
    @ObservedObject private var phoneSync = PhoneSyncService.shared
    @State private var showingPhoneSetup = false
    @State private var showingPauseAllSheet = false

    @AppStorage(AppearanceStyle.storageKey, store: CommitConstants.sharedDefaults)
    private var appearanceStyle: AppearanceStyle = .minimalist

    @AppStorage(GraphColorScheme.storageKey, store: CommitConstants.sharedDefaults)
    private var colorScheme: GraphColorScheme = .githubGreen
    @AppStorage(InformativeThresholds.yellowKey, store: CommitConstants.sharedDefaults)
    private var yellowStartsAt = InformativeThresholds.defaultYellow
    @AppStorage(InformativeThresholds.redKey, store: CommitConstants.sharedDefaults)
    private var redStartsAt = InformativeThresholds.defaultRed

    var body: some View {
        Form {
            interfaceSection
            appearanceSection
            vacationSection
            reminderSection
            layoutSection
            menuBarSection
            phoneSyncSection
            if testerModeEnabled { testerSection }
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .sheet(isPresented: $showingPhoneSetup) {
            PhoneSetupView(folderName: phoneSync.folderName)
        }
        .sheet(isPresented: $showingPauseAllSheet) {
            PauseAllSheet()
        }
        .onAppear {
            reminderTime = Calendar.current.date(
                bySettingHour: ReminderScheduler.hour,
                minute: ReminderScheduler.minute,
                second: 0,
                of: Date()
            ) ?? Date()
            refreshNotifStatus()
        }
        .onChange(of: testerModeEnabled) { _, on in
            if on {
                AppClock.overrideDate = testerDate
                HabitActions.beginTesterSession(in: context)
            } else {
                HabitActions.endTesterSession(in: context)
            }
        }
    }

    private func refreshNotifStatus() {
        ReminderScheduler.checkAuthorization { notifStatus = $0 }
    }

    private func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Reminder

    private var reminderSection: some View {
        Section {
            Toggle("Daily reminder", isOn: $reminderEnabled)
                .onChange(of: reminderEnabled) { _, _ in
                    ReminderScheduler.refresh()
                    refreshNotifStatus()
                }
            if reminderEnabled {
                DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .onChange(of: reminderTime) { _, newValue in
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                        ReminderScheduler.hour = comps.hour ?? 22
                        ReminderScheduler.minute = comps.minute ?? 0
                        ReminderScheduler.refresh()
                    }
                Button("Send test notification") {
                    ReminderScheduler.sendTest()
                    refreshNotifStatus()
                }
                if notifStatus == .denied {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Notifications are turned off for Commit in System Settings.",
                              systemImage: "bell.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open System Settings") { openNotificationSettings() }
                    }
                }
            }
        } header: {
            Text("Reminder")
        } footer: {
            Text("A daily notification nudging you to check off your habits. If nothing appears, use “Send test notification” to confirm delivery.")
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
            Text("How habits that aren't due today appear in Minimalist style. Liquid Glass uses its sidebar instead.")
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

    // MARK: iPhone sync

    private var phoneSyncSection: some View {
        Section {
            Toggle("Sync with iPhone (iCloud)", isOn: $phoneSyncEnabled)
                .onChange(of: phoneSyncEnabled) { _, on in
                    if on { phoneSync.start() } else { phoneSync.stop() }
                }
            if phoneSyncEnabled {
                HStack {
                    Button("Choose iCloud Drive folder…") { phoneSync.chooseFolder() }
                    Spacer()
                    if let name = phoneSync.folderName {
                        Label(name, systemImage: "folder")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }
                Button("Show iPhone setup…") { showingPhoneSetup = true }
            }
        } header: {
            Text("iPhone Sync")
        } footer: {
            Text("Check habits off from your iPhone via a Shortcut and a shared iCloud Drive folder — no account needed. Your Mac must be running to apply changes.")
        }
    }

    // MARK: Tester mode

    private var testerSection: some View {
        Section {
            Toggle("Tester mode", isOn: $testerModeEnabled)
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

    // MARK: Interface
    
    private var vacationSection: some View {
        Section {
            if let status = Vacation.statusText() {
                LabeledContent("Status", value: status)
                Button("Resume All Habits") {
                    HabitActions.resumeAll(in: SharedModelContainer.shared.mainContext)
                    ReminderScheduler.refresh()   // re-arm the nightly reminder
                }
            } else {
                Button("Pause All Habits…") {
                    showingPauseAllSheet = true
                }
                // Tester Mode only rewinds completions, so a pause-all made while testing would
                // be permanent real data — and moving the simulated date mid-vacation corrupts
                // the window `resumeAll` writes back.
                .disabled(testerModeEnabled)
            }
        } header: {
            Text("Vacation Mode")
        } footer: {
            Text(
                Vacation.isActive()
                    ? "Paused days stay neutral — they won't count as missed or break your streaks."
                    : "Pause all habits at once. Useful for taking a break or going on vacation."
            )
        }
    }

    private var interfaceSection: some View {
        Section {
            Picker("Window style", selection: $appearanceStyle) {
                ForEach(AppearanceStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Interface")
        } footer: {
            Text("\(appearanceStyle.blurb) Changes apply immediately.")
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section {
            Picker("Style", selection: $colorScheme) {
                ForEach(GraphColorScheme.allCases) { scheme in
                    Text(scheme.label).tag(scheme)
                }
            }
            accentSwatches
            if colorScheme == .informative { thresholdControls }
        } header: {
            Text("Appearance")
        } footer: {
            Text(colorScheme == .githubGreen
                 ? "GitHub style shades each day by how much you completed, in the accent colour you pick."
                 : "Choose how many missed habits turn a day yellow or red. Days with none missed are green; days with no habits due stay neutral.")
        }
    }

    /// The app accent also supplies the hue for the GitHub-style graph.
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

    private var thresholdControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Stepper("Yellow starts at \(yellowStartsAt) missed", value: $yellowStartsAt, in: 1...99)
                .onChange(of: yellowStartsAt) { _, newValue in
                    redStartsAt = max(redStartsAt, newValue + 1)
                }
            Stepper("Red starts at \(redStartsAt) missed", value: $redStartsAt, in: 2...100)
                .onChange(of: redStartsAt) { _, newValue in
                    yellowStartsAt = min(yellowStartsAt, newValue - 1)
                }
            HStack(spacing: 6) {
                thresholdLabel("Green", color: InformativeThresholds.allDoneColor,
                               range: "0–\(yellowStartsAt - 1)")
                thresholdLabel("Yellow", color: InformativeThresholds.yellowColor,
                               range: "\(yellowStartsAt)–\(redStartsAt - 1)")
                thresholdLabel("Red", color: InformativeThresholds.redColor,
                               range: "\(redStartsAt)+")
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func thresholdLabel(_ title: String, color: Color, range: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text("\(title): \(range)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: About

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: appVersion)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
