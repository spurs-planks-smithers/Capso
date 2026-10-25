# Nextshot (Capso fork): agent instructions

This repository is the `spurs-planks-smithers/Capso` fork of [lzhgus/Capso](https://github.com/lzhgus/Capso). The fork's product name is Nextshot (short name Nshot, renamed 2026-10-21). The fork adds feedback rounds. A feedback round captures screen regions, marks them, adds a note, and writes a bundle that an AI coding agent can act on. Drew renamed "session" to "round" on 2026-10-24, so users do not confuse a round with an AI agent session such as a Claude Code session. Code, text, tests, and docs say round. The on-disk format never said session, so old bundles load unchanged. The Phase 1 plan is `docs/plans/2026-10-20-feedback-sessions-phase1.md`. Every upstream edit is logged in `docs/FORK_NOTES.md`.

## Architecture

- Swift 6 with strict concurrency, SwiftUI and AppKit. All UI coordinators are `@MainActor`.
- XcodeGen generates `Capso.xcodeproj` from `project.yml`. Git ignores the generated project.
- `App/Sources/`: the upstream app shell (coordinators, windows, views).
- `App/Feedback/`: fork-only app code (feedback controller, note panel, status item, App Intents).
- `Packages/`: Swift packages. Each package depends only on `SharedKit` and system frameworks. A fork package may also depend on `FeedbackKit` (2026-10-24).
- `Packages/FeedbackKit/`: fork-only. Foundation only, no UI. It holds the round model, the store, image sizing, the note parser, the manifest and prompt writers, and the feature flag registry.
- `Packages/JevKit/`: fork-only, no UI. The Jev base (#36): the TypeSafe client, typed request content and answers, the job interface and registry, the background job runner, and the `jev.json` and refined-file writer. It depends on FeedbackKit. Spec: `docs/superpowers/specs/2026-10-24-jev-base-design.md`.

## Build

```bash
xcodegen generate
xcodebuild -project Capso.xcodeproj -scheme Capso -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

- Signed local build: `scripts/build-local.sh`. It signs with Apple Development and installs `~/Applications/Nextshot.app` (bundle ID `com.drewschulz.nextshot`).
- The app name comes from `PRODUCT_NAME`: `Info.plist` reads it, and `scripts/local-project.yml` sets it to Nextshot. The upstream `project.yml` keeps Capso, so `Capso.xcodeproj` still builds `Capso.app`. Fork UI text uses `ForkBranding`. Upstream's user-visible text says Nextshot through the string catalogs: `scripts/brand/rename-capso-strings.py` rewrites `Localizable.xcstrings` and `InfoPlist.xcstrings` and leaves the Swift keys alone. Run it again after each upstream sync.
- Logs: `/usr/bin/log show --last 10m --predicate 'subsystem == "com.drewschulz.nextshot"'` (in zsh, plain `log` is a builtin).
- Notarized release for another Mac: `scripts/release-notarized.sh`. It signs with the Developer ID Application certificate, notarizes through the keychain profile `apple-notary`, staples, and writes `build/releases/Nextshot-<version>-<commit>.dmg` and `.zip`. Both ship Capso's license: `Contents/Resources/LICENSE.txt` inside the app and `LICENSE.txt` beside it. The Business Source License requires it on every modified copy. It needs `create-dmg` (Homebrew). Commit first, or the file name ends in `-dirty`.
- Nextshot's version comes from git: the HEAD commit date (2026.10.22) and the commit count as the build number. `scripts/nextshot-version.sh` computes both, and both build scripts pass them to xcodebuild. Updates are manual: people install each new DMG over the old app. Sparkle stays off (backlog issue #4).
- `scripts/local-project.yml` includes `project.yml` and overrides only the Capso target. It generates `CapsoLocal.xcodeproj`. Command-line `PRODUCT_NAME` would rename every package resource bundle and break the build.
- The script reads `DEVELOPMENT_TEAM` from `scripts/local-signing.env`, an untracked file listed in `.git/info/exclude`.

## Tests

- One package: `swift test --package-path Packages/<Name>`.
- CI package set: SharedKit, AnnotationKit, CaptureKit, RecordingKit, OCRKit.
- Fork package: `swift test --package-path Packages/FeedbackKit`.
- App tests: `xcodebuild test -project Capso.xcodeproj -scheme Capso -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:CapsoTests`.
- Run app tests without a `PRODUCT_NAME` override. `TEST_HOST` expects `Capso.app`.

## Rules

### Local only

- Only the Jev package (`Packages/JevKit`) makes outbound requests. It calls only `https://api.typesafe.ai`. It runs only when `jevBase` and a Jev feature flag are on, and only in a dev build (Drew, 2026-10-24).
- All other feedback code stays local: no network code, no outbound requests, and no sockets. `NetworkSourceScanTests` in JevKit fails on network code anywhere else in `App/Feedback`, `Packages/FeedbackKit`, or `Packages/JevKit`.
- Reviewer text (Drew's notes) is the only data that leaves the Mac by default. Screen text needs `jevSendScreenText`, and images need `jevSendImages`. Every value in a Jev request carries its kind, and the runner refuses a request with a kind that has no consent.
- Nextshot's TypeSafe key is the Keychain item `TYPESAFE_API_KEY_NEXTSHOT`. It is never written to a file, a log, or a DMG.
- Handle any URL scheme in-process.
- Bundles stay on disk in `~/Library/Application Support/Nextshot`. Only an agent that Drew starts reads them. On first launch, the app moves the old `CapsoFeedback` folder there.

### Merge hygiene

- Put new functionality in new packages under `Packages/` and new files under `App/Feedback/`.
- Edit upstream files only at the hook points in the plan.
- Log every upstream edit in `docs/FORK_NOTES.md`: file, reason, lines, and upstream PRs at risk.
- Keep each hook edit small. Open upstream PRs edit `AppDelegate.swift`, `MenuBarController.swift`, `ShortcutSettingsView.swift`, and `project.yml`.
- Never edit `.gitignore`. Upstream ignores `docs/`, `CLAUDE.md`, `AGENTS.md`, and `scripts/`. Add fork files there with `git add -f <path>`.
- Follow `CONTRIBUTING.md` and the existing code style. There is no linter or formatter.

### Git

- Work on a feature branch, never on `main`.
- Stage by explicit path. Use conventional commit prefixes. Add no AI attribution lines.
- Run `github-route status` before every push. Stop if it exits nonzero.

## Upstream flow

- `origin` is the fork, `spurs-planks-smithers/Capso`.
- `upstream` is `lzhgus/Capso`. It is fetch-only: its push URL is `DISABLED`.
- To sync: run `git fetch upstream`, merge `upstream/main` on a branch, and resolve conflicts at the hook points that `docs/FORK_NOTES.md` lists. Then run the tests.

## Use a feedback round

- Press Option+Shift+F, then select an area. The first saved capture starts a round named "feedback" when none is active.
- A see-through help box at the bottom right of the screen lists the keys for the current step (select, mark, notes, between captures) in 22-point text. It sat at the top right until 2026-10-24, where it covered the Nshot menu (Drew, 2026-10-24, #31). `visibleFrame` leaves out the Dock, so the box sits above a bottom Dock. The box and its text draw at 75% opacity (50% before 2026-10-24). Between captures it lists five keys with their current values: capture another area (F), copy last capture prompt (C), copy prompt and end round (R), open round folder (O), and end round (E). A small green dot (8 points) in its top right corner shows only while a round is active. It matches the dot on the menu bar mark (see the menu bar item below). The box shows from the hotkey until the round ends. It takes no clicks, and `sharingType = .none` keeps it out of screenshots. The app also hides it before the hotkey freezes the screen. A second press of the hotkey during a selection leaves the box on its display. A selection that ends with no end notification (the overlay fails after its delay) does not keep the box hidden: while a selection phase is set, the controller checks the coordinator's live `isCaptureSelectionActive` four times a second and shows the current stage again when the selection is gone (#28).
- Mark the capture in the inline editor. Counter badges (key C or N) number the items. Command+S saves into the round. Left and Right arrows undo and redo marks (they send Command+Z and Shift+Command+Z), except while text is being typed.
- Esc on an editor with no marks yet copies the screenshot image to the clipboard (PNG or JPEG, per the user's clipboard format setting, never a file path) and closes the editor, so it pastes into an email. It saves nothing to a round or to Nextshot's History. If the copy fails, the editor stays open and Nextshot beeps. To redo a selection, press the hotkey again. With marks, Esc follows upstream's step-back rule (`AnnotationEscapePolicy`) and never closes the editor.
- The note panel opens at Command+S. It asks one question per circle ("Circle 1 (1 of 3): what should change?"), then an optional general note. Return saves the answer and moves on. Esc skips one step. Up and Down move back and forward between steps. Left moves back when the cursor is at the start of the answer, and Right moves on when it is at the end. Each move saves the answer, and a step shows its saved answer again. Typing and dictation (Wispr Flow, fn key) both work: the panel takes keyboard focus without activating the app.
- Under each question, a preview shows the annotated capture zoomed on that circle, with about 150 points of context and any box or arrow it marks. The general-note step shows the whole capture.
- After the last note step, the capture's prompt is on the clipboard, and a toast says "Prompt copied. Paste it into your agent." The capture is stored before OCR runs, so the copy never waits for OCR. A panel closed early (close button, End Round, or a new capture) copies nothing. Copy Last Capture Prompt (Option+Shift+C or the menu) copies the newest capture's prompt again, for example after dictation (Wispr Flow pastes through the clipboard) replaced it.
- A capture is named "Capture: <title of the window under the selection>, <date time zone>". Files are `<HHmm>-<title slug>.png` and `-clean.png`. Agents still refer to items as K.N (the manifest gives each capture's item prefix).
- The feedback menu bar item stays in the menu bar at all times. With no round it shows the icon only. During a round it shows "Nshot" and the capture count, for example "Nshot (2)". A small green dot (5 points, `FeedbackRoundDot`) sits on the top right corner of the mark. It is a separate view over the button, so the mark keeps its menu bar tint. The dot shows only while a round is active, and the help box shows a matching dot. Upstream's capture menu icon is hidden by default (`ForkDefaults`), so only the Nshot item shows. Preferences > General > Show menu bar icon brings the capture menu back.
- The menu starts with a gray line that shows the running build, for example "Nextshot 2026.10.22 (497)", and a separator. During a round, the next gray line names the round, then come Copy Last Capture Prompt, Copy Prompt and End Round, Open Round Folder, and End Round. Each row shows its hotkey on the right in gray. With no round, the gray line reads "No active round" and Start Round takes its place. Start Round runs the same flow as the hotkey, so it never makes an empty round. Both menus end with All Rounds, Change Start Round Shortcut, Settings, and Quit Nextshot.
- Round keys (Drew, 2026-10-24): Option+Shift+C copies the last capture prompt, Option+Shift+R copies the prompt and ends the round, Option+Shift+O opens the round folder, and Option+Shift+E ends the round. They work only while a round is active. With no round, the app removes them (`FeedbackController.updateRoundShortcuts()`), so each key types its character in other apps. A round key pressed with no active round does nothing and does not beep.
- While a capture is open (being selected, in an editor, or in the note panel), Option+Shift+R and Option+Shift+E beep and do nothing (#25). The menu rows still end the round. Option+Shift+C and Option+Shift+O stay active.
- One end at a time (#26): a press of R or E during an end joins that end. A second R copies nothing more.
- Settings > Shortcuts has a Nextshot section with all five keys (`FeedbackShortcutSettingsSection`). Change Start Round Shortcut in the menu changes only Option+Shift+F. Both refuse a key that another action uses (`FeedbackShortcutGuard`, #24): the old key stays, Nextshot beeps, and an orange line says why. The library removes a hotkey by its key combination, so a shared key would turn the other action off between rounds.
- Copy Prompt and End Round (the menu row, Option+Shift+R, or the Copy Feedback Prompt Shortcuts action) waits for saves in progress, ends the round, and copies the ended round's whole prompt. The toast says the round ended and that Resume in Recent reopens it. Copy Round Prompt in Recent and Copy N Selected end nothing.
- Recent lists the last 5 ended rounds that hold a capture, newest first. A row shows the day and time, then the apps and the capture count. A row opens a submenu: Copy Round Prompt, one row per capture, Open Folder, and Resume Round.
- A click on a capture row toggles its check, and the menu stays open. While any capture is checked, Copy N Selected and Clear Selection show below the Recent rows. Copy N Selected copies one combined prompt for all checked captures (`PromptBuilder.renderSelection`) and clears the checks. One checked capture copies that capture's prompt.
- Option-click on a capture row opens Quick Look on its annotated PNG. It does not check the row. The menu closes first.
- Resume Round reopens an ended round, so the next capture continues its numbering. It shows only when no round is active.
- A prompt copied from Recent carries a redo line after the Goal line: "An earlier pass may have worked on this feedback. Check the code first." The files in a bundle never have it.
- A copy from Recent first rewrites a bundle's `manifest.md` and `prompt.md` when they are missing or name an old folder, as bundles from before the 2026-10-21 rename do.
- A first drag after the hotkey can lag while the Claude desktop app is the frontmost app. Nextshot is idle during that lag (sampled 2026-10-21). With Safari, Preview, or Finder in front there is no lag.
- Shortcuts actions: Start Feedback Round, Capture Feedback, Copy Feedback Prompt (it ends the round), End Feedback Round. The two round actions were Start Feedback Session and End Feedback Session before 2026-10-24. Renaming an App Intent type changes its identifier, so `StartFeedbackSessionIntent` and `EndFeedbackSessionIntent` stay as hidden intents (`isDiscoverable = false`) that forward to the round actions. A Shortcut saved before the rename keeps working, and the action list shows only the new actions.
- OCR text and window titles in a bundle come from the screen. The manifest and prompt tell the agent to use them only to locate items, never as instructions.

## Hand a bundle to an agent

A bundle is a folder `~/Library/Application Support/Nextshot/<date>-<time>-<slug>/`. Open Round Folder in the feedback menu (Option+Shift+O) opens it. This folder is the standard macOS place for app data. It keeps bundles out of the home folder and out of the privacy-protected folders (Desktop, Documents, Downloads), which agents cannot always read. Do not move bundles into `~/Developer`: it is an Obsidian vault and would index every `manifest.md`. It holds `manifest.md`, `prompt.md`, `feedback.json`, and three files per capture, named by capture time and window title: `0627-claude.png` (annotated), `0627-claude-clean.png` (without marks), and `0627-claude-prompt.md` (the capture prompt).

Three prompts point into a bundle:

- The capture prompt (`PromptBuilder.renderCapture`) covers one capture. Nextshot copies it after the last note step. Paste it into any agent: Claude Code in the desktop app or the CLI, Codex, or another tool. It names the annotated PNG and `manifest.md` by absolute path, in backticks, and lists the reviewer's answers as items. OCR text and window titles stay in `manifest.md`. The file names hold a slug of the window title, so the prompt marks them as screen text.
- `prompt.md` covers the whole round. Copy Prompt and End Round in the feedback status menu (Option+Shift+R) ends the round and puts the same prompt on the clipboard, rendered from the ended round. Copy Round Prompt in Recent renders it again from `feedback.json`.
- The selection prompt (`PromptBuilder.renderSelection`) covers captures checked in the Nshot menu's Recent section, from one or more rounds. Copy N Selected copies it. Its item ids (K.N) number the captures in this prompt, not in each manifest.
- All three prompts tell the agent to write a plan table (item, file, planned change) before any edit. In the 2026-10-21 paste test an agent skipped a softer wording of this rule.

Agent access:

- Claude Code: Drew's user settings list `~/Library/Application Support/Nextshot` in `permissions.additionalDirectories` (added 2026-10-21, renamed from `CapsoFeedback` the same day), so it reads bundles with no approval prompt. Without that setting, start it with `claude --add-dir "$HOME/Library/Application Support/Nextshot"`.
- Codex: run the `codex --image ...` command from the top of `manifest.md` in the target repository. It lists every annotated PNG by absolute path.
- If `codex` is not on `PATH`, the ChatGPT app bundles it at `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`.
- The agent-facing guide to a bundle is `docs/agents/bundle-guide.md`. Keep it in step with the "How to read this bundle" rules that `manifest.md` prints.

## Feature flags

- The registry is `FeatureFlag` in `Packages/FeedbackKit/Sources/FeedbackKit/FeatureFlags.swift`. App code reads a flag with `Flags.state(.name)` or `Flags.isOn(.name)` (`App/Feedback/Flags.swift`). Flags have no interface in the app.
- Lookup order: a local override (UserDefaults key `flag.<name>`), then the default for the build channel. The channel comes from the code signature: Developer ID Application is `release`, anything else is `dev` (`App/Feedback/BuildChannelDetector.swift`).
- `scripts/nextshot-flags.sh` has `list`, `set <flag> <state>`, and `reset <flag>`. Its `FLAGS=` line must match the registry, and `FeatureFlagsTests` fails when it does not.
- All flags start `off` in both channels. A release default turns on only with a released-in build number, and a test enforces this. The design is `docs/superpowers/specs/2026-10-24-feature-flags-design.md`.
- Every Jev flag is dev-only (`FlagSpec.devOnly`): a release build ignores every override and reads it as `off` (Drew, 2026-10-24). `FeatureFlagsTests` proves it.

## Jev (dev builds only)

- The base (#36) runs each feature's job in the background after a capture's notes are final and its screen text is stored. It never delays a copy, except Copy Prompt and End Round, which waits at most 500 ms and only with a feature on.
- Turn it on: `scripts/nextshot-flags.sh set jevBase on`, then a feature, for example `set noteCoach shadow`. Consent flags: `jevSendScreenText` and `jevSendImages`. Reset each flag after a test.
- Shadow writes `jev.json` in the bundle, and a job may also write its review file `jev-review/<job>.md` for Drew (Drew, 2026-10-24). On also writes `<stem>-refined.md` and `refined.md`, and the copied prompts point to them, refined file first. No prompt names a review file. The files on disk (`prompt.md`, `<stem>-prompt.md`) never change.
- Note coach (`noteCoach`, #37): labels each item's note, with one text-only request per capture and no consent flag. In on, the refined file says "Ask the reviewer first: the note names no change." for a vague note, "Answer this item. Change no code." for a question, and "Ask the reviewer first: the item has no note." for an empty one. Shadow writes each label to `jev.json` and `jev-review/noteCoach.md`. `scripts/note-coach-eval.sh` measures accuracy against a labeled set kept outside the repository. Design: `docs/superpowers/specs/2026-10-24-note-coach-design.md`.
- A feature session edits only its own job file in `Packages/JevKit/Sources/JevKit/Jobs/`. The registry already has one line per planned feature.
- Logs: `/usr/bin/log show --last 10m --predicate 'subsystem == "com.drewschulz.nextshot" AND category == "Jev"'`. They hold job ids, capture numbers, statuses, times, and token counts only.
- Failures are silent: the prompt stays plain, and `jev.json` records the reason.
- Crops and search lines (`cropsAnchors`, #38): each item gets two crop PNGs (`<stem>-item-<N>.png` and `-clean.png`) and at most one search line in the refined file. Without `jevSendImages`, crops are cut around the marks with no Jev check. Search lines need `jevSendScreenText`. In shadow, `scripts/jev-review-crops-anchors.py` draws each crop over its capture. Design: `docs/superpowers/specs/2026-10-24-crops-anchors-design.md`.

## Brand and README

- The fork's README is `.github/README.md`, written for people who install Nextshot. GitHub shows it before the root `README.md`. Never edit the root `README.md`: it is upstream's.
- Nextshot's app icon is `Branding/Nextshot.icon` (Icon Composer). The menu bar mark is `NextshotMark` in `App/Feedback/FeedbackAssets.xcassets`. Both menu bar items load it through `ForkBranding.menuBarMark`. The spec is `docs/brand/nextshot-mark.md`.
- Change the mark only through `scripts/brand/make_nextshot_icon.py`, then check every appearance with `ictool`. The spec gives the commands.
- Never ship Capso's name or logo as Nextshot's. Capso's license gives no right to its trademark or logo.

## Website (nextshot.dev)

- nextshot.dev is the download page: the intro video, the notarized DMG, and download counts at `/stats`. It is one Cloudflare Worker (`nextshot-site`) with static assets and a D1 database. The guide is `docs/site.md`.
- Publish with `site/deploy.sh`. It takes the newest DMG and video in `build/releases`, deploys, and smoke-tests the live site. Run it after each `scripts/release-notarized.sh` and each new video cut.
- The deploy reads the Cloudflare token from the Keychain item `CLOUDFLARE_API_TOKEN_NEXTSHOT`. `wrangler` stays signed out.
- The site stays free. Its footer reads "Free for personal use and internal use only." It shows no Capso credit or license link (Drew, 2026-10-23). The license notice ships inside the DMG, as BSL 1.1 requires.
