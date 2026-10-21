# Fork notes

Fork: `spurs-planks-smithers/Capso`. Upstream: [lzhgus/Capso](https://github.com/lzhgus/Capso). Fork base: `8f07fb6` (v1.2.5).

This file logs every edit to an upstream file: the file, the reason, the lines, and the upstream PRs at risk of a merge conflict. Read it before each upstream merge.

## Upstream file edits

Line numbers are in the fork's version of each file. Added Swift lines carry a `Fork:` comment. Changed lines inside existing `switch` arms and lists do not (`CaptureCoordinator.swift` 90, 99, 172, 1644-1645), so use this table to find them.

Compile risk: `PostCaptureAction.feedback` is a new enum case. An upstream change that adds an exhaustive `switch` over `PostCaptureAction` fails to compile after a merge until it handles `.feedback`.

| File | Reason | Lines | Upstream PRs at risk |
|---|---|---|---|
| `App/Sources/Capture/CaptureCoordinator.swift` | `feedbackSink` property that `FeedbackController` sets | 57-59 (added) | none |
| `App/Sources/Capture/CaptureCoordinator.swift` | `PostCaptureAction.feedback` case | 86 (added) | none |
| `App/Sources/Capture/CaptureCoordinator.swift` | `.feedback` in `playsShutterSound` and `savesOriginalCaptureToHistory` (both false, as for the editors) | 90, 99 (changed) | none |
| `App/Sources/Capture/CaptureCoordinator.swift` | `.feedback` skips auto-Beautify, as the editors do | 172 (changed) | none |
| `App/Sources/Capture/CaptureCoordinator.swift` | `captureAreaForFeedback()` starts an area capture with `.feedback` | 421-425 (added) | none |
| `App/Sources/Capture/CaptureCoordinator.swift` | `showFrozenOverlay` cancel handler resets `pendingAction`, so Esc on a feedback selection cannot send the next fullscreen or window capture to the session (Drew approved this hook point on 2026-10-20). It also fixes upstream's same leak for `.annotate` and `.clipboard`. | 987 (added) | none |
| `App/Sources/Capture/CaptureCoordinator.swift` | `handleCaptureResult` arm: `.feedback` calls `feedbackSink` | 1644-1645 (added) | none |
| `App/Sources/AppDelegate.swift` | One call to `FeedbackController.shared.start(captureCoordinator:settings:)` after `registerGlobalShortcuts()` | 88 (added) | [#349](https://github.com/lzhgus/Capso/pull/349), [#291](https://github.com/lzhgus/Capso/pull/291) |
| `project.yml` | `FeedbackKit` local package | 50-51 (added) | [#349](https://github.com/lzhgus/Capso/pull/349), [#348](https://github.com/lzhgus/Capso/pull/348) |
| `project.yml` | `App/Feedback` source path for the Capso target | 71 (added) | [#349](https://github.com/lzhgus/Capso/pull/349), [#348](https://github.com/lzhgus/Capso/pull/348) |
| `project.yml` | `FeedbackKit` dependency for the Capso target | 98 (added) | [#349](https://github.com/lzhgus/Capso/pull/349), [#348](https://github.com/lzhgus/Capso/pull/348) |
| `App/Resources/Info.plist` | Security rec 1 (approved 2026-10-20): `SUFeedURL` removed, `SUEnableAutomaticChecks` set to false | 63-64 (removed), 66 (changed) | none |
| `App/Tests/UpdateManagerTests.swift` | Rec 1 follow-on: `ShippedUpdateDefaultsTests` asserted automatic checks are on. It now asserts they are off, as `testAutomaticChecksAreOffInTheFork`. | 40-42 (changed, 1 comment line added) | none |
| `App/Sources/Preferences/Tabs/OCRSettingsView.swift` | Security rec 2 (approved 2026-10-20): the provider picker lists only `.apple`. Provider code stays until a later removal branch. | 51 (changed) | [#348](https://github.com/lzhgus/Capso/pull/348) |
| `App/Sources/Preferences/PreferencesView.swift` | Security rec 3 (approved 2026-10-20): Cloud Share is left out of the settings tab list. "Capture Area and Share" can still open its content (`CaptureCoordinator.swift:401`). | 95 (changed) | [#348](https://github.com/lzhgus/Capso/pull/348) |

### Why the coordinator hook is smaller than the plan's estimate

The plan estimated about 35 lines in `CaptureCoordinator.swift`, with the coordinator opening the editor and passing the rendered image, the clean image, and the document objects to the sink. The fork passes only the `CaptureResult` instead. `FeedbackController` opens the inline editor itself in a fork file and reads `document.objects` in its own save closure. The inline editor renders with no crop and no canvas growth, so `CaptureResult.image` is the clean image at the same size. The result is 14 added lines and 3 changed lines in the upstream file.

## Fork-only files

| Path | Purpose |
|---|---|
| `AGENTS.md`, `CLAUDE.md` | Agent instructions. `CLAUDE.md` imports `AGENTS.md`. |
| `docs/plans/2026-10-20-feedback-sessions-phase1.md` | Phase 1 plan |
| `docs/FORK_NOTES.md` | This log |
| `docs/decisions/2026-10-20-feedback-bundle-format.md` | Why the bundle has its format |
| `docs/SECURITY_BASELINE.md` | Network code, entitlements, dependencies, and recommendations |
| `Packages/FeedbackKit/` | Session model, store, image sizing, naming, screen-text cleaning, window picker, preview crop, note parser, OCR matcher, manifest and prompt writers, tests |
| `App/Feedback/` | Feedback controller (editor, Esc rule, save pipeline), mark mapper, window-title lookup, PNG export, note panel with circle previews, status item, shortcut panel, App Intents |
| `scripts/build-local.sh`, `scripts/local-project.yml` | Signed local build. Force-added: upstream ignores `scripts/`. |
| `scripts/local-signing.env` | Untracked. Holds `DEVELOPMENT_TEAM`. Listed in `.git/info/exclude`. |

## Open upstream PRs that touch possible security edits

Checked 2026-10-20. These matter only if a security baseline recommendation is approved.

| Recommendation | File | Open PR that edits it |
|---|---|---|
| 1. Sparkle off | `App/Resources/Info.plist` | none |
| 2. Hide cloud translation providers | `App/Sources/Preferences/Tabs/OCRSettingsView.swift` | [#348](https://github.com/lzhgus/Capso/pull/348) |
| 3. Hide Cloud Share setup | `App/Sources/Preferences/PreferencesView.swift` | [#348](https://github.com/lzhgus/Capso/pull/348) |

## Open upstream PRs that touch hook files

Checked 2026-10-20.

| PR | Files it shares with the fork's hook points |
|---|---|
| [#349](https://github.com/lzhgus/Capso/pull/349) | `AppDelegate.swift`, `MenuBarController.swift`, `ShortcutSettingsView.swift`, `project.yml` |
| [#348](https://github.com/lzhgus/Capso/pull/348) | `ShortcutSettingsView.swift`, `project.yml` |
| [#291](https://github.com/lzhgus/Capso/pull/291) | `AppDelegate.swift` |

- PR #349 checks shortcut conflicts over `KeyboardShortcuts.Name.allCapso`. The fork's `feedbackCapture` name is not in that list, so that check does not see it.
- No open upstream PR edits `CaptureCoordinator.swift`.
