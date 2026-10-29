# Chrome extension execution, October 28, 2026

Implementation lives on `codex/chrome-extension` in [draft PR #173](https://github.com/spurs-planks-smithers/Capso/pull/173). The original [docs-only PR #161](https://github.com/spurs-planks-smithers/Capso/pull/161) remains preserved. This work stays in Later, outside v0.5.0. Nothing is publicly released.

## Issue structure and current acceptance

[#124](https://github.com/spurs-planks-smithers/Capso/issues/124) owns the serial delivery issues. [#157](https://github.com/spurs-planks-smithers/Capso/issues/157) is its Rolling Round sub-issue. [#148](https://github.com/spurs-planks-smithers/Capso/issues/148) remains an optional Apple follow-up. [#174](https://github.com/spurs-planks-smithers/Capso/issues/174) adds the requested embedded-preview coverage and blocks final smoke.

| Work | Status | Remaining acceptance |
|---|---|---|
| C1 #166 | Closed | Browser contract, persistence, portable export verified |
| C2 #167 | Closed | Actual Chrome capture, annotation, private pixels, element match verified |
| C3 #168 | Closed | Installed signed Dev bridge, quiet launch, durable import and duplicate receipt verified |
| C4 #169 | Closed | Actual toolbar permission, sampled recording, selected media, restart and cleanup verified |
| C5 #157 | Implemented, open | Actual rolling permission flow and independent native ended-round acceptance |
| C6 #170 | Implemented, open | External identity setup, live invited sign-in, bounded paid canary |
| C7 #171 | Implemented, open | Actual Chrome sign-in and native assistance acceptance |
| C8 #148 | Implemented, open | Native browser-to-app assist acceptance |
| Embedded previews #174 | Implemented, open | Requested Claude/Artifacts surface acceptance |
| C9 #172 | Package built, open | Final integrated user smoke |

## What runs locally

The extension uses packaged TypeScript and JavaScript without a UI framework. Basic capture needs no account, Mac app, recorder, or model. Native save is optional. The signed helper runs for one operation and exits. It uses framed Chrome native messaging and authenticated local Apple Events. It creates no network server.

Explicit recording and Rolling Round sample at most once per second. They retain masked images and bounded event metadata in memory. The history budget is 24,000,000 bytes. Rolling history keeps 60 recorded seconds. Tab changes, review, navigation, and ordinary selection compose independent pause reasons. Cross-site navigation requires re-arm.

Rolling review starts with the failure moment. Local steps appear immediately. Selected media, key frames, accepted steps, and diagnostics enter a separate ended round. Browser saving preserves an ordinary active round. The package target is a soft 5,000,000 bytes. Optimization and still fallback require no user input.

Optional review assistance starts from selected evidence. Local results stay usable. Jev requires separate enablement, page-text consent, invited sign-in, and optional reviewer-note consent. Apple requires its browser trial, an already-running Dev app, and the native flag. Only Save can launch the app.

## Verified evidence

- Browser checks cover actual screenshot capture, annotations, private-field pixels, portable export, and local IndexedDB save/reload.
- Real Rolling Round checks capture more than 60 seconds and decode an exact 10-second selection. They verify pause composition, navigation, actual worker restart, selected key frames, ordinary browser-round preservation, and cleanup.
- Real embedded-frame fixtures cover ordinary capture, recording, and Rolling Round. They verify nested coordinates, private fields, closed-shadow fields, denied origins, and covered sandbox fallback.
- The signed root Dev app builds with Rolling key frames and the optional Apple adapter. Dev identity and deep signature verification pass. Existing native evidence includes 357 FeedbackKit, 369 Release JevKit, six SupportKit, and 247 app tests before the final integration. Final app tests run again after integration.
- The client has 57 scratch assertions. Integrated browser modules pass 56 assertions with mocked Chrome/native/service APIs. These prove consent, stale results, edited-label preservation, explicit step acceptance, cancellation, and saving without waiting. They do not prove live authentication.
- Local D1 checks use signed test JWTs. They verify invitation subject binding, disabled-user rejection, PKCE, rotating refresh, replay revocation, concurrent quota, and permanent accounting. SQLite checks prove the global $25 cutoff and cross-month reservations. All 96 existing feedback-service tests pass.
- A packaged Dev ZIP contains the extension, install guide, registration tool, file hashes, permission inventory, and source state. Packaging performs no installation or publication.

## Review findings and fixes

Three privacy defects were reproduced and corrected before final acceptance. Revoking consent now cancels assistance and rechecks permission immediately before delivery, including after token refresh. Captured click labels use readable control names without CSS locators or field values. Transient scrolling, resizing, or animation invalidates a capture proof, including inside closed shadow roots and child frames.

The scroll reproduction begins a frame snapshot, scrolls a hidden field into view, captures pixels, then restores the original scroll position. It previously passed the unchanged final fingerprint. The movement guard now rejects that screenshot. Unchanged snapshots still pass. The original review reproductions pass after the fixes.

## External and native constraints

The separate Jev service defaults to disabled processing. It reserves 2,753 microdollars per call under the pinned provider contract. Pending or uncertain earlier calls also reduce later allowances. A completed call that spans a month boundary reduces both months. No reservation is refunded or deleted. The global limit is $25 per UTC month. The owner invitation uses a smaller $5 allowance.

Cloudflare setup stops before resource creation because the setup token returns HTTP 403 for identity-provider creation. Dashboard PIN setup awaits user confirmation. No pilot service, provider secret binding, or paid call is activated at this point.

The native test tool reports a locked Mac after the earlier unlock. Actual permission and installed-app checks await an unlocked session. A direct test using the newly built helper while the older installed app runs fails closed. Their exact executable paths differ. This does not establish acceptance of the new native build.

The final full app run executes 247 tests. Four window or key-focus tests produce five assertion failures. These failures block the next commit under AGENTS.md. Rerun them in an unlocked session before concluding whether they are environmental. The final privacy fixes remain local and uncommitted. The latest integrated commits are not yet pushed to PR #173.

Xcode 27's filesystem cache task stalls in the local build. `SDK_STAT_CACHE_ENABLE=NO` avoids it. The nested helper build uses SwiftPM's native engine when that setting is disabled. Signing stays enabled. No cache deletion or signing bypass is used.

## Reproduction and handoff

October 29 gate update: the Mac is unlocked. The full 247-test app suite passes with zero failures. Browser check/build and all 57 client assertions pass again. The earlier window/focus failures no longer block the final fixes. Native installation, actual browser delivery, and invited PIN acceptance continue next.

Subsequent continuation: the existing Access page renders Cloudflare account sign-in. A separate owner-only Access application now uses that method. Its single policy requires the owner's exact email plus membership in the Cloudflare account. The dedicated Worker and D1 database are deployed. Actual Chrome calls verify unauthenticated token, availability, inference, and revocation routes fail locally without Access redirects. The authorization route renders the pilot login page. Readback verifies processing=false, billing approval=false, no secret binding, and disabled alternate Worker entry points. No paid call occurs. Guest PIN setup, real owner login, and the unlocked native checks remain pending. Earlier setup-stop observations above describe the prior state.

Build and package with `python3 -I browser-extension/package-dev.py`. Follow [the install guide](../../browser-extension/INSTALL.md). The execution order and acceptance criteria remain in [the implementation plan](../superpowers/plans/2026-10-28-chrome-extension-implementation.md).

Task-only evidence and scratch scripts remain under ignored `build/chrome-execution/`. Do not infer completion from a package, mock, or plan checkbox. Close each remaining issue only after its real acceptance check. Finish with Drew's smoke result before closing #124.
