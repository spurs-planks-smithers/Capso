# Browser Visual Targets And Keyboard Flow

## User Findings

Drew confirms that Option+Shift+D opens a real installed Pilot capture. He then reports that repeated Page item choices and div/main paths are illogical. He wants plain names or small screenshot examples. He requires keyboard use after placing dots and visible action shortcuts. He approves Return to advance through notes and Shift+Return for a new line, matching the Mac note flow.

## Cause And Change

Matching preserves a selected element ID. The old rendering still lists every candidate as a button and repeats its selector below. Overlapping containers appear as several identical choices even after one is selected.

The editor now shows one linked part with an outlined thumbnail. Thumbnails use the existing masked clean image. Bounds already use capture pixels, so no second viewport transform applies. Clip previews to the captured image. Do not recapture, read fields, persist thumbnails, or change the evidence schema.

Real alternatives remain optional. Use plain labels such as Button, Heading, Text, Text field, or Page section. Raw selectors remain in exported evidence for agents. A generic container alone creates no extra choice. An unmatched mark with one meaningful candidate still permits an optional choice. Saving never requires a choice.

## Keyboard Behavior

| Action | Key |
| --- | --- |
| Website capture | Actual Chrome assignment, default Option+Shift+D on Mac or Alt+Shift+D on Windows |
| Save and copy | Command+S on Mac, Ctrl+S on Windows |
| Advance from a note | Return; General note then saves and copies |
| Add a line | Shift+Return |
| Select another dot | Esc, then its number; arrow keys and Home also navigate the dot tabs |
| General note | G outside typing |
| Dot, arrow, box | N, A, R outside typing |
| Mark undo or redo | Command/Ctrl+Z or Shift+Command/Ctrl+Z outside typing |
| Copy saved instructions | C outside typing |
| Download saved ZIP | X outside typing |
| Close saved feedback | Command+W on Mac, Ctrl+W on Windows, handled by Chrome |
| Explicitly discard unsaved capture | Shift+X outside typing |
| Focus and activate secondary controls | Tab, Shift+Tab, Enter, Space, or native arrow keys |

Popup and Dev review actions receive direct hints where practical. Saved-round C/X keys apply to the focused round. Secondary buttons show Enter when focused. A collapsed keyboard guide explains the scope. Capture hints read the actual Chrome command assignment.

Keep the current dot tab, image highlight, and note in sync. Restore the selection within the same tab. Otherwise open the last mark. Escape focuses dot navigation in editable and saved feedback without closing or discarding. Preserve normal text undo, composition, Chrome close-tab keys, and native Nextshot global keys. Repeated Return cannot advance or save. Hidden and disabled actions do not run.

## Evidence And Limits

- Regular Chrome renders production editor code through an isolated HTTP fixture with real IndexedDB. This is separate from extension storage.
- The supplied screenshot and a reproduced container case establish the duplicate-choice defect. New renders verify generic, field, matched-button, and ambiguous states.
- A keyboard-only trial switches notes, preserves a multiline note through reload, advances with Return, saves, copies, and downloads a real ZIP.
- The ZIP retains both dot notes, the general note, their element IDs, and the line break. Field text remains empty. A keyboard-selected target collapses to one card.
- A held Return advances only once. Twenty-two scratch boundary cases exercise Mac/Windows labels, text editing, native keys, composition, repeats, and hidden or disabled actions.
- Existing runtime, editor, workflow, matching, profile, icon, shortcut, and local Jev checks pass. No live provider call runs.
- Focused reviews catch and resolve repeated Return, Escape canceling Rolling edits, and a sole meaningful candidate without a selection control.

Installed acceptance for this new interface remains pending. Windows and friend results, full browser restart acceptance, native-first editing, and broader Rolling usability remain open. Keep #177 and #182 in Later and exclude Chrome from v0.5.0. No public release.

The note tabs follow the [WAI tabs pattern](https://www.w3.org/WAI/ARIA/apg/patterns/tabs/). This work does not establish full accessibility compliance.


## October 29 Escape Correction

Drew confirms that Dot 2 and its note stay aligned in installed Pilot 0.1.3. He then reports that Escape closes the view during the Esc-then-1 test. Source reproduction confirms a saved-view close path: Escape means navigation before saving but Close after saving. The smoke instructions failed to account for that state difference. The exact state of Drew's closed view is not observable through the permitted browser tool.

Pilot 0.1.4 removes the state-dependent meaning. Plain Escape focuses the current dot tab in both views. The number key then selects the matching dot and note. Close displays Command+W or Ctrl+W and leaves handling to Chrome. The explicit Close button remains available. Modified Escape keys and composing events retain their native behavior. The previous Escape-to-Close rule is superseded.

A scratch regression reproduces the saved-view closure before the change. Twenty-four regression checks cover editable and saved views on Mac and Windows, preserve saved evidence, and leave Chrome's close key unhandled. Real Chrome tests of the production editor over HTTP verify Esc then 1 in both views. The browser tool cannot establish native Command+W acceptance through its tab key API. Chrome's official shortcut guide documents that key. Installed acceptance remains pending the updated package.


## October 29 Installed Acceptance And Handoff

After reloading Pilot 0.1.4, Drew confirms dot/note alignment and Esc then 1 in the editable view. He then completes notes with Return, saves with Command+S, and confirms Esc then 1 opens Dot 1 while the saved editor stays open. His answer is "Yes, saving and note navigation both work." The reported Escape correction now has installed acceptance. Runtime CI succeeds at `382944f`.

This supersedes the pending installed-navigation status above. Fresh 0.1.4 ZIP/clipboard inspection, restart recovery, Windows/Mac friend results, broad UX acceptance, and native-first work remain open. Drew then requests a stop to implementation and a documented Claude Code handoff. See [the current handoff](2026-10-29-chrome-extension-handoff.md). Do not rebuild the installed runtime for documentation-only changes.
