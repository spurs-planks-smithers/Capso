# Nextshot Chrome Extension Pause

Date: November 7, 2026, America/Los_Angeles. Drew paused all Chrome extension testing and development. All Chrome work moves to the **Later** milestone. No Chrome issue closes because of this pause. Resume only when Drew says so.

## Stop Rules

- Run no Chrome tests, spikes, or smoke checks.
- Write no extension or native-bridge code.
- Contact no friends. Start no paid service. Use no Astra. Do not merge PR #173.
- Keep every Chrome issue open in Later, outside v0.5.0.
- Nothing in this pause removes or changes the installed Pilot or Dev extensions.

## State At The Pause

| Item | State |
| --- | --- |
| Branch | `codex/chrome-extension`, draft [PR #173](https://github.com/spurs-planks-smithers/Capso/pull/173), unmerged. `build-and-test` passed on the last checked head. |
| Pilot build | 0.1.6 candidate from `f19dc3f`. ZIP `Nextshot-Pilot-0.1.6-f19dc3f.zip`, 130,671 bytes, 18 files, SHA-256 `24f4f1d85a32a5f11480851cde767a4d91dd8bc4ac4df01c09a9790e67591732`. |
| Pilot folder | `/Users/drewschulz/Developer/capso/build/friend-pilot/Nextshot-Pilot/extension` matches the 0.1.6 ZIP file for file (checked read-only). Chrome has not been told to Reload. |
| Native design | Rendered checkpoint in `docs/design/2026-10-30-native-browser-flow-checkpoint.md`. Drew chose three items on 2026-10-30. He has not accepted the design as a whole. |
| Native code | None. The Swift bridge still imports finished browser reports only. |
| Chrome-only friend pilot | No Windows result. No friend result. No contact made. |

## Decisions Made Before The Pause

- Trigger: native shortcut with a drag (7 inputs, no extra browser tab).
- Keys in a browser draft: the settled browser keys. Esc picks dots, the last Return saves and copies, Command or Control+S also saves.
- After save: the panel stays open so C and X work. Close with Command or Control+W.
- #178 item 1b: option A. The native shortcut makes an ordinary capture with no automatic page details. Details come from the Chrome key. Options B and C are not built.

## Evidence By Tier

| Claim | Tier |
| --- | --- |
| Pilot 0.1.4 saving and note navigation | installed, Drew |
| Pilot 0.1.6 fixes for draft recovery, element labels, Incognito block, key rules | fixture and local checks only |
| Pilot 0.1.6 Reload, Resume focus, restart recovery, Esc-then-1 after save | **not observed** (Drew's five-step check was never run) |
| Native trigger needs Screen Recording only | installed (code read) |
| Closed-app discovery through the Swift bridge | installed |
| Temporary review transport, idle teardown | fixture (Chrome for Testing 153); idle hold not observed in installed Chrome |
| Toolbar click grants capture, Apple Event helper to app, 5 MB host to extension, 2 MB extension to host | installed Chrome 156 (throwaway extension) |
| macOS 15 media playback | **not observed**. The test Mac runs macOS 27.0.1. MP4 H.264 plays and WebM does not there. |
| Windows behavior of any Chrome flow | **not observed** |

Finding for #179: a repeat toolbar click opens a second connection and ends the first. The extension must ignore a click while a review is open.

## Open Work, All In Later

Read each issue's full comment history before you resume. Resume in this order.

| Order | Issue | Remaining work |
| --- | --- | --- |
| 1 | [#177](https://github.com/spurs-planks-smithers/Capso/issues/177) | Drew accepts or changes the native design as a whole. Run the Pilot 0.1.6 five-step check first (below). |
| 2 | [#178](https://github.com/spurs-planks-smithers/Capso/issues/178) | macOS 15 media run (`docs/research/2026-10-30-n1-spikes/media/probe.swift`). Optional clean idle-hold run in installed Chrome (about 3 minutes with Drew). |
| 3 | [#179](https://github.com/spurs-planks-smithers/Capso/issues/179) | Native draft ownership, routing, receipts, recovery, exactly-once publication. |
| 4 | [#180](https://github.com/spurs-planks-smithers/Capso/issues/180) | Native annotation with browser element context. |
| 5 | [#181](https://github.com/spurs-planks-smithers/Capso/issues/181) | Native Rolling Round review and selected evidence. |
| 6 | [#172](https://github.com/spurs-planks-smithers/Capso/issues/172) | Final package and browser/native smoke test. |
| Any | [#182](https://github.com/spurs-planks-smithers/Capso/issues/182) | Real Chrome-only friend results on Windows and Mac. Needs Drew's separate authorization to contact friends. |
| Any | [#185](https://github.com/spurs-planks-smithers/Capso/issues/185), [#186](https://github.com/spurs-planks-smithers/Capso/issues/186), [#188](https://github.com/spurs-planks-smithers/Capso/issues/188), [#189](https://github.com/spurs-planks-smithers/Capso/issues/189) | Fixed in 0.1.6 at fixture tier. Close only after installed evidence. #186 also needs a Windows restart check. |
| Any | [#190](https://github.com/spurs-planks-smithers/Capso/issues/190), [#191](https://github.com/spurs-planks-smithers/Capso/issues/191), [#192](https://github.com/spurs-planks-smithers/Capso/issues/192) | Scratch check suites, field-role masking, Rolling preselect. Not started. |
| Umbrella | [#124](https://github.com/spurs-planks-smithers/Capso/issues/124) | Stays open until the children close. |

## Pilot 0.1.6 Five-Step Check (Not Run)

1. Reload the extension at `chrome://extensions`. Confirm version 0.1.6 and no Allow in Incognito switch.
2. Press Option+Shift+D on a safe page. Add dot 1 and a note. Leave it unsaved. Open the popup and click Resume. Expect the existing tab focused and the tab count unchanged.
3. Quit Chrome fully and reopen it. Click Resume. Expect the dot and note restored.
4. Press Command+S, then Esc, then 1. Expect the saved view to stay open with dot 1 selected.

After you run it, record each step at the installed tier on #189, #185, #188, #186, and #177.

## Leftovers To Clear

- The throwaway #178 test extension stays in Chrome until Drew removes it at `chrome://extensions`. It is not Pilot (`ffnikmhbnlgmfeniemlmfniihooipmcd`) or Dev (`ghmidcmcjigfckaiopacgpfaffofgjel`).
- The two `com.nextshot.n1spike*` host manifests are deleted and the stand-in processes are stopped.
- The Dev bridge flag `flag.browserBridge` was set off twice for a few seconds, then restored to on and checked.
- The controlled source fixture may still run on `127.0.0.1:54178` (`build/chrome-execution/friend-pilot/fixture.py`). Stop it at will.
- `build/chrome-execution/` holds ignored scratch checks. Keep them. #190 decides their fate.

## Where To Read

`docs/sessions/2026-10-29-chrome-extension-handoff.md` (product rules and package details), `docs/design/2026-10-30-native-browser-flow-checkpoint.md`, `docs/research/2026-10-30-native-trigger-and-review-transport.md`, `docs/decisions/2026-10-30-chrome-draft-restart-recovery.md`, `docs/decisions/2026-10-30-chrome-element-evidence-labels.md`, `docs/decisions/2026-10-30-chrome-incognito-and-dev-drafts.md`, and `docs/runbooks/chrome-pilot-friend-test.md`.
