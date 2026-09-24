# Game Crate

**Local-first iPhone board-game night crate: own your shelf, shortlist tonight's pick by players and time, log each play, and keep a private per-player taste profile — no accounts, no cloud.**

Game Crate is a personal shelf of the board games you own, the people you play with, and the nights you actually played. It answers the three questions every game night has — *what do we have time and people for tonight?*, *have we played this recently, and how did everyone feel about it?*, *what's actually missing from my shelf?* — from data that never leaves the device.

## Motivation

Board-game collections outlive memory. Paper "maybe lists" rot, spreadsheet shelves ignore who is visiting and how long until bedtime, and social platforms lock collection and play history behind accounts. Game Crate keeps a private crate: a shelf you own, a fit rule that explains itself, and a play log that turns into simple, honest per-player preference counts.

## Target users

- Hobby board-game owners (10–300 games) who host casual game nights.
- Households and friend groups who want "you pick, something that fits tonight" to be answerable in seconds.
- Anyone who wants collection + play history without a social network or cloud account.

## Concrete use cases

1. **Friday shortlist.** Set 4 players, 60 minutes, "tabletop only" — the shortlist shows shelf games whose player/time ranges fit, sorted by how recently they were played and average rating, with every exclusion counted and explainable.
2. **Checkout at the table.** One-tap play entry (game + date + players) on the folded phone; add rating and notes unfolded at the end of the night.
3. **Taste profile.** After ten plays, see per-player counts: A plays a lot of cooperative games, B almost never rates party games above 3. Counts only — no personality labels.
4. **Hole list.** "I own zero 2-player games under 30 minutes" — shelf analytics name the gaps in your own categories.
5. **Backup before reshelving.** JSON backup to the Files app, CSV export of the play log for a spreadsheet; restore always previews before replacing.

## How to use (intended workflow)

1. Add your shelf: title, min/max players, play time, your own category tags (from a built-in vocabulary you can extend).
2. Add the people you play with.
3. On game night, open tonight's shortlist, tap a game, log the play when it's done.
4. Browse the wall, per-player profiles, and shelf analytics over time.
5. Back up or export whenever you like.

## MVP feature list

- Shelf: local CRUD for owned games (title, players min/max, minutes, categories, owned-copy count, notes).
- People roster: local, no contacts permission.
- Append-only play ledger: date, game, players, optional per-player rating (1–5), optional notes.
- Fit engine: deterministic shortlist from player-count/time/category filters; explains every exclusion reason; unknown fields never silently pass or fail — they render as unknown.
- Derivations: plays-per-game, days-since-last-play, per-player rating counts, per-player category counts, shelf coverage ("holes") — all pure functions of the ledger.
- Crate wall: glanceable status per game (fits tonight? last played?).
- Versioned JSON backup/restore (previewed replace) and CSV export.
- Local reminder (optional): "game night" weekly nudge.

## Non-goals

- No game database / online lookup, no crowd ratings, no price tracking, no store links.
- No OCR / barcode scanning / photo AI of boxes.
- No social network, friend sharing, leaderboards, or group sync.
- No recommendation ML; the shortlist is an explainable filter, not a model.
- No win/loss or score tracking (that is `court-tally`'s domain), no seating charts (`seat-weave`).
- No diagnosis, treatment, or wellness claims of any kind — entertainment log only.
- No cloud, no accounts, no analytics, zero network by construction.

## Privacy, permissions, and data storage

- All data lives in a local SQLite store (GRDB) inside the app sandbox. Photos/attachments are out of MVP scope.
- Permissions: none required for MVP (no camera, contacts, location, or network). Only local notifications, opt-in.
- Backups are user-initiated files the user owns (Files app); nothing is uploaded anywhere.
- People names are plain local strings shown only inside the app; support exports (if ever added) redact nothing needed because nothing sensitive is stored beyond what the user typed.

## iPhone Duo dual-screen design target (migration path)

The dual-screen experience is a documented design target, **not** a current dependency — foldable APIs are not yet available. Today's build shape is a **standard native Swift (SwiftUI) iPhone app with iPad support disabled by default** (`TARGETED_DEVICE_FAMILY = 1`; tablet layouts require explicit user opt-in). All layout decisions route through one seam, `CrateWorkspaceLayout`, which today renders a single-column iPhone stack. When Apple ships dual-screen/fold-region APIs, that seam maps to:

- **Folded:** one-handed quick log — tap-to-play entry, shortlist glance, and last-night wall.
- **Unfolded:** crate wall as the persistent control surface on one screen while the other hosts the shortlist workbench, game detail editor, or per-player profile (canonical console/detail span).
- **Continuity:** selection and scroll position persist across fold/unfold because view state lives in the workspace model, not the view.

## Bundle ID & App Store Connect

- Bundle ID: `com.infinityball.gamecrate` (matches `PRODUCT_BUNDLE_IDENTIFIER` in every future app/extension target and CI signing config; never any other prefix).
- App Store Connect registration: **CREATED** (this bundle ID was registered via the App Store Connect API during repo scaffolding).
- GitHub Actions secrets configured for the future release pipeline (names only, values never shown): `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID`.

## Current status & milestones

Native skeleton landed (issue #1): `GameCrate.xcodeproj` (app + UI-test targets,
bundle id `com.infinityball.gamecrate`, `TARGETED_DEVICE_FAMILY = 1` in every
configuration), pure Swift 6 `Packages/CrateKit`, launch XCUITest smoke, and
CI that measures the exact pinned toolchain, enforces iPhone-only pre-build grep
+ post-build `UIDeviceFamily == [1]`, runs a zero-network empty-allowlist gate,
and runs the package tests on Linux. See `docs/bootstrap-evidence.md` for what
is host-verified vs CI-authoritative. **No device, archive, or TestFlight
evidence exists yet.** Remaining backlog:

1. CrateKit domain (shelf, ledger, fit engine, unknown-safe semantics)
2. GRDB store (`Packages/CrateStore`) + schema v1 + repositories
3. Shelf + people management UI
4. Play logging, crate wall, tonight's shortlist UI (incl. `CrateWorkspaceLayout` seam)
5. Player profiles + shelf analytics at the UI edge
6. Backup/restore/CSV export + privacy controls
7. TestFlight/release packaging with real evidence gates

## Development quickstart

- Native Swift + SwiftUI only. **No Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity, or any cross-platform/hybrid framework.**
- iPhone-only iOS app; no Android target and no native iPad support (user opt-in required for either).
- Toolchain pinned in `toolchain.json`: iOS 26 SDK or newer, Xcode 26.0.1 (17A400) baseline, Swift 6 language mode. A missing exact pin on CI is an environment acceptance blocker.
- CI asserts `TARGETED_DEVICE_FAMILY = 1` in all app-target configurations and verifies built `UIDeviceFamily == [1]` on Apple runners. Archive verification never happens on Linux and is never faked there.
- Release path: TestFlight via App Store Connect API using the repository Actions secrets above (secret names only).
