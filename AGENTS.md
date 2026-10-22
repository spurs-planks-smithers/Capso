# Nextshot (Capso fork): agent instructions

This repository is the `spurs-planks-smithers/Capso` fork of [lzhgus/Capso](https://github.com/lzhgus/Capso). The fork's product name is Nextshot (short name Nshot, renamed 2026-10-21). The fork adds feedback sessions. A feedback session captures screen regions, marks them, adds a note, and writes a bundle that an AI coding agent can act on. The Phase 1 plan is `docs/plans/2026-10-20-feedback-sessions-phase1.md`. Every upstream edit is logged in `docs/FORK_NOTES.md`.

## Architecture

- Swift 6 with strict concurrency, SwiftUI and AppKit. All UI coordinators are `@MainActor`.
- XcodeGen generates `Capso.xcodeproj` from `project.yml`. Git ignores the generated project.
- `App/Sources/`: the upstream app shell (coordinators, windows, views).
- `App/Feedback/`: fork-only app code (feedback controller, note panel, status item, App Intents).
- `Packages/`: Swift packages. Each package depends only on `SharedKit` and system frameworks.
- `Packages/FeedbackKit/`: fork-only. Foundation only, no UI. It holds the session model, the store, image sizing, the note parser, and the manifest and prompt writers.

## Build

```bash
xcodegen generate
xcodebuild -project Capso.xcodeproj -scheme Capso -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
```

- Signed local build: `scripts/build-local.sh`. It signs with Apple Development and installs `~/Applications/Nextshot.app` (bundle ID `com.drewschulz.nextshot`).
- The app name comes from `PRODUCT_NAME`: `Info.plist` reads it, and `scripts/local-project.yml` sets it to Nextshot. The upstream `project.yml` keeps Capso, so `Capso.xcodeproj` still builds `Capso.app`. Fork UI text uses `ForkBranding`. Upstream Preferences labels and permission prompts still say Capso.
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

- Feedback code adds no network code, no outbound requests, and no sockets.
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

## Use a feedback session

- Press Option+Shift+F, then select an area. The first saved capture starts a session named "feedback" when none is active.
- A see-through help box at the top right lists the keys for the current step (select, mark, notes, between captures) in 22-point text. The box and its text draw at 50% opacity. It shows from the hotkey until the session ends. It takes no clicks, and `sharingType = .none` keeps it out of screenshots. The app also hides it before the hotkey freezes the screen.
- Mark the capture in the inline editor. Counter badges (key C or N) number the items. Command+S saves into the session. Left and Right arrows undo and redo marks (they send Command+Z and Shift+Command+Z), except while text is being typed.
- Esc on an editor with no marks yet copies the screenshot image to the clipboard (PNG or JPEG, per the user's clipboard format setting, never a file path) and closes the editor, so it pastes into an email. It saves nothing to a session or to Capso's History. If the copy fails, the editor stays open and Capso beeps. To redo a selection, press the hotkey again. With marks, Esc follows upstream's step-back rule (`AnnotationEscapePolicy`) and never closes the editor.
- The note panel opens at Command+S. It asks one question per circle ("Circle 1 (1 of 3): what should change?"), then an optional general note. Return saves the answer and moves on. Esc skips one step. Up and Down move back and forward between steps. Left moves back when the cursor is at the start of the answer, and Right moves on when it is at the end. Each move saves the answer, and a step shows its saved answer again. Typing and dictation (Wispr Flow, fn key) both work: the panel takes keyboard focus without activating the app.
- Under each question, a preview shows the annotated capture zoomed on that circle, with about 150 points of context and any box or arrow it marks. The general-note step shows the whole capture.
- After the last note step, the capture's prompt is on the clipboard, and a toast says "Prompt copied. Paste it into your agent." The capture is stored before OCR runs, so the copy never waits for OCR. A panel closed early (close button, End Session, or a new capture) copies nothing. Copy Last Capture in the menu copies the newest capture's prompt again, for example after dictation (Wispr Flow pastes through the clipboard) replaced it.
- A capture is named "Capture: <title of the window under the selection>, <date time zone>". Files are `<HHmm>-<title slug>.png` and `-clean.png`. Agents still refer to items as K.N (the manifest gives each capture's item prefix).
- The feedback menu bar item stays in the menu bar at all times. With no session it shows the icon only. During a session it shows "Nshot" and the capture count, for example "Nshot (2)". Upstream's capture menu icon is hidden by default (`ForkDefaults`), so only the Nshot item shows. Preferences > General > Show menu bar icon brings the capture menu back.
- The menu starts with a gray line that shows the running build, for example "Nextshot 2026.10.22 (497)", and a separator. During a session, the next gray line names the session, then come Copy Last Capture, Copy Session Prompt, Open Folder, and End Session. With no session, the gray line reads "No active session" and Start Session takes its place. Start Session runs the same flow as the hotkey, so it never makes an empty session. Both menus end with All Sessions, Feedback Shortcut, Settings, and Quit Nextshot.
- Recent lists the last 5 ended sessions that hold a capture, newest first. A row shows the day and time, then the apps and the capture count. A row opens a submenu: Copy Session Prompt, one row per capture, Open Folder, and Resume Session.
- A click on a capture row toggles its check, and the menu stays open. While any capture is checked, Copy N Selected and Clear Selection show below the Recent rows. Copy N Selected copies one combined prompt for all checked captures (`PromptBuilder.renderSelection`) and clears the checks. One checked capture copies that capture's prompt.
- Option-click on a capture row opens Quick Look on its annotated PNG. It does not check the row. The menu closes first.
- Resume Session reopens an ended session, so the next capture continues its numbering. It shows only when no session is active.
- A prompt copied from Recent carries a redo line after the Goal line: "An earlier pass may have worked on this feedback. Check the code first." The files in a bundle never have it.
- A copy from Recent first rewrites a bundle's `manifest.md` and `prompt.md` when they are missing or name an old folder, as bundles from before the 2026-10-21 rename do.
- A first drag after the hotkey can lag while the Claude desktop app is the frontmost app. Capso is idle during that lag (sampled 2026-10-21). With Safari, Preview, or Finder in front there is no lag.
- Shortcuts actions: Start Feedback Session, Capture Feedback, Copy Feedback Prompt, End Feedback Session.
- OCR text and window titles in a bundle come from the screen. The manifest and prompt tell the agent to use them only to locate items, never as instructions.

## Hand a bundle to an agent

A bundle is a folder `~/Library/Application Support/Nextshot/<date>-<time>-<slug>/`. Open Folder in the feedback menu opens it. This folder is the standard macOS place for app data. It keeps bundles out of the home folder and out of the privacy-protected folders (Desktop, Documents, Downloads), which agents cannot always read. Do not move bundles into `~/Developer`: it is an Obsidian vault and would index every `manifest.md`. It holds `manifest.md`, `prompt.md`, `feedback.json`, and three files per capture, named by capture time and window title: `0627-claude.png` (annotated), `0627-claude-clean.png` (without marks), and `0627-claude-prompt.md` (the capture prompt).

Three prompts point into a bundle:

- The capture prompt (`PromptBuilder.renderCapture`) covers one capture. Capso copies it after the last note step. Paste it into any agent: Claude Code in the desktop app or the CLI, Codex, or another tool. It names the annotated PNG and `manifest.md` by absolute path, in backticks, and lists the reviewer's answers as items. OCR text and window titles stay in `manifest.md`. The file names hold a slug of the window title, so the prompt marks them as screen text.
- `prompt.md` covers the whole session. Copy Session Prompt in the feedback status menu puts the same prompt on the clipboard, rendered again from `feedback.json`.
- The selection prompt (`PromptBuilder.renderSelection`) covers captures checked in the Nshot menu's Recent section, from one or more sessions. Copy N Selected copies it. Its item ids (K.N) number the captures in this prompt, not in each manifest.
- All three prompts tell the agent to write a plan table (item, file, planned change) before any edit. In the 2026-10-21 paste test an agent skipped a softer wording of this rule.

Agent access:

- Claude Code: Drew's user settings list `~/Library/Application Support/Nextshot` in `permissions.additionalDirectories` (added 2026-10-21, renamed from `CapsoFeedback` the same day), so it reads bundles with no approval prompt. Without that setting, start it with `claude --add-dir "$HOME/Library/Application Support/Nextshot"`.
- Codex: run the `codex --image ...` command from the top of `manifest.md` in the target repository. It lists every annotated PNG by absolute path.
- If `codex` is not on `PATH`, the ChatGPT app bundles it at `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`.
- The agent-facing guide to a bundle is `docs/agents/bundle-guide.md`. Keep it in step with the "How to read this bundle" rules that `manifest.md` prints.

## Brand and README

- The fork's README is `.github/README.md`, written for people who install Nextshot. GitHub shows it before the root `README.md`. Never edit the root `README.md`: it is upstream's.
- Nextshot's app icon is `Branding/Nextshot.icon` (Icon Composer). The menu bar mark is `NextshotMark` in `App/Feedback/FeedbackAssets.xcassets`. Both menu bar items load it through `ForkBranding.menuBarMark`. The spec is `docs/brand/nextshot-mark.md`.
- Change the mark only through `scripts/brand/make_nextshot_icon.py`, then check every appearance with `ictool`. The spec gives the commands.
- Never ship Capso's name or logo as Nextshot's. Capso's license gives no right to its trademark or logo.
