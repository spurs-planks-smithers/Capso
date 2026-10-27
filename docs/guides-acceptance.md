# Nextshot Guides acceptance

Verified October 27, 2026. This closes the two acceptance checks left after the Guides launch in [PR #116](https://github.com/spurs-planks-smithers/Capso/pull/116).

## Native capture to a local agent

The native test uses the installed Nextshot Dev 0.4.0-dev (866), which has Screen Recording access. The extracted release copy, Nextshot 0.4.0 (804), reports no access. This test does not claim to verify that release binary. No permission setting changes.

The target is the fictional Lemonaid page from the Guides practice project. No private screen content enters the test.

1. Start a real area capture through Nextshot Dev's Capture Feedback action.
2. Select the fictional shop in Chrome, then place three marks with the native counter tool.
3. Save the capture and answer each native note question.
4. Run Copy Feedback Prompt, which uses the same controller path as Copy Prompt and End Round.
5. Read the operating system clipboard and compare it with the ended round's `prompt.md`. They match exactly.
6. Give that copied prompt to a fresh local agent. It opens the annotated PNG, the manifest, and the practice source before returning its plan table.

| Item | Visible target | Saved instruction | Agent plan |
| --- | --- | --- | --- |
| 1.1 | Lemonaid heading | Change the title from Lemonaid to Lemonade. | Change the shop heading. |
| 1.2 | $9 a cup | Change the price to $3 a cup. | Change the displayed price. |
| 1.3 | Small yellow Buy button | Make the Buy button larger and easier to click. | Increase its font, padding, and click area. |

The agent confirms all three marks and notes. It finds no mismatch or missing instruction. It correctly leaves the unmarked checkout labels and totals outside its plan. The acceptance check ends at the plan table, before code edits.

The actual app bundle is `~/Library/Application Support/Nextshot/2026-10-27-1421-feedback/`. It contains one 1918-by-1108 capture and three instructions. Its ended time is 2026-10-27 21:22:26 UTC, or 14:22:26 in Phoenix.

The temporary Shortcuts helper is removed. The existing user shortcut remains. The test round remains on disk. Other active work is preserved.

The Shortcuts command does not return its requested output file. Its client is canceled after the app completes the action. Clipboard comparison, the saved ended time, and the independent agent read confirm the handoff result without relying on that client output.

Local evidence lives in `build/closeout/native/`: `annotated.png` and `copied-prompt.txt`. These files come from the native app, not a generated bundle fixture.

## Published video, issue #30

The [published onboarding video](https://nextshot.dev/media/Nextshot-onboarding-2026.10.24.mp4) matches the reviewed local release asset byte for byte.

| Property | Verified value |
| --- | --- |
| Size | 13,309,268 bytes |
| Duration | 81.733333 seconds |
| SHA-256 | `9590261ab4d03f9f7f3fd971e0543ec68038ab1e7222606cbc505f859119ac2d` |

At 56 to 57 seconds, the visible menu reads Round, All Rounds, and Copy Prompt and End Round. The full narration uses round. Text recognition of 82 frames sampled once per second finds no Session label. Visual review of the contact sheet and the menu frame finds no further material defect.

No source change or rerender is required for [issue #30](https://github.com/spurs-planks-smithers/Capso/issues/30). The published file already contains the corrected terminology.

Local evidence lives in `build/closeout/video/`: the downloaded `published.mp4`, `menu-57s.png`, `contact.png`, `ocr.txt`, and `narration.srt`.

See [[site-guides]] for guide maintenance and publishing.
