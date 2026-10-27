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

Signed Release build succeeds. Installed artifact: Nextshot Dev 0.4.0-dev, build 817. The local screenshotCopy override is on. Both registry defaults remain off. Search issue 125 is open.

Live UI review is pending a switch from another chat's running build 827. The native automation target cannot select build 817 while the higher build owns the app identity. No foreign process is quit. There is no current end-to-end UI verification claim.

Final review finds four important issues. The fixes hide and guard unavailable Pin, reuse saved versions before retention-source reads, retain capture purpose through fallback delivery, and commit inherited general notes with the round capture.
