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
| C5 #157 | Closed | Actual toolbar flow, native ended save, ordinary-round preservation, and permission revocation verified |
| C6 #170 | Acceptance verified | PIN sign-in, refresh/revoke, live quota, bounded provider call, and paused readback verified |
| C7 #171 | Implemented, open | Actual Chrome sign-in and native assistance acceptance |
| C8 #148 | Closed | Installed on-device adapter, actual Chrome suggestions, disabled result, and local-only fallback verified |
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

## October 29 acceptance update

The unlocked full app suite passes 247 tests with zero failures. Signed Nextshot Dev build 909 is installed. Actual toolbar Rolling Round capture saves an independent ended native round and preserves the active ordinary round. Duplicate native delivery returns the same receipt. Removing the granted site permission stops tracking and closes the offscreen document. Issue #157 is closed.

Actual on-device assistance selects only captured IDs in 1,222 milliseconds. Chrome displays the suggestions for explicit acceptance. Disabling the native flag returns unavailable in 61 milliseconds. The temporary Apple flag is reset off. Apple mode now always keeps the local fallback when native help is unavailable. Saved Jev consent cannot cause cloud escalation. Independent fallback and clipboard-status checks pass at 5bfabdd. Issue #148 is closed. These measurements do not claim one-second Apple completion or macOS15 hardware coverage.

Source5bfabdd is pushed to draft PR #173. Cloudflare email PIN is enabled with Drew's approval. The existing feedback app stays pinned to its Cloudflare provider. Only the dedicated Jev application uses PIN. Its sole policy admits the owner's exact email. The deployment guard verifies both application provider IDs through API readback. Provider IDs come from the dashboard because the scoped token cannot read provider details. Processing and billing approval remain false. No provider key or paid call is active. Actual Chrome invited sign-in is in progress.

## October 29 service acceptance

Chrome completes the real invited PIN flow. Sign-in enables neither Jev nor content consent. The session survives a browser restart. Refresh rotates both credentials. Sign-out revokes the family. The former access token returns 401. A live zero allowance returns local fallback with no admitted request.

One synthetic provider request completes in 422 milliseconds end to end. It returns only supplied IDs and scores. No score meets the browser display threshold, so the local result stays intact. The Worker reports 112 milliseconds of provider time and 518 input tokens. Three earlier runtime failures retain their reservations. Total permanent reservation is 11,012 microdollars. The $25 global ceiling and $5 owner allowance remain enforced. No private preview data enters these tests.

The live failure finds a platform mismatch that Node mocks miss. Cloudflare Workers rejects `redirect: error` before outbound traffic. The adapter now uses manual mode and refuses redirects through status checks. An independent actual-workerd probe confirms the cause and correction with a synthetic outbound handler. The pause command now works without the Access credential or Access policy checks. Processing is paused after acceptance. Billing approval remains verified. Browser feature defaults remain off.

The supplied Claude Artifact is private. Its signed-in Chrome page exposes an embedded frame on a distinct claudeusercontent.com origin. Compatibility acceptance still needs the existing test browser to sign into Claude. The browser policy blocks opening the normal Chrome extension manager. No alternate installation workaround is attempted. The user modal offers the isolated test browser or deferral. #174 and final user smoke stay open.

## October 29 regular Chrome continuation

Drew directs the Artifact check to regular Chrome after repeated human-verification blocks in Chrome for Testing. He loads the Dev extension from a requested one-time Downloads copy. The canonical package stays in the repository. The regular Chrome Artifact opens successfully. Its frame is covered before its explicit site grant. It remains covered after that grant because the original guard rejects every sandboxed iframe.

The correction admits readable sandboxed frames that permit `allow-same-origin`. It still rejects opaque effective origins, including Content Security Policy and inherited sandbox restrictions. Nine actual Chrome scripting checks pass for exact child matches, private masks, denied origins, opaque fallback, flag changes, mutation, and navigation. The private Artifact URL, screen content, and screenshots stay outside tracked files. Regular Chrome acceptance after the correction remains pending.

An actual toolbar Rolling Round request to the invited Jev service completes in 506 milliseconds. Its bounded payload contains one captured action, no note, and no media. Local steps remain available. Browser-only Save creates an ended round and copies its prompt. Permanent reservations total 13,765 microdollars. Processing is paused again. An independent operational browser check intercepts all provider requests. Valid suggestions appear, edits and consent revocation reject delayed replies, and Save completes in 35 milliseconds before a pending reply. Network failure preserves local matches. Offline saving of an existing draft takes 21 milliseconds. Fresh offline screen capture still requires a real toolbar gesture and remains a final smoke check.

