# CrateStore evidence (issue #3)

## What shipped

- `Packages/CrateStore` depends on local `CrateKit` and GRDB.swift pinned with
  `exact: "7.11.1"` (`Package.resolved` records revision
  `b83108d10f42680d78f23fe4d4d80fc88dab3212`). The app project links the
  local CrateStore product.
- Frozen migration `v1` creates `games`, `people`, `plays`, and `play_players`.
  `plays.game_id` and both `play_players` foreign keys use `ON DELETE CASCADE`.
  Indexes cover play date, game, and participant person. SQLite triggers reject
  UPDATE on play and participant rows; the repository protocol exposes append
  and read only. Game and person projections support save, read, list, delete.
- The fixture is `Packages/CrateStore/Tests/CrateStoreTests/Fixtures/v1.sqlite`.
  Regenerate with `python3 Packages/CrateStore/Tools/regenerate_v1_fixture.py`.
  The tool reads the frozen migration SQL, uses fixed UUIDs/dates/row order, and
  writes the GRDB migration marker. Two consecutive regenerations on this host
  yielded identical SHA-256
  `329e2a1f63ffb62c0a0994687f53a5a2654680fbc9273ea772064f95e9faca5e`.

## Host verification (2026-09-27, Linux aarch64)

- Swift 6.2.4 in the **`swift:6.2-noble`** container, with `libsqlite3-dev`
  installed and tests running as host UID/GID 1000:1000: CrateKit **23 tests
  passed** and CrateStore **8 tests passed**, 0 failures. The store tests cover
  fresh and fixture migration, domain
  round trips, correction inserts, duplicate rejection, in-memory fakes,
  cascade foreign keys, indexes, orphan rollback, and UPDATE/direct DELETE rejection.
- `scripts/check_zero_network.sh`: pass, empty allowlist.
- `scripts/check_cratekit_purity.sh`: pass.
- `python3 -m unittest discover -s Scripts/tests -q`: 21 passed.
- `git diff --check`: pass.

The macOS CI store test step is configured but was not run on this Linux host.
Xcode, simulator, device-family post-build, archive, and TestFlight checks are
not available here. The Linux store tests exercise GRDB against system SQLite;
the app build remains CI-authoritative on macOS.
