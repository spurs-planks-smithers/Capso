# Rolling Round development trial

Rolling Round stays in Later and outside v0.5.0. `rollingEnabled` starts absent, which means off. No release flag changes accompany this work.

## Use

1. Enable Rolling Round trial in the popup.
2. Choose Arm current tab. Approve that site's access and offscreen permission.
3. Reproduce the issue. Return to the popup and choose Rolling Round, or press Alt+Shift+G.
4. Move through the actual captured frames. Mark the failure moment first.
5. Review the local observed steps. Edit, remove, or add a step if needed. Range edits are optional.
6. Continue to the existing marks and notes screen. Save there.

Each save creates a separate ended browser round. Optional native delivery uses the same selected payload. An ordinary active round remains active. Browser saving works without the Mac app.

## Retention and privacy

Masked independent JPEG frames stay only in offscreen memory. History retains at most 60 recorded seconds, 24,000,000 accounted bytes, and 1,000 combined events. Time spent paused does not consume that interval. Frames sample at most once per second. Page changes can cause missing frames. There is no audio or typed-value capture.

Pauses compose: focus, review, navigation, manual, ordinary area selection, and snapshot availability. Returning to a tab clears only focus. Same-origin navigation reinjects observers. Cross-origin navigation preserves history but requires explicit re-arm, which starts fresh history.

Review has no inactivity timer. Service-worker restart preserves the owner metadata and offscreen images. Browser exit clears memory. Browser startup removes orphaned extracted drafts. Stop, source closure, permission loss, and disabling the trial clear unsaved history and the extracted draft. Save or cancel clears the extracted draft and resumes eligible tracking. Saved rounds remain intact.

The frame proof uses capture-time source metadata and matching uniform image geometry. Private fields and embedded frames are covered before image retention. Missing capture proof skips a frame. The extension adds no overlay or animation pause while tracking. Ordinary area selection pauses rolling sampling first.

The report contains only selected issue/clean images, at most 12 selected key frames, accepted steps, selected diagnostics, and optional selected animation. Short low-color excerpts use a compact local GIF encoder. Other excerpts use VP8 WebM. Both preserve image aspect. The soft target is 5,000,000 bytes. Animation is omitted when the estimated selected bundle exceeds that target. An oversized still bundle saves normally.

## Local suggestions and extension hooks

A captured visible alert with explicit failure wording can produce an optional issue hint within one second. Other errors produce no hint. After manual issue selection, local step candidates come from indexed observed clicks in the suggested recent interval. The default starts near ten seconds before the issue, within its continuous segment. Suggestions describe observations, not causes or new instructions.

`nextshot-rolling` messages support `status`, `open`, `pause`, `resume`, `preview`, `select`, `cancel`, and `stop`. `select` requires the current owner identity and revision. It writes only selected assets into the standard draft store. Selected drafts use `Capture.kind = rolling` and optional `keyFrames` entries with `at`, `file`, `width`, and `height`.

The review page exposes `nextshotRollingSelection.snapshot()`: owner identity, owner revision, selection revision, chosen bounds, issue, and edited steps. `apply(revision, suggestions)` rejects stale revisions and returns in-range suggestions without changing reviewer edits. Later assistance must retain this behavior. No model request runs during tracking.

## Verification limits

Scratch headless Chromium tests use the production browser APIs with a copied manifest that pregrants recording permissions. They verify media and lifecycle behavior. A real toolbar permission grant and native app import remain integration acceptance checks. Lightweight diagnostics do not provide full console or network coverage. The UI and saved coverage metadata state that limit.
