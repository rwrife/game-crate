# Play Logging, Crate Wall, and Tonight's Shortlist Evidence (Issue #5)

## Scope delivered

1. **Tonight's shortlist screen (`TonightView`)**:
   - Player count stepper (1–20) and time budget stepper (15–480 minutes, 15-minute steps).
   - Ranked picks rendered with recency details derived from the append-only ledger (`shortlist.pick.<Title>`).
   - Dedicated tap-through for games with `unspecified` player/time ranges (`shortlist.unspecified`).
   - Named, collapsible exclusion reason lists (`shortlist.exclusion.<Title>`) explaining why each known game does not fit.

2. **Quick log & compensating corrections (`QuickLogView`)**:
   - One-hand quick log: game + date defaults + player picker toggles.
   - Optional per-player integer ratings (1–5) and notes.
   - History viewer with compensating correction flow (`PlayEvent(correctionOf:)`), never in-place rewrites.
   - Compensating events render as corrections and mark the superseded event.

3. **Crate wall (`CrateWallView`)**:
   - Status derived strictly from ledger events (no cached truth).
   - Glanceable status: "Fits tonight" vs "Fit unknown" vs "Does not fit tonight".
   - DST-safe days-since-last-play derived via `Derivations.daysSinceLastPlay`.

4. **iPhone workspace layout seam (`CrateWorkspaceLayout`)**:
   - Single layout seam wrapping root tab content.
   - Documents the future dual-screen migration path (folded quick-log vs unfolded wall + workbench span).
   - `TARGETED_DEVICE_FAMILY = 1` preserved across all app-target configurations; no fold SDK APIs, no iPad layout.

5. **XCUITest journey**:
   - `testShortlistPickLogAndWallUpdateJourney`: shortlist → pick → quick log → crate wall updates.
   - `testCorrectionAppendsVisibleCompensatingEvent`: historical play correction appends compensating event and visibly marks original superseded.
   - `testManagementScreensStayHittableAtAX5`: AX5 Dynamic Type hittability maintained.

## Verification results on Linux host

- Zero-network gate (`scripts/check_zero_network.sh`): PASS (empty allowlist).
- CrateKit purity gate (`scripts/check_cratekit_purity.sh`): PASS (no UIKit/GRDB imports).
- Python test suite (`python3 -m unittest discover -s Scripts/tests -v`): 21/21 passed.
- Platform policies: `TARGETED_DEVICE_FAMILY = 1` declared in 4/4 configurations; no iPad family.
- `PRODUCT_BUNDLE_IDENTIFIER`: `com.infinityball.gamecrate` exact match.
- Swift 6 compiler frontend syntax check: `GameCrateApp.swift`, `BootstrapHomeView.swift`, and `GameCrateLaunchTests.swift` parse cleanly.
- Authoritative iOS build and XCUITest execution: GitHub Actions pinned macOS CI (`macos-15`, Xcode 26.0.1/17A400/iOS SDK 26.0).
