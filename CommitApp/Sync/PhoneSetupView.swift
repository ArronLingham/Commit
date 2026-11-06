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
             "Add “Get Dictionary Value” → Get Value for “menu”. Add “Set Variable” and name it Habit Menu. Then add another “Get Dictionary Value” → Get “All Keys” of Habit Menu."),
            ("Choose several habits",
             "Add “Choose from List” with the keys as input. Open its options and turn ON “Select Multiple”. Choose the habits you want to mark complete; ○ means not yet done and ✓ means already done."),
            ("Handle an empty selection",
             "Add “If”: if Chosen Items does not have any value, add “Stop This Shortcut” inside the If. Place the remaining actions after End If."),
            ("Look up each selection",
             "Add “Repeat with Each” using Chosen Items. Inside the repeat, add “Get Dictionary Value”: get the value for Repeat Item from Habit Menu. End Repeat collects the habit IDs as Repeat Results."),
            ("Join the IDs",
             "Add “Combine Text” after End Repeat, using Repeat Results. Choose Custom as the separator and type a double quote, comma, double quote: \",\"."),
            ("Build one command",
             "Add a Text action containing: {\"ids\":[\"[Combined Text]\"],\"action\":\"complete\"}. Replace [Combined Text] with the Combined Text magic variable; keep the surrounding quotes and brackets."),
            ("Send it to the Mac",
             "Add “Current Date”, “Format Date” including seconds, and “Random Number”. Add “Set Name” to the command Text, using the formatted date and random number for a unique name ending in .json. Add “Save File” to iCloud Drive → \(folder)/inbox/ and turn off “Ask Where to Save”."),
            ("Use it anywhere",
             "Run the shortcut, choose multiple habits, and tap Done. Your Mac marks them complete while Commit is running; already completed habits stay complete. Changes appear after iCloud syncs."),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Set this up once on your iPhone. It reads today’s habits from your shared iCloud Drive folder and marks your selections complete on your Mac.")
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
