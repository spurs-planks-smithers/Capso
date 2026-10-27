# Feedback Public Launch Implementation Plan

> Execute this plan in the current task. The user authorizes website publication and the next app release handoff. The user owns the production app build.

**Goal:** Publish protected website feedback now and prepare native submission for Nextshot v0.5.0.

**Architecture:** Keep the existing isolated feedback Worker, private storage, scanner, and owner review. Publish anonymous web admission with Turnstile. Keep review routes behind exact-owner Access. Enable only the reviewed native support feature for the next app release.

**Spec:** [[2026-10-26-secure-feedback-intake]]. Operations: [[feedback-intake]].

## Global constraints

- Do not build, notarize, archive, tag, promote, or publish a production app.
- Preserve the live v0.4.0 artifact, latest record, Guides, media, and parallel changes.
- v0.4.0 is already published as build 804. Drew selects v0.5.0 for native activation on October 27, 2026.
- Keep all malware, privacy, injection, authentication, quota, budget, retention, and network controls.
- No original attachment download route. Rebuilt files require owner authorization.
- No unrelated Gmail reads. Use only synthetic launch submissions and the fixed notification recipient.
- Keep inactive email contact information hidden until exact-address inbound routing works.

## Review focus

- Anonymous visitors can use the public form but cannot inspect private receipts, files, or drafts.
- Owner sign-in and rebuilt-file download work without bypassing browser warnings.
- Native submission uses its fixed host and frozen reduced package. Other capability and Jev flags retain their current behavior.
- Website publication preserves the current downloadable app and every released object.
- Rollback closes admission while preserving private review, retention, and stored submissions.

## M1: Verify and record current boundaries

Files: this plan, [[feedback-intake]], and the prior progress record.

- [x] Read current main and isolate this work from parallel checkout changes.
- [x] Verify current live release, exact-owner Access, service switches, signature freshness, and successful scheduled refresh.
- [x] Complete real owner sign-in and an authorized rebuilt-image download. Reject missing or forged credentials through existing boundary checks.
- [x] Record any remaining blocker before changing public admission.

Expected: security checks pass without relaxed controls. The live app remains v0.4.0 build 804.

## M2: Publish public website feedback

Files: site/feedback/wrangler.jsonc, src/worker.js, public/index.html, public/form.js, existing service tests, site/public/index.html, and site/public/site.css.

- [x] Make public deployment settings durable and reversible. Keep inbound email disabled until its own delivery check passes.
- [x] Update the existing configuration test before exposing any new availability field. Run it, implement the field, and rerun the service suite.
- [x] Hide the inactive email alternative. Preserve the existing form design and disclosure.
- [x] Change Access from whole-host staging to the exact review path and children. Verify the unchanged owner policy and audience.
- [x] Deploy the feedback service with the approved private scanner image and existing secret bindings.
- [x] Verify anonymous form/config access, Turnstile enforcement, private review denial, limits, and a real synthetic receipt through screening and notification.
- [x] Stage the complete current homepage and Guides. Render the form and homepage before publishing.
- [x] Publish the exact staged site. Run existing live smoke checks and compare latest.json before and after.

Expected: public feedback works from nextshot.dev. Private files remain protected. The app release pointer and checksum match the recorded baseline.

## M3: Prepare native submission for v0.5.0

Files: Packages/FeedbackKit/Sources/FeedbackKit/FeatureFlags.swift, its existing tests, App/Feedback support hooks, CHANGELOG.md, AGENTS.md, and affected Guides.

- [x] Prepare the real fixed-host transport check for the app release owner. Native admission stays off in the website launch task.
- [x] Carry forward the real native panel review and require signed Dev app review in the separate app release runbook. No production build is created.
- [x] Prepare a guarded activation helper for the release owner. It sets only supportSubmission after the graph freezes and calculates the actual first release build.
- [x] Verify helper failure cases, exact flag scope, and existing package checks. Actual activation stays in the owner-run release process.
- [x] Update the Guides and release notes with the actual screenshot disclosure and submission behavior.

Expected: the release owner can include the reviewed feature through the normal next minor release. No production app is built or published in this task.

## M4: Publish source and hand off operations

Files: [[feedback-intake]], the progress record, and the release handoff checklist.

- [x] Document activation, owner review, held submissions, scanner failure, quota pause, retention, and rollback commands.
- [x] Document the separate v0.5.0 release checks and production commands for Drew.
- [x] Run applicable existing tests and one focused branch review. Preserve separate parallel work.
- [ ] Publish and merge the scoped source PR after checks pass. Attach the PR to this task.
- [x] Record live URLs, verification evidence, remaining email state, and the unchanged production artifact.

Expected: the website is live, source and operations agree, and Drew has a concrete app release handoff.

## Execution record

- October 27, 2026: live latest.json identifies v0.4.0 build 804, commit 3d2ddc8, published at 13:45:27 UTC (06:45:27 Pacific).
- Drew selects v0.5.0 for the next app handoff. No production build is authorized here.

- Public human verification passes after browser automation disconnects. Receipt 086892f7 completes screening, private draft preparation, and notification sending.
- Base source controls remain closed. The production website profile enables four controls and keeps native and email off. Its existing configuration test verifies exact bindings and image digest.
- Form checks reproduce and fix stale verification copy, accepted receipt overwrite, duplicate clicks, and status-poll outages. No persistent test gate is added.
- Ruling: preserve the existing released-in build meaning. The separate owner runbook freezes the graph, activates only supportSubmission, and verifies the final build marker.
- Automatic approval review declines temporary live native activation in this website task. The native backend stays off. Its real transport harness is compiled with synthetic input and remains ready for the owner-run gate.

- Website publication succeeds from the sealed site-iC8DYD artifact. The live homepage links Feedback. The public guide is https://nextshot.dev/guides/send-feedback/.
- Site Worker version: 27b2fec8-dbdc-4bbd-8729-28b18b375a83. Feedback Worker version: 6aa41e49-f2e3-4cab-a3e2-fb0444192739.
- Existing service tests: 96 pass. Site tests: 22 pass. SupportKit tests: 6 pass. FeedbackKit tests: 341 pass. Twelve disposable helper fixtures pass. Focused source review finds no consequential defect.
- Live site smoke checks pass. The complete latest.json record remains unchanged at 0.4.0 build 804. Its DMG SHA-256 remains 5145cdafb022dab61784689766d912977a4f3037fbf17cd144d1b62ecf141346.
- Final evidence lives in the ignored build/feedback-launch folder: live-final-checks.json, live-controls.json, public-receipt.json, site-publish.log, live-home.jpg, and live-guide.jpg. PR checks and the merge record supply source publication evidence.
