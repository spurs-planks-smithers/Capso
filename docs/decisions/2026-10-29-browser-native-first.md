# Native editing for browser captures

Date: 2026-10-29. Owner: Drew. Status: product direction confirmed; implementation contracts remain proposed.

## Direction and correction

Drew makes native editing the default when Nextshot is installed and usable. Chrome supplies browser capture, element details, and explicitly armed recording. Nextshot supplies annotation, notes, review, saved rounds, and the copied prompt. Standalone browser editing remains available without Nextshot.

This corrects the October 28 browser-first architecture. Review no longer stays in Chrome for every user. A native capture opens an editable draft before final publication. Opening Nextshot for deliberate editing supersedes quiet launch only after browser Save. The previous finished-report import remains implemented, but does not establish native editing acceptance.

All Chrome work stays in Later and outside v0.5.0. This review changes no runtime code, flags, deployment, or installed package. The existing implementation authorization remains separate from the required rendered design review in #177.

## Chrome-only pilot exception, October 29

Drew explicitly requests Chrome-only friend tests on Windows and Mac. The [friend pilot plan](../superpowers/plans/2026-10-29-chrome-friend-pilot.md) and #182 deliver that standalone test before the native engineering sequence. This supersedes the immediately preceding paired-app pilot selection. It does not establish Windows release support or change the native-first product direction.

## Experience

| Situation | Proposed behavior |
| --- | --- |
| Native app available | Capture the permitted browser region. Open its draft in Nextshot. Use native annotation and notes. Publish once and copy the native prompt. |
| Native app installed but closed | Start the paired app for deliberate native editing. Do not require a browser Save first. |
| Native app absent | Open the existing browser editor. Capture, save, and export require no account. |
| Native bridge disabled or incompatible | Preserve the draft. Use the browser fallback with a brief explanation. Do not re-enable a disabled integration. |
| Native delivery outcome uncertain | Resolve draft ownership through a bounded status request before opening another editor. Never publish twice. |
| Rolling Round | Review the issue frame, suggested steps, and selected interval in Nextshot. Use native marks and notes. Save one independent ended round. |

Choose the editing destination once per deliberate operation. Do not ask on every capture. Put integration setup, trial flags, assistance, and diagnostics in Settings. Keep browser permission prompts only where Chrome requires them. Show a compact armed or paused indicator and an accessible Stop action.

Drew confirms automatic browser context on October 29. Keep the normal Nextshot capture shortcut. When Chrome is frontmost on an approved site, add permitted browser element details when available. Do not require a separate extension action. The trigger mechanism remains unproven and belongs to #178. If context is unavailable, preserve ordinary native capture without adding popup steps.

Rolling tracking resumes after Save or Cancel when the source tab is active and still eligible. Preserve the existing explicit arming decision. Do not ask this settled question again. A cross-site navigation still requires re-arming.

## Ownership and contracts

Chrome retains responsibility for capture-time page structure, permission checks, masks, frame proof, and the rolling buffer. Native receives sanitized evidence. Match marks against the frozen capture, never a later live page.

Use a draft ID, source digest, edit revision, editor owner, and protocol version. Separate staged acceptance from final publication. A staged receipt never means saved. Final publication returns the native capture and round identity. Retry, lost receipt, and recovery must preserve one editor and one publication. Keep the source digest separate from the final edited digest.

The app remains the only writer of native round state. An ordinary capture joins its active round. A Rolling Round creates an ended round and preserves that ordinary round. Standalone captures use the browser store. Do not save two independent finished reports by default when native editing succeeds.

Reuse the existing native image editor and note controls. Add a browser-draft entry point. The current save coordinator persists before notes finish and resizes images. Adapt its draft lifecycle rather than reusing it unchanged. Carry pixel transforms through resizing, cropping, zoom, and display scaling. Limit geometry-changing tools until their mappings are verified.

For ambiguous element matches, offer a quick choice. Use bounded, consented Jev help only when useful. Keep local suggestions and immediate manual selection. Do not delay Save for assistance.

## Rolling review and resource bounds

Keep the full rolling buffer in browser memory. Native review requests bounded metadata and masked frames through an authenticated active-review connection. Transfer only the final selected evidence for publication. Avoid a second full history copy on disk.

Pause tracking during review. Preserve the issue-first flow and immediate local steps. Keep range adjustment secondary. Native marks and notes belong to the same review flow. A final Save produces one ended round. Unselected frames, steps, and diagnostics do not enter that round.

Retain 60 recorded seconds, no audio, no typed values, and sanitized request summaries without headers or bodies. Preserve privacy masks, tab-switch pauses, pause gaps, explicit cross-site re-arming, and cleanup. The 5,000,000-byte package target stays soft. Optimize silently and save the smallest practical package without asking the user.

GIF remains preferred when efficient. Compact video and still frames remain fallbacks. Native acceptance of a WebM asset does not prove playback. Verify macOS 15 playback or encode selected frames with a system codec. Do not add an embedded browser or bundled codec by default.

## Feasibility before implementation

The existing signed helper supports short handshake, finished import, and assistance operations. Handshake needs an already-running app. An unavailable response does not establish that Nextshot is absent. Human review cannot fit inside the current short import exchange.

Prove two distinct mechanisms: a native capture trigger with Chrome's required permissions, and a temporary browser-initiated connection for native review. Native messaging alone does not prove a native app can wake an idle extension. Do not simulate key presses or retain a hidden permanent port to bypass this constraint.

Chrome documents that `sendNativeMessage` starts a helper per message. `connectNative` retains its host until the port closes. A native connection also keeps the extension worker alive. Restrict the proposed connection to active review and verify teardown. [Native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging), [worker lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle).

Chrome's temporary `activeTab` access requires an extension gesture. Native key handling is not listed as such a gesture. Verify the trigger contract instead of assuming it supplies permission. [Active tab access](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab), [capture API](https://developer.chrome.com/docs/extensions/reference/api/tabs#method-captureVisibleTab).

If native-triggered capture cannot meet permission and idle limits, report that limit before choosing a fallback. Browser shortcut entry followed by native editing is an interim option. Browser range selection followed by native annotation does not establish full native Rolling review acceptance.

## Delivery and acceptance

The revised serial sequence belongs in the [implementation plan](../superpowers/plans/2026-10-28-chrome-extension-implementation.md). It covers bridge feasibility, draft routing, native annotation, native Rolling review, workflow simplification, and final smoke. #124 remains the parent. #157 preserves the completed browser Rolling scope. #148 remains an optional linked follow-up.

Before interface changes, #177 requires a rendered proposal and Drew's review. Final acceptance needs ordinary capture and Rolling Round in the actual native app. Verify closed, running, absent, disabled, and incompatible app states. Verify offline standalone capture, uncertain delivery recovery, source closure, cancellation, no duplicate saves, accurate element mapping, and unchanged ordinary round state.

Measure actions, browser tabs opened, repeated choices, context changes, latency, helper lifetime, and idle worker suspension. Require no browser annotation page during a successful native path. Do not claim zero overhead or a completion percentage from closed issue counts.

Keep Jev processing paused, the $25 monthly ceiling enforced, and feature defaults off. This review authorizes no public release or new paid provider calls.
