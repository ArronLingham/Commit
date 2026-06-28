# Commit

A minimalist habit tracker for **macOS**, with a GitHub-style contribution graph
and a menu-bar quick-toggle. Fully **local** and **free** — no accounts, no
external services, runs on a free Apple ID.

- **Contribution graph** — your habits rendered as a "commit graph": each day's
  colour intensity is how many habits you completed that day, over the month or year.
- **Menu bar** — check habits off from the macOS menu bar without opening the app.
- **Widget** — the contribution graph plus an interactive widget to toggle today's
  habits (see the note on widgets + free Apple IDs below).
- **Flexible schedules** — daily, specific weekdays, or "X times per week".

## Project layout

```
CommitCore/      Shared framework: SwiftData models, scheduling, persistence,
                 theme, contribution-graph view, toggle AppIntent.
CommitApp/       macOS app: Today, Progress, Habits, Settings, menu bar.
CommitWidget/    WidgetKit extension: contribution graph + interactive today widget.
CommitCoreTests/ Pure-logic unit tests (scheduling, intensity mapping).
project.yml      XcodeGen project definition — the source of truth for the Xcode project.
```

The SwiftData `@Model` types, scheduling logic, and the contribution-graph view live in
**CommitCore** so the app and the widget share one implementation.

## Building (on a Mac with Xcode)

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonyz/XcodeGen), so it isn't committed.

```sh
brew install xcodegen     # one-time
xcodegen generate         # creates Commit.xcodeproj from project.yml
open Commit.xcodeproj
```

Requirements: **Xcode 15+**, targeting **macOS 14+**.

### Signing (free Apple ID)

The macOS build is configured to **"Sign to Run Locally"** (ad-hoc) in `project.yml`
(`CODE_SIGN_IDENTITY[sdk=macosx*]: "-"`), so it runs on your Mac with a **free Apple ID**
— no team, no provisioning profile, no contact with Apple. Just `xcodegen generate`,
select **My Mac**, and run (⌘R). On first launch of an ad-hoc-signed app, macOS Gatekeeper
may ask you to confirm — right-click the app → **Open**.

You can also copy the built `Commit.app` into `/Applications` and use it daily; unlike iOS,
a locally-signed **macOS** app does **not** expire after 7 days.

### Widgets on a free Apple ID

The app and the widget share data through an **App Group** container
(`group.com.arronlingham.commit`, see the `.entitlements` files and
`SharedModelContainer`). The macOS entitlements request that App Group. Whether macOS
honours it under a free / ad-hoc signature isn't guaranteed:

- **If it works**, the desktop / Notification-Center widget shows your real habits.
- **If macOS refuses it**, the widget falls back to an empty store — but the **menu bar**
  (which runs in the app's own process and needs no App Group) still gives you the
  always-visible glance.

(On iOS, App Groups are strictly paid-only, which is one reason this app targets macOS.)

## Running & testing

- Run **My Mac**. The app window has Today / Progress / Habits / Settings; a checkmark
  icon appears in the **menu bar** — toggle habits there and the graph/widget update.
- Add habits with different schedules, toggle them on **Today**, and watch the
  contribution graph fill in.
- **Tests:** `⌘U` runs `CommitCoreTests` (scheduling, intensity mapping).

## Upgrading later (paid Apple Developer Program)

With a paid membership you could re-enable native **iCloud → CloudKit** sync and reliable
**App Groups** for on-device widgets / iOS, and reintroduce an iOS target. The data layer
(`SharedModelContainer`) is already structured around an App Group container to make that
straightforward.

## Status

Local-only macOS app: contribution graph, menu bar, widget (best-effort on free accounts),
flexible schedules. See `project.yml` for targets and `CommitCore/` for the shared model
and logic.
