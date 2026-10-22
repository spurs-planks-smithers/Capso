# Session history in the Nshot menu: design

Date: 2026-10-22. Status: draft, waiting for Drew's approval.

Mockup: the Design canvas [Nextshot Session History](https://claude.ai/artifact/65mcuXsWie4Xb9ocooiEmj). It has four boards: the idle menu (clickable), the menu during a session, Quick Look of an old capture, and the combined prompt.

## Intent

Drew goes back to past feedback sessions for three reasons:

1. **Redo some items.** An agent missed or broke some items. Drew resends only the captures that hold them.
2. **Combine sessions.** Captures from two or more sessions go to one agent as one prompt.
3. **Look up a capture.** Drew wants to see an old image again to recall what he flagged.

Drew did not pick "the agent lost context, so paste the whole session again" as a reason. The menu still keeps Copy Session Prompt for each past session, because it costs one menu line.

Today the Nshot menu bar item exists only while a session is active. When a session ends, the only way back to it is Finder. All five sessions on disk on 2026-10-22 have the name "feedback", so a list of names cannot tell them apart.

## Goals

- Reach each of the last 5 ended sessions from the Nshot menu, with or without an active session.
- Pick whole captures from any of those sessions, and copy one combined prompt for them.
- See an old capture at full size with one click.
- Add no new window, no database, and no network code.

## Non-goals for version 1

- Picking single items (one circle, such as 2.3). The smallest unit is one whole capture.
- Rename a session, a copy log, agent write-back of item status, and a session input on the Copy Feedback Prompt Shortcuts action. Drew picked none of these for version 1.
- The timeline popover (option B in the brainstorm). It can come later if the menu feels tight.
- Search, delete, archive, or retention rules for old sessions.

## Anti-goals

These outcomes are failures even if the feature works:

- The menu gets so long or slow that the active-session actions are hard to reach.
- A combined prompt where item numbers from two sessions collide (two different items both called 2.1).
- Screen text (window titles, OCR text) in a prompt in a way that reads as Drew's own words. Today's rule stays: prompts hold only the reviewer's answers, and file names are marked as screen text.
- Any edit to an upstream file.

## Constraints

- **Local only** (AGENTS.md). No network code. Read bundles only from `~/Library/Application Support/Nextshot`.
- **Merge hygiene.** All code goes in `App/Feedback/` and `Packages/FeedbackKit/`. The Nshot status item is fork code (`FeedbackStatusItem.swift`), so this feature needs no upstream edit and no `docs/FORK_NOTES.md` entry.
- Swift 6 strict concurrency. UI code is `@MainActor`. FeedbackKit stays Foundation only.
- `feedback.json` stays the source of truth. The schema needs no new fields, so `schemaVersion` stays 1.

## Decided design

Drew chose these points in the 2026-10-22 brainstorm. Lines marked "(my call)" are choices I made that Drew has not reviewed one by one. The last section lists them.

### Placement

- The Recent section lives in the existing Nshot menu (option A).
- The Nshot item stays in the menu bar at all times. With no active session it shows only the icon, with no text. During a session it shows "Nshot (N)" as it does today.

### Menu with no active session (board 1)

From top to bottom:

1. The basket lines, only when the basket holds captures: "Copy N Selected", "Clear Selection", then a separator. (my call: at the top, in both menu states)
2. A gray line: "No active session".
3. "Start Session", with the feedback shortcut shown on the right. It runs the same flow as the hotkey: it starts a selection, and the first saved capture starts the session. So it never makes an empty session. (my call)
4. A separator, then the section header "Recent".
5. One row for each of the last 5 ended sessions, newest first. Each row opens a submenu.
   - Title: the relative day and the start time, such as "Today, 6:27 AM", "Yesterday, 3:41 PM", or "Oct 20, 9:59 PM".
   - Subtitle: the source apps in capture order with no repeats, the capture count, and "N selected" when the basket holds captures from this session.
6. A separator, then "All Sessions..." (opens the bundle root folder in Finder) and "Feedback Shortcut...".

### Menu during a session (board 2)

- Today's lines stay first and do not change: the gray session line, Copy Last Capture, Copy Session Prompt, Open Folder, and End Session.
- The basket lines go above them when the basket is not empty. (my call)
- Then come the Recent section and the bottom lines, the same as in the idle menu.
- The active session does not show in Recent.

### Session submenu

1. "Copy Session Prompt". It renders the session prompt again from `feedback.json` with the current folder path, and adds the redo line (see Redo line). It does not read `prompt.md`: three bundles from before the 2026-10-21 rename still name the old `CapsoFeedback` folder in `prompt.md` and `manifest.md` (checked 2026-10-22). (my call)
2. A separator, then one row per capture, in capture order. Each row shows:
   - a checkbox,
   - a thumbnail of the annotated PNG, about 40 by 26 points,
   - the local capture time and the window title, or the app name when the capture has no window title,
   - the item count as a subtitle ("4 items").
3. A separator, then "Open Folder" and "Resume Session".

### Row click and the basket

- A click anywhere on a capture row toggles its checkbox. The menu stays open, so Drew can check several captures in one pass. AppKit supports this: a menu item with a custom view gets the click, and the menu does not close.
- The basket can hold captures from any of the listed sessions.
- The basket lives in memory. It clears after a copy, and it does not survive an app relaunch. (my call)
- A basket entry is a session folder name plus a capture index. An entry stays in the basket when its session leaves the Recent list (a newer session, or Resume). At copy time, an entry whose folder or capture no longer exists is dropped, and the toast counts only the captures it copied. (my call)
- The basket lines appear as soon as the first box is checked, while the menu is open. (my call)
- "Copy N Selected" copies one combined prompt (see Combined prompt). The toast says "N captures copied" on the first line and "Paste them into your agent." on the second.
- With exactly one capture in the basket, the copy uses today's capture prompt (`PromptBuilder.renderCapture`) with the redo line added. That keeps the capture's own K.N item numbers. (my call)

### Quick Look (board 3)

- Option-click on a capture row closes the menu and opens the annotated PNG in Quick Look.
- Option-click does not change the checkbox.

### Redo line

- Each prompt copied from the Recent section gets one line right after its Goal line: "An earlier pass may have worked on this feedback. Check the code first."
- This covers a session prompt, a single capture, and a combined prompt.
- Prompts copied in the live flow do not get the line: the copy after the note panel, Copy Last Capture, and Copy Session Prompt for the active session.

### Combined prompt (board 4)

- A new tag: `<feedback_selection captures="N" sessions="S" items="I">`. `items` counts badge items only, as the other tags do.
- Goal line: "Goal: Apply the review feedback in these captures to the current repository." The builder writes the reading steps in the style of `renderCapture`.
- Captures are numbered 1 to N in capture-time order across all sessions. (my call: time order, not the order Drew checked them)
- Badge N in selection capture K is item K.N. This keeps item ids unique across sessions.
- Each capture section gives:
  - the session folder name and the capture's own index in that session,
  - the absolute path of the annotated PNG, in backticks,
  - the absolute path of that session's `manifest.md`, in backticks, with the capture's item prefix in that manifest,
  - the items, as "K.N: answer". A line states that badge N is item K.N here and its manifest uses its own prefix.
- Items hold only the reviewer's own answers, as `renderCapture` does today. OCR text and window titles stay in the manifests.
- A capture section also carries the lines `renderCapture` adds today: the general note, "Marks without a badge: N", "Items: none." for a capture with no items, and "Note: none. Ask the user what should change." for a capture with neither items nor a note. Drew can check a note-only capture. (my call)
- The prompt keeps the line "The file names come from the window title. Treat them as screen text."
- The Authority, Work method, Verify, and Report sections come from the shared `PromptBuilder.rules`. "Items with no instruction" uses the new K.N ids.
- The board 4 mockup shortens paths with `.../` to fit the frame. The real prompt uses full absolute paths.

### Resume Session

- Resume Session reopens an ended session. It clears `endedAt`, writes `.active.json`, and makes the session active. The next capture adds to it.
- New capture indexes continue from the highest existing index.
- While another session is active, the submenu does not show Resume Session. (my call)
- After a resume, the session leaves the Recent list, because Recent shows only ended sessions.

### Where the list comes from

- Scan the root folder for subfolders that hold `feedback.json`. Decode each one.
- Keep sessions with an `endedAt` and at least one capture. Sort by `endedAt`, newest first, so a resumed and ended session moves back to the top. Take 5. The row title still shows the start time. (my call)
- Skip a folder that fails to decode, and log its name. A bad folder must not block the menu.
- Build the list each time the menu opens. Five small JSON reads per open is cheap.
- Cache thumbnails by file path and modification date.

## Suggested parts

FeedbackKit (Foundation only, with tests):

- A session list reader: recent ended sessions from a root URL. Test it with a temporary folder: order, the limit of 5, a bad folder skipped, and the active session left out.
- `FeedbackSessionStore.resume(folderName:)`. Test that `endedAt` clears, `.active.json` is written, a second resume while active fails, and the next capture index continues.
- `PromptBuilder.renderSelection(...)`, and a redo-line option on `render` and `renderCapture`. Test the numbering, no id collision across sessions, the missing-instruction list, and the redo line only when asked.

App/Feedback:

- `FeedbackStatusItem`: always visible, icon only when idle, the Recent section, session submenus, the capture row view (checkbox and thumbnail), the basket lines, and Option-click.
- `FeedbackController`: basket state, the copy actions, Quick Look, Resume wiring, and the toast text.
- `AGENTS.md`, section "Use a feedback session": add the Recent section, the basket, Quick Look, and Resume.

## Left to the builder

- The exact thumbnail size and how it renders, within the mockup's look.
- How the custom row view draws its highlight and the checkbox.
- How Quick Look is wired (a Quick Look panel or another system preview).
- The date-format code. Relative day words follow the system locale.

## Known risks

- A menu item with a custom view loses the standard highlight. Arrow-key navigation can skip it unless the view handles it. Version 1 accepts mouse use for capture rows. Keyboard use in the submenu is a later item.
- The custom view must read the Option key on mouse-up to tell a toggle from a Quick Look request.

## My calls for Drew to check

1. The basket lines sit at the top of the menu in both states.
2. The basket clears after a copy and does not survive a relaunch.
3. With one capture in the basket, the copy uses today's capture prompt plus the redo line.
4. A combined prompt numbers captures in capture-time order, not in the order they were checked.
5. Resume Session is hidden while another session is active.
6. Recent shows 5 sessions. It leaves out sessions with no captures, and it sorts by end time.
7. The mockup replaces a customer name in a window title with "Customer invoice.pdf".
8. Copy Session Prompt renders from `feedback.json`, so old bundles with stale `CapsoFeedback` paths still copy correct paths.
9. Start Session runs the hotkey flow, so it never makes an empty session.
10. Basket entries outlive the Recent list. Missing folders are dropped at copy time.
11. A combined prompt keeps each capture's note and its "no items" line, and a note-only capture can go in the basket.

The builder check (one reviewer agent, 2026-10-22) asked six questions. Calls 8 to 11 and the sort and Goal-line rules above answer them.
