import SwiftUI
import CommitCore

/// Accent colour, iCloud status, and about info.
struct SettingsView: View {
    @AppStorage(Theme.accentColorHexKey, store: CommitConstants.sharedDefaults)
    private var accentHex = Theme.defaultAccentHex
    private var accent: Color { Color(hex: accentHex) ?? Theme.defaultAccent }

    var body: some View {
        Form {
            Section("Accent") {
                HStack(spacing: 12) {
                    ForEach(Theme.presetAccents, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex) ?? .gray)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle().strokeBorder(.primary, lineWidth: accentHex == hex ? 2.5 : 0)
                            )
                            .onTapGesture {
                                accentHex = hex
                                Theme.setAccent(hex: hex)
                                HabitActions.reloadWidgets()
                            }
                    }
                }
                .padding(.vertical, 4)

                ContributionLegend(accent: accent, cellSize: 14)
            }

            Section("Sync") {
                Label {
                    Text("Habits sync across your devices via iCloud when signed in.")
                } icon: {
                    Image(systemName: "icloud").foregroundStyle(accent)
                }
                .font(.subheadline)
            }

            Section("About") {
                LabeledContent("App", value: "Commit")
                LabeledContent("Version", value: appVersion)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
