# Game Crate — release checklist (v0.1.3 candidate)

## App Store Connect metadata (draft, not evidence of submission)

- Name: Game Crate
- Subtitle: Your private game night shelf
- Category: Games / Board
- Description: Keep the board games you own, the people you play with, and the nights you played in one private iPhone crate. Shortlist games by player count and time with clear fit reasons. Log plays, explore count-based insights, and export your own backup or CSV. Works offline; no account required.
- Keywords: board games,collection,game night,play log,offline
- Privacy policy: publish a public policy URL before an App Store submission. **Not yet published.** The current policy text is below; do not fabricate a URL.
- Screenshots: capture actual iPhone simulator/device screens before a public App Store submission; no iPad screenshots required or claimed.
- TestFlight notes: First private preview of an offline board-game shelf and play ledger. Add games and players; try Tonight's shortlist, log a play, then export a backup. Do not enter sensitive real names during testing unless you accept local storage.

## Privacy questionnaire / nutrition-label answers to confirm in ASC

- Data used to track you: **none**; third-party tracking: **none**.
- Data collected by the developer: **none**. Player names, shelf entries, ratings and notes remain on-device, except user-initiated Files exports chosen by the user.
- Linked-to-you or unlinked analytics/advertising/diagnostics uploaded: **none**.
- Permissions: only local notifications if explicitly enabled; no camera, contacts, location or photo-library permission. Files backup/export uses the system document picker.
- In-app policy: no account or network dependency; exports are owned by the user and can be shared by the user outside the app.
- Cross-check before publication: `App/PrivacyInfo.xcprivacy`, zero-network and UI hygiene gates, and the exact ASC privacy questionnaire answers. This draft does not assert that ASC questionnaire has been submitted.

## Tagged release gate

1. Merge a reviewed green PR. On `main`, record the change in `CHANGELOG.md`, then create/push `vMAJOR.MINOR.PATCH` pointing to a main commit. Never tag an unmerged feature head.
2. `Tagged TestFlight release` checks the exact tag and main ancestry, selects only measured Xcode 26.0.1 / 17A400 / iPhoneOS SDK 26.0, archives using the four configured Actions secrets, and asserts archived `CFBundleIdentifier == com.infinityball.gamecrate`, version/build and `UIDeviceFamily == [1]` before upload. It also verifies the signature; logs/signing key stay on the ephemeral runner.
3. Upload with Xcode's App Store Connect API-key export, then poll ASC for a **new** build numbered `<run number>.<run attempt>` (reruns must not reuse Apple's version/build identity) and an upload timestamp after this attempt started. Only `processing_state: VALID` in `processed-build.json` counts as processed-build evidence. An archive or export command alone does not.
4. Link the successful Actions run, evidence artifact, build ID and the redacted JSON in the release PR; check the real app's TestFlight page before claiming installation or availability. Invalid or timed-out processing is a blocker, not a success.
5. Public App Store shipping requires additional review: a real privacy-policy URL, ASC questionnaire submission, current iPhone screenshots, localization/metadata review, install smoke on a real iPhone, and approval. None of those are implied by this TestFlight workflow.

## Observed release attempts

- `v0.1.2`, build `3.1`, [run 37446107837](https://github.com/rwrife/game-crate/actions/runs/37446107837): exact Xcode 26.0.1 / 17A400 / SDK 26.0 was selected on `macos-26`, but archive failed with categories `missing-ios-platform=1, missing-destination=1, provisioning=1`. No archived identity/signature, upload or processed build was verified. Redacted record is `docs/release-evidence/v0.1.2-attempt-1.json`.
- `v0.1.1`, build `2.1`, [run 37439079735](https://github.com/rwrife/game-crate/actions/runs/37439079735): exact Xcode 26.0.1 / 17A400 / SDK 26.0 was selected, but archive failed. The retained diagnostic is `provisioning=1, compiler-or-build=2`. This is not sufficient to establish a specific root cause. No archived identity/signature, upload or processed build was verified. The redacted record is `docs/release-evidence/v0.1.1-attempt-1.json`.
- The registered bundle ID and matching ASC app record both exist (read-only/idempotent lookup performed by the executor); this is not proof of usable provisioning or signing.
- On the next attempt, fixed subcategories distinguish missing platform/destination, missing profiles, disabled automatic signing, missing account, invalid credentials and certificate quota. Never infer quota exhaustion from the broad `provisioning` category, revoke certificates automatically, or substitute a toolchain to make the release pass.

## Failure and secret hygiene

- Required secret **names only**: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID`. Values are never committed or printed. The p8 is written mode 600 under runner temp, deleted on exit. An absent secret fails before signing.
- `testflight-evidence-<run>` contains only release context, selected Xcode/SDK, archived app Info.plist and processed-build JSON if available, plus fixed error categories/counts on failure (no raw Xcode lines or key fragments). Do not upload the archive, IPA, raw signing logs or key.
- Pin absence, signing/provisioning errors, missing App Store Connect app, upload failure and processing timeout all leave the issue open. CI simulator success is not signing, archive, upload or device evidence.
