# Repeat area key (Option+Shift+G, issue #194)

Release target: 0.6.0. Drew decided the behavior on 2026-10-31. This plan covers the build only.

## Behavior

- Option+Shift+G captures the same rectangle, on the same display, as the last Option+Shift+F capture. It skips the selector.
- The result follows the normal feedback flow: inline editor on the counter tool, Command+S, notes, round auto-start.
- The key is always on, like Option+Shift+F. It is not a round key.
- With no previous area, the key runs exactly the Option+Shift+F path and opens the selector. It never does nothing.
- Option+Shift+C stays "Copy Last Capture Prompt".

## What the investigation found

| Question | Answer |
| --- | --- |
| What does Capture Previous Area store? | `AppSettings.lastCaptureSelection`, saved in UserDefaults. Area is `x, y, width, height, screenID` in screen-local, bottom-left points. |
| Does a feedback capture write it? | Yes, `showFrozenOverlay` writes it on every selection. |
| Why not reuse it? | Fullscreen, All-in-One, and other modes overwrite the same key. "The last Option+Shift+F area" needs its own record. |
| What does a feedback result carry? | `CaptureResult.captureRect` (display-local, top-left points) and `displayID`, for the frozen path and the fallback path. |
| How does a known rect reach the sink? | `CaptureCoordinator.performAreaCapture(rect:screen:)` is private. It sets `.feedback` only when `feedbackRequestID` is set. |

## Design

1. Record. `FeedbackController` stores `captureRect` and `displayID` in the feedback sink for every `.area` result that is not an instant screenshot (Option+Shift+4). The record lives in memory only.
2. Replay. `FeedbackController.repeatCapture()` finds the screen, converts the stored rect to screen-local bottom-left points, and calls a new coordinator method. If no usable area exists, it calls `capture()`.
3. Coordinator hook. `CaptureCoordinator.captureAreaForFeedback(rect:screen:)` mirrors `captureAreaForFeedback()`. It sets a request token and `.feedback`, then calls `performAreaCapture`. Failure and cancel reuse `cancelFeedbackCapture`.

### Decisions

- In memory only. A relaunch clears the area, which matches "fresh launch" in the issue. No display check is needed across launches.
- A usable area needs a connected display with that `displayID` whose current size still holds the rect. Otherwise the key opens the selector.
- An open capture (selector, editor, note panel) makes the key beep and do nothing. The new capture would include the open editor. The no-area fallback is unchanged, so it matches Option+Shift+F.
- No Nshot menu row. The menu shows no capture row during a round, so one row for G would stand alone. Settings > Shortcuts lists the key.
- The help box gets one line in the between-captures stage: "Capture the same area again".
- `Capabilities.allowsShortcut` stays unchanged. It filters upstream's keys. The Nextshot keys sit in `nextshotKeys`, and `FeedbackShortcutGuard` already checks that list.

## Files

| File | Change | Upstream? |
| --- | --- | --- |
| `App/Feedback/FeedbackShortcuts.swift` | Add `feedbackRepeatCapture` and put it in `nextshotKeys` | no |
| `App/Feedback/FeedbackController.swift` | Record the area in the sink, add `repeatCapture()`, register the key, add it to the always-on set in `updateRoundShortcuts()` | no |
| `App/Feedback/FeedbackShortcutSettingsSection.swift` | Add a row | no |
| `App/Feedback/FeedbackHelpOverlay.swift` | One line in the between stage | no |
| `Packages/FeedbackKit/.../SettingsVisibilityFlag.swift` | Add `shortcutsCoreFeedbackRepeatCapture` | no |
| `App/Sources/Capture/CaptureCoordinator.swift` | Add `captureAreaForFeedback(rect:screen:)` | yes, logged in `docs/FORK_NOTES.md` |
| `AGENTS.md`, `.github/README.md`, `docs/reference/2026-10-27-settings-catalog.md` | Hotkey text | no |
| `site/guides/...` and `make-shortcuts.py` | Shortcuts, multiple captures, and the PDF sheet | no |
| `CHANGELOG.md` | One line under Unreleased | no |

## Risks

- The sibling session (#195, Esc on a marked capture) edits `FeedbackController.swift`, `AGENTS.md`, and the Unreleased section. Keep edits local to new blocks. Rebase before merge.
- The library removes a hotkey by key combination. `updateRoundShortcuts()` must treat the new key as always on, or a round key that shares its combination would turn it off between rounds.
- The replayed capture uses ScreenCaptureKit, not a frozen frame. It shows the live screen at the key press. Upstream's Capture Previous Area does the same.
- A held Option key can change the pointer or an app's state. The capture includes no cursor unless the user chose it.
- Guides document released behavior. The new text ships with 0.6.0, so `reviewedFor` stays at 0.5.0 until Drew checks the 0.6.0 app. The Settings screenshot still shows five rows.

## Verify

- `swift test --package-path Packages/FeedbackKit`, then the app tests from `AGENTS.md`.
- Live test in Nextshot Dev: a first G with no area opens the selector. After an F capture, G captures the same rectangle with and without a round. Settings > Shortcuts shows the row and refuses a shared key.
