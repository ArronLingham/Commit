# Commit

A minimalist, **local-only** habit tracker for macOS with a GitHub-style
contribution graph. No accounts, no backend, no paid Apple Developer
Program — runs entirely on-device with a free Apple ID.

---

## Table of contents

- [Why it's built this way](#why-its-built-this-way)
- [Features](#features)
- [Architecture](#architecture)
  - [Project layout](#project-layout)
  - [Data model](#data-model)
  - [Schedule encoding](#schedule-encoding-the-key-trick)
  - [Mutations: `HabitActions`](#mutations-habitactions)
  - [Contribution graph & stats](#contribution-graph--stats)
  - [Streaks](#streaks)
  - [Theme](#theme)
  - [Reminders](#reminders)
  - [Sound](#sound)
  - [Shortcuts / Siri integration](#shortcuts--siri-integration)
  - [Menu bar](#menu-bar)
- [UI walkthrough](#ui-walkthrough)
- [Settings](#settings)
- [Notable bugs fixed along the way](#notable-bugs-fixed-along-the-way)
- [Building (on a Mac with Xcode)](#building-on-a-mac-with-xcode)
- [Using the app](#using-the-app)
- [Scope & possible upgrades](#scope--possible-upgrades)

---

## Why it's built this way

The app was originally going to sync across iPhone and Mac via Firebase, with
a WidgetKit widget. Both were dropped:

- **Widgets** need an **App Group** to share storage between the widget
  extension and the host app, and App Groups require a provisioning profile —
  unavailable on a free Apple ID. The **menu bar** extra was built instead, to
  give the same "glance without opening the app" value for free.
- **Cross-device sync** (Firebase, or iCloud/CloudKit) hit the same wall:
  on a free, sandboxed macOS app, anonymous auth/Keychain access failed
  silently, and provisioning is gated behind the paid Developer Program
  either way.

So the app is **macOS-only, single-device, fully local**, signed
**"Sign to Run Locally"** (ad-hoc) so it builds and runs with zero Apple
account requirements beyond having Xcode installed.

## Features

- **Contribution graph** — habits rendered as a GitHub-style "commit graph";
  each day's colour intensity reflects how many of your active habits you
  completed that day. Switchable between **Week**, **Month**, and **Year**.
- **Flexible schedules** — daily, specific weekdays, N times per week, N times
  per month, specific days of the month, a fixed yearly date, or every N days.
- **Streaks** — per-habit streak tracking that understands all schedule types
  (e.g. a Mon/Wed/Fri habit doesn't break on Tuesday).
- **Menu bar quick-toggle** — check habits off without opening the main
  window; removable via Settings.
- **Daily reminder** — an optional local notification at a time you choose.
- **Shortcuts/Siri support** — an `AppIntent` lets you toggle any habit from
  the Shortcuts app or by voice.
- **Sound feedback** — a satisfying click when you check a habit off.
- **Hover tooltips** — hovering a graph cell shows "X of Y completed" for
  that day.
- **Configurable layout** — three ways to see habits that aren't due today,
  and three ways the "next occurrence" date is worded, both chosen in
  Settings.
- **Custom accent colour** and an on-brand app icon (a dark rounded square
  with its own mini contribution grid).

## Architecture

### Project layout

```
CommitCore/      Shared framework: SwiftData models, scheduling, persistence,
                 stats/contribution-graph logic, theme, reminders, the
                 Shortcuts AppIntent.
CommitApp/       The macOS app: single-page home view, habit editor, menu
                 bar popover, settings, sound effects.
CommitCoreTests/ Pure-logic unit tests (scheduling, intensity mapping).
project.yml      XcodeGen project definition — the source of truth for the
                 Xcode project (Commit.xcodeproj is generated, not committed).
```

`CommitCore` is a framework target so the same models/logic are usable from
the main app, the menu bar, and the `AppIntent` without duplication.

### Data model

`Habit` (`CommitCore/Models/Habit.swift`) is the single SwiftData `@Model`:

| Field | Purpose |
|---|---|
| `id`, `name`, `iconName`, `colorHex` | Identity and display. |
| `scheduleRaw`, `weekdays`, `targetPerWeek` | The schedule, encoded (see below). |
| `sortOrder` | Manual ordering. |
| `isArchived` / `isDeleted` | Soft-delete flags — filtered out of every query rather than hard-deleted, so deletions are consistent everywhere a habit could be referenced. |
| `completions` | A `@Relationship` to `HabitCompletion` (one row per completed day), cascade-deleted with the habit. |

`HabitCompletion` (`CommitCore/Models/HabitCompletion.swift`) is just a `day`
date plus an `isDeleted` tombstone flag and a back-reference to its habit.

### Schedule encoding (the key trick)

`Schedule` (`CommitCore/Scheduling/HabitSchedule.swift`) is a Swift `enum`
with seven cases — `.daily`, `.weekdays(Set<Int>)`, `.timesPerWeek(Int)`,
`.timesPerMonth(Int)`, `.monthly(Set<Int>)`, `.yearly(month:day:)`,
`.everyNDays(Int)` — but SwiftData can't store an enum with associated
values directly, and adding new stored properties later means a schema
migration.

So `Habit` stores the schedule across **three primitive fields it already
had from day one** — `scheduleRaw: String` (the case name),
`weekdays: [Int]`, `targetPerWeek: Int` — and a computed `schedule` property
on `Habit` (`CommitCore/Models/Habit.swift`) encodes/decodes between the
enum and those fields. Every new schedule kind added since the first version
reused the *existing* two generic fields for something new instead of adding
a column:

- `.monthly(days)` → stores days-of-month in `weekdays`.
- `.yearly(month, day)` → stores `[month, day]` in `weekdays`.
- `.timesPerMonth(n)` / `.everyNDays(n)` → reuse `targetPerWeek` as a generic
  integer parameter.

Result: every schedule type added so far has shipped with **zero SwiftData
migrations**.

Each `Schedule` case implements:
- `isScheduled(on:)` — is the habit due on a given date.
- `shortDescription()` — e.g. "Mon, Wed, Fri", "3× / week".
- `nextDate(after:)` — the next date it's due, scanning up to 400 days ahead
  (used to show "Next: Sunday · Jun 29" for habits not due today).

### Mutations: `HabitActions`

All writes go through `CommitCore/Store/HabitActions.swift`, so the main app,
the menu bar, and the Shortcuts intent always mutate state the same way:

- `toggleCompletion(for:on:)` — checks/un-checks a habit for a day. Checking
  inserts a `HabitCompletion`; un-checking **hard-deletes** it (see
  [bugs fixed](#notable-bugs-fixed-along-the-way) for why it's not just a flag
  flip). Returns whether the habit is now completed (used to decide whether
  to play the check sound).
- `addHabit(...)` — inserts a new habit at the end of the sort order.
- `saveEdits(to:)` — stamps `updatedAt` after editing a habit's fields.
- `softDelete(_:)` — tombstones a habit and all its completions.

### Contribution graph & stats

`CommitCore/Stats/ContributionData.swift` is the math behind the graph:

- `ContributionGraphRange` — `.week`, `.month`, `.calendarYear` (full Jan–Dec),
  `.year` (trailing 52 weeks), `.trailingWeeks(n)` (used by the compact menu
  bar graph).
- `makeContributions(habits:range:)` builds a `Contributions` value: a
  week-aligned grid of `DayContribution`s, each carrying that day's
  completion `count`, a 0–4 `level` (GitHub-style intensity, via
  `ContributionLevel.level(count:max:)`), and `scheduled` — how many active
  habits were actually due that day (the "out of N" denominator shown in
  hover tooltips, via `DayContribution.summary`).
- `ContributionGraphView` (`CommitCore/Views/ContributionGraphView.swift`)
  renders the grid as coloured cells with month labels, used for the Year
  span; Week and Month spans use bespoke layouts in `HomeView` (a row and a
  calendar grid, respectively) for a more native feel at those scales.

### Streaks

`Habit.currentStreak()` (in `ContributionData.swift`) branches by schedule
type:
- **`timesPerWeek` / `timesPerMonth`** — counts consecutive weeks/months that
  hit the target, without breaking on the current (still in progress)
  period.
- **Everything else** (daily, weekdays, monthly, yearly, everyNDays) — walks
  backward day by day, only counting/breaking on days the habit was actually
  *scheduled*, and not breaking on today if today simply hasn't been done
  yet.

### Theme

`CommitCore/Theme/Theme.swift` holds the accent colour (persisted as a hex
string in `UserDefaults`, with 8 presets) and the 5-step intensity palette
used by the graph (`Theme.cellColor(level:accent:)`). A `Color(hex:)`
initializer/parser lives alongside it.

### Reminders

`CommitCore/Reminders/ReminderScheduler.swift` wraps `UserNotifications`:
a single repeating `UNCalendarNotificationTrigger` fires once a day at a
user-chosen hour/minute, entirely local (no push, no server, no paid
account needed). Permission is only requested when the user actually enables
the reminder in Settings. `refresh()` is called on every app launch and
whenever the time/enabled state changes, so it stays in sync with the stored
preference.

### Sound

`CommitApp/SoundEffects.swift` plays a system "Pop" sound on check-off via
`NSSound`, retained in a `static let` so it isn't deallocated mid-playback
(see [bugs fixed](#notable-bugs-fixed-along-the-way)).

### Shortcuts / Siri integration

`CommitCore/Intents/ToggleHabitIntent.swift` defines an `AppIntent` —
**"Toggle Habit"** — that takes a habit's UUID and flips its completion for
today via the same `HabitActions.toggleCompletion` every other surface uses.
Because `openAppWhenRun = false`, it runs silently in the background. This
is what makes the app driveable from:
- the **Shortcuts** app (search "Toggle Habit" when building a shortcut —
  no shell script needed),
- **Siri** ("Hey Siri, toggle [habit] in Commit"),
- or a Shortcuts **automation** (e.g. a daily time trigger, or tied to
  another event), without opening Commit at all.

### Menu bar

`CommitApp/MenuBar/MenuBarView.swift` is a `MenuBarExtra` popover: today's
completion count, a compact 14-week graph, a checkable row per habit due
today, and shortcuts to open the main window or quit. It's bound to
`isInserted:` on an `@AppStorage` flag so it can be hidden entirely from
Settings without restarting the app.

## UI walkthrough

The whole app is one page (`CommitApp/HomeView.swift`) — no sidebar, no tabs:

1. **Graph + span picker** — a centered contribution graph with a
   Week/Month/Year picker in the toolbar. Hovering any cell shows a caption
   ("Jun 3 — 2 of 3 completed") and a native tooltip.
2. **Today's habits** — a checkable list; tapping a row's circle toggles
   completion (and plays the sound) with a `.snappy` animation. Right-click
   for Edit/Delete.
3. **Habits not due today** — shown per the **Settings** layout choice (see
   below).
4. **Quick add** — an inline text field at the bottom adds a new daily habit
   immediately; full schedule editing happens later via the row's context
   menu → Edit (`HabitEditView`, a sheet with name/icon/colour/schedule).

`HabitRow`'s subtitle shows the streak (🔥 N) plus either "X/N this week",
"X/N this month", or the schedule's short description.

## Settings

`CommitApp/Settings/SettingsView.swift`:

- **Accent** — 8 preset colours; also previews the graph's intensity scale.
- **Reminder** — enable + pick a time for the daily notification.
- **Layout** — two independent pickers:
  - *Other habits*: how non-today habits are shown —
    **Upcoming section** (separate list under Today),
    **Today/All toggle** (segmented control swaps the whole list),
    or **Collapsible list** (a `DisclosureGroup` under Today).
  - *Next occurrence*: how a non-today habit's next date is worded —
    **Weekday**, **Date**, or **Weekday + date**.
- **Menu Bar** — show/hide the menu bar icon entirely.
- **About** — app name and version (from the bundle's `Info.plist`).

## Notable bugs fixed along the way

- **Uncheck silently did nothing**: flipping `HabitCompletion.isDeleted` in
  place didn't change `habit.completions` as an array, so SwiftData's
  `@Query` never saw a reason to refresh the view. Fixed by hard-deleting the
  completion row instead of soft-deleting it.
- **Sound didn't play**: an `NSSound` created and used inline could be
  deallocated by ARC before playback finished. Fixed by retaining it in a
  `static let`.
- **Month labels wrapped to two lines** in the year graph: fixed by
  positioning labels with a `ZStack` + explicit offset instead of fixed-width
  `HStack` slots.
- **Year graph needed horizontal scrolling**: fixed by computing cell size
  dynamically from the available content width instead of using a fixed cell
  size.
- **Dock icon stayed generic when run from Xcode**: this is expected — Xcode
  runs from a transient DerivedData path and macOS's icon cache is keyed by
  path, so it often shows the generic icon for Xcode-launched builds even
  though the icon is compiled in correctly. Confirmed by copying the built
  `Commit.app` into `/Applications` and launching it from there.

## Building (on a Mac with Xcode)

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen), so it isn't committed.

```sh
brew install xcodegen     # one-time
xcodegen generate         # creates Commit.xcodeproj from project.yml
open Commit.xcodeproj
```

Requirements: **Xcode 15+**, targeting **macOS 14+**.

### Signing (free Apple ID)

The macOS target is configured for **"Sign to Run Locally"** (ad-hoc) in
`project.yml` (`CODE_SIGN_IDENTITY[sdk=macosx*]: "-"`), so it runs with a
**free Apple ID** — no team, no provisioning profile, no contact with Apple.
Just `xcodegen generate`, select **My Mac**, and run (⌘R). On first launch of
an ad-hoc-signed app, Gatekeeper may ask you to confirm — right-click the app
→ **Open**.

### Keeping a local clone up to date

```sh
git pull
xcodegen generate
# then build/run in Xcode (⌘R)
```

## Using the app

- Run **My Mac**. The single window shows the graph, today's habits, and a
  quick-add field; a checkmark icon in the **menu bar** lets you toggle
  habits without opening the window.
- Add a habit via quick-add (defaults to daily), then right-click → Edit to
  set a different schedule, icon, or colour.
- Toggle habits on **Today** and watch the contribution graph fill in.
- Copy the built `Commit.app` into `/Applications` to use it daily — unlike
  iOS, a locally-signed **macOS** app does **not** expire after 7 days.
- **Tests:** `⌘U` runs `CommitCoreTests` (scheduling and intensity-mapping
  logic).
- **Shortcuts:** in the Shortcuts app, add the "Toggle Habit" action (search
  for it), set the habit's UUID, and run it from a shortcut, a Siri phrase,
  or an automation — no shell scripting required.

## Scope & possible upgrades

This is intentionally a **single-device, local-only macOS app** so it stays
free on a personal Apple ID. Two features were deliberately left out because
they need the **paid Apple Developer Program**:

- **Widgets** — a WidgetKit widget needs an **App Group** to read the app's
  store, and App Groups require a provisioning profile a free account can't
  provide. The menu bar covers the same always-visible glance for free.
- **Cross-device sync / iOS** — would need iCloud (CloudKit) or a backend,
  both gated by the paid program for App Group / device provisioning.

`SharedModelContainer` (`CommitCore/Store/ModelContainer+Shared.swift`) is
still structured around an App Group container, so re-enabling either of the
above after upgrading to a paid account would be straightforward rather than
a rewrite.

## Status

Local-only macOS app: contribution graph (week/month/year), menu bar,
flexible schedules (7 kinds), streaks, reminders, sound, Shortcuts support,
and a configurable layout. See `project.yml` for build targets and
`CommitCore/` for the shared model and logic.
