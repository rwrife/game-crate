# Game Crate — PLAN

## Scope

A local-first, iPhone-only native Swift app that manages a personal board-game shelf, an append-only play ledger, an explainable fit/shortlist engine, deterministic per-player preference counts, and user-owned backup/export. Zero network. MVP excludes: online game databases, crowd data, OCR, social features, ML recommendations, win/loss scoring, wellness claims.

## Architecture

```
GameCrateApp (SwiftUI, iPhone-only)
  └─ View layer (SwiftUI views + view models)
       └─ CrateWorkspaceLayout  ← single dual-screen migration seam
  └─ CrateKit (pure Swift 6 SPM package — no UIKit, no GRDB)
       ├─ Models: Game, Person, PlayEvent, Rating, CategoryTag
       ├─ FitEngine: deterministic shortlist + named exclusion reasons
       ├─ Derivations: daysSinceLast, perPlayerCounts, coverageHoles
       └─ BackupCodec: versioned JSON encode/decode, migration-safe
  └─ CrateStore (SPM package — GRDB SQLite)
       ├─ Schema v1: games, people, plays, play_players(+rating)
       ├─ DatabaseMigrator (versioned migrations + fixture DB)
       └─ Repositories (protocols + in-memory fakes for previews/tests)
```

- **Append-only ledger:** plays are immutable events; edits are compensating corrections, never silent rewrites. Derivations are pure functions of ledger state.
- **Unknown-safe semantics:** missing player-range/time data renders *unknown* and is neither auto-included nor auto-excluded from a shortlist without a user-visible "unspecified" count.
- **Integer math everywhere:** ratings stored as integer 1–5; minutes/counts are integers; no floating-point accumulation in derived stats.

## Technology choices

| Choice | Rationale |
|---|---|
| SwiftUI + Swift 6 | Apple-native, matches all tool-lab iOS policy; iPhone-only is trivially enforceable. |
| GRDB/SQLite | Same store family proven across sibling repos (carelabel, aquarist); relational fit for games×plays×people; Linux-testable core. |
| Pure-Swift CrateKit | Fit engine + derivations unit-testable on Linux CI without Xcode. |
| No network stack at all | Zero-network CI audit gate (empty allowlist) keeps the privacy promise structural, not aspirational. |

## Milestones & dependency order

1. **Skeleton + CI** — Xcode app target (bundle `com.infinityball.gamecrate`, `TARGETED_DEVICE_FAMILY = 1` × all configs), CrateKit/CrateStore packages, pinned macOS CI (Xcode 26.0.1/17A400/SDK 26.0), iPhone-only grep + post-build `UIDeviceFamily == [1]` guard, zero-network gate.
2. **Domain layer** — CrateKit models, fit engine with named exclusion reasons, derivations; swift-testing suites incl. DST-boundary date tests.
3. **Persistence** — GRDB schema v1, migrator + fixture DB, repositories + fakes.
4. **Core UI** — shelf CRUD, people roster, play logging flow, crate wall, shortlist screen; accessibility labels on every control.
5. **Profiles & analytics** — per-player rating/category counts, shelf-hole list.
6. **Backup/export** — versioned JSON backup with previewed replace, CSV play-log export.
7. **Release** — TestFlight upload via ASC API secrets with real signing evidence.

Milestone 1 blocks everything; 2→3 ordered by data flow; 4–6 sequential UI slices; 7 last.

## Testing strategy

- CrateKit: property-style unit tests (fit engine exclusion names, unknown handling, DST-safe days-since-last, count derivations) — run on Linux CI (swift:6.x) and macOS.
- CrateStore: migration up-tests against committed fixture DB; repository integration tests.
- UI: XCUITest smoke (add game → log play → wall updates) on pinned macOS runner.
- Privacy: CI grep gate for network APIs (`URLSession`, socket imports) with empty allowlist.
- Device family: pre-build config grep + post-build Info.plist `UIDeviceFamily == [1]` check on Apple runners; never claimed from Linux.

## Packaging / distribution

- Ad-hoc/simulator builds on CI; signed TestFlight builds via App Store Connect API using repo secrets (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID` — names only).
- Bundle ID `com.infinityball.gamecrate` fixed across targets, signing, and provisioning.
- App Store record, privacy nutrition labels, and screenshots are release-time artifacts; no claims before real evidence exists.

## Risks

- **Fit-engine overreach** — temptation to "guess" ranges; mitigated by unknown-safe rendering and named exclusions in tests.
- **Social drift** — feature requests for sharing/leaderboards conflict with zero-network charter; reject or make an explicit new product.
- **Xcode project hand-authoring fragility** — follow sibling-repo CI patterns (carelabel/aquarist) for pbxproj wiring.
- **Dual-screen SDK gap** — mitigated by single `CrateWorkspaceLayout` seam; today's behavior is an ordinary iPhone stack, future migration is local to one type.

## Explicit non-goals

No Android. No native iPad support (opt-in only). No cross-platform or hybrid frameworks — no Flutter, React Native, Expo, Kotlin Multiplatform, .NET MAUI, Unity, or equivalents. No accounts/cloud/sync. No crowd data or OCR. No ML. No win/loss scores. No medical/wellness claims. No `tablet-friendly` topic or iPad acceptance criteria anywhere in this repo.
