# Plan: Capso fork becomes "agentic feedback" capture (Phase 1)

Revised 2026-10-20: Xcode 27.1 installed, bundle format rebuilt from research. Approved by Drew on 2026-10-20.

## Status and handoff (2026-10-20)

Planning ran on m4max. Execution runs on m5pro. This file is the only change on the branch.

Done on m4max:
- Fork `spurs-planks-smithers/Capso` exists (public). Its `main` equals upstream `main` at `8f07fb6` (v1.2.5).
- Branch `feature/feedback-sessions` holds this plan, pushed to `origin`.
- No code, no other docs, no `accounts.ini` change, no `upstream` remote yet.

Facts measured on m4max that m5pro must check again:
- Xcode version, license state, `xcode-select` path, `xcodegen` install, and code-signing identities.
- `swift test --package-path Packages/SharedKit` passes (279 tests).

On m5pro, clone with `github-route clone spurs-planks-smithers/Capso`, then check out `feature/feedback-sessions`. This replaces Step 0 items 1, 3, and 4. Start at Step 0 item 2. Run `github-route status` before any push.

## Context

Drew reviews PDFs and web pages, captures regions, annotates them, and hands the bundle to Claude Code, Codex, or other AI tools. Capso (Swift 6, SwiftUI + AppKit, XcodeGen, 12 SPM packages) already has capture, annotation (including a numbered Counter tool), on-device OCR, and a configurable global shortcut system. Phase 1 adds a "feedback session" that writes a bundle an agent can act on with few errors. The triggers are a global hotkey and four App Intents. All new code sits in new files, so upstream merges stay clean. Nothing may touch the network.

## Decisions (Drew, 2026-10-20)

| Topic | Decision |
|---|---|
| GitHub fork | Create `spurs-planks-smithers/Capso`. The create and first push get a confirm at that step. |
| Upstream remote | Add `lzhgus` to the personal identity's `owners` in `accounts.ini`. `upstream` is fetch-only. |
| Local build identity | Distinct bundle ID and app name through command-line overrides. |
| Status item | A separate menu bar item, shown only during a session. |
| Editor after capture | Inline editor. Command+S saves to the session. Falls back to the full editor. |
| Signing | Drew's paid Apple Developer Program account, "Apple Development" certificate. |
| Typed note | Yes in Phase 1. A one-line panel after each save. Phase 2 dictation fills the same field. |
| Browser URL capture | After Phase 1. It needs Apple Events permission per browser. |

## Bundle format: what the research says, and what the plan now does

The first plan wrote numbered PNGs and a manifest with an empty note. The evidence below says that format under-delivers. Images with no paired text, unlabeled marks, and no scope or verify rules are the documented failure modes.

