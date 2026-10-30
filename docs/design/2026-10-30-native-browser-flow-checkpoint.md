# Native browser flow: rendered design checkpoint

Date: 2026-10-30. Issue: [#177](https://github.com/spurs-planks-smithers/Capso/issues/177) (checkpoint), unblocks [#178](https://github.com/spurs-planks-smithers/Capso/issues/178). Status: proposal for Drew's review. Drew has not accepted it. All Chrome work stays in Later and outside v0.5.0.

This is design only. No Swift, no native UI code, no app launch. The images are real browser renders (Chromium over local HTTP) of HTML mockups, sized 1440 by 900. They copy the look of the native Nextshot Dev help box, note panel, menu bar item, toast, and annotate window. The sources are `AGENTS.md`, `App/Feedback/FeedbackHelpOverlay.swift`, `App/Feedback/FeedbackNotePanel.swift`, and the published guide screenshots in `site/guides/public/media/`. No live Nextshot Dev window was captured. The standalone editor screenshots from #177 are not native-design acceptance and are not used here.

## Images

All files are in [2026-10-30-native-browser-flow](2026-10-30-native-browser-flow/). The HTML sources and shared `common.css` and `common.js` sit beside them. Serve the folder with `python3 -m http.server` and open any page to re-render it.

| # | Image | What it shows |
| --- | --- | --- |
| 1 | [01-native-capture-chrome-frontmost.png](2026-10-30-native-browser-flow/01-native-capture-chrome-frontmost.png) | Chrome in front on an approved site. Option+Shift+F and a drag. The normal help box is the only Nextshot UI. Page details arrive with the capture and show nothing. |
| 2 | [02-native-annotation-editor.png](2026-10-30-native-browser-flow/02-native-annotation-editor.png) | Native editor with three dots, the note panel, and one linked-part preview. The help box lists the settled keys. |
| 2b | [02b-native-saved-state.png](2026-10-30-native-browser-flow/02b-native-saved-state.png) | After save: prompt copied toast, notes with plain part labels, C copies, X exports, Esc never closes. |
| 3 | [03-states-without-chrome-context.png](2026-10-30-native-browser-flow/03-states-without-chrome-context.png) | Connected reference, bridge turned off, extension not found, site not allowed. Capture shows no extra step in any state. Status lives in Settings. |
| 4 | [04-native-rolling-round-review.png](2026-10-30-native-browser-flow/04-native-rolling-round-review.png) | Native Rolling Round review. Suggested moment preselected, 60 recorded seconds, selected interval, steps, Save as new round. |
| 5 | [05-minimal-inputs-count.png](2026-10-30-native-browser-flow/05-minimal-inputs-count.png) | Keys, pointer actions, tabs, and windows per flow, against the Pilot editor. |

## Decisions in the design

- **Nothing extra at capture.** The normal shortcut starts capture. Chrome details join automatically when Chrome is in front on an approved site. No popup, extra key, or new window appears. Without details, capture is identical (image 3).
- **Reuse the native look.** Same help box (22 point, dark glass, green round dot), same floating note panel with one question per circle, same toast, same menu bar item. The panel moves beside the capture so dots stay visible.
- **One linked part.** The note panel preview already zooms on the circle. It now outlines the linked element and shows a plain label (Heading, Text, Button) with an optional Change link. No selectors. The outline is an editor aid and is never saved into the PNG.
- **Dot tabs in the panel.** A tab row (1, 2, 3, General) shows the selected dot. Esc focuses the tabs, a number selects a dot, Return advances, Shift+Return adds a line, Command+S saves. The last Return saves and copies, so Command+S is optional.
- **Saved state.** The prompt is copied at save. C copies again, X exports the ZIP. Esc never closes. The red button or Command+W closes.
- **Status in Settings only.** A Browser section shows connected, off, extension not found, or site not allowed, with one fix action each. The saved capture records why details are missing in one plain line.
- **Rolling review is an ordinary native window.** It follows #180, which accepts an ordinary native window first. Moment first, then marks and notes with the same panel, then save. The ended round is separate. The ordinary active round is untouched. Tracking is paused during review. No audio and no typed values.
- **Steps are local and editable.** The step list shows observed actions with times. A typed value is never shown.

## Inputs, from image 5

Counts exclude typed words and the final paste. Pilot and Rolling counts come from reading `review.ts` and `rolling-review.ts`. Native rows come from this design. Nothing was timed.

| Flow | Keys | Pointer | Total | New browser tabs | What you read |
| --- | --- | --- | --- | --- | --- |
| Pilot, standalone (today) | 4 | 2 | 6 | 1 | 1 browser tab |
| Native today, no Chrome details | 5 | 3 | 8 | 0 | 2 native windows |
| Native shortcut, Chrome in front (proposed) | 4 | 3 | 7 | 0 | 2 native windows |
| Chrome key opens the native editor (fallback) | 4 | 2 | 6 | 0 | 2 native windows |
| Rolling, Dev extension (today) | 3 | 4 | 7 | 1 | 1 tab, 2 pages |
| Native Rolling review (proposed) | 4 | 1 | 5 | 0 | 1 native window |

The proposed native shortcut costs one more input than Pilot (the drag) and removes the browser tab. It is one input cheaper than native capture today, because the last Return saves. Starting Rolling review counts as one key. The real start gesture is unverified.

## Decisions

On 2026-10-30, Drew chose the recommended option for all three choices below. This settles only these three choices. Drew has not accepted the design as a whole, and #177 stays open.

1. **Trigger:** the native shortcut with a drag (7 inputs, no extra browser tab). #178 proves feasibility. If it cannot meet the permission and idle limits, #178 reports that limit before any fallback is chosen.
2. **Keys in a browser draft:** the settled browser keys. Esc focuses the dot tabs, a number selects a dot, and the last Return saves and copies. Command+S also saves.
3. **After save:** the panel stays open so C copies and X exports. Esc never closes it. Close with Command+W or the red button.

## Choices as asked

1. **Trigger.** Native shortcut with a drag (7 inputs) or the Chrome key opening the native editor (6 inputs, no drag, no Mac shortcut). Feasibility is #178. If only one works, #178 reports the limit before a fallback is chosen. Recommend the native shortcut, because it keeps one capture key.
2. **Keys in a browser draft.** Use the settled browser keys (Esc picks dots, last Return saves and copies, Command+S also saves), or keep native order (Command+S first, then notes, Esc skips a step). The images show the browser keys. Native ordinary capture would stay unchanged either way. Recommend the browser keys for browser drafts, so one muscle memory works in both places.
3. **Panel after save.** Keep it open so C and X work (as drawn), or close it as native does today and leave copy and export to the Nshot menu and Option+Shift+C. Recommend keeping it open, because it honors the settled C and X rule.

## Not decided or not drawn

- The inline editor toolbar is the existing one and is not redrawn.
- Arrow keys between note steps stay as today in text. With the tabs focused, arrows and Home move between tabs.
- The Settings Browser section appears with the browser feature, like other optional sections. Its exact text is a draft.
- Rolling start gesture, window size, and frame playback are open until #178 and #181.
- The mockup uses a made-up site (lemonaid.example) and wording drawn from the existing guide fixture.
