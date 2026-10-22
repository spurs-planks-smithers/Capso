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
| `App/Sources/AppDelegate.swift` | One call to `FeedbackController.shared.start(captureCoordinator:settings:)` after `registerGlobalShortcuts()` | 90 (added) | [#349](https://github.com/lzhgus/Capso/pull/349), [#291](https://github.com/lzhgus/Capso/pull/291) |
| `App/Sources/AppDelegate.swift` | One call to `ForkDefaults.register()` after the single-instance guard. It registers `showMenuBarIcon = false`, so only the Nshot item shows in the menu bar by default (Drew, 2026-10-22). Upstream's `AppSettings.swift` keeps its `true` default and its test. | 40 (added) | [#349](https://github.com/lzhgus/Capso/pull/349), [#291](https://github.com/lzhgus/Capso/pull/291) |
| `App/Sources/AppDelegate.swift` | One call to `SingleInstanceGuard.quitIfAnotherCopyRuns()` right after the unit-test early return. A relaunch on 2026-10-22 started two copies, and both registered the hotkeys and menu bar items. | 39 (added) | [#349](https://github.com/lzhgus/Capso/pull/349), [#291](https://github.com/lzhgus/Capso/pull/291) |
| `project.yml` | `FeedbackKit` local package | 50-51 (added) | [#349](https://github.com/lzhgus/Capso/pull/349), [#348](https://github.com/lzhgus/Capso/pull/348) |
| `project.yml` | `App/Feedback` source path for the Capso target | 71 (added) | [#349](https://github.com/lzhgus/Capso/pull/349), [#348](https://github.com/lzhgus/Capso/pull/348) |
| `project.yml` | `FeedbackKit` dependency for the Capso target | 98 (added) | [#349](https://github.com/lzhgus/Capso/pull/349), [#348](https://github.com/lzhgus/Capso/pull/348) |
| `App/Resources/Info.plist` | Security rec 1 (approved 2026-10-20): `SUFeedURL` removed, `SUEnableAutomaticChecks` set to false | 63-64 (removed), 66 (changed) | none |
| `App/Tests/UpdateManagerTests.swift` | Rec 1 follow-on: `ShippedUpdateDefaultsTests` asserted automatic checks are on. It now asserts they are off, as `testAutomaticChecksAreOffInTheFork`. | 40-42 (changed, 1 comment line added) | none |
| `App/Sources/Preferences/Tabs/OCRSettingsView.swift` | Security rec 2 (approved 2026-10-20): the provider picker lists only `.apple`. Provider code stays until a later removal branch. | 51 (changed) | [#348](https://github.com/lzhgus/Capso/pull/348) |
| `App/Sources/Preferences/PreferencesView.swift` | Security rec 3 (approved 2026-10-20): Cloud Share is left out of the settings tab list. "Capture Area and Share" can still open its content (`CaptureCoordinator.swift:401`). | 95 (changed) | [#348](https://github.com/lzhgus/Capso/pull/348) |
| `App/Resources/Info.plist` | Nextshot rename (Drew, 2026-10-21): `CFBundleName` and `CFBundleDisplayName` read `$(PRODUCT_NAME)`. Upstream's `PRODUCT_NAME` is Capso, so upstream builds keep their name. | 6, 8 (changed) | none |
| `App/Resources/InfoPlist.xcstrings` | Nextshot rename: the `CFBundleName` and `CFBundleDisplayName` entries are removed. Every locale held "Capso", which would override `Info.plist`. On a conflict, delete the two entries again. | 4-111 of the upstream file (removed) | none |
| `App/Sources/MenuBar/MenuBarController.swift` | Nextshot rename: "About Capso" and "Quit Capso" pass through `ForkBranding.renamed`, so each locale keeps its translation. | 160, 162 (changed) | [#349](https://github.com/lzhgus/Capso/pull/349) |
| `App/Sources/MenuBar/MenuBarController.swift` | Nextshot mark (Drew, 2026-10-22): the main menu bar item shows `ForkBranding.menuBarMark` instead of Capso's `MenuBarIcon` logo. Capso's license gives no right to its logo. The helper sizes the image, so upstream's two sizing lines are gone. | 65-66 (a `Fork:` comment and one line replace upstream's 65-67) | [#349](https://github.com/lzhgus/Capso/pull/349) |
| `App/Resources/Localizable.xcstrings` | Nextshot rename (Drew, 2026-10-22): every locale's text says Nextshot, and the 24 keys that name Capso get an explicit English text. Swift keys stay upstream's. `scripts/brand/rename-capso-strings.py` writes it. On a conflict, take upstream's file and run the script again. | texts throughout (script-made) | [#291](https://github.com/lzhgus/Capso/pull/291) |
| `App/Resources/InfoPlist.xcstrings` | Nextshot rename: the permission texts in every locale, by the same script | texts throughout (script-made) | none |
| `App/Resources/Info.plist` | Nextshot rename: the three permission texts, the URL name "Nextshot Automation", and a `nextshot` URL scheme before `capso`, so old `capso://` links still work | 23, 57, 59, 61 (changed), 26 (added) | none |
| `Packages/SharedKit/Sources/SharedKit/AutomationURLAction.swift` | The automation parser accepts `nextshot://` and `capso://` | 32 (changed) | none |
| `App/Sources/Preferences/Components/AutomationURLsSheetView.swift` | The Automation URLs sheet lists `nextshot://` links | 27-81 (25 lines changed) | none |
| `Packages/SharedKit/Sources/SharedKit/Utilities/FileNaming.swift` | Default and fallback file names say "Nextshot Screenshot" and "Nextshot Recording" | 56 (added), 57-58, 252, 254 (changed) | none |
| `Packages/SharedKit/Tests/SharedKitTests/FileNamingTests.swift` | The default-name tests expect Nextshot | 28, 31, 34, 37, 52, 65, 138 (changed) | none |
| `App/Sources/Preferences/Tabs/GeneralSettingsView.swift` | Report a Bug, Request a Feature, and Source Code open the fork's GitHub page | 133, 138, 143 (changed) | [#348](https://github.com/lzhgus/Capso/pull/348) |

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
| `Packages/FeedbackKit/` | Session model, store, image sizing, naming, screen-text cleaning, window picker, preview crop, note parser, OCR matcher, manifest and prompt writers, session library and cache, basket, tests |
| `App/Feedback/` | Feedback controller (editor, Esc and arrow keys, save pipeline), mark mapper, window-title lookup, PNG export, note panel with circle previews and arrow-key steps, help box, status item with the Recent section, capture row view, thumbnails, Quick Look, shortcut panel, App Intents, `ForkBranding` (product name and `menuBarMark`), `FeedbackAssets.xcassets` (the `NextshotMark` menu bar image), `SingleInstanceGuard` (one running copy), `ForkDefaults` (fork defaults for upstream settings) |
| `Branding/Nextshot.icon` | Nextshot's app icon (Icon Composer). Only `scripts/local-project.yml` adds it, so `Capso.app` keeps Capso's icon. |
| `scripts/brand/rename-capso-strings.py` | Makes the string catalogs say Nextshot. Run it again after each upstream sync. Force-added. |
| `scripts/brand/make_nextshot_icon.py` | Writes the app icon and the menu bar image from the spec values. Force-added. |
| `docs/brand/`, `docs/decisions/2026-10-22-nextshot-icon.md` | The mark's spec and previews, and why it exists |
| `docs/agents/bundle-guide.md` | How an AI agent reads a feedback bundle |
| `.github/README.md`, `.github/assets/nextshot-icon.png` | The fork's README. GitHub shows `.github/README.md` before the root `README.md`, so upstream's README stays unedited. |
| `scripts/build-local.sh`, `scripts/local-project.yml` | Signed local build. `local-project.yml` also sets Nextshot's app icon. Force-added: upstream ignores `scripts/`. |
| `scripts/nextshot-version.sh` | Nextshot's version (HEAD commit date) and build number (commit count). Both build scripts source it. Force-added. |
| `scripts/release-notarized.sh` | Developer ID build, notarized and stapled, as a DMG and a zip for another Mac. It ships Capso's `LICENSE` as `Resources/LICENSE.txt` in the app and as `LICENSE.txt` beside it in the DMG and zip. Adapted from upstream's `.github/workflows/build-release.yml`. Force-added. |
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
