# Chrome Workflow Simplification Implementation Plan

> For agentic workers: use superpowers:executing-plans for inline execution. The user authorizes execution in chat. One approved Astra planning review supplies this plan.

**Goal:** Make standalone feedback follow mark, note, Done, with automatic optional page context and reliable local recovery.

**Architecture:** Reuse the current browser capture and editor. Keep matching separate from detail rendering. Use the existing IndexedDB draft and round store. Keep native-first delivery in its existing serial issues.

**Tech stack:** TypeScript, browser DOM, IndexedDB, Chrome Manifest V3, existing esbuild tooling.

**Spec:** [Workflow issue #177](https://github.com/spurs-planks-smithers/Capso/issues/177), the rendered review proposal, and the user's October 29 execution instruction. Preserve the [native-first decision](../../decisions/2026-10-29-browser-native-first.md).

## Global Constraints

- Keep every issue in Later and exclude Chrome from v0.5.0. Open no public release.
- Use the existing isolated checkout and branch. Stage each changed path explicitly.
- Add no permissions, dependencies, schema fields, permanent test framework, or provider calls.
- Keep field pixels covered. Exclude field values, labels, and editable text from element evidence.
- Keep native ownership, native annotation, and native Rolling review in #178 through #181.
- Use regular Chrome. Do not bypass the browser tool's restrictions on extension-internal pages.
- Preserve the user's current unsaved capture. Update installed files only after local verification and a clean package.
- Keep #177 open through its broader native and Rolling usability acceptance. Close matching bugs only after their actual acceptance evidence exists.

## Review Focus

- Initial selection must preserve a stored general note.
- Saved feedback must not change through note or detail navigation.
- Undo and redo must preserve notes, choices, and contiguous mark IDs.
- Draft writes must finish before final save or explicit discard. Late writes must not recreate a saved draft.
- A failed cleanup message must not misreport a successful store commit.
- A missing match or unresolved ambiguity must not block Done.

## Task 1: Establish Real Browser Evidence

Files: ignored scratch under `build/chrome-execution/workflow-177/` and the existing editor checks.

- [x] Build the production editor over an isolated HTTP fixture with real IndexedDB.
- [x] Reproduce general-note loss before changing production code. The seeded note loads empty.
- [x] Extend the existing scratch editor checks for notes, readonly state, completion failures, and draft ordering.
- [x] Preserve actual export geometry and existing nearby-match regressions.

## Task 2: Simplify Editing And Matching

Files: `browser-extension/src/review.ts`, `browser-extension/public/review.html`, `browser-extension/public/style.css`.

- [x] Replace the primary action with Done. Explain once that it saves and copies the prompt.
- [x] Replace Previous/General/Next with explicit mark selection and an optional general note.
- [x] Clicking an existing badge selects its note. Show the selected badge clearly.
- [x] Put ordinary page information inside collapsed Page details. Use ordinary element names for optional ambiguity choices.
- [x] Reconcile matches on editable draft load, mark creation, history restoration, and final save.
- [x] Preserve a valid existing elementId. Automatically assign only a sole candidate. Leave ambiguity unresolved without blocking Done.
- [x] Remove the duplicate choices map. Detail rendering never mutates feedback.
- [x] Keep selectors, nearby inference context, and optional assistance source labels secondary.

## Task 3: Preserve Notes, Drafts, And History

Files: `browser-extension/src/review.ts`. Reuse the existing store without changing its schema.

- [x] Initialize the selected note without writing the empty textarea first.
- [x] Preserve general and per-mark notes through selection, undo, redo, and readonly viewing.
- [x] Persist editable drafts after a short edit debounce. Serialize writes and coalesce revisions.
- [x] Flush the draft queue before final save. Stop and drain writes before explicit discard.
- [x] Invalidate optional assistance on selection, note, history, and completion changes.
- [x] Disable unavailable history and saved editing controls. Keep saved note navigation available.

## Task 4: Complete Once And Recover Truthfully

File: `browser-extension/src/review.ts`.

- [x] Freeze editing during Done and commit the capture once.
- [x] Treat saveCapture completion as durable success. Handle cleanup messaging separately.
- [x] Attempt prompt copying after save. Keep Copy prompt and Export round available when copying fails.
- [x] Keep the review page open for sharing. Replace Cancel with Close after saving. Require no second completion step.
- [x] Keep optional native delivery separate from clipboard and export status. Catch its failures.
- [x] Retain editable notes and a retryable Done action on store failure.

## Task 5: Verify And Package

Files: pilot instructions, changelog, execution record, and existing packaging scripts.

- [x] Keep the pilot popup's single capture action and collapsed saved rounds.
- [x] Update instructions for Done. Preserve current Dev trial, consent, and Rolling controls.
- [x] Run TypeScript, both builds, existing runtime/editor/profile checks, and actual-export matching regressions.
- [x] Use real Chrome DOM, IndexedDB, and actual downloaded exports to verify note retention, matching, save, copy recovery, and round reopening.
- [x] Render empty, single-mark, two-mark, ambiguous, and saved states. Check the resulting images.
- [x] Obtain one focused standard-model source review. Reuse the approved Astra plan without another Astra call.

- [x] Commit and push explicit paths. Build a clean, hash-verified pilot package and update the existing visible folder.

Runtime implementation is committed in 5b0720c. The final test card asks about capture and notes instead of requiring users to inspect automatic element matching. Record the latest package checksum and CI status in #177 and #182.

- [ ] Complete the remaining installed acceptance at the manual browser boundary. Preserve the current capture until saved or explicitly discarded by the user.
- [ ] Verify corrected exports before closing #183 and #184. Keep #182 open for actual Windows and Mac friend acceptance.

## Scope Rulings

The user explicitly requests planning followed by execution. Do not add a second plan approval step. The earlier rendered proposal establishes the standalone design direction.

The browser review page stays open after Done because standalone users need access to export and clipboard recovery. Closing it automatically would add a recovery step.

Draft saving runs only during editing. It introduces no idle polling or permanent helper. Reuse the existing store and retain feature defaults.

A real immediate-reload check exposes a race before the debounced IndexedDB write starts. A tab-local sessionStorage journal retains only bounded marks and reviewer notes. Restore it only over an existing valid draft and validate the merged capture. Clear it after the latest durable write, final save, explicit discard, a missing draft, or Rolling invalidation. It contains no image or page evidence and has no wall-clock expiry. It cannot restore a missing or expired source draft.

The HTTP fixture verifies production editor logic and a real browser store. It cannot establish installed-extension acceptance or Windows behavior. Keep those limits explicit.

## October 29 Branding And Clarity Correction

Drew rejects the remaining unclear workflow, generic icon, and missing Nextshot branding. He asks for keyboard capture, clearer dot-to-note guidance, and sharing labels that explain their results. This supersedes the earlier Done label. The implementation keeps one completion action named Save & copy instructions. Sharing uses Copy instructions and Download ZIP, with a short explanation of text versus image handoff.

- Export browser raster icons from the existing approved Icon Composer source. Preserve its artwork. Use those assets in both manifests, toolbar, page favicon, and visible headers.
- Query Chrome's actual capture shortcut in the popup and editor. Show setup when it is unassigned. Never silently replace another extension's key.
- Keep the configured Option+Shift+B or Alt+Shift+B suggestion. Dev and Pilot request the same combination, so a collision is possible. User-managed assignment remains Chrome's responsibility.
- Explain that each numbered dot owns one note. Keep the selected dot and note label aligned. Use the approved graphite and teal palette.
- Reject missing or incorrectly sized brand icons during packaging. Add no permissions or dependencies.

Chrome's [Commands API](https://developer.chrome.com/docs/extensions/reference/api/commands) documents blank assignments and collisions. Its [icon rules](https://developer.chrome.com/docs/extensions/reference/manifest/icons) require raster formats. The macOS app continues to ship the original Icon Composer file.

The assigned and unassigned shortcut states are tested in the isolated browser fixture. This does not establish the key assigned to Drew's installed Pilot. A manifest reload is required to activate new toolbar icons. Prepare and verify the full package before requesting that manual action.

## October 29 Default Shortcut Correction

Drew confirms that Pilot's capture shortcut is unassigned. He requires a default at installation. This supersedes the earlier ruling that retained the same suggestion in both profiles. Pilot 0.1.1 requests Option+Shift+P on Mac and Alt+Shift+P on Windows. Dev retains B for capture and G for Rolling Round. The capture command name and each extension's identity stay unchanged.

Chromium's [command service](https://github.com/chromium/chromium/blob/main/chrome/browser/extensions/commands/command_service.cc) attempts a new default on update when the former suggestion was never assigned. It preserves custom assignments and keys the user cleared after assignment. It does not overwrite an occupied key. This source behavior supports an update repair, but installed Chrome acceptance requires a reload and actual shortcut readback.

The existing packager rejects missing capture defaults and overlap between Pilot capture and any Dev command on Mac or Windows. Verify that rejection before changing the conflicting manifests. Run both builds and the existing browser checks before packaging. Update the same visible Pilot folder only from a clean, verified package. Ask for one manual reload, then verify automatic assignment before testing keyboard capture.

## October 29 Left-Hand Shortcut Correction

Drew confirms that Chrome assigns Option+Shift+P automatically and that the shortcut opens an actual capture. He then requires left-hand hotkeys and explicitly chooses Option+Shift+D. This supersedes the preceding P default. Pilot 0.1.2 requests Option+Shift+D on Mac and Alt+Shift+D on Windows. Dev retains its separate B/G defaults. No capture behavior changes.

Chromium source supports moving an untouched assigned default during update. A custom or intentionally cleared shortcut remains protected. Verify the installed D key after one reload. Keep broader usability, native-first work, Windows acceptance, and friend tests open. Keep all work in Later and outside v0.5.0.


## October 29 Visual Targets And Keyboard Flow

Drew rejects repeated Page item choices and code paths. The selected target remains one linked part. Show it once with an outlined preview from the existing masked clean image. Keep real alternatives optional and use plain names. Do not ask a reviewer to interpret selectors. Preserve raw evidence for the receiving agent. A generic container alone creates no new choice.

Drew requires keyboard operation after placing dots. He approves the Mac note flow: Return saves a note and advances; Shift+Return adds a new line. General note is optional, and Return there saves and copies. Show action hints in the editor, popups, and Dev review pages. Keep secondary controls reachable by native Tab, Enter, Space, and arrow behavior.

- Restore the selected dot in the same tab. Otherwise start at the last mark. Keep its tab, image highlight, and note aligned.
- Escape leaves note entry and focuses the selected dot tab. Number keys select dots outside typing. Arrow keys and Home navigate the tab list. Follow the WAI tabs pattern.
- Keep Command/Ctrl+S for Save. Keep normal text undo inside notes. Use Command/Ctrl+Z for marks outside typing.
- After saving, C copies instructions, X downloads the ZIP, and Escape closes. Before saving, Shift+X explicitly discards outside typing. Plain Escape never discards notes.
- Preserve Chrome close-tab keys and native Nextshot global keys. Add no extension command, permission, service, or polling.
- Optional settings and saved-round actions use focus-scoped keys or native control activation. A collapsed Keyboard controls guide explains the scope.
- Repeated Return cannot advance or save. Composition and typing retain native behavior. Ignore hidden and disabled actions.

Validate production editor code in regular Chrome with real IndexedDB and an actual downloaded ZIP. Distinguish this isolated HTTP fixture from installed-extension acceptance. Verify the current package after one reload. Keep #177 open for broader usability, native-first work, and Rolling acceptance.


## October 29 Escape Correction After Installed Feedback

Drew reports that Escape closes the installed view during note navigation. Reproduction confirms that saving changes Escape from note navigation to Close. This supersedes the Escape-to-Close rule above. Plain Escape must focus the current dot tab before and after saving. Number selection must open the matching note without closing or changing saved evidence. Show Command+W on Mac or Ctrl+W on Windows for Close and preserve native browser handling. Cover both view states before another installed smoke request.


## October 29 Handoff Status

Drew confirms installed 0.1.4 saving and Esc-then-1 navigation before and after saving. The Escape finding is accepted; broader #177 usability remains open. Corrected installed exports already close #183 and #184. Keep #182 open for current export/restart and actual Windows/Mac friend results. Native-first issues #178 through #181 and final #172 remain open. See [the handoff](../../sessions/2026-10-29-chrome-extension-handoff.md) for the current runtime, package, checks, and continuation order. Drew requests no further implementation in this Codex run.
