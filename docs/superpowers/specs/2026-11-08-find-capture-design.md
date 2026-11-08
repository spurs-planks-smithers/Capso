# Nextshot Find Capture (design)

Date: 2026-11-08. Status: built on `feature/find-capture`, on top of `feature/zip-default-on` (PR #280). Issue: #125. Related: #123 (the unshipped screenshot history window this builds on), #85 (zip handoff), #264 (selection rows in round submenus).

## Decisions log

All from Drew on 2026-11-08.

- A "Find Capture..." row in the Nshot menu, right after All Rounds and before Change Start Round Shortcut, in both menu states. It has no global hotkey.
- A new feature flag, `findCapture` (#125). It allows off and on. It is on in both channels, and it is not dev-only. Off hides the menu row. The released-in build (927) is a placeholder above the 0.7.0 release build (919). The 0.8.0 release commit sets the real number.
- The window builds on the unshipped #123 window code (`ScreenshotHistoryView`, `ScreenshotHistoryWindow`, `ScreenshotHistoryIndex`). Its title is "Find Capture".
- The window works with the `screenshotCopy` capability off, the default. It then lists round captures only. Saved screenshots show only with `screenshotCopy` on. They have no check.
- A search field at the top takes keyboard focus when the window opens. Esc closes the window. Quick Look takes Esc first while it shows.
- The app filter and the day groups stay. An empty search lists every capture, newest first, grouped by day. The active round's captures are in the list.
- The search matches the app name, the window title, each mark's instruction, the general note, the round name, and the capture name. It never matches OCR text. It ignores case and diacritics. The query splits into words, and every word must appear in at least one field. Results come newest first with a fixed tie-break.
- A card shows the app and the time, the capture name (summary name or first instruction), and a round chip.
- The #123 image actions leave this window: Copy Image, Copy Without Marks, and Edit.
- A click anywhere on a card toggles its check. The checks are one selection with the Nshot menu's Recent Rounds checks, the basket behind Copy N Selected, Zip N Selected, and Clear Selection. A double-click does nothing special. A click on a card also moves keyboard focus from the search field to the grid, so Space opens Quick Look on the last clicked card and types no space.
- The bottom bar in selection mode: "N selected", Copy N Selected, Zip N Selected (only with `zipHandoff` on), and Clear.
- A click on a card's round chip narrows the window to that round's captures. The typed search still applies inside the round. The bar then shows Back (it clears only the round filter), Copy Round Prompt, Zip Round (with `zipHandoff` on), Open Folder, and Resume Round (only when no round is active).
- No hover preview in the window.

## Design

### Search (`CaptureSearch`, FeedbackKit)

`CaptureSearch.Fields` folds each field once when it is made (case, diacritics, and width). `Fields(capture:roundName:captureName:)` reads the capture's app, window title, mark instructions, and note. It leaves out `ocrText` of the capture and of each mark. `CaptureSearch.results` splits the query at white space, folds each word, keeps the entries where every word is a substring of some field, and sorts by date, newest first. Equal dates go by the tie-break key, smallest first. The app passes `ScreenshotSourceID.sortKey`, the same order that the #123 index used.

### Bar (`FindCaptureBar`, FeedbackKit)

A pure value: the leading label and the buttons, each with its action, title, and enabled state. Selection mode reuses the titles of `SubmenuSelectionRows`. With nothing checked, the buttons stay in the bar and are off, as in the round submenus. Round mode puts Back first. The view shows Back at the leading edge and the other buttons at the trailing edge.

### Window and coordinator (app)

- `FindCaptureCoordinator` owns the window. `FeedbackController.start` makes it beside `connectHistoryMenu()` with no capability check.
- The index runs off the main actor. It calls `ScreenshotHistoryIndex.items` with `includeProvenance: false`, so it skips each capture's `-screenshot.json` file. It reads stored summary names from `FeedbackSessionSummary.current` and never calls `names(priming:)`, so opening the window starts no model request.
- The round name is the Recent Rounds row title: `SessionName.displayName` with `sessionTitle` on, else the date title. The capture name is `SessionName.summaryName` (with `sessionTitle` on), else `RoundTitle.title(for:)`.
- With `screenshotCopy` off there is no `ScreenshotWorkflow`, so the coordinator passes no local items and never makes `ScreenshotHistoryStore`, whose init makes a folder and prunes.
- The window reloads when it shows, when it becomes key, and when the active round changes while it shows. A newer reload wins over an older one.
- The panel is not a nonactivating panel, and the app activates when it shows, so the search field gets real focus. The panel catches Esc in `sendEvent` and sends `cancelOperation`, so Esc works while the search field has focus. A field that composes text with an input method keeps its Esc.

### One selection

`FeedbackController` stays the only owner of the basket. A `didSet` pushes a copy to the window. The menu and the window call the same methods: `toggleCapture(_:)`, `clearSelection()`, `zipSelected()`, `copySelected()`, and `openRoundFolder(named:)`. `toggleCapture` calls `statusItem.basketDidChange` and `primeSelectionSummary`, as the menu path did. A round action resolves its round by folder name: the active round when it matches, else the round on disk.

## Not done

- The Windows flag list (`scripts/nextshot-flags.ps1`) leaves out `findCapture`. That list must match the Windows registry, which holds only the flags that Windows uses, and Windows has no Find Capture.
- No hotkey, by decision.

## Privacy

The window reads local files only. It makes no network call. `NetworkSourceScanTests` covers `App/Feedback` and FeedbackKit. OCR text never feeds the search, the card, or the chip.
