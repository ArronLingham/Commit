import SwiftUI
import CommitCore

/// Step-by-step instructions for building the iPhone Shortcut that talks to the shared folder.
struct PhoneSetupView: View {
    @Environment(\.dismiss) private var dismiss

    /// The folder the user picked, so the paths below are concrete.
    let folderName: String?

    private var folder: String { folderName ?? "Commit" }

    private var steps: [(String, String)] {
        [
            ("iCloud Drive on your iPhone",
             "Settings → [your name] → iCloud → turn on iCloud Drive. In the Files app you should see the “\(folder)” folder (it may take a moment to sync from your Mac)."),
            ("New Shortcut",
             "Open the Shortcuts app → tap ＋ → name it “Commit”."),
            ("Read today’s habits",
             "Add “Get File”. Turn OFF “Show Document Picker”, set the file to iCloud Drive → \(folder)/today.json."),
            ("Parse it",
             "Add “Get Dictionary from Input” (it takes the file)."),
            ("Get the menu",
             "Add “Get Dictionary Value” → Get Value for “menu”. Then add another “Get Dictionary Value” → Get “All Keys” of that menu."),
            ("Show the list",
             "Add “Choose from List”, input = the keys. This shows your habits with ○ (not done) / ✓ (done)."),
            ("Find the picked habit’s id",
             "Add “Get Dictionary Value” → Get Value for [Chosen Item] from the menu dictionary. This is the habit’s id."),
            ("Build the command",
             "Add “Text” with exactly: {\"id\":\"[Dictionary Value]\",\"action\":\"toggle\"} — insert the id from the previous step where [Dictionary Value] is."),
            ("Send it to the Mac",
             "Add “Save File”. Turn OFF “Ask Where to Save”, set Destination to iCloud Drive → \(folder)/inbox/. Give it a unique name, e.g. combine the id with the Current Date. Save."),
            ("Use it anywhere",
             "Run the shortcut from the Shortcuts app, add it to your Home/Lock Screen, or say “Hey Siri, Commit”. Your Mac applies the toggle within a few seconds while the app is running."),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Set this up once on your iPhone. It reads today’s habits from the shared iCloud Drive folder and sends a toggle back to your Mac — no account or App Store needed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(index + 1). \(step.0)").font(.headline)
                            Text(step.1).font(.callout).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                Section {
                    Text("Keep the Mac app running (add it as a Login Item, and the menu-bar icon keeps it alive) so commands apply promptly. If the Mac is asleep, they apply the next time it’s awake.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("iPhone Setup")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 560)
    }
}
