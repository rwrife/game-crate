# CrateKit Domain Verification Evidence (Issue #2)

- Date: 2026-09-26
- Branch: `feat/issue-2-cratekit-domain`
- Issue: https://github.com/rwrife/game-crate/issues/2
- Milestone: `M1-domain`

## Summary of deliverables

1. **Domain models (`Packages/CrateKit/Sources/CrateKit/Models.swift`):**
   - `Game`: optional `minimumPlayers`, `maximumPlayers`, `playTimeMinutes`. Absence is strictly `nil` (unknown), never defaulted.
   - `Rating`: strictly integer raw values 1...5 (`Rating(rawValue:)` returns nil otherwise).
   - `Person`, `CategoryTag`, `PlayParticipant`.
2. **Append-only play ledger (`Packages/CrateKit/Sources/CrateKit/PlayLedger.swift`):**
   - `PlayEvent`: immutable record; corrections set `correctionOf` pointing to prior effective event.
   - `PlayLedger.append(_:)`: validates existence and game match of target; rejects duplicate IDs.
   - `effectiveEvents`: filters out superseded events while keeping raw audit trail.
3. **Deterministic fit engine (`Packages/CrateKit/Sources/CrateKit/FitEngine.swift`):**
   - Evaluates games against `FitQuery(playerCount:timeBudgetMinutes:requiredCategories:)`.
   - Games with unknown player range or time are segregated into `unspecifiedGames` (and `unspecifiedCount`); never silently included or excluded.
   - Every excluded game receives an explainable `ExclusionReason`:
     - `.tooFewPlayers(minimum:requested:)`
     - `.tooManyPlayers(maximum:requested:)`
     - `.exceedsTimeBudget(gameMinutes:budgetMinutes:)`
     - `.missingCategory([CategoryTag])`
   - Deterministic ranking: longest since last play (never-played/undated first), then integer cross-multiplied rating sum/count (no float comparisons), then title ascending.
4. **Calendar-safe derivations (`Packages/CrateKit/Sources/CrateKit/Derivations.swift`):**
   - `daysSinceLastPlay`: calendar-day difference from latest dated play using `calendar.startOfDay(for:)`, preserving correctness across DST spring-forward (23h) and fall-back (25h) boundaries, plus pre-1970 dates. Returns `nil` when undated.
   - `playsPerGame`: effective play count per game including zeros.
   - `playerProfile`: integer-only play count, rating count, rating sum, distribution map, and category counts. No personality labels, no predictions, no wellness framing. Zero history yields zero counts.
   - `coverageHoles`: checks user-requested shapes against owned games; unknown fields never count as a match.
5. **Architectural purity & privacy gates:**
   - `scripts/check_cratekit_purity.sh`: asserts no `import UIKit` or `import GRDB` in `Packages/CrateKit/Sources`.
   - `scripts/check_zero_network.sh`: empty allowlist privacy gate passes.

## Test suite execution

All 23 swift-testing cases in 4 suites pass in the Linux `swift:6.2-noble` container (identical to GitHub Actions `linux-package` runner):

```
◇ Suite "Skeleton placeholder" (3 tests)
✔ Test "domain namespace is reachable" passed after 0.001 seconds.
✔ Test "milestone marker is set for M1" passed after 0.001 seconds.
✔ Test "skeleton exposes no stored state beyond constants" passed after 0.001 seconds.

◇ Suite "Domain models and append-only ledger" (5 tests)
✔ Test "games preserve unknown fit fields" passed after 0.001 seconds.
✔ Test "ratings accept only integers from one through five" (6 parameterized cases) passed after 0.001 seconds.
✔ Test "duplicate event identifiers are rejected" passed after 0.001 seconds.
✔ Test "correction must reference an existing effective event" passed after 0.001 seconds.
✔ Test "corrections append a compensating event and preserve the original" passed after 0.001 seconds.

◇ Suite "Fit engine shortlist and exclusion explainability" (5 tests)
✔ Test "shortlist includes games matching player count and time budget" passed after 0.001 seconds.
✔ Test "games missing player range or time budget are marked unspecified and never shortlisted" passed after 0.001 seconds.
✔ Test "named exclusions explain why a known game did not fit" passed after 0.001 seconds.
✔ Test "shortlist ranks deterministic tie-break: days since last play descending, then average rating descending, then title ascending" passed after 0.001 seconds.
✔ Test "all excluded case reports empty shortlist, zero unspecified, and full exclusion count" passed after 0.001 seconds.
✔ Test "all unknown case reports empty shortlist, empty exclusions, and full unspecified count" passed after 0.001 seconds.

◇ Suite "Derivations: calendar-safe recency and count-based insight" (10 tests)
✔ Test "days since last play counts calendar days, not 24-hour periods" passed after 0.001 seconds.
✔ Test "DST spring-forward boundary still yields one calendar day" passed after 0.001 seconds.
✔ Test "DST fall-back boundary still yields one calendar day" passed after 0.001 seconds.
✔ Test "pre-1970 play dates produce a correct positive day count" passed after 0.001 seconds.
✔ Test "absent dates and empty ledgers return unknown instead of guessing" passed after 0.001 seconds.
✔ Test "plays per game counts only effective (non-corrected) events" passed after 0.001 seconds.
✔ Test "per-player counts aggregate ratings and categories as integers" passed after 0.001 seconds.
✔ Test "insufficient history yields zero counts, never interpolated stats" passed after 0.001 seconds.
✔ Test "coverage holes name user tag/range gaps and respect unknowns" passed after 0.001 seconds.

Total: 23 tests in 4 suites passed.
```

## Static check results

- `scripts/check_cratekit_purity.sh`: PASS (no UIKit/GRDB imports)
- `scripts/check_zero_network.sh`: PASS (empty allowlist, no network API usage found)
- Signing material check: PASS
