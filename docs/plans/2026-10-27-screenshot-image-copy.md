# Screenshot Image Copy: Requirements and Preparation Plan

Status: product interview complete. Requirements and preparation plan ready for review. Target: candidate for v0.5.0. Prepared October 27, 2026.

Backlog: [Copy screenshots for pasting, with or without annotations, issue 123](https://github.com/spurs-planks-smithers/Capso/issues/123). Milestone: Later. Labels: enhancement and sev-blocker. Severity rates the unavailable screenshot-only retention workflow, not a crash.

Separate backlog: [Search capture history by app or window title, issue 125](https://github.com/spurs-planks-smithers/Capso/issues/125). Search has no assigned release target and does not block this feature.

### Outcome

Copy a new or saved screenshot as an image that pastes directly into email and other apps. Choose the visible annotations or a version without them. Screenshot use does not require feedback notes or a round.

This document isolates feature planning from the older-round work in this checkout. It authorizes no implementation, release, push, or capability activation. GitHub holds the backlog record. This document holds the detailed requirements and preparation plan.

### Confirmed requirements

| ID | Requirement | Source |
| --- | --- | --- |
| R1 | Support screenshots just captured and screenshots captured previously. | Initial request |
| R2 | Copy actual image data, ready for ordinary Paste in email and other image-capable apps. | Initial request |
| R3 | Offer image copy with annotations and without annotations. | Initial request |
| R4 | Finishing the area selection copies the image and closes immediately. Offer a separate way to annotate. | Interview, October 27 |
| R5 | Keep screenshot-only captures in a simple screenshot history. Require no notes or feedback round. | Interview, October 27 |
| R6 | For an older annotated capture, ordinary Copy Image copies the visible annotated image. Offer a separate Copy Without Annotations action. | Interview, October 27 |
| R7 | Keep the feature easy to discover and quick to use. | Initial request |
| R8 | Prepare the feature for consideration in v0.5.0. This is a candidate target, not a release commitment. | Initial request |
| R9 | Explicitly copying a newly annotated screenshot asks for no notes. Keep the image in screenshot history. Save to Round is separate. | Interview, October 27 |
| R10 | Copy Without Annotations removes circles, arrows, and text. Keep deliberate redactions or pixelation over private areas. | Interview, October 27 |
| R11 | Option+Shift+4 starts instant screenshot copy. Keep Option+Shift+F for feedback capture. | Interview, October 27 |
| R12 | Annotate Last Screenshot reopens the newest image from instant screenshots or feedback rounds. Capture first, then annotate. | Interview, October 27 |
| R13 | Keep the latest 100 screenshot-only entries. Automatically remove older screenshot-only images. Round captures are outside this limit. | Interview, October 27 |
| R14 | Browse screenshot-only captures and round captures together. Reference round images without making duplicate files for browsing. | Interview, October 27 |
| R15 | Option+Shift+A opens Annotate Last Screenshot as a global shortcut. | Interview, October 27 |
| R16 | Finishing annotation creates a new history version. Keep the source entry. Each screenshot-only version counts toward the 100. | Interview, October 27 |
| R17 | Offer Add to Round in the screenshot annotation editor. An instant screenshot can become feedback afterward. | Interview, October 27 |
| R18 | Reopening an annotated image permits new marks only. Earlier marks remain flattened. Clean copy still uses the separate clean image. | Interview, October 27 |
| R19 | Combined history supports visual thumbnails, date browsing, and filtering by captured app. All three belong in this feature. | Interview, October 27 |
| R20 | Track text search by app or window title as a separate feature request. Do not make search a prerequisite for this feature. | Interview, October 27 |
| R21 | Add to Round carries inherited feedback requests and their earlier notes forward as actionable requests, alongside new requests. | Interview, October 27 |

### Source findings

Source inspection uses the current checkout. Live inspection confirms installed Nextshot Dev 0.4.0-dev, build 807. The Settings window is visible. This inspection does not verify the new behavior.

| Current path | Behavior | Owning source |
| --- | --- | --- |
| Escape in an unmarked inline editor | Copies the original image using the clipboard format setting. Closes only after success. Saves no capture. | `App/Feedback/FeedbackController.swift`, `installKeyMonitor`, `copyScreenshotAndClose` |
| Copy in the inline feedback editor | Copies PNG, then saves a round capture and opens notes. Completing notes copies a prompt over the image. Copy success is not checked. | `App/Feedback/FeedbackController.swift`, `openInlineEditor`, `save` |
| Copy in the full-editor fallback | Copies PNG without the inline path's round save. | `App/Feedback/FeedbackController.swift`, `openFullEditor` |
| Recent Rounds capture row | Click selects it for prompt copy. Option-click previews its annotated image. No direct image-copy action exists. | `App/Feedback/FeedbackStatusItem.swift`, `App/Feedback/FeedbackCaptureRowView.swift` |
| Stored round images | Each capture has annotated and clean PNG paths. Clean images retain redactions. A canvas-size change can make the clean image equal the rendered image. | `Packages/FeedbackKit/Sources/FeedbackKit/FeedbackRoundStore.swift`, controller save pipeline |
| Clipboard encoding | Existing helper writes PNG, JPEG, or TIFF image bytes. | `Packages/SharedKit/Sources/SharedKit/Utilities/ImageUtilities.swift` |
| Optional History | Standalone tools and related startup work are gated off by current capabilities. Screenshot history must respect that policy. | `App/Feedback/Capabilities.swift`, `Packages/FeedbackKit/Sources/FeedbackKit/AppCapabilities.swift` |

The project instruction's Escape description lists PNG and JPEG. Current source also supports TIFF. This dated discrepancy does not authorize an instruction edit or a format change.

The current copy paths differ between editors. The implementation must settle that difference explicitly. It must preserve ordinary text copy and annotation-object copy while users edit.

Shortcut review, October 27: `captureText` currently defaults to Option+Shift+4 in `App/Sources/Preferences/Tabs/ShortcutSettingsView.swift`. Current capability policy disables that action with standaloneCapture off. The new screenshot shortcut needs a separate fork action and explicit duplicate handling if optional text capture becomes available. Preserve saved shortcut preferences. Never register both actions for the same key or silently change a user's saved key.

### Related decisions and issue history

Read the complete bodies and all comments for these issues:

- [Copy Last Capture Prompt, issue 12](https://github.com/spurs-planks-smithers/Capso/issues/12): the existing shortcut deliberately copies a prompt and runs only during a round.
- [Copy Prompt and End Round, issue 13](https://github.com/spurs-planks-smithers/Capso/issues/13): explicit prompt copy waits for saves and ends the round. Historical prompt copy keeps its separate behavior.
- [Older rounds, issue 115](https://github.com/spurs-planks-smithers/Capso/issues/115): historical round actions must also work beyond the newest five rounds. Reuse that access path when available.
- [Settings and capabilities, issue 119](https://github.com/spurs-planks-smithers/Capso/issues/119): optional tools stay gated. This feature does not imply enabling all standalone tools.

These records contain no approved design for the new image-copy flow. Their earlier tests establish existing prompt behavior and capability boundaries.

### Interview result

All interview decisions are recorded above. Add to Round carries earlier requests and notes forward. The earlier proposal to treat them as context only is rejected. Visual layout still needs review in the running prototype before implementation is retained.

### Implementation approach to prepare

Use Swift, AppKit, and existing image encoding. Keep new behavior in fork-owned files under `App/Feedback/`. Reuse stored annotated and clean files for round captures. Reuse HistoryKit storage through a narrow fork service with an explicit Nextshot directory. Do not enable unrelated standalone capture, network, or cleanup services.

Builder calls for design review: preserve round state during image copy. An explicit image copy takes priority over an earlier pending automatic prompt copy. Preserve available source resolution. Respect the PNG, JPEG, or TIFF format setting while always writing image bytes. Start with one image per copy. If no reliable clean variant exists, disable clean copy with a reason. Existing explicit prompt actions retain their behavior.

HistoryKit supports an explicit storage directory. Reuse its database in a dedicated Nextshot screenshot directory. Keep fixed annotated and clean image files plus a versioned metadata sidecar per entry. The sidecar holds original capture time, version creation time, parent identity, dimensions, marks, inherited instructions, general notes, and clean-image availability. No shared HistoryKit schema change is required. Do not claim retention success until storage completes.

Historical round PNGs can already be resized to a 2000-pixel maximum edge. They cannot restore the original resolution. New screenshot-only history can retain the captured resolution.

Existing captures discarded without storage cannot be recovered. Never remove redactions to reconstruct a clean image. Establish variant availability from reliable stored metadata or provenance. Comparing image pixels alone cannot prove that an image has no annotations.

The combined history uses source identities: a HistoryEntry UUID for screenshot-only entries, or a round folder and capture index for round entries. Read both sources and include the active round once. Load images only when needed. Browsing never copies round images into screenshot storage.

Distinguish image creation time from original capture time. An initial screenshot uses its capture time for both. An edited version uses its commit time as creation time and retains the original capture time in metadata. Annotate Last Screenshot, browsing order, date groups, and 100-entry retention use creation time. Show the original capture time as metadata when it differs. Round references use their stored capture time as their available creation time. Break timestamp ties by stable source identity. Copying an unchanged image renews no timestamp.

Open a focused Screenshot History window from the Nshot menu. Give it thumbnail browsing, date groups, and an app filter. These controls use existing capture metadata. Missing app data belongs in an Unknown App group. Keep text search in its separate backlog issue. Exact layout receives visual review before implementation is retained.

Annotate Last Screenshot resolves the newest image across both sources. Copying the completed edit creates a new screenshot-only UUID and image pair. Preserve the source entry and its original capture time. Never overwrite a round's images, dimensions, marks, notes, manifest, or prompt. A deliberate edited version is a new result, not a duplicate created by browsing.

Add to Round uses the current active round, or starts the default feedback round when none is active. Reuse existing capture storage and note collection through an explicit save-input boundary. Carry the inherited redacted-clean image separately from the visible base image. Apply new redactions to both variants. Preserve known inherited badge numbers in a version sidecar. Start new badges above them and prevent manual number collisions. Legacy sources with unknown badge provenance cannot silently reuse numbers.

Carry inherited mark metadata and instructions into the new capture. Preserve an earlier general note alongside a new general note with explicit labels. Ask for missing and new badge notes without erasing existing answers. Never infer a missing instruction. Scale inherited and new mark geometry together when creating the round export. The resulting prompt includes earlier and new requests. A pending promotion disables repeated submission until it completes. A failed promotion keeps the edited screenshot available.

Retention applies only within the isolated screenshot store. After a successful insert, keep its newest 100 entries and remove older owned files and rows. Startup completes interrupted cleanup. A failed new save does not evict an older entry. Never pass a round reference into deletion. Existing upstream time-based cleanup stays off.

| Work area | Expected files | Responsibility |
| --- | --- | --- |
| Copy coordination | New fork helper under `App/Feedback/`; `FeedbackController.swift` | Resolve image variant, write the clipboard, report success, and manage the finish action. |
| New captures | `FeedbackController.swift`; shared capture selection; narrow editor callback hooks if required | Route a capture purpose to immediate copy or feedback editing. Clear the purpose on success and cancellation. Never switch it during another active selection. |
| Screenshot shortcuts | `App/Feedback/FeedbackShortcuts.swift`, `FeedbackShortcutSettingsSection.swift`; relevant registration hooks | Add Option+Shift+4 and Option+Shift+A independently of round activity. Reject active conflicts and preserve saved optional-tool keys. |
| Screenshot history | `Packages/HistoryKit/Sources/HistoryKit/HistoryStore.swift`, `HistoryEntry.swift`; new fork service | Keep screenshot-only captures without notes or a round. Reuse available storage without activating optional services. |
| Combined index | New fork index under `App/Feedback/`; `FeedbackRoundCache`, `FeedbackLibrary` | Combine source references, include active captures once, and avoid duplicate storage. |
| History window | New fork window and SwiftUI view under `App/Feedback/` | Show thumbnails, date groups, and an app filter. Reuse no optional network or recording service. |
| Annotation versions | New fork annotation coordinator; existing editor | Open the latest combined image. Save each completed edit as a new screenshot-only entry. Preserve source files. |
| Add to Round | Fork editor action; controller save-input boundary; version metadata | Promote a snapshot through the existing note pipeline. Keep clean variants and inherited badge identities accurate. |
| Retention | New fork retention service and isolated HistoryStore | Keep 100 screenshot-only entries. Delete only owned entry folders and matching rows. |
| Saved round captures | `FeedbackStatusItem.swift`, `FeedbackCaptureRowView.swift`, controller | Add accessible image actions while preserving selection, Quick Look, and prompt actions. |
| Clipboard priority | Controller copy and note-completion callbacks | Prevent older automatic work from replacing a newly requested image. |
| Feature control | Existing flag registry and capability resolver, if required | Keep an isolated review switch. Select defaults only after the product flow is approved. |
| User guidance | `FeedbackHelpOverlay.swift`; affected Guides; `CHANGELOG.md` | Explain image copy, feedback save, and history using exact visible labels. |
| Upstream edits | `docs/FORK_NOTES.md` | Record every required upstream hook and its merge risk. |

### Preparation and build sequence

- [x] Inspect existing copy callbacks, stored variants, clipboard encoding, and related issue history.
- [x] Collect initial decisions on automatic copy, screenshot retention, and historical copy defaults.
- [x] Settle inherited-request behavior and record every interview answer.
- [x] Inspect existing History storage and identify a reuse path that preserves capability gates.
- [x] Select separate images and a versioned sidecar in the isolated screenshot store.
- [ ] Show proposed actions against screenshots from the real running app. Confirm labels, clicks, and keyboard behavior.
- [x] Prepare the build sequence in [[2026-10-27-screenshot-image-copy-implementation]].
- [ ] Review the complete design and prototype before retaining implementation.
- [ ] Implement on a dedicated feature branch from current main after design approval. Preserve other local work.
- [ ] Review in signed Nextshot Dev. Keep the feature isolated until Drew accepts the flow.
- [ ] Update affected existing tests and run the repository's required checks before a commit. Add no new test framework or broad gate.
- [ ] Update Guides and release notes after the behavior is verified. Keep public instructions aligned with the released version.
- [ ] Consider the reviewed feature for v0.5.0 through the existing release process.

### Acceptance criteria to finalize

| Scenario | Expected result |
| --- | --- |
| New capture without annotations | The agreed finish action copies image bytes and stores it in screenshot history without notes or a round. |
| Screenshot shortcut | Option+Shift+4 starts instant screenshot copy, with or without an active round. Option+Shift+F keeps feedback capture. |
| Annotation shortcut | Option+Shift+A opens the newest compatible image across screenshot-only entries and round captures. With no image, show a clear message. |
| Optional text-capture conflict | Never register two actions on Option+Shift+4. Preserve saved keys and show the conflict before enabling the second action. |
| New capture with annotations | Copy Image yields the visible rendering, stores screenshot history, and asks for no notes. Save to Round stays separate. |
| New annotation version | Store a new screenshot-only version. Preserve the source entry and round files. Count each screenshot-only version toward 100. |
| Version recency | Editing an older image makes the new version newest by creation time. Keep its original capture time visible as source metadata. |
| Earlier marks | New marks are editable in the reopened editor. Earlier marks stay in the base image. Clean copy removes both generations of non-redaction marks when a reliable clean source exists. |
| Add to Round | Add the current edited snapshot to the active or new round. Collect feedback notes only through this explicit action. Never change the source capture. |
| Inherited requests | Preserve older badge instructions and general notes in the new capture and prompt. Include new requests without overwriting inherited answers. |
| Badge identity | New badge numbers never collide with inherited visible numbers. Each actionable note maps to one intended mark. |
| Saved annotated capture | Copy Image yields the annotated image. Copy Without Annotations uses the supported clean variant. |
| Deliberate redaction | The action follows the approved privacy rule and never silently substitutes an unredacted source. |
| History access | A user finds and copies an earlier screenshot without opening a folder or assembling a feedback package. |
| Combined history | Show each source entry once. Include active and ended round captures. Browsing makes no duplicate image files. |
| Browse methods | Thumbnails, date groups, and app filtering operate on the same combined index. Search is not required to copy or browse. |
| Retention boundary | After the 101st successful screenshot-only save, remove the oldest screenshot-only entry. Keep all round captures. |
| Retention failure | A failed save evicts nothing. Cleanup cannot delete any round path or an image outside the owned screenshot root. |
| Active or ended round | Image copy preserves the round, saved files, numbering, prompt selection, and explicit prompt actions. |
| Pending automatic work | A previous automatic callback does not unexpectedly replace a newly requested image. |
| Missing or unreadable image | Show a useful failure. Do not copy the wrong variant or claim success. |
| Older flattened image | Follow the approved fallback. Do not label a flattened annotated image as a verified clean copy. |
| Clipboard failure | Keep the new capture available. Do not report success or start notes as a recovery side effect. |
| Editor text or selected object | Existing native text and annotation-object copy keep working. |
| Paste into another app | Verify actual image paste in an email editor and one other image-capable app. Do not send anything. |
| Capability defaults | The reviewed image-copy feature works without enabling unrelated optional tools. |

Use existing focused coverage where behavior changes, including `App/Tests/AnnotationCanvasClipboardShortcutTests.swift`, `AnnotationEditorWindowCloseTests.swift`, and `ScreenshotClipboardContentTests.swift`. The final implementation plan names only the checks that its chosen design needs.

### Release and isolation

The only native GitHub milestone currently present is Later. Keep this feature in that backlog and record v0.5.0 as the candidate target in the issue body. Do not create a release milestone or change VERSION during preparation.

No product code, installed app, settings, feature flag, public Guide, or release artifact changes during this planning step. The existing modification in `docs/plans/2026-10-26-feedback-progress.md` belongs to other work and stays untouched.
