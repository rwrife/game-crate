# Shelf and People Management Evidence (Issue #4)

## Scope delivered
1. **Shelf flow**:
   - Empty state `shelf.empty` with explanatory guidance.
   - Add game (`shelf.addGame`, `game.save`, `game.cancel`) with validation for required title and invalid player ranges.
   - Stepper inputs for players (1–20) and play time (1–480 minutes, 5-minute steps) with explicit opt-out toggles rendering as `Players unknown` / `Time unknown` rather than guessed numbers.
   - User-extensible tag vocabulary chips and comma-separated tags.
   - Detail view with unknown-safe rendering (`unknown`, never guessed), edit sheet, and delete with cascade citation count confirmation dialog (`Delete Game and X Plays`).
2. **People roster flow**:
   - Tab item `People` (`people.empty`).
   - Add person (`people.addPerson`, `person.save`, `person.cancel`) with required name validation.
   - Edit and delete person (`person.delete` -> confirmation action sheet).
   - Local strings only; zero contacts framework/permission requests.
3. **Accessibility**:
   - Every interactive control carries an `accessibilityIdentifier` and `accessibilityLabel`.
   - VoiceOver summaries for game cards and person rows.
   - Dynamic Type AX5 (`UICTContentSizeCategoryAccessibilityXXXL`) hittability test suite in XCUITest.
4. **App Root Composition**:
   - `GameCrateApp` wires `GameCrateModel` with in-memory fallback during test/error launches and sandboxed SQLite URL during standard execution.

## Host verification (Linux)
- `check_zero_network.sh`: PASS (empty allowlist, no networking imports).
- `check_cratekit_purity.sh`: PASS (no UIKit/GRDB imports in CrateKit).
- `Packages/CrateKit`: 23 swift-testing cases passed on `swift:6.2-noble`.
- `Packages/CrateStore`: 8 swift-testing cases passed on `swift:6.2-noble` with SQLite v1 migration, cascade, and foreign key verification.
- Swift frontend syntax validation: `GameCrateApp.swift`, `BootstrapHomeView.swift`, and `GameCrateLaunchTests.swift` parse cleanly under Swift 6 compiler.

## Environment & CI limitations
- Host is Linux (`Linux 6.17.0-1032-nvidia`). No local iOS Simulator or macOS `xcodebuild` available on host.
- Full UI journey execution and AX audit runs on pinned macOS CI runner (`macos-15`, Xcode 26.0.1/17A400/iOS SDK 26.0) via `Scripts/ci.sh`.
