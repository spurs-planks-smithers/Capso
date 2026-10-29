# Nextshot Chrome extension implementation plan

Date: 2026-10-28. Owner: Drew. Execution authorized in chat on October 28. This supersedes earlier planning-only statements. Keep the tracked issues in Later. Exclude v0.5.0. No public release is implied.

## Goal and authority

Build the Mac-first Chrome extension with browser-only operation, optional quiet native save, explicit recording, Rolling Round, invited standalone Jev, and optional Apple Intelligence. Close an issue only after its acceptance evidence exists. Preserve unfinished issues as open. Finish with automated browser/native checks and a guided user smoke test.

Specs: [architecture](../specs/2026-10-28-chrome-extension-architecture.md), [Jev service](../specs/2026-10-28-standalone-jev-service.md), [Rolling Round](../../plans/2026-10-27-rolling-round-discovery.md), and [Chrome discovery](../../plans/2026-10-27-chrome-extension-discovery.md).

Drew approves a $25 per calendar month hard ceiling for paid Jev pilot work. The service must reserve bounded cost before paid requests. Keep it disabled if a defensible per-request bound or required credentials are unavailable. No public enrollment or recurring charge beyond that ceiling is authorized.

## Global constraints

External browser evidence uses schema namespace `nextshot.browser`, version 1. Native image-only rounds stay schema 1. Native browser imports use schema 2 with browser evidence attachments. Older native apps must hide schema 2. New code must continue reading schema 1. C3 verifies this mapping before native delivery.


- Keep Chrome runtime code small. Use event-driven Manifest V3 and packaged TypeScript/JavaScript with no application framework.
- Preserve account-free capture, review, local save, and export. The service, native app, and AI must never block them.
- Use only Nextshot Dev on m5pro. Preserve macOS 15 support. Keep all new flags off by default until the required Dev review.
- Allow only selected sanitized event/element details, diagnostics, and still images for Jev. Never send animation or audio.
- Retain annotation-driven element lookup, source context when reliable, ambiguity choice, per-site permission, and honest missing coverage.
- Use no debugger permission. Collect permitted request summaries without headers/bodies. Mask sensitive fields and exclude typed values.
- Retain 60 recorded seconds in Rolling Round. Use issue-first review, one-second local suggestions, explicit pause gaps, and separate ended-round save.
- Target a complete 5,000,000-byte bundle softly. Optimize invisibly. Save an oversized minimal bundle without a size prompt.
- Native imports are idempotent. The app alone writes native round state. Ordinary captures join the active native round. Rolling Round preserves it.
- Deploy a service only after configuration, access controls, cost enforcement, and consent are verified. No key enters the extension or a file.
- Preserve all unrelated local work. Stage explicit paths. Never edit .gitignore. Log upstream hooks in FORK_NOTES.
- Keep personal-repo tests minimal. Use existing checks plus task smoke evidence. Add no unrelated test framework or CI gate.

## Serial issue sequence

