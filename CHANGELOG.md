# Changelog

## 0.1.2 — release candidate

- Keeps all 0.1.1 app features unchanged; sharpens the release-failure diagnostic with fixed, secret-safe signing/provisioning subcategories (certificate quota, missing profiles, automatic signing disabled, missing App Store Connect account, invalid credentials) and records the retained redacted evidence for the failed v0.1.1 attempt.
- No processed TestFlight build is asserted by this source entry. The v0.1.2 tagged run must supply that record.

## 0.1.1 — release candidate

- Keeps all 0.1.0 app features unchanged; adds safe category-only archive/export error evidence for a new release attempt after the first tagged archive failed before signing evidence or upload.
- No processed TestFlight build is asserted by this source entry. The v0.1.1 tagged run must supply that record.

## 0.1.0 — release candidate

- Native iPhone shelf and people roster, offline play ledger and explainable game-night shortlist.
- Count-only player profiles and shelf coverage insights; user-owned versioned JSON backup and CSV export.
- Privacy manifest, iPhone app icon and evidence-gated tagged TestFlight workflow.

This entry records a candidate's source changes; it is **not** an assertion that signing, upload, processing, TestFlight availability, or App Store publication succeeded. See `docs/release-checklist.md` and the actual tagged Actions run before making those claims.
