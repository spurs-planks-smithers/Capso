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
| Close saved feedback | Esc |
| Explicitly discard unsaved capture | Shift+X outside typing |
| Focus and activate secondary controls | Tab, Shift+Tab, Enter, Space, or native arrow keys |

Popup and Dev review actions receive direct hints where practical. Saved-round C/X keys apply to the focused round. Secondary buttons show Enter when focused. A collapsed keyboard guide explains the scope. Capture hints read the actual Chrome command assignment.

Keep the current dot tab, image highlight, and note in sync. Restore the selection within the same tab. Otherwise open the last mark. Escape leaves note entry without discarding. Preserve normal text undo, composition, Chrome close-tab keys, and native Nextshot global keys. Repeated Return cannot advance or save. Hidden and disabled actions do not run.

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
