# Esc on a marked capture: copy, save, keep the round open (#195)

Target release: 0.6.0. Behavior decided by Drew on 2026-10-31. This plan covers the build only.

## Behavior

In the inline editor, Esc on a capture that has marks:

1. Renders the annotated image, as Command+S does.
2. Copies it to the clipboard in the clipboard format setting (PNG, JPEG, or TIFF). Never a file path.
3. Saves the capture into the round with no notes. The note panel does not open.
4. Closes the editor and shows a toast: "Marked screenshot copied and saved to the round".

The round stays active and keeps its numbering. Esc never ends it. With no active round, the save starts the round "feedback", as Command+S does. The save copies no capture prompt, so the image stays on the clipboard.

Unchanged: Esc while text is typed commits the text. Esc with no marks copies only and saves nothing. A failed copy keeps the editor open and beeps. The inline editor has no crop mode, so the "Esc in crop mode leaves crop mode" case applies to the full editor only, which this monitor never handles.

## Items

| Item | File | Change |
| --- | --- | --- |
| 1. Route Esc with marks | `App/Feedback/FeedbackController.swift` (`installKeyMonitor`) | The monitor takes the capture result. An empty editor keeps `copyScreenshotAndClose`. A marked editor calls the new `copyMarkedAndSave`. |
| 2. Copy and save | `App/Feedback/FeedbackController.swift` (`copyMarkedAndSave`) | Render with `AnnotationRenderer.render`, copy, bump `clipboardRevision`, save without notes, close, toast after the store result. |
| 3. Save without the note panel | `App/Feedback/FeedbackController.swift` (`save`) | New `showNotes` parameter, default true. When false, close any open note panel, skip a new one, and start Jev at once, as the panel's `onEnd` does. |
| 4. Help box | `App/Feedback/FeedbackHelpOverlay.swift` | The Esc line with marks reads "Copy marked, save, close". |
| 5. Docs | `AGENTS.md`, `CHANGELOG.md`, `site/guides/.../shortcuts.mdx`, `settings/capture.mdx` | Replace the "step back" wording. One line under Unreleased. |

`AnnotationEscapePolicy` stays untouched. No upstream file changes, so `docs/FORK_NOTES.md` needs no new row.

## Hook points and reuse

- The key monitor already runs before the editor's own Esc button, so the fork decides first.
- `save(rendered:objects:result:)` stores the capture, runs OCR, writes `feedback.json`, and registers a save task so End Round waits for it. The change reuses all of it.
- With the `screenshotCopy` capability on (off by default), the empty-editor Esc uses `ScreenshotWorkflow.copyFresh`, which saves to History. The marked case does not. It copies and saves as a round capture, which History lists through its round index. A first draft used `copyFresh` for both. A review showed it would list the capture twice and add an alert and a toast of its own, so the final code has one path.
- Command+S closes an earlier capture's open note panel when it opens a new one. The no-note save closes it too, so it never stays open.

## Checks on a save with empty notes

- `feedback.json`: marks carry no `instruction`, and `note` is nil. The note panel's "Esc skips a step" path already writes this shape.
- `manifest.md`, `prompt.md`, and the capture prompt: render a capture with unanswered items. Check one real bundle after the live test.
- Recent Rounds: a round that holds a capture is listed. The title comes from the first reviewer words, else the day and time.
- Jev: `startJev` waits for the stored capture, the answers, and the screen text. The note coach labels each item "no note", which is the labeled empty case.
- OCR: runs in the save task as for Command+S.

## Risks

| Risk | Handling |
| --- | --- |
| A double Esc starts two saves | The editor closes in the same call, so the monitor is gone before the second key. |
| The toast claims a save that failed | The toast waits for the store result. A failed save says so. |
| A pending prompt copy replaces the image | Bump `clipboardRevision` right after the image copy, so an earlier capture's pending prompt copy is skipped. |
| Both sibling PRs edit `FeedbackController.swift`, `AGENTS.md`, `CHANGELOG.md` | The second to merge rebases on `origin/main`, keeps both changes, and re-runs build and tests. |
| Guides describe unreleased behavior | Edit the text. Leave `reviewedFor` at 0.5.0 until Drew checks a 0.6.0 build. |

## Verification

- Existing tests: FeedbackKit and the app tests command. No new tests (personal repo rule).
- Build: `scripts/build-local.sh Release --no-install`.
- Live run in the installed Nextshot Dev: skipped (Drew, 2026-10-31). A Dev build 909 with a browser bridge (pid 52229) runs from the installed path, and a newer launch would yield to it or end it. Drew tests from his next build.
- In-process check instead: a throwaway test (never committed) opened the inline editor, added two counters, and sent a real Esc key event through `NSApp.sendEvent`, so the fork key monitor handled it. It checked the clipboard image, one saved capture with no notes, the active round, the closed editor, a second Esc, and Esc with no marks.
- Logs for Drew's run: `/usr/bin/log show --last 10m --predicate 'subsystem BEGINSWITH "com.drewschulz.nextshot"'`. Look for "Esc on a marked editor".
