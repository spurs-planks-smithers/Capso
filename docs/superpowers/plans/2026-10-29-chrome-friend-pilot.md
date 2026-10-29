# Chrome-only friend pilot

Date: 2026-10-29. Owner: Drew. Execution authorized in chat. Keep Later and outside v0.5.0.

## Current direction

Drew requests the fastest useful external test and a test he can run himself. His latest instruction makes the friend pilot Chrome-only on Windows and Mac. This supersedes his immediately preceding extension-plus-app selection for this pilot. The native-first product direction remains in the roadmap. It does not block this explicitly standalone pilot.

The browser foundation already supports capture, marks, notes, element matching, local rounds, copied prompts, and portable export. Native drafts and native Rolling review remain unfinished. PRs #161 and #173 remain draft and unmerged. No public release is implied.

## First pilot boundary

Use ordinary capture for the first test. Keep a small popup with Capture and a collapsed saved-round section. Put ending a browser round inside that section. Reuse the existing review editor. Use the correct save shortcut label on Mac and Windows.

Build a separate Nextshot Pilot extension identity. Do not replace Drew's Dev extension or inherit its native/AI settings. The pilot has no native host, account, cloud assistance, recording, or rolling controls. Exclude their runtime entry points and optional permissions from this package. The full Dev build keeps its existing capabilities and defaults.

Keep capture-time proof, private-field masks, permitted embedded-frame context, ambiguity choice, local saving, and relative export paths. Request site access only for deliberate captures. Keep the popup free of trial flags and configuration questions.

The ordinary flow is: open a safe website, capture an area, mark it, add a note, then save and copy the prompt. Export is available after Save and from saved rounds. Store all feedback locally. Exported files can contain visible private content. No automatic upload or telemetry is added.

Tracking: [Chrome-only friend pilot #182](https://github.com/spurs-planks-smithers/Capso/issues/182) is a formal child of #124. Keep it open through the required user and friend results.

## Serial execution

| Order | Work | Exit evidence |
| --- | --- | --- |
| P1 | Isolate a browser-only build profile and common capture path | Pilot manifest excludes native, model, recording, and identity permissions. Dev build remains intact. |
| P2 | Render the minimal popup and platform labels | Actual rendered preview, clear Capture action, saved rounds collapsed, no trial controls. |
| P3 | Package the pilot for Mac and Windows | Deterministic ZIP, clean source revision, hashes, plain-text installation guide, and short test card. No native executable or setup script. |
| P4 | Verify capture and handoff | Actual Chrome capture, marks, element match, local save, clipboard, export, restart recovery, and error handling. Separate OS evidence from simulated checks. |
| P5 | Drew smoke | Load the pilot once in regular Chrome. Complete one capture and export. Record usability feedback before friend handoff. |
| P6 | Friend smoke | Use the same package on Windows Chrome and Mac Chrome. Record browser/OS version, save/copy/export results, and remaining friction. |

The existing #178 through #181 native sequence remains separate. #177 stays open for full workflow refinement. #172 and #124 stay open for broader acceptance. Do not close those issues from the narrower pilot result.

## Distribution

Use a ZIP with one clearly named extension folder. Chrome's Load unpacked path is the first private delivery route. It requires one-time Developer mode and manual folder selection. Do not promise a silent install or browser security bypass. A later Chrome Web Store listing can reduce that setup burden.

Save the canonical package under `build/friend-pilot/`. Give Drew an exact path and checksum. Do not overwrite a released artifact. Build the final package from a clean commit. No email, message, public upload, or friend invitation is sent without explicit delivery instructions.

## Validation and stop conditions

Run existing TypeScript checks and build both profiles. Verify the packaged runtime excludes native/model transports. Check archive contents, required permissions, secret patterns, deterministic rebuilds, and relative bundle paths. Use targeted scratch checks rather than adding a test framework or CI gate.

Use regular Chrome for Drew's visible smoke. Browser policy requires manual unpacked installation. Prepare the complete package before requesting that step. Never infer a user smoke pass from a ready Save button.

The local machine is a Mac. Windows-specific installation, clipboard, and download acceptance need the friend's actual Windows run. A Windows user agent or platform stub proves only the code branch. Keep that limitation explicit.

Keep Jev processing paused. Spend no provider allowance. Install no production Nextshot on m5pro. This Chrome-only pilot requires no app installation or native permission changes.

## Execution evidence

The separate pilot identity is `ffnikmhbnlgmfeniemlmfniihooipmcd`. Its generated package has thirteen files. Profile verification excludes native, AI, identity, and recording permissions and transport code. TypeScript and both build profiles pass. Thirteen mocked runtime checks cover permissions, continuation, sender trust, and disabled capabilities. Twelve editor fixture checks cover platform hints, element matching, notes, copy failure, and export. Existing 57 Jev client assertions pass without live calls. The common capture body matches the prior verified implementation exactly.

The popup preview is rendered in regular Chrome. An independent source review reports no actionable findings. CI passes at runtime source `465b23b`. Drew confirms loading Pilot, capturing the test page, adding a dot and note, saving, and pasting the expected prompt. Export inspection, saved-round recovery, and actual Windows acceptance remain pending. The friend instructions clarify that an agent needs the exported ZIP with the copied prompt.

Chrome documents the [unpacked installation route](https://developer.chrome.com/docs/extensions/get-started/tutorial/hello-world#load-unpacked). Private and unlisted Store items still require review. A later [Store distribution](https://developer.chrome.com/docs/webstore/cws-dashboard-distribution) task can reduce installation effort. No Store upload occurs under this pilot.
