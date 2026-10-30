# Nextshot Chrome Extension Handoff

Date: October 29, 2026, America/Los_Angeles. Drew requests a stop to implementation, committed documentation, updated issues, and a Claude Code handoff. No new feature work runs during this handoff. The stop applies to the outgoing Codex run. Drew controls continuation through the prompt he gives Claude Code.

## Start Here

Use `/Users/drewschulz/.codex/worktrees/chrome-extension-plans/capso`, branch `codex/chrome-extension`. Read `AGENTS.md` before changes. Do not switch to the shared `/Users/drewschulz/Developer/capso` checkout for source work.

Runtime source is `382944f01f1db6b43f9bfbd10de5b0a2c6a1d4af`. Subsequent handoff commits change documentation only. [Runtime CI succeeds](https://github.com/spurs-planks-smithers/Capso/actions/runs/40988041075). Refresh GitHub and `git status` before continuing.

| Artifact | Verified state |
| --- | --- |
| [Implementation PR #173](https://github.com/spurs-planks-smithers/Capso/pull/173) | Open, draft, unmerged; branch `codex/chrome-extension`, base `main` |
| [Original planning PR #161](https://github.com/spurs-planks-smithers/Capso/pull/161) | Open, draft, unmerged; preserved planning history |
| Nextshot Pilot | Private Chrome-only build 0.1.4; no app, account, AI, recording, or Rolling controls |
| Nextshot Dev extension | Separate full-profile identity; contains optional trials and finished-report native import |
| Public release | None; all Chrome issues stay in Later and outside v0.5.0 |

The native-first product is unfinished. The existing Swift bridge imports finished browser reports. It does not open editable native drafts or satisfy the native-first plan.

## Product Priorities And Settled Choices

- Minimize controls, user inputs, screen transitions, browser tabs, and overhead. Make routine choices automatically. Ask only material product questions or required permissions.
- When the Mac app is usable, annotation, notes, review, and saving belong in the native app. Chrome supplies capture and private page evidence. Standalone editing remains available without the app.
- The immediate friend pilot is explicitly Chrome-only on Windows and Mac. It can proceed before native-first engineering. It does not establish Windows release support.
- Preserve Nextshot branding. Do not reintroduce a generic icon or raw selector questions. Show one linked-part preview. Keep real alternatives optional and use plain labels.
- Prefer left-hand shortcuts. Pilot defaults to Option+Shift+D on Mac and Alt+Shift+D on Windows. Read actual Chrome assignments. Dev retains its separate B/G defaults to avoid collisions.
- Keep the selected dot, its image highlight, and its note aligned. Return advances notes; Shift+Return adds a line. General note is optional; Return there saves and copies. Command/Ctrl+S also saves.
- Escape focuses dot tabs before and after saving. A number selects the matching dot. Escape never closes this editor. After saving, C copies and X downloads the ZIP. Close uses native Command/Ctrl+W. Preserve normal text editing and browser keys.
- Collect element context from the frozen capture. Keep field values, placeholders, labels, and editable content out of element evidence. Use existing masked images for previews. Save must not depend on a match or AI.
- Rolling Round is separately enabled, explicitly armed, and retains 60 recorded seconds. Save a selected interval as a separate ended round. Preserve any ordinary active round. Keep no audio or typed values. Review remains issue-first.
- Rolling suggestions should be useful within one second. Suppress uncertain or late automatic issue guesses. Keep local suggestions when Jev is unavailable. Treat five megabytes as a soft target and optimize silently.
- Keep Jev processing paused. The approved pilot ceiling is $25 per calendar month, with enforceable reservation. This handoff authorizes no new paid calls, public access, or service activation.
- Ask Drew before new Astra use. Prior focused Astra planning reviews are complete. Never use prohibited model providers from the project instructions.

## Current Package

Canonical visible ZIP: `/Users/drewschulz/Developer/capso/build/friend-pilot/Nextshot-Pilot-0.1.4-382944f.zip`.

Chrome loads this folder: `/Users/drewschulz/Developer/capso/build/friend-pilot/Nextshot-Pilot/extension`.

The ZIP has 18 files and 128,528 bytes. SHA-256: `7ac39c37f6a40f743c12ec3e87ac087deddaf04b2263156b9f8887cac007f73e`. The audit records clean runtime source `382944f`. Every extracted file matches the ZIP. Do not repackage or ask for another Reload solely because a documentation commit changes HEAD.

Pilot ID: `ffnikmhbnlgmfeniemlmfniihooipmcd`. Dev ID: `ghmidcmcjigfckaiopacgpfaffofgjel`. Preserve both public keys and the capture command name. Do not replace the installed folder with a new identity or remove saved browser data.

## Evidence And Acceptance Limits

| Evidence | What it proves |
| --- | --- |
| Drew, installed regular Chrome | D-key capture, branded icon, dot/note alignment, Return note flow, Command+S saving, and Esc then 1 before and after saving |
| Earlier installed exports | Capture/save/copy/export, corrected button and field matches, covered fields, empty field text, and portable paths; #183 and #184 are closed |
| Current production editor over isolated HTTP | Real Chrome and IndexedDB; keyboard-only notes, multiline retention, selected-dot recovery, save, copy, actual ZIP download and inspection, visual alternatives, and both Escape states |
| Current local checks | TypeScript and both builds; profile boundaries; 13 runtime, 12 editor, 26 workflow, 22 key-boundary, 24 Escape, and 57 local Jev assertions; matching, icon, and shortcut guards |
| Runtime CI | Successful at `382944f`; documentation-head CI must be checked separately |

Drew's last result is: "Yes, saving and note navigation both work." This verifies the installed Escape correction. It does not establish a fresh 0.1.4 ZIP/clipboard-content inspection, full browser restart recovery, friend results, Windows OS behavior, overall UX acceptance, native editing, or native Rolling usability.

The Escape regression matters: the old editor used Escape for navigation before Save and Close after Save. The first smoke instruction missed that difference. The corrected handler and tests cover both states. Do not restore Escape-to-Close.

## GitHub Work Map

[#124](https://github.com/spurs-planks-smithers/Capso/issues/124) is the open umbrella. Its delivery, pilot, and native items are formal sub-issues. #157 is its closed Rolling Round child. #148 remains a closed, optional linked Apple follow-up, not a required native-first dependency.

| Issue | State and remaining work |
| --- | --- |
| [#182](https://github.com/spurs-planks-smithers/Capso/issues/182) | Open. Finish current package handoff checks and restart recovery. Obtain real Chrome-only friend results on Windows and Mac. |
| [#177](https://github.com/spurs-planks-smithers/Capso/issues/177) | Open. Current save/navigation correction is accepted. Broader standalone, native, and Rolling usability remain unaccepted. |
| [#178](https://github.com/spurs-planks-smithers/Capso/issues/178) | Open, N1. Prove native trigger permissions, closed-app discovery, temporary active-review transport, idle teardown, and media limits. |
| [#179](https://github.com/spurs-planks-smithers/Capso/issues/179) | Open, after #178. Editable draft ownership, routing, staged/final receipts, recovery, and exactly-once publication. |
| [#180](https://github.com/spurs-planks-smithers/Capso/issues/180) | Open, after #179. Native annotation, frozen element context, coordinate transforms, and native prompt copying. |
| [#181](https://github.com/spurs-planks-smithers/Capso/issues/181) | Open, after #180. Native Rolling review and selected-evidence save. |
| [#172](https://github.com/spurs-planks-smithers/Capso/issues/172) | Open. Final native/browser package and smoke after required engineering and usability evidence. |

Closed baseline: #148, #157, #166 through #171, #174 through #176, #183, and #184. Their original evidence does not establish the revised native-first experience. Read full issue comments before recommending a change. Do not infer completion from closed-issue counts.

## What To Read

Read the current handoff first. Historical discovery records contain superseded planning-only and Mac-required statements. Later dated decisions and the user's instructions govern.

1. `docs/decisions/2026-10-29-browser-native-first.md`.
2. `docs/superpowers/plans/2026-10-28-chrome-extension-implementation.md` and `2026-10-29-chrome-friend-pilot.md`.
3. `docs/superpowers/plans/2026-10-29-chrome-workflow-simplification.md` and `docs/sessions/2026-10-29-browser-visual-targets-and-keys.md`.
4. `docs/research/2026-10-28-chrome-swift-integration.md`, `2026-10-29-chrome-pilot-performance.md`, and the Chrome/Rolling discovery records under `docs/plans/`.
5. Existing architecture and service specs under `docs/superpowers/specs/`; the execution history is `docs/sessions/2026-10-28-chrome-extension-execution.md`.

## Code And Checks

Browser entry points are `browser-extension/src/{pilot-background,pilot-popup,background,popup,capture,content,frame-context,review,shortcut}.ts`. Keyboard handling is `src/ui/keyboard.ts`. Persistence/export are under `src/core/`. Chrome uses Manifest V3 and TypeScript. Swift runs in the Mac app and native helper. Recording and Rolling have separate controllers and review pages. The isolated Jev service is `site/jev/`.

The native bridge is `Packages/BrowserBridgeKit/`, `App/Feedback/BrowserImportCoordinator.swift`, and `scripts/register-browser-host.py`. Read contracts before changing the Swift app. Match source flags against runtime overrides before native trials. On m5pro, only Nextshot Dev may run.

Start verification with the existing commands:

```bash
npm --prefix browser-extension run check
npm --prefix browser-extension run build
npm --prefix browser-extension run build -- --pilot
```

Existing scratch checks are in `build/chrome-execution/`, including `friend-pilot/`, `workflow-177/`, `element-177/`, `escape-177/`, and `shortcut-default/`. They exist in this checkout but are not tracked or CI acceptance. Preserve this ignored evidence; do not clean it away during the handoff. Do not add a framework or gate for routine UI work. Run relevant existing Swift checks when native code changes.

Use `python3 -I browser-extension/package-dev.py --pilot` only when a new runtime candidate is needed. Verify its audit, source cleanliness, identity, archive, and visible-folder hashes before requesting a manual Reload. `npm` dependencies require `--include=dev` in Drew's production-default shell when installation is needed.

## Review And Continuation

First assess the implementation, source/issue drift, privacy, state recovery, keyboard behavior, and overhead. State concrete gaps and recommend the smallest next step. Continue authorized work through #182 and the existing native sequence. Verify the native design checkpoint in #177 before native UI changes. Do not treat the standalone screenshots as native-design acceptance.

Keep a clear evidence boundary between fixtures, installed user results, and actual Windows/native behavior. Reuse settled product choices. Ask only material questions. Avoid another long sequence of trivial smoke confirmations. When manual action is required, give one clear step and wait.

Use regular Chrome, never Chrome for Testing. Codex's browser tool blocks extension-internal pages and extension management. Do not bypass that through raw CDP, profile files, AppleScript, or another automation path. Explain the actual blocker if a manual action is required.

The controlled source fixture may remain on `127.0.0.1:54178`, served by `build/chrome-execution/friend-pilot/fixture.py`. It remains available to avoid breaking the user's test tab. The separate review fixture servers are stopped. Preserve regular Chrome, user tabs, installed packages, exports, and native app state.

Stage explicit paths. Use the routed Git and `~/.local/bin/gh` commands. Run full `github-route status` before GitHub writes. Add no AI attribution. Keep Later placement. Close only issues whose required evidence exists. Do not merge, release, publish, send invitations, activate paid services, or install production Nextshot without separate authorization.
