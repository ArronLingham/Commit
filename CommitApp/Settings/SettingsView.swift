import SwiftUI
import CommitCore
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

/// Accent colour, cross-device sync (pairing code + status), and about info.
struct SettingsView: View {
    @AppStorage(Theme.accentColorHexKey, store: CommitConstants.sharedDefaults)
    private var accentHex = Theme.defaultAccentHex
    private var accent: Color { Color(hex: accentHex) ?? Theme.defaultAccent }

    @ObservedObject private var sync = SyncEngine.shared
    @State private var currentCode = SyncCode.current
    @State private var enteredCode = ""

    var body: some View {
        Form {
            accentSection
            syncSection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
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
                            HabitActions.reloadWidgets()
                        }
                }
            }
            .padding(.vertical, 4)
            ContributionLegend(accent: accent, cellSize: 14)
        }
    }

    // MARK: Sync

    private var syncSection: some View {
        Section {
            Label {
                Text(statusText)
            } icon: {
                Image(systemName: statusIcon).foregroundStyle(statusColor)
            }
            .font(.subheadline)

            if let code = currentCode {
                LabeledContent("Your sync code") {
                    Text(code).font(.system(.body, design: .monospaced))
                }
                Button("Copy code") { copyToPasteboard(code) }
                Button("Turn off sync", role: .destructive) {
                    SyncCode.set(nil)
                    SyncEngine.shared.stop()
                    currentCode = nil
                }
            } else {
                Button("Create a sync code") {
                    let code = SyncCode.generate()
                    SyncCode.set(code)
                    currentCode = code
                    SyncEngine.shared.restart()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("…or pair with another device").font(.caption).foregroundStyle(.secondary)
                    TextField("Enter code from your other device", text: $enteredCode)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.characters)
                        #endif
                    Button("Pair") {
                        let code = SyncCode.normalize(enteredCode)
                        guard !code.isEmpty else { return }
                        SyncCode.set(code)
                        currentCode = code
                        enteredCode = ""
                        SyncEngine.shared.restart()
                    }
                    .disabled(enteredCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if case .unavailable = sync.status {
                Text("Sync needs Firebase set up first — see the README (add GoogleService-Info.plist and the Firebase package).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Sync")
        } footer: {
            Text("Create a code on one device, then enter it on the other to sync your habits between them.")
        }
    }

    private var statusText: String {
        switch sync.status {
        case .off: return "Sync is off"
        case .unavailable: return "Sync unavailable"
        case .syncing: return "Syncing…"
        case .synced: return "Synced"
        case .error(let message): return "Error: \(message)"
        }
    }

    private var statusIcon: String {
        switch sync.status {
        case .off: return "icloud.slash"
        case .unavailable: return "exclamationmark.icloud"
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .synced: return "checkmark.icloud"
        case .error: return "xmark.icloud"
        }
    }

    private var statusColor: Color {
        switch sync.status {
        case .synced: return .green
        case .error, .unavailable: return .orange
        default: return accent
        }
    }

    private func copyToPasteboard(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
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
