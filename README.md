# Commit

A minimalist habit tracker for **iPhone and Mac**, with a GitHub-style
contribution graph and a macOS menu-bar quick-toggle.

- **Contribution graph** — your habits rendered as a "commit graph": each day's
  colour intensity is how many habits you completed that day, over the month or year.
- **iPhone + Mac** — one native SwiftUI codebase, synced across your devices with
  iCloud (CloudKit). No server to run.
- **Menu bar** — check habits off from the macOS menu bar without opening the app.
- **Home-screen / desktop widgets** — the contribution graph, plus an interactive
  widget to toggle today's habits in place.
- **Flexible schedules** — daily, specific weekdays, or "X times per week".

## Project layout

```
CommitCore/      Shared framework: SwiftData models, scheduling, persistence,
                 theme, the contribution-graph view, and the toggle AppIntent.
CommitApp/       iOS + macOS app: Today, Progress, Habits, Settings, menu bar.
CommitWidget/    WidgetKit extension: contribution graph + interactive today widget.
CommitCoreTests/ Pure-logic unit tests (scheduling + intensity mapping).
project.yml      XcodeGen project definition — the source of truth for the Xcode project.
```

The SwiftData `@Model` types, scheduling logic, and the contribution-graph view live
in **CommitCore** so the app and the widget share one implementation.

## Building (on a Mac with Xcode)

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonyz/XcodeGen), so it isn't committed.

```sh
brew install xcodegen     # one-time
xcodegen generate         # creates Commit.xcodeproj from project.yml
open Commit.xcodeproj
```

Requirements: **Xcode 15+**, targeting **iOS 17+ / macOS 14+** (needed for SwiftData,
`MenuBarExtra`, and interactive widgets).

### Signing & capabilities

In Xcode, select each target and set your **Team** under *Signing & Capabilities*
(or set `DEVELOPMENT_TEAM` in `project.yml`). Then confirm:

| Target          | Capabilities                                        |
| --------------- | --------------------------------------------------- |
| `Commit`        | App Groups (`group.com.arronlingham.commit`), iCloud → CloudKit (`iCloud.com.arronlingham.commit`) |
| `CommitWidget`  | App Groups (same group)                             |

The App Group lets the widget read the same store; iCloud/CloudKit syncs it across
your devices. If you change the bundle ID prefix, update the App Group / container
IDs in `project.yml`, the `.entitlements` files, and `CommitConstants` in
`CommitCore/Store/ModelContainer+Shared.swift` to match.

### Accounts

- **CloudKit sync + App Groups across iOS & macOS** require a paid **Apple Developer
  Program** membership.
- **Running on a physical iPhone** needs at least a free Apple ID.
- The Mac app + menu bar run on your own Mac without a paid account.

If you don't have a paid account yet, the app still builds and runs **local-only** —
`SharedModelContainer.make` falls back to a local store when CloudKit / the App Group
isn't available. iCloud is additive and needs no UI changes to enable later.

## Running & testing

- **iOS:** run on a simulator or device. Add a few habits with different schedules,
  toggle them on **Today**, watch the contribution graph fill in, then add the
  home-screen widgets.
- **macOS:** run "My Mac". A checkmark icon appears in the menu bar — toggle habits
  there and the graph/widget update.
- **Tests:** `⌘U` runs `CommitCoreTests` (scheduling + intensity mapping — the main
  regression surface).

## Status

Initial implementation. See `project.yml` for targets and
`CommitCore/` for the shared model + logic.