| Finding | Source | Design rule in this plan |
|---|---|---|
| Models struggle to turn visual feedback into functional requirements ("visual interpretation gap", 20 models tested). Visual feedback scored below text: 55.0% against 56.0% before the authors' fix, 60.2% against 65.3% after it. | FronTalk, Wu et al., arXiv 2601.04203, ICML 2026 | Every mark gets a written instruction. The text is the instruction, the image is the evidence. Typed note in Phase 1. |
| Over multi-turn edits, models overwrite earlier fixes ("forgetting"). A self-check against all earlier instructions cut forgetting to near zero. | FronTalk (AceCoder method) | The prompt makes the agent re-verify every item at the end, not only the last one. |
| Agents lack fine-grained visual-to-code alignment, and they damage content that should stay unchanged. | MT-Web2Code, arXiv 2608.03474, Aug 2026 | Give exact pixel boxes and the on-image text near each mark. The prompt says "change only the listed items." |
| Numbered marks on regions let a model refer to them by a short label. GPT-4V grounding beat a fine-tuned state-of-the-art model with this method. | Set-of-Mark, Yang et al., arXiv 2310.11441 | Capso's Counter tool (key C or N) draws the badges. Item `2.3` means badge 3 in capture 2, the same ID in image and text. |
| A drawn red circle directs model attention to a region and keeps global context. | Shtedritski et al., ICCV 2023 | Keep shapes and arrows. Record their pixel boxes too. |
| Claude works best with absolute pixel coordinates on the image it sees. Oversized images are resized, which shifts coordinates. | Anthropic, [Coordinates and bounding boxes](https://platform.claude.com/docs/en/build-with-claude/vision-coordinates) | Export each PNG small enough that Claude does not resize it. Give coordinates in pixels of that PNG, origin top-left. |
| Opus 5.5 reads up to 2576 px and 4784 visual tokens per image. Above 20 images in one request, any image over 2000 px is rejected. Lossy compression hurts text. | Anthropic, [Vision](https://platform.claude.com/docs/en/build-with-claude/vision) | Cap the long edge at 2000 px and the cost at 4784 visual tokens with Anthropic's published resize rule. Keep PNG (lossless). |
| Images work best before the text about them. Label each image so later text can name it. | Anthropic, Vision | For each capture the agent opens the image first, then reads its section. Files and headings use the same ID. |
| "Don't rely on the image alone." Name what the image shows, point to the area, state the outcome and constraints, ask for a new screenshot to verify. | OpenAI, [Codex image inputs](https://learn.chatgpt.com/docs/image-inputs?surface=cli) | The prompt holds a goal, rules, a work method, and a verify step. A ready `codex --image a.png,b.png` command goes in the manifest. |
| Give a check the agent can run, such as a screenshot compared with the target. Be specific: files, symptoms, constraints. | Anthropic, [Claude Code best practices](https://code.claude.com/docs/en/best-practices) | The prompt asks for a located-items table before edits, then a screenshot comparison where the UI can render. |
| Feedback tools built for agents (Agentation, AgentEcho, Markagent, MarkUp, SenAnnotate) all export numbered marks plus a Markdown report with greppable locators. | Product pages, 2025 to 2026 | Use on-device OCR text under each mark as the locator. The agent can grep the repo for it. Browser URL and DOM selectors come later. |

Two rules are my inference, not a cited result. First, keep a clean copy of each capture, because marks can hide the content they point at. Second, keep the per-item fields few, per Drew's ceiling rule for specs.

### Bundle layout

```
~/Feedback/2026-10-20-1912-pricing-page/
  manifest.md      entry point: how to read the bundle, then one section per capture
  prompt.md        the prompt that Copy Prompt puts on the clipboard
  feedback.json    machine-readable, schemaVersion 1, source of truth
  001.png          annotated, long edge <= 2000 px, <= 4784 visual tokens
  001-clean.png    same size, no marks
  002.png ...
```

### One capture section in `manifest.md`

```
## Capture 2: 002.png
Image: 002.png (annotated), 002-clean.png (no marks), 1840x1012 px
Source: Safari, window "Pricing | Acme"
Captured: 2026-10-20 19:14 PDT
Note: The plan cards feel cramped on this page.

| Item | Where in 002.png (px, x1 y1 x2 y2) | Text under the mark (OCR) | Instruction |
|---|---|---|---|
| 2.1 | badge (412, 188), points to (520, 240) | "Starter $19/mo" | Price is wrong, should be $15 |
| 2.2 | badge (900, 610), box 860 580 1500 700 | "Compare plans" | Make this the primary button |
| 2.3 | badge (300, 820) | "Billed annually" | n/a (no instruction: ask) |

Other marks: arrow 100 400 to 300 420; text on image "too much padding" at 640 300 900 340
```

- A note line that starts with a badge number (`2: wrong price`) becomes that item's instruction. Other note text becomes the capture note.
- Text typed with the Text tool on the image is copied into the manifest as text. The agent does not need to read it from pixels.
- `n/a` shows a missing value, never a blank cell.

### `prompt.md` structure

1. A `<feedback_bundle path="...">` tag with the absolute path and the counts of captures and items.
2. How to read: open `manifest.md`. For each capture, open the annotated PNG, then read its section. Open `-clean.png` only when a mark hides content. Badge N in image K is item `K.N`. Coordinates are pixels in that PNG, origin top-left.
3. Authority rule: the written instruction wins. The image shows where and what it looks like now. If text and image conflict, or an item has no instruction, ask first.
4. Work method: locate each item (grep the OCR text and labels), then show a table of item, file, planned change before any edit. Change only the listed items.
5. Verify: re-check every item against its capture at the end. Where the UI can render, take a screenshot of the same region and compare.
6. Report: one line per item: done, not done, or needs input, with evidence.
7. Context note: read each image only when working on its item. Each image costs up to 4784 tokens.

## What the code reading found

**Machine (m4max, macOS 26.7.1, Apple Silicon)**
- Clone: `~/Developer/capso`, upstream main at `8f07fb6` (v1.2.5). `origin` points at upstream over https. No fork exists yet.
- Xcode 27.1 (build 27A9275) is in `/Applications`. The license is not accepted, `xcode-select` points to Command Line Tools, and `xcodegen` is not installed.
- The keychain has 0 code-signing identities. No upstream Capso is installed.
- `swift test --package-path Packages/SharedKit` passes with Command Line Tools alone (279 tests).

**Repo facts that shape the design**
- `.gitignore` ignores `docs/`, `CLAUDE.md`, `AGENTS.md`, and `.claude/`. New docs need `git add -f <path>`.
- `project.yml` signs with "Developer ID Application", team `T247WTJV77` (the upstream owner). Local builds override this on the command line.
- The app is **not sandboxed**, so `com.apple.security.network.client` is a no-op.
- Upstream ships `capso://grab/<action>` (25 actions). The README roadmap line "URL scheme API" is stale. "Raycast / Shortcuts integration" is open. No upstream issue or PR covers App Intents, feedback sessions, or dictation.
- Open upstream PRs #349, #348, #291 edit `AppDelegate.swift`, `MenuBarController.swift`, `ShortcutSettingsView.swift`, and `project.yml`. Keep hook edits there to one or two lines.
- Xcode 27.1 is newer than anything upstream tests. The baseline can show new warnings or errors.
- Capture flow: `startAreaCapture(action:)` sets `pendingAction`. `handleCaptureResult` switches on `PostCaptureAction`. `.inlineAnnotate` opens `InlineAnnotationEditorWindow`, whose `onSave` calls `saveRenderedImage(...)`.
- `InlineAnnotationEditorWindow.document` (internal `AnnotationDocument`) holds `objects`. `CounterObject` has `number`, `center`, `tip`, `bounds`. `TextObject` has `text`. Every object has `bounds`. The coordinator's save closure can read these with no editor edit.
- `OCRKit.TextRecognizer` runs Vision OCR on-device.
- App Intents SDK (Xcode 27.1 `AppIntents.swiftinterface`): `openAppWhenRun` is deprecated only from macOS 26, and `supportedModes` needs macOS 26. The target is macOS 15, so use `openAppWhenRun`.
- Package pattern: `swift-tools-version: 6.0`, `.macOS(.v15)`, Swift Testing. Packages depend only on `SharedKit`.
- License: BSL 1.1. Personal and internal use are permitted.

## Prerequisites (Drew runs the sudo steps)

1. `sudo xcodebuild -license accept`
2. `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
3. `sudo xcodebuild -runFirstLaunch`
4. Xcode, Settings, Accounts: sign in with the paid account. Manage Certificates, add "Apple Development". I confirm with `security find-identity -v -p codesigning`.
5. I run `brew install xcodegen` (2.46.0, no sudo).

## Steps (all on `feature/feedback-sessions`, small commits, nothing on main)

**Step 0: Git and GitHub setup**
1. Create branch `feature/feedback-sessions`.
2. Add `lzhgus` to the personal `owners` line in `~/.dotfiles/claude-code/github-routing/accounts.ini`. Run `github-route render`, then `github-route install`. Commit that file in the dotfiles repo by explicit path. No push.
3. Confirm, then fork: `gh repo fork lzhgus/Capso --clone=false --remote=false`.
4. `github-route set-remote spurs-planks-smithers/Capso` points `origin` at the fork.
5. Add `upstream` (`https://github.com/lzhgus/Capso.git`) with its push URL disabled.
6. `github-route status` must exit 0 before any push. The first push gets a confirm.

**Step 1: Housekeeping docs**
- `CLAUDE.md`: architecture, build, per-package tests, local-only rule, merge-hygiene rule, upstream flow, and how to hand a bundle to Claude Code (`--add-dir` for `~/Feedback`) and Codex (`--image`).
- `docs/FORK_NOTES.md` skeleton: file, reason, lines, upstream PRs at risk.
- `docs/decisions/2026-10-20-feedback-bundle-format.md`: the research table above with links.
- Add all three with `git add -f`.

**Step 2: Baseline build (no code changes)**
- `xcodegen generate`. Build Debug and Release with the CI-style overrides (`CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`). Record every warning.
- If the build fails on Xcode 27.1, stop and report. A fix is an upstream edit and needs approval.
- Run `xcodebuild test -only-testing:CapsoTests` and the CI package tests.
- Build once with Apple Development signing (Step 7), install to `~/Applications`, launch, and have Drew grant Screen Recording.

**Step 3: `docs/SECURITY_BASELINE.md`, then STOP for approval**
- Network code:
  - `TranslationKit/ProviderTranslationService.swift`: URLSession to OpenAI, DeepSeek, OpenRouter, DeepL, Google Cloud, or a custom endpoint, only when a cloud provider and key are set. The default `.apple` provider uses on-device Apple Translation. The OS can still download language packs.
  - `ShareKit`: SigV4 uploads to S3, R2, Aliyun OSS, Tencent COS, only when Cloud Share is configured. R2 and the factory also make a check request.
  - Sparkle 2.9.1: `SUFeedURL` (`lzhgus.github.io/Capso/appcast.xml`), automatic checks every 86400 seconds (24 hours). **The one outbound call with no user setup.** It would also offer upstream builds that replace the fork.
  - No analytics, telemetry, crash SDK, socket server, or WebView. `OCRProcessFallback` starts the app's own binary.
- Entitlements: camera, audio-input, network.client (no-op). Screen Recording is a TCC grant (TCC is the macOS privacy-permission database).
- Dependencies: KeyboardShortcuts 2.2.1, Defaults 9.0.6, LaunchAtLogin-Modern 1.1.0, Sparkle 2.9.1, GRDB.swift 7.4.1.
- Recommendations, none applied until Drew approves:
  1. Sparkle: set `SUEnableAutomaticChecks` false and remove `SUFeedURL` (two `Info.plist` lines).
  2. Cloud translation: hide or remove the cloud providers. **DeepSeek conflicts with Drew's rule against China-based models.** Keep `.apple`.
  3. ShareKit: leave it unconfigured and hide the setup. Do not delete the package.
  4. Add a run-time check: `nettop -p <pid>` during a session.
  5. Keep the existing `capso://` scheme.
- Feedback bundles hold screenshots of work documents. They stay in `~/Feedback` on disk. Only the agent Drew starts reads them.

**Step 4: FeedbackKit (test-driven, runs without Xcode)** `Packages/FeedbackKit`
- Foundation only. No UI, no AnnotationKit or OCRKit dependency. All public types are `Sendable`.
- Model: `FeedbackSession`, `FeedbackCapture` (index, files, size, timestamp, source app, window title, note, OCR text), `FeedbackMark` (kind, badge number or nil, box, point, text on image, OCR text under it, instruction).
- `FeedbackSessionStore`: injected root URL and clock. `start(name:)`, `activeSession`, `addCapture(...)`, `updateNote(capture:text:)`, `end()`. It saves the active session to `<root>/.active.json`.
- `ImageSizing`: a Swift port of Anthropic's published resize rule, with a 2000 px edge and 4784-token cap. It also scales mark coordinates to the exported size.
- `NoteParser`: splits a note into the capture note and per-badge instructions (`2: ...`).
- `ManifestWriter` and `PromptBuilder` render `manifest.md` and `prompt.md` from `feedback.json`.
- Tests: folder naming, slug, collision, numbering, resize against Anthropic's published examples (1075x1520 to 924x1307 and 1920x1080 to 1456x819 at the standard tier, 3840x2160 to 2576x1449 at the high tier), coordinate scaling, note parsing, manifest table with `n/a`, prompt sections, save and resume.

**Step 5: App wiring in `App/Feedback/`**
- `FeedbackController` (`@MainActor`) owns the store, hotkey, status item, and note panel.
- On Save it receives the rendered image, the clean image, the `AnnotationDocument` objects, and the `CaptureResult`. It does four things in order:
  1. Map annotation objects to `FeedbackMark`.
  2. Run on-device OCR on the clean image.
  3. Resize both PNGs and scale the coordinates.
  4. Call `addCapture`, then open the note panel.
- Note panel: a one-line SwiftUI field in an `NSPanel`. Return saves through `updateNote`. Esc skips. The manifest and prompt regenerate on each change.
- Hotkey: `KeyboardShortcuts.Name("feedbackCapture")` in our own file, default Option+Shift+F. A "Feedback Shortcut..." panel holds a `KeyboardShortcuts.Recorder`. With no active session, the hotkey starts one named "feedback".
- Status item: a second `NSStatusItem`, shown only during a session. Title: slug and capture count. Menu: Copy Prompt, Open Folder, End Session, Feedback Shortcut.
- `FeedbackIntents.swift`: Start (optional name), Capture (`openAppWhenRun = true`), Copy Prompt (also returns the text), End, and an `AppShortcutsProvider`. Spike one intent first and confirm it appears in Shortcuts.

**Step 6: Upstream hook edits (each logged in `docs/FORK_NOTES.md`)**

| File | Edit | Size |
|---|---|---|
| `App/Sources/Capture/CaptureCoordinator.swift` | `PostCaptureAction.feedback` and its 4 switch arms, `captureAreaForFeedback()`, and a feedback sink. The sink receives the rendered image, the clean image, the editor's `document.objects`, and the `CaptureResult`. | about 35 lines |
| `App/Sources/AppDelegate.swift` | One call to `FeedbackController.shared.start(captureCoordinator:)` | 1 to 2 lines |
| `project.yml` | `FeedbackKit` package and dependency, `App/Feedback` source path | about 6 lines |

- No edits to editor windows, `MenuBarController.swift`, `ShortcutSettingsView.swift`, `Info.plist`, entitlements, or `.gitignore`.
- Risk to log: PR #349 checks conflicts over `KeyboardShortcuts.Name.allCapso`, and our name is not in that list.

**Step 7: Signing (no tracked-file change without approval)**
- `scripts/build-local.sh` (new) runs `xcodegen generate` and `xcodebuild` with `CODE_SIGN_STYLE=Automatic`, `CODE_SIGN_IDENTITY="Apple Development"`, `DEVELOPMENT_TEAM`, a distinct `PRODUCT_BUNDLE_IDENTIFIER`, and `PRODUCT_NAME`. It copies the app to `~/Applications`.
- The team ID lives in an untracked file listed in `.git/info/exclude`.
- Check: `Info.plist` hardcodes `CFBundleName` "Capso". Check: `CapsoTests` `TEST_HOST` uses `Capso.app`, so run tests without the `PRODUCT_NAME` override.
- App Intents need no entitlement and no `Info.plist` key. They need a full Xcode build, which writes `Metadata.appintents` into the bundle.
- m5pro: repeat the Xcode sign-in there.

## How the work runs

- I implement in this checkout, one step at a time, in small commits staged by explicit path.
- FeedbackKit is test-driven: a failing test first, then the code.
- A separate `code-reviewer` subagent reviews the branch diff before I report done.
- Commits carry no AI attribution lines, per Drew's rule. This conflicts with the managed-settings attribution request, and Drew's rule wins.

## Verification (definition of done)

1. The three docs exist and are committed.
2. `swift test --package-path Packages/FeedbackKit` passes. The CI package set still passes.
3. The Release build succeeds. `xcodebuild test -only-testing:CapsoTests` passes.
4. In the running app: hotkey, select a region, add two Counter badges and a box, Command+S, type `1: fix price` and Return. The folder holds `001.png`, `001-clean.png`, `manifest.md`, `prompt.md`, and `feedback.json`. Item 1.1 has the instruction and OCR text, and 1.2 shows `n/a`.
5. Open `001.png` and check that the manifest pixel boxes land on the badges.
6. **End-to-end agent test:** put a test page with three known defects in a scratch repo. Capture and mark them, then paste the prompt into Claude Code and into Codex (`codex --image ...`). Pass: each agent shows the located-items table first and fixes all three. It touches nothing else and reports one line per item. This also confirms how each tool reads `~/Feedback`.
7. The Shortcuts app shows all four intents, and each runs.
8. The status item shows the slug and count. Copy Prompt, Open Folder, and End Session work.
9. After a rebuild, Screen Recording still works with no new prompt.
10. `nettop -p <pid>` shows no outbound connection during a session, after the approved Sparkle change.

## Order of commits

1. docs: add CLAUDE.md, FORK_NOTES skeleton, bundle-format decision
2. docs: add security baseline (then wait for approval)
3. chore: add local signing build script
4. feat(FeedbackKit): model, store, sizing, note parser, manifest, prompt, tests
5. feat: hotkey capture into the active session with marks and OCR
6. feat: note panel and feedback status item
7. feat: App Intents for feedback sessions
8. docs: final FORK_NOTES and CLAUDE.md

## Later (not Phase 1)

- Phase 2: local Whisper dictation into the note field.
- Browser URL and DOM selector capture (Apple Events).
- An optional local MCP server over stdio (no socket), so an agent reads the active session live. It needs approval.
