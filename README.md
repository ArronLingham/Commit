# Commit

A minimalist habit tracker for **macOS**, with a GitHub-style contribution graph
and a menu-bar quick-toggle. Fully **local** and **free** — no accounts, no
external services, runs on a free Apple ID.

- **Contribution graph** — your habits rendered as a "commit graph": each day's
  colour intensity is how many habits you completed that day, over the month or year.
- **Menu bar** — check habits off from the macOS menu bar without opening the app.
- **Flexible schedules** — daily, specific weekdays, or "X times per week".

## Project layout

```
CommitCore/      Shared framework: SwiftData models, scheduling, persistence,
                 theme, contribution-graph view, toggle AppIntent.
CommitApp/       macOS app: Today, Progress, Habits, Settings, menu bar.
CommitCoreTests/ Pure-logic unit tests (scheduling, intensity mapping).
project.yml      XcodeGen project definition — the source of truth for the Xcode project.
```

The SwiftData `@Model` types, scheduling logic, and the contribution-graph view live in
**CommitCore**.

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

## Running & testing

- Run **My Mac**. The app window has Today / Progress / Habits / Settings; a checkmark
  icon appears in the **menu bar** — toggle habits there and the graph updates.
- Add habits with different schedules, toggle them on **Today**, and watch the
  contribution graph fill in.
- **Tests:** `⌘U` runs `CommitCoreTests` (scheduling, intensity mapping).

## Scope & possible upgrades

This is intentionally a **single-device, local-only macOS app** so it runs free on a
personal Apple ID. Two features need the **paid Apple Developer Program** and were left out:

- **Widgets** — a WidgetKit widget needs an **App Group** to read the app's store, and App
  Groups require a provisioning profile a free account can't provide. The **menu bar**
  covers the same always-visible glance for free.
- **Cross-device sync / iOS** — would use iCloud (CloudKit) or a backend; also gated by the
  paid program for App Groups / device provisioning.

The data layer (`SharedModelContainer`) is still structured around an App Group container,
so re-enabling widgets / iCloud after upgrading is straightforward.

## Status

Local-only macOS app: contribution graph, menu bar, flexible schedules. See `project.yml`
for targets and `CommitCore/` for the shared model and logic.
