# Optional browser Apple assistance

Date: October 28, 2026. Execution is authorized. Issue #148 stays in Later and outside v0.5.0. This does not authorize a release.

## Boundary

The extension keeps its immediate local suggestions. A deliberate assist action may rank selected text through the running native app. It never launches the app. No background collection invokes a model. The independent `browserAppleIntelligence` and `browserBridge` flags both start off. Drew must review this feature in Dev before a release enables it.

The adapter uses only `SystemLanguageModel.default`. Apple identifies this as its [on-device model](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel). It creates a session only after an eligible assist request. No remote model, custom model adapter, tool, media input, network client, or cloud escalation exists in this path.

The macOS 15 package floor remains. SDK compilation uses `canImport(FoundationModels)`. Model types and execution require macOS 26. The helper links FoundationModels weakly.

## Selected request

The payload is JSON with version 1, a UUID requestID, a nonnegative integer selectionVersion, purpose `steps` or `elements`, optional nonnegative issueAt, timeline, and candidates. Each timeline entry has id, at, kind, and label. Each candidate has id, role, and label. Time values use seconds within the selected excerpt.

The payload limit is 32,768 bytes. Each list permits at most 100 entries. IDs are unique within each list. IDs permit letters, digits, underscores, and hyphens, up to 96 bytes. Labels permit 512 bytes. Kind and role permit 64 bytes. Control characters and unknown fields fail validation. No image, media, header, body, full DOM, endpoint, path, or reviewer-edit field exists. The caller must sanitize selected labels before sending them. Page text remains untrusted evidence.

The typed model answer contains at most 12 IDs. Steps select only timeline IDs. Elements select only candidate IDs. Unknown IDs, duplicates, and excess results fail validation. The adapter cannot generate instructions, source locations, notes, or reviewer edits. An empty answer keeps the local fallback.

## Native transport API

Use the existing one-message native host. The envelope carries version 1, channel, operation `assist`, id matching requestID, SHA-256 digest of exact payload bytes, and base64 payload. The full envelope permits at most 49,152 bytes. The helper uses the existing handshake, private inbox, digest, and mutually authenticated Apple Events. It reserves host `browser-assist`. No general automation capability is involved.

Example selected payload:

```json
{"version":1,"requestID":"cc0b57ed-36ac-4801-89e1-c504573ce238","selectionVersion":3,"purpose":"steps","issueAt":4,"timeline":[{"id":"event1","at":1,"kind":"click","label":"Open settings"},{"id":"event2","at":3,"kind":"click","label":"Save changes"},{"id":"event3","at":4,"kind":"error","label":"Save failed"}],"candidates":[]}
```

C7 integration: serialize that object once to UTF-8 bytes. Compute its lowercase SHA-256 hex digest. Call `chrome.runtime.sendNativeMessage("com.drewschulz.nextshot.dev.browser", {version: 1, channel: "dev", operation: "assist", id: payload.requestID, digest, payload: base64Bytes})`.

A validated reply contains state `available`, `unavailable`, or `refined`, requestID, selectionVersion, capturedIDs, and selectedIDs. A request with no evidence probes availability without a model session. A valid assist request with the app closed returns a correlated unavailable reply. Transport or validation errors may instead return the existing failed receipt. All failures keep the local fallback.

Apply a refined reply only when requestID and selectionVersion still match the current selection. Verify its IDs against the submitted snapshot again. Preserve every reviewer edit. Never replace the local result while awaiting assistance. An unavailable, failed, canceled, empty, or stale reply requires no prompt or retry. No numeric model confidence is exposed.

The adapter requests cancellation after 20 seconds. The native Apple Event waits at most 30 seconds. These are optional refinement limits, not a one-second suggestion promise.

## Verification and remaining acceptance

The package builds with a macOS 15 target. `otool` reports `LC_LOAD_WEAK_DYLIB` for FoundationModels. An actual m5pro synthetic request returns the supplied event IDs through guided generation. Observed adapter time is 1.06 seconds on the second run. This is one small synthetic sample, not a browser latency or quality result.

Scratch assertions reject extra top-level fields, nested headers, oversized payloads, excess events, invalid request IDs, negative timestamps, unknown result IDs, and duplicate result IDs. Disabled and pre-canceled requests return unavailable. An in-flight cancellation also returns unavailable. A scratch build with the SDK branch disabled returns unavailable with assistance enabled. This checks conditional compilation, not unsupported hardware. Existing FeedbackKit checks pass with 357 tests. JevKit Release checks pass with 369 tests.

Actual Chrome-to-installed-Dev assistance remains for the parent integration check. Unsupported hardware, a disabled system model, and macOS 15 runtime execution are not tested on this eligible m5pro. Compare suggestion quality and cold/warm latency through the final browser review before acceptance. No deployment, push, issue closure, flag change, or app installation occurs here.

The configured backlink scanner is absent at its documented path and in searched project/configuration files. Edited links receive a manual check. The API note names no bare Markdown file reference.
