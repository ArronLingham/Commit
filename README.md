# Commit

A minimalist habit tracker for **iPhone and Mac**, with a GitHub-style
contribution graph and a macOS menu-bar quick-toggle.

- **Contribution graph** — your habits rendered as a "commit graph": each day's
  colour intensity is how many habits you completed that day, over the month or year.
- **iPhone + Mac** — one native SwiftUI codebase, with **free cross-device sync**
  via Firebase (no paid Apple Developer account needed).
- **Menu bar** — check habits off from the macOS menu bar without opening the app.
- **Home-screen / desktop widgets** — the contribution graph, plus an interactive
  widget to toggle today's habits in place.
- **Flexible schedules** — daily, specific weekdays, or "X times per week".

## Project layout

```
CommitCore/      Shared framework: SwiftData models, scheduling, persistence,
                 theme, contribution-graph view, toggle AppIntent, and the
                 sync engine (CommitCore/Sync/*).
CommitApp/       iOS + macOS app: Today, Progress, Habits, Settings, menu bar.
CommitWidget/    WidgetKit extension: contribution graph + interactive today widget.
CommitCoreTests/ Pure-logic unit tests (scheduling, intensity mapping, sync merge).
project.yml      XcodeGen project definition — the source of truth for the Xcode project.
```

The SwiftData `@Model` types, scheduling logic, the contribution-graph view, and the
sync engine live in **CommitCore** so the app and the widget share one implementation.

## Building (on a Mac with Xcode)

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonyz/XcodeGen), so it isn't committed.

```sh
brew install xcodegen     # one-time
xcodegen generate         # creates Commit.xcodeproj from project.yml
open Commit.xcodeproj
```

Requirements: **Xcode 15+**, targeting **iOS 17+ / macOS 14+**. (Sync adds a Firebase
Swift package in a later step — see *Cross-device sync* below; until then the app builds
and runs local-only.)

### Signing (free Apple ID)

This project is configured to run on a **free Apple ID** (no paid program):

1. Xcode → Settings → Accounts → add your Apple ID (creates a "Personal Team").
2. Select the **Commit** and **CommitWidget** targets → Signing & Capabilities →
   set **Team** to your Personal Team.
3. Run on an **iOS Simulator** (no signing needed), **My Mac**, or a real iPhone.

The iOS / widget entitlements are intentionally empty, and the macOS build uses a
sandbox-only entitlement, so a free account can sign everything. Notes on the free
tier: an app side-loaded to a **physical iPhone expires after 7 days** (reinstall from
Xcode), and **on-device widgets can't read the app's data** (App Groups is paid-only).
Both are Apple device limits, unrelated to sync.

## Cross-device sync (free, via Firebase)

Sync uses **Firebase Firestore** instead of iCloud, so it's free. Devices are paired
with a **sync code** (no login). One-time setup:

1. Create a free project at <https://console.firebase.google.com>.
2. Add an **Apple app** with bundle id `com.arronlingham.commit`; download
   **`GoogleService-Info.plist`** and drop it into the **`CommitApp/`** folder, then
   re-run `xcodegen generate` (it'll be bundled automatically).
3. In the console, enable **Firestore Database** and **Authentication → Anonymous**.
4. Set Firestore security rules to:

   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /spaces/{space}/{document=**} {
         allow read, write: if request.auth != null;
       }
     }
   }
   ```

   (Access is namespaced by the long, unguessable sync code; you can add real
   per-user auth later.)

Then in the app: **Settings → Sync → Create a sync code** on one device, and **enter
that code** on the other. Habits, completions and deletions sync both ways
(last-write-wins on a per-record `updatedAt`, with tombstones for deletes).

If `GoogleService-Info.plist` / the Firebase package aren't set up yet, the app runs
**local-only** and Settings shows "Sync unavailable" — everything else works.

### Upgrading to iCloud later (paid program)

The code already supports CloudKit. With a paid Apple Developer Program membership you
can re-add **App Groups** + **iCloud → CloudKit** capabilities (see the commented
hints in the `.entitlements` files) and switch `SharedModelContainer` back to
`cloudKitDatabase: .automatic` to use native iCloud sync and on-device widget sharing.

## Running & testing

- **iOS:** run on a simulator or device. Add habits with different schedules, toggle
  them on **Today**, watch the contribution graph fill in, add the home-screen widgets.
- **macOS:** run "My Mac". A checkmark icon appears in the menu bar — toggle habits
  there and the graph/widget update.
- **Sync:** pair two devices/simulators with a code (above) and confirm changes flow
  both ways.
- **Tests:** `⌘U` runs `CommitCoreTests` (scheduling, intensity mapping, sync merge —
  the main regression surface).

## Status

Core app complete; **free Firebase sync** added. See `project.yml` for targets and
`CommitCore/` for the shared model, logic, and sync engine.
