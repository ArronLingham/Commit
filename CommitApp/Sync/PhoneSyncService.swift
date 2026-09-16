import Foundation
import SwiftData
import CommitCore
#if canImport(AppKit)
import AppKit
#endif

/// Bridges the Mac app to an iPhone via a shared iCloud Drive folder (chosen by the user):
/// publishes today's habits to `today.json`, and applies toggle commands the phone drops into
/// `inbox/`. No server, no account — just files that iCloud Drive syncs between the devices.
@MainActor
final class PhoneSyncService: ObservableObject {
    static let shared = PhoneSyncService()

    static let enabledKey = "phoneSyncEnabled"
    static let bookmarkKey = "phoneSyncFolderBookmark"

    /// Name of the chosen folder, shown in Settings (nil when none is set).
    @Published var folderName: String?

    private var defaults: UserDefaults { CommitConstants.sharedDefaults }
    private var accessingURL: URL?
    private var timer: Timer?
    private var lastTodayJSON: String?

    private var context: ModelContext { SharedModelContainer.shared.mainContext }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    // MARK: Lifecycle

    /// Called at app launch — starts syncing if the user has it enabled and picked a folder.
    func startIfEnabled() {
        guard isEnabled else { return }
        start()
    }

    func start() {
        stop()
        guard let url = resolveFolder() else { return }
        accessingURL = url.startAccessingSecurityScopedResource() ? url : nil
        folderName = url.lastPathComponent
        try? FileManager.default.createDirectory(at: inboxURL(in: url), withIntermediateDirectories: true)
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        accessingURL?.stopAccessingSecurityScopedResource()
        accessingURL = nil
        lastTodayJSON = nil
    }

    // MARK: Folder selection

    /// Prompt the user to pick (or create) a folder in iCloud Drive; persist a security-scoped
    /// bookmark so we can keep reaching it across launches while sandboxed.
    func chooseFolder() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Pick (or create) a folder in iCloud Drive to sync with your iPhone."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(data, forKey: Self.bookmarkKey)
            isEnabled = true
            start()
        } catch {
            folderName = nil
        }
        #endif
    }

    private func resolveFolder() -> URL? {
        guard let data = defaults.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
    }

    // MARK: Tick — publish state + drain commands

    private func inboxURL(in folder: URL) -> URL { folder.appendingPathComponent("inbox", isDirectory: true) }

    private func tick() {
        guard let folder = accessingURL else { return }
        publishToday(to: folder)
        drainInbox(in: folder)
    }

    /// Write `today.json` (only when its contents change) so the iPhone Shortcut can list today's
    /// habits with their done state.
    private func publishToday(to folder: URL) {
        let habits = (try? context.fetch(
            FetchDescriptor<Habit>(predicate: #Predicate { !$0.isArchived && !$0.isDeleted },
                                   sortBy: [SortDescriptor(\.sortOrder)])
        )) ?? []
        let today = habits
            .filter { !$0.isPaused() && $0.isDueForList() }
            .map { SyncHabit(id: $0.id.uuidString, name: $0.name.isEmpty ? "Untitled" : $0.name,
                             done: $0.isCompleted(on: AppClock.now)) }

        // A ready-made "label → id" menu so the iPhone Shortcut can Choose-from-List directly.
        var menu: [String: String] = [:]
        for habit in today {
            menu["\(habit.done ? "✓" : "○") \(habit.name)"] = habit.id
        }

        // Ready-made counts and a notification line, so the iPhone's time-of-day automation can
        // post a reminder by reading one string — no logic on the phone, and it still works from
        // the last published file while the Mac is asleep.
        let doneCount = today.filter(\.done).count
        let remaining = today.count - doneCount
        let summary: String
        if today.isEmpty {
            summary = "Nothing scheduled today."
        } else if remaining == 0 {
            summary = "All \(today.count) habits done today."
        } else if remaining == today.count {
            summary = "\(remaining) \(remaining == 1 ? "habit" : "habits") to go today."
        } else {
            summary = "\(doneCount) of \(today.count) done — \(remaining) to go."
        }

        let file = SyncTodayFile(date: Self.dayFormatter.string(from: AppClock.now),
                                 habits: today, menu: menu,
                                 done: doneCount, remaining: remaining, summary: summary,
                                 reminderTime: Self.reminderTime())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file),
              let json = String(data: data, encoding: .utf8) else { return }
        guard json != lastTodayJSON else { return }   // avoid needless iCloud churn
        try? data.write(to: folder.appendingPathComponent("today.json"), options: .atomic)
        lastTodayJSON = json
    }

    /// Apply each command file the phone dropped into `inbox/`, then delete it.
    private func drainInbox(in folder: URL) {
        let inbox = inboxURL(in: folder)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) else { return }

        for url in entries {
            // Not-yet-downloaded iCloud files show up as ".name.json.icloud" placeholders.
            if url.pathExtension == "icloud" {
                try? fm.startDownloadingUbiquitousItem(at: url)
                continue
            }
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let command = try? JSONDecoder().decode(SyncCommand.self, from: data) else { continue }
            apply(command)
            try? fm.removeItem(at: url)
        }
    }

    private func apply(_ command: SyncCommand) {
        // `ids` toggles several habits from one file; `id` is the original single-habit form and
        // still decodes, so a Shortcut built before batching keeps working.
        let ids = command.ids ?? [command.id].compactMap { $0 }
        guard !ids.isEmpty else { return }
        for raw in ids {
            guard let uuid = UUID(uuidString: raw) else { continue }
            let match = try? context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == uuid }))
            guard let habit = match?.first else { continue }
            switch command.action {
            case "toggle":
                HabitActions.toggleCompletion(for: habit, in: context)
            default:
                break
            }
        }
        // Force a fresh publish so the phone sees the new state promptly.
        lastTodayJSON = nil
    }

    /// The daily reminder time as "HH:mm", or nil when it's switched off.
    private static func reminderTime() -> String? {
        guard ReminderScheduler.isEnabled else { return nil }
        return String(format: "%02d:%02d", ReminderScheduler.hour, ReminderScheduler.minute)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Wire formats (shared with the iPhone Shortcut)

private struct SyncHabit: Codable {
    let id: String
    let name: String
    let done: Bool
}

private struct SyncTodayFile: Codable {
    let date: String
    let habits: [SyncHabit]
    /// "○ Meditate" / "✓ Read" → habit id, for the iPhone Shortcut's Choose-from-List step.
    let menu: [String: String]
    let done: Int
    let remaining: Int
    /// A finished notification line, e.g. "2 of 5 done — 3 to go." The phone shows this verbatim.
    let summary: String
    /// The Mac's daily reminder as "HH:mm", or nil when the reminder is off — lets you set the
    /// iPhone automation to the same time, and notice when they drift apart.
    let reminderTime: String?
}

private struct SyncCommand: Codable {
    /// A single habit id — the original wire format, kept so existing Shortcuts still work.
    let id: String?
    /// Several habit ids in one command, for a multi-select Shortcut.
    let ids: [String]?
    let action: String
}
