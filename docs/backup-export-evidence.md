# Backup / Restore / CSV Export Evidence (Issue #7)

## Scope delivered
1. **`BackupCodec` (CrateKit)** — versioned JSON envelope:
   - Fields: `schemaVersion` (int, currently 1), `appVersion`, `createdAt`,
     `payloadDigest`, and the complete `snapshot` (games, people, ALL play
     events including superseded originals).
   - `payloadDigest` is a SHA-256 over the canonical (sorted-keys) payload
     JSON, computed by a dependency-free pure-Swift SHA-256 in CrateKit
     (no platform crypto imports; keeps the Linux lane and the CrateKit
     purity gate intact). Known-answer vectors: empty string, `"abc"`, and
     a 60-byte multi-block input, checked against coreutils `sha256sum`
     (python `hashlib` agrees).
   - Forward-incompatible files (`schemaVersion > currentSchemaVersion`)
     fail closed with `.schemaTooNew`; versions below the floor with
     `.schemaVersionInvalid`; digest mismatches (edited/truncated payload)
     with `.integrityMismatch`; garbage with `.unreadableFile`. Nothing is
     ever partially imported — validation completes before a caller sees
     the snapshot.
2. **Store snapshot/restore (CrateStore)**:
   - `CrateStore.snapshot()` reads games, people, and the complete ledger
     history in a stable order.
   - `CrateStore.restore(_:)` validates referential integrity AND replays
     the pure `PlayLedger` invariants BEFORE touching the database, then
     replaces all rows inside a single GRDB write transaction: any failure
     (FK violation included) rolls the store back byte-for-byte. The frozen
     v1 schema and its append-only triggers are untouched — restore
     deletes games/people (cascade allowed by the v1 triggers) and inserts
     complete rows (in-place play updates remain trigger-forbidden).
     Post-restore, direct `DELETE FROM plays` is still rejected.
3. **CSV export (CrateKit `PlayLogCSV`)** — RFC 4180 escaping (commas,
   doubled quotes, embedded newlines, unicode names pass through), fixed
   `yyyy-MM-dd` UTC dates, unknown dates export as empty (never guessed),
   effective events only (superseded originals never export).
4. **Files-app UI (App/PrivacySettingsView.swift)**:
   - `fileExporter` for backup JSON and play-log CSV into a user-picked
     location; `fileImporter` for restore with security-scoped reads.
   - Restore is preview-first: choosing a file decodes + fully validates it
     and shows integer counts (games/people/plays both sides); the store is
     replaced only on "Replace crate", and Cancel/rejection paths leave it
     untouched.
   - Reachable from the Insights tab toolbar (`privacy.open`).
5. **CI**:
   - The UI hygiene gate import allowlist gains `UniformTypeIdentifiers`
     ONLY (document UTType declarations for the pickers; no transport API;
     the empty-allowlist pattern scan is unchanged and still runs first).
   - Zero-network gate and CrateKit purity gate: unchanged, empty allowlist.

## Host verification (Linux, Docker `swift:6.2-noble`)
- `swift test Packages/CrateKit`: results in `## Host results` below.
- `swift test Packages/CrateStore` (with `libsqlite3-dev`): results below.
- `bash -n` on both gate scripts; gate re-run locally: see below.
- `swiftc -frontend -parse` on all `App/*.swift` + `UITests/*.swift`:
  clean (syntax only — not a type-check; macOS compile is authoritative).
- SHA-256 vectors cross-checked: the 60-byte vector used in
  `SHA256Tests` was generated with `python3 hashlib`
  (`sha256(b'a'*60) = 11ee3912…aaad4`), which agrees with coreutils.

## Host results
- `swift test Packages/CrateKit` (Docker `swift:6.2-noble`):
  `Test run with 42 tests in 7 suites passed` (23 pre-existing + 19 new:
  9 BackupCodec, 3 SHA-256 vectors, 7 CSV).
- `swift test Packages/CrateStore` (same image + `libsqlite3-dev`):
  `Test run with 15 tests in 0 suites passed` (8 pre-existing + 7 new
  snapshot/restore tests).
- `bash -n scripts/check_ui_network_hygiene.sh`: clean.
- `scripts/check_ui_network_hygiene.sh`: PASS (empty pattern allowlist;
  import allowlist gained only `UniformTypeIdentifiers`).
- `scripts/check_zero_network.sh`: PASS (empty allowlist).
- `scripts/check_cratekit_purity.sh`: PASS.
- `swiftc -frontend -parse` on `App/*.swift` + `UITests/*.swift`: clean
  (syntax only; the macOS compile is the authoritative type-check).

## CI-authoritative (cannot run on this Linux host)
- Xcode 26.0.1 (17A400) build of app + UI-test targets.
- XCUITest journey `testRestorePreviewShowsCountsAndCancelKeepsStore`
  (preview counts via a real codec round-trip, cancel-keeps-store proof).
- Post-build `UIDeviceFamily == [1]` guard (unchanged phase).

## Honesty notes
- No archive, device, signing, or TestFlight evidence exists or is claimed.
- XCUITest assertions are launch/journey evidence on a simulator only.
- The Files-app picker interaction itself is OS-owned surface; the journey
  injects the preview through the same `startRestorePreview(from:)` path
  the importer uses, so file-picker UI automation is not claimed.
