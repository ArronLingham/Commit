# Context Handoff — "Commit" habit tracker

## What we're building
A minimalist **habit tracker**, native **SwiftUI for iOS + macOS**, with:
- A **GitHub-style contribution graph** (aggregate of all habits; intensity = # completed/day), shown in-app and as a widget.
- **iCloud/CloudKit** sync across devices (zero backend).
- A **macOS menu-bar** quick-toggle.
- **Flexible per-habit schedules**: daily / specific weekdays / X-times-per-week.

## Repo / git
- GitHub: **ArronLingham/Commit**, working branch **`claude/awesome-volta-pwvmw4`**, open **draft PR #1**.
- Assistant works in a remote **Linux env with no Xcode** → it writes/pushes code; the **user builds on their Mac** and pulls fixes. Loop: assistant edits on branch & pushes → user runs `cd ~/Commit && git pull origin claude/awesome-volta-pwvmw4` (+ `xcodegen generate` if project.yml changed) → user presses ▶ → pastes any error.

## Architecture (all pushed)
- **CommitCore** (shared framework): SwiftData models `Habit`, `HabitCompletion`; `HabitSchedule.swift` (Schedule enum, isScheduled); `ContributionData.swift` (Calendar helpers, ContributionLevel, makeContributions, streaks); `Store/ModelContainer+Shared.swift` (App Group + CloudKit, with local fallback) + `CommitConstants`; `Store/HabitActions.swift` (toggle/add + widget reload); `Intents/ToggleHabitIntent.swift`; `Theme/Theme.swift` (palette, `Color(hex:)`); `Views/ContributionGraphView.swift`.
- **CommitApp** (iOS+macOS): `CommitApp.swift` (WindowGroup id "main" + macOS MenuBarExtra + Settings), RootView (iOS TabView / macOS NavigationSplitView), Today/ManageHabits/HabitEdit/Stats/MenuBar/Settings views, Assets, entitlements.
- **CommitWidget**: `ContributionWidget` (month/year) + interactive `TodayWidget` (toggles via ToggleHabitIntent), `WidgetData.swift`.
- **CommitCoreTests**: scheduling + intensity-mapping unit tests.
- **project.yml** (XcodeGen) defines 3 targets + tests. Min: **iOS 17 / macOS 14**. `Commit.xcodeproj` is git-ignored (generate with `xcodegen generate`).

## User environment
- Beginner with the command line. Mac = "Arron's MacBook Air". Repo cloned at **`~/Commit`**. XcodeGen 2.45.4 installed via Homebrew.
- **Free Apple ID only** (NOT in the paid Apple Developer Program).

## Current state
- ✅ **Builds & runs on the iOS Simulator.** Fixed compile errors along the way: `Calendar.endOfWeek` (`self.date(...)`), `Habit.init` (explicit schedule encoding), `DayContribution` public init, discard `toggleCompletion` Bool in Void closures (`_ =`), AppKit import in MenuBarView.
- For free-account macOS signing, added **macOS-only entitlements** (`CommitApp/Commit-macOS.entitlements`, `CommitWidget/CommitWidget-macOS.entitlements` — sandbox only, no iCloud/App Groups) wired via `CODE_SIGN_ENTITLEMENTS[sdk=macosx*]` in project.yml. iOS keeps full entitlements.

## ⛔ Current blocker
Running on **My Mac** → a **signing error** (exact text not yet provided). Most likely:
1. **Didn't re-run `xcodegen generate`** after pulling the project.yml change → old full entitlements still in effect → "Personal team does not support iCloud/App Groups." (Re-generate first!)
2. **"Bundle identifier not available"** for Personal Team → change bundle IDs in project.yml to something unique, regenerate.
3. No team selected on a target.

## Next steps
1. Get the **exact signing error text** (Xcode Issue navigator).
2. Confirm user ran **`xcodegen generate`** after the last pull (critical for macOS entitlements). Verify in Xcode: Commit target → Build Settings → "Code Signing Entitlements" shows `Commit-macOS.entitlements` for macOS.
3. Set **Team = Personal Team** on **both** `Commit` and `CommitWidget` targets; destination **My Mac**; Run. Expect a menu-bar checkmark icon (top-right).
4. If bundle-ID error: bump `PRODUCT_BUNDLE_IDENTIFIER`/`bundleIdPrefix` to a unique value, regenerate.
5. Later (needs paid account): real iPhone + iCloud sync; then merge PR #1 to main.

## How to resume on the Mac
```sh
cd ~/Commit
git pull origin claude/awesome-volta-pwvmw4
xcodegen generate     # only needed if project.yml changed
open Commit.xcodeproj
```
