# Capso fork: agent instructions

This repository is the `spurs-planks-smithers/Capso` fork of [lzhgus/Capso](https://github.com/lzhgus/Capso). The fork adds feedback sessions. A feedback session captures screen regions, marks them, adds a note, and writes a bundle that an AI coding agent can act on. The Phase 1 plan is `docs/plans/2026-10-20-feedback-sessions-phase1.md`. Every upstream edit is logged in `docs/FORK_NOTES.md`.

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

- Signed local build: `scripts/build-local.sh`. It signs with Apple Development, sets a distinct bundle ID and app name, and copies the app to `~/Applications`.
- The script reads the team ID from an untracked file listed in `.git/info/exclude`.

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
- Bundles stay on disk in `~/Feedback`. Only an agent that Drew starts reads them.

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

## Hand a bundle to an agent

A bundle is a folder `~/Feedback/<date>-<time>-<slug>/`. It holds `manifest.md`, `prompt.md`, `feedback.json`, and two PNG files per capture (`001.png` annotated, `001-clean.png` without marks). Copy Prompt in the feedback status menu puts `prompt.md` on the clipboard.

- Claude Code: start it in the target repository with `claude --add-dir ~/Feedback`, then paste the prompt.
- Codex: run `codex --image <bundle>/001.png,<bundle>/002.png "<prompt>"` in the target repository. `manifest.md` holds this command ready to copy.
- If `codex` is not on `PATH`, the ChatGPT app bundles it at `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`.