## October 29 preview and offline acceptance

Drew reloads the corrected extension in regular Chrome. The supplied Artifact now captures its preview and maps a numbered annotation to the embedded heading. Independent final browser checks verify child context and private pixels in ordinary capture, recording, and Rolling Round. Opaque and denied frames stay covered. Exact-head CI passes at 01dfd8a. Issue #174 closes with these support limits. Drew then presses Save himself and confirms prompt copy. Chrome also displays Saved and Prompt copied.

The controlled source tab runs under DevTools Offline mode. A fresh toolbar capture requests its site grant, masks its field, matches its button, saves, and copies the prompt. The test restores No throttling and the original DevTools preference. Combined with service-network abort, stale-reply, consent, and pending-save checks, this completes #171. Jev processing remains paused. The owned service session is revoked. Private Artifact data stays local.

## October 29 completion-audit corrections

Two additional bugs receive separate Later sub-issues under #124. Issue #175 replaces system-clock offsets with monotonic clocks. A real browser reproduction first loses an action after a backward clock adjustment. Six checks pass after e843b82. They cover forward/backward adjustments, both recording clocks, and worker recovery. Recovery preserves the latest evidence offset and records an explicit gap.

Issue #176 adds a bounded resource-loss warning through 9523e7a. Nine checks cover early eviction, oversized frames, event limits, normal expiry, selected warnings, Clear, and tiny budgets. One fixed control marker remains outside the payload budget. A subsequent real offscreen test finds diagnostic saturation can prevent explicit-recording selection. The final selection cap reserves the coordinator's coverage row and preserves omission warnings. Both modes now create drafts with 1,000 diagnostics and valid selected timestamps.

The [performance record](../research/2026-10-29-chrome-pilot-performance.md) separates steady idle from active-state measurements. It proves natural worker suspension and cleanup. It makes no battery-life or universal-overhead claim. Final package reload and Drew's native/Rolling smoke remain in #172. Keep the umbrella open until those results exist.

## October 29 usability feedback

Drew reports that the extension feels heavy and falls short of the seamless, unobtrusive principle. Issue #177 records refinement before umbrella acceptance. Reduce visible controls, decisions, prompts, and transitions before expanding capabilities. Functional smoke remains separate evidence. A successful Save alone does not establish usability acceptance.

The smoke harness also adds avoidable friction. Chrome automatically closes agent-created tabs at turn end unless they are marked. The omitted handoff mark closes the source and correctly clears unsaved rolling history. The test now preserves its source tab across each user step. This correction changes no product code.

Drew opens the live review. The final selection covers 8 to 18 recorded seconds and includes the observed click. Its annotation matches the captured button. The new draft is ready for Save. Native readback and cleanup remain pending. The planning update introduces no runtime change or required extension reload.

## October 29 native-first review

Drew requires native annotation and review when Nextshot is available. Browser editing remains the standalone fallback. Fable 5.1 is unavailable in the agent catalog. Drew approves one Astra review instead. That read-only review uses source `206c4e0` and the supplied smoke screenshots. It identifies native draft ownership, closed-app discovery, element transforms, active review commands, and media playback as unfinished contracts.

The current source opens browser review and imports a completed report afterward. Native saving also resizes images and persists before the note flow finishes. Reusing those operations unchanged cannot establish native-first acceptance. The dated decision records the correction explicitly. Four new serial Later sub-issues cover feasibility, drafts, annotation/context, and native Rolling review. #177 covers design and simplification. #172 remains final smoke.

At review start, ten of twelve formal #124 children are closed. Optional #148 is also closed. #124, #172, and #177 stay open. PRs #161 and #173 remain draft and unmerged. CI passes for `206c4e0`. These counts describe the earlier browser pilot. They do not measure completion of the new native experience.

The live browser draft remains unsaved. The source tab retains its handoff mark. A fresh screenshot audit cannot proceed because browser policy rejects access to the internal extension page. No alternate access path is attempted. This is a code and plan review, not a completed current-screen usability audit. Rendered design and running-app acceptance remain in #177 and #172.

GitHub readback verifies sixteen formal children under #124: ten closed and six open. New issues #178 through #181 are sequential, open, and in Later. #172 and #177 stay open. Every open enhancement has one severity label. Both PR descriptions now identify the native-first correction.

This update changes documents and tracking only. It requires no extension reload. Jev processing stays paused. No provider call, app installation, release, or runtime change occurs.
