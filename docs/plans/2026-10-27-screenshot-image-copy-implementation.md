# Screenshot Image Copy Implementation Plan

> For agentic workers: use superpowers:subagent-driven-development or superpowers:executing-plans to implement these tasks. This document prepares the work. It does not start implementation.

**Goal:** Copy screenshots directly, reopen the latest image with Option+Shift+A, and browse local history with safe round promotion.

**Architecture:** Keep screenshot-only images in a dedicated HistoryKit store. A fork index references that store and existing round captures. Fork coordinators handle capture purpose, clipboard writes, immutable annotation versions, and explicit Add to Round.

**Tech stack:** Swift 6, AppKit, SwiftUI, HistoryKit, FeedbackKit, AnnotationKit, SharedKit, and KeyboardShortcuts. Add no dependency.

**Spec:** [[2026-10-27-screenshot-image-copy]]. Read its confirmed requirements and builder calls before implementation.

### Global constraints

- Work on a dedicated feature branch from current main. Preserve unrelated work. Recheck source drift before building.
- Keep new native code under `App/Feedback/`. Keep upstream edits narrow and log each in `docs/FORK_NOTES.md`.
- Register Option+Shift+4 for instant capture and Option+Shift+A for annotation. Keep Option+Shift+F for feedback.
- Use one new non-Jev capability, `screenshotCopy`, independent of standaloneCapture. Start off in both channels for isolated review.
- Keep all unrelated capabilities and Jev flags unchanged. No new network path or key read.
- Store images under `~/Library/Application Support/Nextshot/ScreenshotHistory/`. Round enumeration must ignore this non-round directory.
- Keep the newest 100 screenshot-only versions. Retention never deletes round files or modifies an existing round capture.
- Preserve redactions in every clean variant. Keep original and version timestamps distinct.
- Search remains in [issue 125](https://github.com/spurs-planks-smithers/Capso/issues/125). Do not implement it here.
- Update only affected existing tests. Add no test framework, broad gate, or standalone new test suite.

### Review focus

- A new version of an older image becomes the latest image without changing its original capture date.
- Redactions survive multiple annotation generations and Copy Without Annotations.
- The 101st successful save removes only the oldest screenshot-only version. A failed save removes nothing.
- Round promotion carries inherited instructions and general notes with unique, correctly mapped badge numbers.
- An older asynchronous prompt copy cannot overwrite a newer explicit image copy. Explicit prompt commands still work.

### Shared types and files

Create `App/Feedback/ScreenshotHistoryModel.swift` for the following types. These are implementation decisions for review, not additional product requirements.

| Type | Contract |
| --- | --- |
| `ScreenshotSourceID: Hashable, Codable, Sendable` | `.local(UUID)` or `.round(folderName: String, captureIndex: Int)` |
| `ScreenshotMetadata: Codable, Sendable` | Schema version 1, UUID, parent source, createdAt, capturedAt, PixelSize, app/title, `[FeedbackMark]`, optional general note, and reliable-clean availability |
| `ScreenshotWrite: Sendable` | Metadata plus annotated PNG Data and optional redacted-clean PNG Data |
| `ScreenshotHistoryItem: Identifiable, Sendable` | Source ID, timestamps, app/title, dimensions, annotated URL, optional safe clean URL, and mark/note snapshot |
| `ScreenshotImageVariant` | `.annotated` or `.withoutAnnotations`; never implies an unredacted original |
| `ScreenshotCapturePurpose` | `.feedback` or `.instantScreenshot`; the coordinator owns one accepted request at a time |
| `FeedbackPromotionInput` | Annotated/clean PNG data, dimensions, original capture metadata, combined marks with existing instructions, inherited general note, and badges needing answers |

### Task 1: Isolated storage and retention

**Create:** `ScreenshotHistoryModel.swift`, `ScreenshotHistoryStore.swift`, and `ScreenshotRetention.swift` under `App/Feedback/`.

**Coverage:** R5, R10, R13, and R16.

**Interfaces:** `ScreenshotHistoryStore.init(rootURL: URL) throws`; `save(_ input: ScreenshotWrite) async throws -> ScreenshotHistoryItem`; `items() async throws -> [ScreenshotHistoryItem]`; `pruneToLatest(_ limit: Int) async throws`.

- [ ] Use `HistoryStore(directory:)` at the dedicated root. Write `capture.png`, `clean.png` when reliable, `thumbnail.jpg`, and `screenshot.json` per UUID.
- [ ] Stage complete entry files before inserting the row. Surface save failure. Recovery removes only staging files or finishes explicitly recorded cleanup.
- [ ] Keep HistoryEntry.createdAt equal to version creation time. Keep original capture time in the sidecar. An unchanged copy creates no version.
- [ ] After a successful save and during recovery, prune only owned entries beyond 100. Resolve deletion through owned UUIDs, never arbitrary indexed paths.
- [ ] Verify empty storage, 100 and 101 entries, equal timestamps, interrupted save, failed insert, missing files, and an external-path rejection. Verify round files stay intact.

### Task 2: Combined history and browse window

**Create:** `ScreenshotHistoryIndex.swift`, `ScreenshotHistoryWindow.swift`, and `ScreenshotHistoryView.swift` under `App/Feedback/`. **Modify:** `FeedbackStatusItem.swift`.

**Coverage:** R1, R3, R6, R7, R14, and R19.

**Interfaces:** `ScreenshotHistoryIndex.items(local: [ScreenshotHistoryItem], rounds: [FeedbackRound], rootURL: URL) -> [ScreenshotHistoryItem]`; `ScreenshotHistoryWindow.show(items: [ScreenshotHistoryItem])`.

- [ ] Adapt compatible rounds through existing library/cache APIs. Add the active round once. Identify round images by folder and capture index.
- [ ] Sort by image creation time and stable source ID. Round references use capturedAt. Load thumbnails only for visible rows.
- [ ] Add Screenshot History to the Nshot menu. Show a thumbnail grid, date groups, and app filtering. Use Unknown App for missing app metadata.
- [ ] Offer Copy Image, Copy Without Annotations when reliable, and preview. Preserve existing Recent Rounds selection and Quick Look behavior.
- [ ] Render the running native window with empty, mixed, long-title, and large histories. Review every visible state before retaining the layout. Keep search absent.

### Task 3: Capability, instant capture, and clipboard

**Create:** `ScreenshotCaptureCoordinator.swift` and `ScreenshotImageCopy.swift` under `App/Feedback/`. **Modify:** `FeedbackController.swift`, `FeedbackShortcuts.swift`, `FeedbackShortcutSettingsSection.swift`, and `Capabilities.swift` in that folder; `Packages/FeedbackKit/Sources/FeedbackKit/FeatureFlags.swift`, `Packages/FeedbackKit/Sources/FeedbackKit/AppCapabilities.swift`, and `scripts/nextshot-flags.sh`.

**Coverage:** R2, R4, R9, and R11.

**Interfaces:** `ScreenshotCaptureCoordinator.capture()`; `receive(_ result: CaptureResult)`; `cancel()`; `ScreenshotImageCopy.copy(_ image: CGImage, format: ScreenshotClipboardFormat) -> Bool`.

- [ ] Add `screenshotCopy` to the existing registry, script, and launch-frozen capability policy. Update affected registry expectations.
- [ ] Reuse shared feedback selection with an accepted capture purpose. Reject concurrent capture before setting that purpose. Clear it on completion, cancellation, and selection failure.
- [ ] Register Option+Shift+4 independently of round activity. Expose the recorder in Settings. Preserve dormant Capture Text settings and refuse an active collision.
- [ ] On successful selection, copy image bytes immediately through ImageUtilities, close selection, and persist screenshot history without notes or a round.
- [ ] Route editor Copy and unmarked Escape through the same image-only service. Preserve text and selected-object copy. Retain an image on copy/save failure.
- [ ] Track explicit clipboard intent. Suppress a stale automatic prompt write after a newer image request. Do not suppress a subsequent explicit prompt command.
- [ ] Verify both round states, cancellation, repeat hotkeys, clipboard formats, saved file-path preferences, and clipboard failure. Confirm no optional service starts.

### Task 4: Annotation versions and hotkey

**Create:** `ScreenshotAnnotationCoordinator.swift` under `App/Feedback/`. **Modify:** fork shortcut/menu wiring; `App/Sources/AnnotationEditor/InlineAnnotationEditorWindow.swift`, `AnnotationEditorWindow.swift`, `AnnotationEditorView.swift`, and `AnnotationCanvasNSView.swift` in that folder for narrow copy and badge-policy hooks.

**Coverage:** R3, R10, R12, R15, R16, and R18.

**Interfaces:** `ScreenshotAnnotationCoordinator.annotateLatest(in items: [ScreenshotHistoryItem])`; `copyVersion() async throws -> ScreenshotHistoryItem`; `promotionInput() throws -> FeedbackPromotionInput`.

- [ ] Register Option+Shift+A independently of round activity. Open the newest indexed image. Give a clear empty-history response.
- [ ] Flatten earlier marks into the visible base. Permit new marks only. Keep geometry fixed so inherited and new coordinates remain compatible.
- [ ] Reserve inherited badge numbers. Start new badges above their maximum and reject manual collisions. Keep inherited mark geometry and instructions in the sidecar.
- [ ] On Copy Image, save one new version with the source preserved. Rebuild its clean variant from the inherited clean image plus new redactions.
- [ ] For legacy sources without reliable clean data or badge provenance, offer ordinary image copy. Explain unavailable clean copy or numbered round promotion. Never infer badge identities from pixels.
- [ ] Verify a round source, multiple edit generations, edits of older images, inherited badges, redactions, cancellation, and no changes. Confirm no source is overwritten.

### Task 5: Add to Round with inherited requests

**Create:** `ScreenshotRoundPromotion.swift` under `App/Feedback/`. **Modify:** `App/Feedback/FeedbackController.swift`; `App/Sources/AnnotationEditor/AnnotationEditorWindow.swift`, `AnnotationEditorView.swift`, and `AnnotationToolbar.swift` for an optional fork action. Reuse FeedbackRoundStore APIs.

**Coverage:** R17 and R21.

**Interfaces:** `ScreenshotRoundPromotion.add(_ input: FeedbackPromotionInput) async throws`; controller accepts explicit annotated/clean images, combined marks, inherited notes, and unanswered badges.

- [ ] Add Add to Round in the screenshot editor. Preserve a completed edited version before promotion. Reuse the active round or `startIfNeeded`.
- [ ] Scale inherited and new marks together. Preserve every inherited badge instruction. Use unique destination capture numbering without changing visible badge IDs.
- [ ] Present missing/new badge questions. Keep inherited answers. Combine inherited and new general notes under explicit labels rather than replacing earlier text.
- [ ] Reuse local OCR, save waiting, and explicit feedback completion. The new prompt makes both inherited and new requests actionable.
- [ ] Disable repeated promotion while pending. Keep the edited screenshot on failure. Never overwrite the source round or duplicate a pending submission.
- [ ] Verify older instructions, a missing earlier instruction, inherited general notes, multiple inherited generations, no active round, and a round ending during promotion.

### Task 6: Review, documentation, and release preparation

**Modify:** affected existing tests, `CHANGELOG.md`, `docs/FORK_NOTES.md`, affected Guides, and the bundle guide only if its contract changes.

**Coverage:** R7, R8, and R20, plus the complete acceptance matrix.

- [ ] Review the real Dev flow first: Option+Shift+4, Paste, Option+Shift+A, new version, clean copy, Add to Round, and both prompt generations.
- [ ] Verify actual image paste in an email editor and a second app. Send nothing. Check default-off and reviewed-enabled states.
- [ ] Run affected existing tests and required repository checks before each commit. Before a trial build, run the required JevKit Release command below.
- [ ] Build only Nextshot Dev for local review. Update exact UI instructions and capture real screenshots after acceptance. Add no unreleased public instructions.
- [ ] Keep both GitHub issues separate. Consider this reviewed feature for v0.5.0. Use the existing release command only when a release is authorized.

### Verification commands

Run only during implementation, after source changes justify these checks. No code tests are needed to publish this plan.

```bash
swift test --package-path Packages/FeedbackKit
swift test --package-path Packages/HistoryKit
swift test -c release -Xswiftc -enable-testing --package-path Packages/JevKit
xcodegen generate
xcodebuild test -project Capso.xcodeproj -scheme Capso -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:CapsoTests
scripts/build-local.sh Release
```

Also run the existing required CI package checks before a commit. Do not add a PRODUCT_NAME override or bypass any existing hook.

### October 27 execution note

The implementation keeps capture, annotation, clipboard intent, and promotion orchestration in App/Feedback/ScreenshotWorkflow.swift. Dedicated storage, retention, index, and history-view files retain their planned boundaries. This combines several planned coordinator files to reduce callback duplication. A later split can change file ownership without changing the product contract.

The feature remains isolated on feature/screenshot-image-copy. No text search is implemented. Registry defaults remain off. The installed Dev trial has a local override for review.
