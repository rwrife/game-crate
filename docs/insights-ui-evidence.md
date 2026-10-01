# Insights UI Evidence (Issue #6)

## Scope delivered
1. **Insights tab** (`tab.insights`) — a fifth tab item on the existing
   `TabView`; all layout stays behind the single `CrateWorkspaceLayout` seam.
2. **Per-player profiles** (`insights.person.<name>` → `PlayerProfileView`):
   - Integer counts only, straight from `Derivations.playerProfile` over the
     effective ledger: plays logged, "X of Y plays rated", the full 1–5
     rating distribution (including explicit `N stars: 0` rows), and
     per-category play counts.
   - No personality labels, predictions, averages presented as facts, or
     wellness/psychology framing anywhere in the UI copy.
3. **Shelf-hole list** (`holes.*`):
   - Requests are user-authored shapes only (min/max players, minutes budget,
     optional user tag via chip picker or free text). Nothing is auto-suggested.
   - Each line explains itself: proven-covering game titles or
     `Hole: no shelf game provably covers this`, plus an explicit
     "N games with unspecified fields never counted" note whenever unknown
     data was excluded from the proof.
   - Requests live for the session in `GameCrateModel` (not stored), so the
     frozen CrateStore schema v1 is untouched.
   - Validation: inverted player ranges and blank category requests are
     rejected with a visible message; the existing list is untouched.
   - Rows are removable (`holes.remove.<index>`), and remaining rows
     re-explain themselves.
4. **Unknown/short-history states**:
   - No people: `insights.profiles.empty`; no requests: `holes.empty`.
   - No plays: `profile.no-plays.<name>` says counts are zero, nothing guessed.
   - Plays but no ratings: `profile.no-ratings-short.<name>` states the
     distribution stays zero; empty vs short-history are distinct states.
5. **CI: UI-target network/tracking hygiene gate**
   (`scripts/check_ui_network_hygiene.sh`, wired into both the Linux
   `swift:6.2-noble` job and the macOS `Scripts/ci.sh` phase list):
   - Empty-allowlist pattern scan over `App/` for network **and**
     tracking/analytics/ads symbols (URLSession family plus Firebase,
     ATTrackingManager, AdSupport, Mixpanel, Amplitude, PostHog, etc.).
   - Transitive-reachability approximation: every `import` in `App/` must be
     in a small vetted allowlist (SwiftUI, Observation, Foundation, XCTest,
     CrateKit, CrateStore); the local packages are themselves enforced by the
     zero-network and CrateKit purity gates, so the closure stays clean.
   - The existing repo-wide zero-network gate keeps its empty allowlist.

## Host verification (Linux)
- `swift test Packages/CrateKit`: 23/23 passed (Docker `swift:6.2-noble`,
  scratch path `/tmp/kit-build`).
- `swift test Packages/CrateStore`: 8/8 passed (Docker `swift:6.2-noble` with
  `libsqlite3-dev`, scratch path `/tmp/store-build`). No package sources were
  changed by this issue; suites re-run as regression evidence.
- `scripts/check_cratekit_purity.sh`: PASS.
- `scripts/check_zero_network.sh`: PASS (empty allowlist).
- `scripts/check_ui_network_hygiene.sh`: PASS locally (empty allowlist;
  imports limited to SwiftUI Observation Foundation CrateKit CrateStore XCTest).
- `bash -n` on both shell gates and `Scripts/ci.sh`; CI YAML parses;
  `Scripts/tests` helper unittests: 21/21 OK.
- `swiftc -frontend -parse` on `App/*.swift` and `UITests/*.swift` under
  Swift 6.2: clean (syntax only — not a type-check).
- pbxproj object-ID integrity check: all new IDs (`…106`/`…206`) defined once,
  zero referenced-but-undefined IDs, zero conflict markers.

## CI-authoritative (cannot run on this Linux host)
- Xcode 26.0.1 (17A400) build of the app + UI-test targets.
- The four new XCUITest journeys (`testInsightsEmptyStatesSayNothingToCount`,
  `testProfileShowsIntegerCountsForRatedHistory`,
  `testShortHistoryProfileRendersUnknownRatings`,
  `testShelfHoleListIsExplainedAndRemovable`) on the pinned simulator.
- Post-build `UIDeviceFamily == [1]` guard (unchanged phase).
- `swiftc -parse` is not a type-check; the macOS compile is the authoritative
  gate for the new SwiftUI view code.

## Honesty notes
- No archive, device, signing, or TestFlight evidence exists or is claimed.
- XCUITest assertions are launch/journey evidence on a simulator only.