| Order | Issue | Prerequisite |
|---|---|---|
| C1 | [Chrome C1: browser evidence, local rounds, and portable export](https://github.com/spurs-planks-smithers/Capso/issues/166) | None |
| C2 | [Chrome C2: area capture, annotation, and element context](https://github.com/spurs-planks-smithers/Capso/issues/167) | #166 |
| C2a | [Chrome: permitted embedded preview element context](https://github.com/spurs-planks-smithers/Capso/issues/174) | #167; required before #172 |
| C3 | [Chrome C3: signed Swift bridge and quiet native import](https://github.com/spurs-planks-smithers/Capso/issues/168) | #167 |
| C4 | [Chrome C4: explicit recording and lightweight diagnostics](https://github.com/spurs-planks-smithers/Capso/issues/169) | #168 |
| C5 | [Rolling Round: capture and annotate recent browser history (discovery)](https://github.com/spurs-planks-smithers/Capso/issues/157) | #169 |
| C6 | [Chrome C6: invited standalone Jev service with hard spending cap](https://github.com/spurs-planks-smithers/Capso/issues/170) | #157 |
| C7 | [Chrome C7: browser Jev consent, authentication, and refinement](https://github.com/spurs-planks-smithers/Capso/issues/171) | #170 |
| C8 | [Apple Intelligence: improve local Rolling Round suggestions (Later research)](https://github.com/spurs-planks-smithers/Capso/issues/148) | #171 |
| C9 | [Chrome C9: install package and browser/native smoke test](https://github.com/spurs-planks-smithers/Capso/issues/172) | #171, #174 (Apple optional) |


| Order | Deliverable | Prerequisite | Acceptance evidence |
|---|---|---|---|
| C1 | Browser evidence contract, local rounds, prompt, and ZIP export | None | Saved browser record, valid portable bundle, sanitization and duplicate-save checks |
| C2 | Area capture, annotation, notes, element context, and review UI | C1 | Real Chromium capture/review screenshot, element match, saved notes, usable export |
| C2a | Permitted nested preview context, existing #174 | C2 | Child element matches, safe coordinate mapping, private-field masks, denied/opaque-frame fallback, actual requested surface review |
| C3 | Swift host, quiet native import, registration, and channel pairing | C2 | Signed Dev host, actual Chrome handshake, app closed/running imports, durable receipt, unchanged ordinary round |
| C4 | Explicit silent recording and lightweight diagnostics | C3 | Start/stop video and event timeline, no audio/header/body data, coverage markers, cleanup |
| C5 | Rolling Round, existing #157 | C4 | Selected excerpt/frames, issue-first review, local steps, pause/re-arm behavior, independent ended native round |
| C6 | Invited Jev service, quota and cost enforcement | C5 | Authenticated access, revocation, atomic quota reservation, no paid overage, bounded upstream adapter, local failure fallback |
| C7 | Extension Jev sign-in/consent and refinement | C6 | Browser-only invited assistance, selected payload, stale-result rejection, offline/capped fallback |
| C8 | Optional Apple Intelligence, existing #148 | C7 | Availability-gated on-device adapter, native eligibility checks, structured evidence-linked output, fallback |
| C9 | Distribution package, install instructions, and final smoke | C7, C2a; C8 optional | Reloadable extension, helper setup, full local/browser/native smoke, resource cleanup evidence, reviewer handoff |

#124 remains the umbrella. #157 remains its formal Rolling Round sub-issue. #148 remains a linked optional follow-up. Other delivery issues become formal children of #124. Every issue records its predecessor. Apple support never blocks the core fallback.

October 28 scope correction: Drew's later standalone requirement supersedes the earlier Mac-required pilot. Browser capture and tracking continue without the Mac app. A native-save failure preserves the browser report and offers a later retry. The earlier disconnect-only 15-minute draft policy does not govern browser-only operation. Unsaved rolling media remains in memory and clears on Stop or browser restart. Native assistance probes an already-running app. Only Save can launch the app quietly.

### Task 1: Browser evidence and local handoff

Create `browser-extension/package.json`, `browser-extension/build.mjs`, `browser-extension/src/core/model.ts`, `sanitize.ts`, `store.ts`, `bundle.ts`, and `zip.ts`. Build packaged scripts under ignored `build/chrome-extension/`. Use native browser storage and a small ZIP writer. Define versioned capture, mark, element, diagnostic, action, clip, and round data. Preserve reviewer authority separately from page evidence. Keep export paths relative and agent-neutral.

Verify real persistence, restart recovery, safe field limits, rejected traversal, duplicate save, ZIP structure, and selected-only asset inclusion. Use narrow scratch assertions and browser smoke. Run applicable existing checks before committing. Record commit and evidence.

### Task 2: Browser capture and review

Create `browser-extension/manifest.json`, page adapter, coordinator, review page, and CSS. Inject area selection and bounded DOM context only on user action. Freeze screenshot and source context together. Support numbered dots, arrows, boxes, notes, and ambiguity choice. Review the running UI before adding more controls. Keep normal saves independent of the app.

Verify browser capture without a host, element mapping after scrolling/zoom, sensitive-field filtering, useful keyboard control, round history, clipboard prompt, and portable export. Capture screenshots of the real running extension.

### Task 3: Swift native integration

Create `Packages/BrowserBridgeKit/`, its host executable, and `App/Feedback/BrowserImportCoordinator.swift`. Extend fork build overlays to embed and sign the helper. Register a per-user host manifest with an exact extension ID and channel. Use framed JSON, bounded transfer, private inbox, stable import IDs, and durable receipts. Add narrow AppDelegate hooks and log them in FORK_NOTES. Add atomic ended-round import to FeedbackKit while preserving its actor ownership.

Verify native framing and rejected inputs, real browser host delivery, installed Dev identity, quiet app launch, duplicate imports, current native round numbering, and a separate ended Rolling Round. Build only Nextshot Dev for local testing. Run existing FeedbackKit and app checks for touched behavior.

### Task 4: Explicit recording and diagnostics

Add the offscreen recorder and bounded event collection. Require explicit Start/Stop. Capture no audio. Collect clicks, navigation, relevant visible changes, observable errors, and permitted request summaries. Sanitize before retention. Keep coverage and pause markers. Close media tracks and offscreen work when no longer needed.

Verify actual media, action timing, missing permissions, cross-origin coverage gaps, and cleanup. Demonstrate that basic capture uses no recording process.

### Task 5: Rolling Round

Implement armed-tab 60-second buffering, review pause, tab-switch pause, cross-site re-arm, issue-first selection, local step candidates, and selected-only export. Keep user-selected boundaries and edits stable during later assistance. Generate animation when practical. Keep still-frame fallback and the soft package target.

Verify a 10-second selection from longer history, key-frame and diagnostic alignment, one-second local step availability, cancellation cleanup, no unseen media in exports, and preservation of an ordinary native round. Close #157 only after that evidence.

### Task 6: Invited Jev service

Create isolated `site/jev/` Worker code, invitation/access handling, quota storage, fixed upstream adapter, and deployment configuration. Reuse reviewed support patterns only where schemas and trust boundaries remain separate. Use revocable invited access. Hold provider credentials server-side. Default to disabled paid processing until cost bounds and credentials pass checks. Enforce the approved $25 monthly ceiling before each call, including concurrency and uncertain retries.

Verify authenticated request admission, denied/revoked access, excluded content, atomic allowance reservation, idempotency, timeout behavior, and a fixed endpoint. Then verify deployment configuration and only the explicitly approved bounded paid pilot path. Record unresolved external prerequisites honestly.

### Task 7: Browser Jev integration

Add a first-use invited sign-in flow, content consent, bounded selected request, and asynchronous refinement. Use local results immediately. No continuous request during tracking. Keep animation out of model requests. Discard stale responses. Do not open authentication during capture or after every expired request.

Verify the actual extension-to-service path, approved payload, capped/offline behavior, no key in browser assets, and no delay to capture/save. Keep its flag off until the required Dev review.

### Task 8: Optional Apple Intelligence

Add an isolated native adapter using the on-device default model only when the SDK and runtime permit it. Preserve the macOS 15 floor with availability gates. Reuse selected sanitized evidence and output validation. Avoid automatic cloud escalation. Keep its own off-by-default flag and local fallback.

Verify runtime availability, unavailable/disabled cases, evidence-linked output, and review latency. SDK presence alone is insufficient. Close #148 only after the optional behavior and fallback are verified.

### Task 9: Final distribution and smoke

Package a reproducible Dev extension build and helper registration path. Document installation, site grant, capture, native save, recording, Rolling Round, standalone Jev, and cleanup. Keep release channels separate. Record tested supported/unsupported cases and performance measurements. Run the final review and required existing checks. Preserve open issues for any missing acceptance evidence.

Help Drew smoke test one visible step at a time after automated verification. Never claim that a user smoke step passed without his result. Close the umbrella only after its deliverables and required smoke are complete.

## Execution ledger

The task ledger lives under ignored `build/chrome-execution/progress.md`. It records issue IDs, commits, checks, rulings, and active work. This avoids adding a skill-generated .gitignore. No task completion may be inferred from a plan checkbox alone.
