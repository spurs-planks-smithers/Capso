# Screenshot Copy: Nextshot Dev Review

Issue: [Screenshot image copy, 123](https://github.com/spurs-planks-smithers/Capso/issues/123). Separate open backlog: [Search capture history, 125](https://github.com/spurs-planks-smithers/Capso/issues/125).

This build prepares the screenshot workflow for local testing. It does not publish v0.5.0. The new screenshotCopy capability defaults off. The installed Dev trial receives a local override only.

### Review outline

| Action | Expected result |
| --- | --- |
| Option+Shift+4 and area selection | Image reaches the clipboard immediately. Screenshot history saves it. No editor, notes, or round opens. |
| Option+Shift+A | The newest image across both sources opens for new marks. Earlier marks stay flattened. |
| Copy Image from annotation | A new history version saves. The source stays intact. No feedback notes appear. |
| Copy Without Annotations | The clean image retains every deliberate redaction. Unverified old clean files remain unavailable. |
| Add to Round | Active or new round receives a new capture. Earlier requests and notes remain actionable. New badges receive unique numbers. |
| Screenshot History | Thumbnails, creation-date groups, and app filters use one combined index. Search is absent. |
| More than 100 screenshot-only versions | Only older owned screenshot versions expire. Round files remain intact. |

### Source and safety limits

Creation time determines image recency and screenshot retention. Original capture time remains source metadata. An unchanged copy creates no new version.

Earlier round exports can be smaller than the original capture. The app does not reconstruct missing resolution or editable marks. A legacy image without reliable mark provenance cannot become numbered feedback through a guessed badge number.

The existing PNG, JPEG, and TIFF clipboard setting remains in use. Image copy always writes image data rather than a file path. All new behavior stays local.

### Public documentation review

Reviewed the first-handoff, reuse-rounds, and shortcuts Guides for this change. Their released default workflow does not change while screenshotCopy stays off. Keep public instructions and reviewedFor at the released version. Capture guide media from the accepted release before publishing the new workflow.

### Verification record

Baseline FeedbackKit: 341 existing tests pass. Worker validation covers 117 AnnotationKit tests and focused editor tests. Synthetic native storage probes cover 100-entry retention, failed saves, interrupted journals, and root/child symlink rejection. Final integrated checks and live Dev results are recorded after the build.

Final existing checks pass: SharedKit 279, AnnotationKit 117, CaptureKit 95, RecordingKit 27, OCRKit 8, FeedbackKit 341, HistoryKit 4, CapsoTests 247, and JevKit Release 369. Total: 1,487 tests. The first Jev run hits deadline thresholds during concurrent builds. Its unchanged rerun passes after build contention ends.

Signed Release build succeeds. Installed artifact: Nextshot Dev 0.4.0-dev, build 820. The local screenshotCopy override is on. Both registry defaults remain off. Search issue 125 is open.

Drew approves switching to issue 123. The other Dev trial is stopped. Native automation then stalls while opening a local TextEdit fixture. Another session installs build 864 during that delay. The approved screenshot trial is restored as build 820. The intervening build is preserved at /private/tmp/nextshot-123-superseded-dev-864.app. The launch log confirms build 820 runs.

Live image paste and round-promotion checks remain pending. Selecting the menu-only app through native automation times out. Its synthetic capture shortcut reaches TextEdit as a character and produces no screenshot. This result does not verify global shortcut delivery or image capture. The local fixture is saved under /private/tmp. The PR remains draft for Drew's hands-on Dev review.

Final review finds four important issues. The fixes hide and guard unavailable Pin, reuse saved versions before retention-source reads, retain capture purpose through fallback delivery, and commit inherited general notes with the round capture.

Implementation and testing handoff: [draft PR 149](https://github.com/spurs-planks-smithers/Capso/pull/149). Search remains tracked in the open issue 125.

The handoff query reports no hosted workflow run for the draft PR. The 1,487-test result refers to the existing local checks.

Final isolation check: unique badge enforcement is enabled only in screenshot version editors. Existing editors retain their earlier numbering behavior while the capability is off. AnnotationKit 117, CapsoTests 247, and JevKit Release 369 pass again after this change. Signed build 820 supersedes the earlier build 817.

### Follow-up source review fixes

Instant-copy failures now open Screenshot Recovery with the captured pixels and Try Copy Again. This path retains the image before clipboard encoding or history saving succeeds. Discard Screenshot explicitly releases it. It starts no feedback notes.

A screenshot shortcut that conflicts at launch receives its handler when Settings changes it to an available key. Registration remains conditional because KeyboardShortcuts registers onKeyDown immediately and disables by key combination. Current-main Settings visibility and grouping remain intact. Both screenshot rows have independent visibility keys.

Follow-up verification passes on the reconciled source: SharedKit 279, AnnotationKit 117, CaptureKit 95, RecordingKit 27, OCRKit 8, FeedbackKit 341, HistoryKit 4, JevKit Release 369, and CapsoTests 247. Total: 1,487 existing checks. App compilation and the full app test command succeed. Native failure recovery and repaired-shortcut delivery still require the acceptance review. No new tests or gates are added.

### Native stale-row correction

The native review finds that a browser row can predate the completed note panel. Opening that cached round capture then repeats inherited badge questions and loses earlier notes in the promoted result. Annotation now resolves the selected source identity against the current index before constructing the editor. A missing source fails instead of using stale metadata. Annotate Latest already reads the current index and opens that fresh result directly.

Round JSON serializes capture dates to whole seconds. Screenshot sidecars retain fractional seconds. Provenance checks now compare dates at the round format's precision. Source identity, image size, and complete marks still match. A Foundation encoding probe reproduces the earlier exact-date mismatch and confirms the stored-precision comparison.

A scratch probe compiles the real index and metadata sources. The old index hides clean copy for a verified unmarked capture after the round timestamp loses fractions. The fixed index keeps clean copy available. A second probe step resolves the same source identity with newly saved badge instructions and a general note. It preserves those current values. No UI or stored user data enters the probe.
