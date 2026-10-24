# Crops and anchor text: design (draft)

Date: 2026-10-24. Status: design complete; Drew answered every open question on 2026-10-24. The build waits for the Jev base (#36). Issue: #38 (parent #34). Flag: `cropsAnchors` (off, shadow, on). Ideas 7 and 8 in `docs/plans/2026-10-24-jev-image-ideas.md`. The shared design is `docs/superpowers/specs/2026-10-24-jev-handoff-design.md`. This document covers only what is special to crops and anchor text.

## Intent

Today the agent gets one full annotated image per capture. `manifest.md` gives it the OCR text under each mark ("Text under the mark"), and the prompt tells it to search the repository for that text. Two things slow it down:

- Small text in a large image is hard to read. A full Retina capture is scaled down to fit 2000 pixels, so menu text and shortcut hints lose detail.
- The text under a mark is often a poor search string. A box over a menu joins every row into one long string. A badge with no arrow gets the nearest line, which can be a count, a date, or a file name that is not in the code. A badge far from any text gets nothing.

This feature adds two things per item (one numbered badge):

1. Item crop: a small, padded image of the item and its context. Jev finds the part the note is about and checks that the crop does not cut it off. The full image stays as a fallback.
2. Anchor text: one line of screen text that the agent can search the repository for. Jev picks it from the capture's OCR lines.

It runs in the background after the capture is stored. Drew sees no change on the capture path.

## Goals, non-goals, anti-goals

Goals:

- The agent finds the right file on the first search more often.
- Fewer image tokens per item: a crop costs a fraction of the full image.
- Small text in a crop is as sharp as in the exported capture.
- Shadow data that lets Drew judge each crop and each search line before any prompt changes.

Non-goals:

- New marks, new circles, or a found item that Drew did not mark (idea 5 is a separate feature).
- OCR changes. The feature uses the OCR lines that Nextshot already makes.
- A search for the code. The agent searches. Nextshot only suggests the text.
- Crops for the note panel preview. That preview stays as it is.

Anti-goals (a failure even if it works):

- A new keystroke, a wait, or a visible change on the capture path.
- A crop that cuts off the thing the note is about, with no warning to the agent.
- A search line that the agent treats as an instruction. Screen text stays data.
- A capture image that leaves the Mac while `jev.sendImages` is off.
- A changed `prompt.md`, capture prompt file, or annotated PNG.

## What exists today

| Part | File | What it does | Use here |
| --- | --- | --- | --- |
| Items | `FeedbackItems.swift` | Splits a capture's marks into items: a badge, plus the box or ellipse it sits on. | One crop and one search line per item. |
| Preview crop | `PreviewCrop.swift` | For each badge: the badge box, its shape, and its arrow tip, plus a margin, widened to an aspect ratio. | The same focus box seeds the item crop. The builder moves the focus code into a shared helper. |
| Export size | `ImageSizing.swift` | Sizes exported PNGs to Claude's limits (2000 pixels, 4784 visual tokens). | Counts crop tokens. Jev's limits differ (280 to 1568 pixels per side), so Jev sizing is a separate helper. |
| OCR lines | `FeedbackController.save` | Runs on-device OCR after the capture is stored. Each line has text and a box in export pixels. | Candidate search lines, and their positions. |
| OCR per mark | `OCRMatcher.swift` | Picks the OCR text under each mark. | A strong candidate for the search line. |
| Stored text | `feedback.json` | Stores the capture's OCR text as one block, and each mark's OCR text. It does not store line boxes. | Fallback candidates when line boxes are not available. |
| Screen text rules | `ScreenText.swift` | Cleans screen text and quotes it. | The search line uses the same cleaning and quoting. |

Facts that shape the design:

- OCR line boxes exist only in memory, in the save task. OCR can take 30 seconds when the Neural Engine is cold (measured 2026-10-20).
- The exported annotated PNG has Redact marks applied, and OCR lines under a Redact mark are already removed. Crops cut from it keep redactions.
- Feedback captures are mostly regions of a window. A region under 2000 pixels and 4784 tokens exports at full size, so a crop of it has full detail.

## Flag states

The Jev base (interface `d1de328`) gives each job a set of allowed data kinds. Reviewer text (Drew's notes) is always allowed. Images need `jevSendImages`. Screen text (OCR text) needs `jevSendScreenText`. The job runs the same way in shadow and on. The runner writes the job's refined lines and files only in on.

| `cropsAnchors` | Images allowed | Screen text allowed | Requests | Crops | Search lines |
| --- | --- | --- | --- | --- | --- |
| off (or `jevBase` off) | any | any | none | none | none |
| shadow or on | no | no | none | cut around the marks | none |
| shadow or on | no | yes | C | cut around the marks | yes |
| shadow or on | yes | no | A, B | Jev target, edge-checked | none |
| shadow or on | yes | yes | A, B, C | Jev target, edge-checked | yes |

- With `cropsAnchors` off, the runner never starts the job. The base's tests prove that no request goes out and the bundle files match today's.
- The client refuses any request that holds a data kind without consent, so a bug in this job cannot send an image or screen text by mistake.
- The images header goes only on requests A and B.

## Item crops

An item is one numbered badge, with the box or ellipse it sits on and its arrow tip. Each request holds every item of the capture, so a capture needs at most four requests (A, B, a second B, and C) for any number of items. The base allows 16 requests per capture for all jobs together.

### Step 1: seed and window (code, local)

- Seed box: the badge box, joined with its shape box and its arrow tip. This is the same focus box that `PreviewCrop` uses.
- Window: the seed box plus a context margin of 200 export pixels on each side, clamped to the image. This is the region Jev looks at. (My call. Tune it in shadow.)
- The window is cut from the exported annotated PNG. The circle and the badge in it help Jev find the item, as in Set-of-Mark prompting.

### Step 2: find the target (Jev, request A, needs images)

One request for all items. The state holds, per item N, the window image `shot_N` and Drew's note `note_N`. The base's loader cuts the window from the annotated PNG and sizes it. Two questions per item, with ids that start with the item id (K.N):

| Id | Type | Instructions (draft) |
| --- | --- | --- |
| `K.N.target` | Box | the part of `shot_N` that `note_N` is about. The numbered badge N marks it. |
| `K.N.target_shown` | Noul | Does `shot_N` show the thing that `note_N` is about? |

An item with no note uses "the element that badge `badge` sits on or points to" in both questions.

Code reads the answer:

- The base's client rejects a box with an edge outside 0 to 1 or out of order.
- `JevImage.sourceBox` maps the fractions back to capture pixels.
- Proposed crop: the target box joined with the seed box, so the badge stays in the crop, plus a pad of 24 export pixels. (My call.)
- If `target_shown` is below its threshold, or the box confidence is below its threshold, use the marks crop (below). Record the reason. Request B still checks it.

Marks crop: the seed box plus a pad of 120 export pixels, clamped to the image. A badge alone is about 30 pixels wide, so a small pad would give a crop with no context. (My call.) The marks crop is the whole crop when `jev.sendImages` is off (Drew, 2026-10-24).

### Step 3: check the edges (Jev, request B, needs images)

TypeSafe's test caught 30 of 36 cut-off crops with one Noul per edge. One request for all items. The state holds, per item, the proposed crop image `crop_N` and the note. Four questions per item: `K.N.cut_left`, `K.N.cut_right`, `K.N.cut_top`, `K.N.cut_bottom`, each a Noul: "Does the thing that `note_N` is about continue past the left edge of `crop_N`?"

- Each edge with a yes above its threshold moves out by 25% of the crop's size on that axis, clamped to the image.
- If any edge moved, ask once more on the new crop, for those items only. The question ids end in `_2`. At most two checks per item. (My call.)
- If an edge still says yes after the second check, move it out once more and record "edges unsure".
- If a request fails (timeout, error, cap), the item keeps the best crop so far and records "not checked". Nothing waits on Jev.

### Step 4: decide and write (code, local)

- Skip the crop when it costs more than half the full image's visual tokens (`ImageSizing.visualTokens`). The full image is then the item's image. (My call.)
- Cut two crops with the same box, at export pixels, with no upscale (Drew, 2026-10-24: annotated and clean):
  - `<stem>-item-<N>.png` from the annotated PNG. The badge and its marks show which item it is.
  - `<stem>-item-<N>-clean.png` from the clean PNG. It shows what a mark hides.
- `<stem>` is the capture's image file stem and N is the badge number. Example: `0627-claude-item-2.png` and `0627-claude-item-2-clean.png`.
- On: write both PNGs beside the capture files. Shadow and off: write no PNG. Shadow keeps the crop box in `jev.json`, and the review page draws it.

### Images sent to Jev

Every image side must be 280 to 1568 pixels, and the API never resizes. The base's `JevImageLoader` cuts a region from a capture PNG, scales it into those limits, and pads what one scale cannot fit. Its `JevImage.sourceBox` maps a Box answer back to capture pixels.

Padding would confuse an edge check: the edge of the sent image would be padding, not the crop's edge. Scaling alone cannot fit a wide, thin region such as one menu row (1200 by 88 pixels): a scale that lifts 88 to 280 lifts 1200 past 1568. So this job shapes each region first (`ItemCrop.shaped`):

1. The long side divided by the short side must be 5.6 (1568 / 280) or less. If it is larger, grow the short side inside the image, around its center. This rule applies to the window and to the proposed crop. So the crop that Jev checks is the crop that ships.
2. If the capture itself cannot hold the shaped region (for example, a capture 200 pixels high), skip the edge check for that item and record "too small". The item keeps the full image.

The sized copy goes only to Jev. The crop PNG for the agent is cut at export pixels and is never scaled.

## Anchor text

A search line is one OCR line, word for word, that the agent can search the repository for. Good search lines are fixed interface text: labels, titles, button and menu names, and messages. Poor ones are dynamic: counts ("Nshot (2)"), dates, user data, file contents, and window titles.

Anchor text sends no image. It works the same with images allowed or not. (My call: one behavior is easier to test and to judge, and Jev's text accuracy is higher than its image accuracy.) It sends OCR text, so it runs only when screen text is allowed (`jevSendScreenText`).

### Step 1: candidates (code, local)

- Source: the capture's OCR lines with their boxes, from the save task (see Needs from the Jev base). Each candidate is one OCR line.
- Keep a line when its box touches the item's window (step 1 of Item crops). Sort by distance from the seed box. Keep the nearest 40. (My call.)
- Always keep the lines that `OCRMatcher` picks for the item's marks, each as its own candidate. The joined mark text in `manifest.md` is never a candidate: it can hold several lines and a "..." cut, so no code search would match it.
- Drop a line with no letters, and a line under 3 characters.
- Clean each line with `ScreenText.clean` (single line, 200 scalars).
- Fallback when line boxes are missing: split the stored OCR block at line breaks, and keep up to 120 lines in reading order. The base's interface `d1de328` gives no line boxes, so this path is the default until the base adds them (Needs from the Jev base, request B).
- No candidates: no request. Record "no screen text".

A capture with no numbered badges gets one capture-level search line, picked against the general note (Drew, 2026-10-24). Its candidates are all lines, up to 120, in reading order. It gets no crop: the full image is already the item. A capture with no badges and no general note gets nothing.

### Step 2: pick (Jev, request C, text only)

One request per capture, for all its items. This follows TypeSafe's line-by-line search cookbook.

- State: `screen_text`, one entry per candidate of the whole capture, each tagged with an id (`L001| Copy Last Capture Prompt`). `items`, one object per item: `note` (Drew's words) and `screen_text` (the text under the item's marks, from `manifest.md`). The text under the marks tells Jev where the item is when line boxes are missing.
- The base's rule: screen text goes only into fields named `screen_text`, and each question that reads it starts with `JevPrompting.screenTextNotice`.
- Per item, a Choice `K.N.anchor` whose options are that item's candidate ids. The model sees the text through the ids in `screen_text`. Screen text never becomes an option name.
- Per item, a Noul `K.N.anchor_fits`: "Is one of the lines in `screen_text` fixed interface text that names the thing in item N, as the app's code would spell it?"
- Instructions for the Choice (draft): "Which line in `screen_text` is the best text to search the app's source code for, to find the code for item N? Prefer fixed interface text: labels, titles, button and menu names. Avoid counts, dates, user data, file contents, and window titles."
- A capture with no badges asks `K.anchor` and `K.anchor_fits` against `general_note`.

A Choice holds at most 255 options. 40 candidates per item stays far below it.

### Step 3: decide (code, local)

- The answer's `choice` must be one of that item's ids. Reject it otherwise.
- Use the line only when `K.N.anchor_fits` and the Choice confidence both pass their thresholds. Otherwise the item has no search line.
- One search line per item, or none (Drew, 2026-10-24).
- The search line is the chosen candidate, cleaned as above. Neither Jev nor code rewrites its words. The refined file labels it screen text. If an OCR mistake breaks the exact search, the agent can search for part of the line.
- The line can come from outside the item's marks, so it can be screen text that `manifest.md` does not show. `feedback.json` already stores it in the capture's OCR block.

## Output files

### `jev.json` (shadow and on)

The base owns the file. Its runner records every answer of every request, with timings and the job's status. It never stores notes, screen text, or images.

The shadow review page also needs what this job derives from the answers: each item's final crop box, crop status, crop source, and the chosen line. The base's interface `d1de328` has no place for derived values. Request A to the base (Needs from the Jev base) asks for a code-only summary per job: numbers, booleans, and code strings, never screen text. With it, this job records per item:

```json
{"item": "2.1", "cropStatus": "checked", "cropSource": "target", "crop": [330, 180, 640, 300], "anchorStatus": "picked", "anchorLine": 7}
```

- Boxes are export pixels, `[x1, y1, x2, y2]`, origin top-left, the same as `manifest.md`.
- `anchorLine` is the line's position in the stored OCR block, so `jev.json` holds no screen text. The review page reads the text from `feedback.json`.
- Crop status: `checked`, `edgesUnsure`, `marksOnly` (images not allowed, so no Jev check), `notChecked` (a request failed before the edge check finished), `tooSmall`, or `notWorthIt` (over half the full image's tokens).
- Crop source: `target` (Jev's box) or `marks` (the marks crop, after a low `target_shown` or a low box confidence, or with images not allowed).
- Anchor status: `picked`, `noneFit`, `noScreenText` (no candidates, or screen text not allowed), or `notChecked`.

### Refined file (on only)

The base owns `<stem>-refined.md` and its writer. A job returns lines with a scope (round, capture, or item), a label, and at most one screen text or one file. The writer groups item lines under "Item K.N:", quotes screen text, and shows a file as an absolute path. This feature returns one capture line, then up to three lines per item:

```text
- Open each item's crop before the full image. Open the full image only for layout, or when a crop line says unsure or not checked.

Item 2.1:
- Search the repository for this screen text: "Copy Last Capture Prompt"
- Crop of this item (edges checked; px 330 180 640 300 of the full image): `/Users/drewschulz/Library/Application Support/Nextshot/2026-10-24-1028-feedback/0627-claude-item-1.png`
- The same crop without marks: `/Users/drewschulz/Library/Application Support/Nextshot/2026-10-24-1028-feedback/0627-claude-item-1-clean.png`
```

| Crop status | Words in the Crop label |
| --- | --- |
| `checked` | (edges checked; px ... of the full image) |
| `edgesUnsure` | (edges unsure: open the full image if the crop cuts something off; px ...) |
| `marksOnly` | (cut around the marks, not checked; px ...) |
| `notChecked` | (not checked: open the full image if the crop cuts something off; px ...) |
| `tooSmall`, `notWorthIt` | no Crop lines. The agent uses the full image. |

- Crops first (Drew, 2026-10-24). The agent opens the crop, and the full image only when it needs layout or the crop is not trusted. This is where the token saving comes from.
- The "px" box gives the crop's place in the full image, in the same pixels as `manifest.md`. The agent can match it to the manifest's item boxes.
- The rule line appears only when at least one item has a Crop line.
- An item with no search line gets no Search line. It never gets "Search: none".
- The base's writer cleans and quotes the search text, as `manifest.md` does.
- A capture with no badges gets one capture line: "Search the repository for this screen text (whole capture):" and the line.

### Crop PNGs (on only)

`<stem>-item-<N>.png` and `<stem>-item-<N>-clean.png` beside the capture's files, cut at export pixels. With images not allowed, the box is the marks crop. The job returns the PNG data in its output. The base's writer checks each name and writes the files only in the on state.

### Shadow review page (dev tool)

Shadow writes `jev.json` only (Drew, 2026-10-24). To judge the results, Drew runs a script: `scripts/jev-review-crops-anchors.py`, Python standard library only.

- Input: one round folder (default: the newest round). It reads `feedback.json` and `jev.json` (the raw answers and this job's summary).
- Output: `jev-review.html` in the same round folder, then `open` shows it. The app never writes or reads this file, and no prompt names it.
- Per capture: the annotated image, with the final crop of each item drawn over it as an HTML outline, labeled with the item id.
- Beside the image, one row per item: item id, Drew's note, crop status and source, the four edge answers, the search line (looked up in `feedback.json` by its position) with `anchor_fits` and the Choice confidence.
- The page needs the summary from request A to the base. Without it, the page can show answers but cannot draw final crops.
- Drew marks each row right or wrong in his own notes. The page has no form and saves nothing. (My call. A verdict form can come later.)

## Needs from the Jev base

Sent to the jev-base session on 2026-10-24 through the shared notes folder. Status against the early interface `d1de328` (read 2026-10-24):

| # | Need | Why | Status |
| --- | --- | --- | --- |
| 1 | Start after OCR and after the note panel closes. | Requests A and C need the notes and the screen text. | Met: the runner starts when both are done. |
| 2 | Job input: the capture, the round folder, the images, the allowed kinds, a deadline. | All steps read these. | Met: `JevJobContext`. |
| 3 | Typed answers with range checks. The images header only with an image or a Box. | A and B hold images. C holds none. | Met. |
| 4 | A Jev image sizing helper that maps a Box back to capture pixels. | Every image job needs it. | Met: `JevImageLoader` and `JevImage.sourceBox`. This job still shapes regions first (see Images sent to Jev). |
| 5 | Writers for `jev.json` and refined lines. A safe way to add the crop PNGs. | One owner per file. | Met: `JevJobOutput` lines and files. |
| 6 | A fake asker for tests. | Request-shape and consent tests. | Met: `JevAsker` takes a closure. |
| 7 | Thresholds per model version in one place. | TypeSafe can change accuracy. | Changed: thresholds live in the job's own file. |
| A | A code-only summary per job in `jev.json`, in shadow and on. | The review page draws final crop boxes, which code derives. | Asked 2026-10-24. |
| B | OCR line boxes in the job context, optional. | Candidates near the item, and the lines under its marks. | Asked 2026-10-24. Until then, the fallback path runs. |
| C | List the refined file first in "Open these files first". | Crops first saves tokens only if the agent reads the refined file first. | Asked 2026-10-24. |

Cold OCR (30 seconds) also delays the crops, which do not need OCR. If shadow data shows many late crops, ask the base for an earlier crop phase.

## Security

| What leaves the Mac | When |
| --- | --- |
| Drew's notes | `jevBase` on and `cropsAnchors` shadow or on |
| Candidate OCR lines and the text under each item's marks (cleaned, with lines under Redact marks already removed) | the above, and screen text allowed (`jevSendScreenText`) |
| The window and crop images, cut from the annotated PNG (Redact marks applied) | the above, and images allowed (`jevSendImages`) |

- Screen text is untrusted. It goes only into state fields named `screen_text`, and each question that reads it starts with the base's screen text notice. Option names are line ids, never screen text.
- Jev returns typed values only. The base's client checks types and ranges. This job checks that a choice is an offered id. A value that fails is dropped, and the item falls back.
- New screen text for the agent: the search line can come from outside the marks, so `manifest.md` may not show it. It is one cleaned line from the OCR block that `feedback.json` already stores. It is quoted with `ScreenText.quoted` and labeled screen text, under the existing rule that screen text is data. The build commit adds a line about it to `docs/SECURITY_BASELINE.md` and `docs/agents/bundle-guide.md`. (My call.)
- Crop file names use the capture's existing stem and the badge number. They add no new screen text.
- All writes go through the base's writer, inside the round folder.
- The API key and the network rules belong to the base.

## Latency and cost

Requests for a capture with k items, all after OCR:

| Request | Count | Starts | Holds |
| --- | --- | --- | --- |
| A, find the target | 1 | at once | k window images, 2 questions per item |
| B, check the edges | 1 or 2 | after A | k crop images, 4 questions per item |
| C, anchor text | 1 | at once, beside A | text only, 2 questions per item |

- Longest path: A, then B, then B again. At 0.22 seconds per request (measured 2026-10-24 with one 514 by 584 image), that is under 1 second. Requests with several images take longer. Shadow data will show the real time against the 2-second budget.
- At most 4 requests per capture, under the base's cap of 16 for all jobs.
- On a timeout or an error, the item keeps what is done, with status `notChecked`. Nothing waits on Jev.
- Jev cost: about 1,500 input tokens per image request, at $0.042 per million tokens, so about $0.00006 per request. A round of 20 captures with 3 items each makes about 200 requests, about $0.012.
- Agent saving: the full annotated image costs up to 4,784 visual tokens (one token per 28 by 28 pixel patch). A 600 by 400 pixel crop costs 330.

## Tests

Pure logic tests run with `swift test`. Each test uses fixed numbers and no network.

| Area | Checks |
| --- | --- |
| Seed and window | Seed joins the badge, its shape, and its arrow tip. The window clamps to the image. |
| Shape rule | A 1200 by 88 region grows to a 5.6 aspect. "Too small" when the capture cannot hold the shaped region. |
| Box use | The target joins the seed and pads. A low `target_shown` gives the marks crop. The crop always holds the seed. |
| Edge checks | A yes on the left edge moves only the left edge, by 25%, clamped. Two checks at most. A yes on the second check gives `edgesUnsure`. |
| Requests | At most 4 per capture for any item count. With no consent beyond reviewer text, no request. With screen text only, no request holds an image and none has the images header. With images only, no request holds screen text. A failed request gives `notChecked` and no error. |
| Marks crop | Seed plus 120 pixels, clamped. Used with images off, and after a low `target_shown`. |
| Worth it | A crop over half the full image's tokens gives `not_worth_it` and no PNG. |
| Two crops | The annotated and clean crops use the same box and the file names above. |
| Candidates | Window filter, nearest 40, the marks' own lines kept one by one, the joined mark text never used, lines with no letters dropped, ids stable, fallback from the stored OCR block. |
| No badges | One capture-level search line from the general note. No crop. No request without a general note. |
| Anchor answers | A choice that is not an offered id is dropped. Low `anchor_fits` gives `none_fit`. The search text is the cleaned line, unchanged. |
| Refined lines | Exact text per crop status, with the px box. The crops-first rule line only when a Crop line exists. No "Search: none". Screen text quoted. |
| Flag off | With `cropsAnchors` off, the fake transport records zero requests, and the bundle files match today's byte for byte. |
| Shadow | `jev.json` only. No PNG and no refined lines. |
| Images off | No request holds an image, and no request has the images header. |

## Research

Light research on 2026-10-24 (four searches), with the TypeSafe docs.

| Source | Finding | Effect on this design |
| --- | --- | --- |
| TypeSafe [Box](https://docs.typesafe.ai/primitives/box.md) | A Box always returns a box. Ask a Noul with it. One Noul per edge caught 30 of 36 cut-off crops. One "is it all inside" Noul caught 26. | `target_shown` with each Box. Four edge Nouls in request B. |
| TypeSafe [Images](https://docs.typesafe.ai/images.md) | Each side 280 to 1568 pixels, never resized. An image used by several questions goes in the state once. | The sizing rules. One image per request, in the state. |
| TypeSafe [Choice](https://docs.typesafe.ai/primitives/choice.md) and [Line-by-line search](https://docs.typesafe.ai/cookbooks/semantic_find.md) | A Choice holds up to 255 options. Tag lines with ids, put the text in the state, and ask a Noul for "is there an answer at all". A "none" option works poorly. | Request C: ids as options, text in the state, `anchor_fits` Noul. |
| TypeSafe [Pre-parsed value extraction](https://docs.typesafe.ai/cookbooks/pre_parsed_value_extraction_cookbook.md) | Code finds candidates, Jev picks one, code keeps the value word for word. | Code builds candidates. The search line is never rewritten. |
| [ScreenSpot-Pro](https://arxiv.org/abs/2504.07981) (2025) | On high-resolution professional screens, models miss small targets. Zooming into a region and grounding again improves accuracy. | Find the target on a window, not on the full capture. |
| [DiMo-GUI](https://arxiv.org/abs/2507.00008) (2025) and [UI-Zoomer](https://arxiv.org/abs/2604.14113) (2026) | Crop around a first guess and run again. A fixed crop can remove needed context, so zoom only when needed. | Keep the full image as the fallback. Pad crops. Record low-confidence crops. |
| Zhang and others, [MLLMs Know Where to Look](https://arxiv.org/abs/2502.17422) (ICLR 2025) | A crop of the relevant region improves the reading of small details. | The reason for item crops. |
| A Claude Code [bug report on computer-use zoom](https://claudeissues.com/issue/82437-bug-computer-use-zoom-returns-interpolated-blurry-crops-on-high-res-displays-sma) (2026, unverified) | A zoom cut from an already scaled-down screenshot is blurry. | Crops are cut at export pixels and never upscaled. A crop from the full-resolution capture is a later option (see Left to the builder). |
| Saha and others, [Buggy UI localization](https://arxiv.org/abs/2408.04075) (2024), and Mahmud and others, [GUI-aided bug localization](https://arxiv.org/abs/2310.08083) (2023) | Screen text and GUI information help find buggy screens and files. Text models did better at finding the component. A gap stays between report words and code words. | Search on the screen's own words, not on Drew's note. |
| [React Grab](https://www.mintlify.com/aidenybai/react-grab/introduction) and [Agentation](https://cdn.jsdelivr.net/gh/benjitaylor/agentation@main/README.md) | Browser tools hand the agent a source hint (file, component, selector) for a clicked element. They work only in React web apps. | Nextshot captures any macOS app, so screen text is the general hint. A search line is the closest match for native apps. |

## Decisions log

- 2026-10-24: every Jev feature sits behind a flag. `cropsAnchors` has off, shadow, and on. Shadow writes `jev.json` only (Drew, from the shared design).
- 2026-10-24: images leave the Mac only with `jev.sendImages` on (Drew, from the shared design).
- 2026-10-24: one crop and one search line per item, with the full image as a fallback (Drew, issue #38).
- 2026-10-24: with `jev.sendImages` off and the flag on, cut crops around the marks on the Mac, with no Jev check. Search lines still use Jev, text only (Drew).
- 2026-10-24: each item gets two crops with the same box, annotated and clean (Drew).
- 2026-10-24: shadow writes `jev.json` only. A dev script builds a review page that draws the crop boxes over each capture (Drew).
- 2026-10-24: crops first. The refined file tells the agent to open crops before the full image (Drew).
- 2026-10-24: one search line per item, or none (Drew).
- 2026-10-24: a capture with no badges gets one capture-level search line from its general note, and no crop (Drew).
- 2026-10-24: build the pure crop geometry (#41) and anchor candidates (#42) before the Jev base publishes its job interface. The Jev request job (#43) still waits for the base. The Jev sizing rule lives in `ItemCrop` for now, and the base can take it over (Drew).
- My calls, open to Drew's change: anchor text is text only in every state; the window margin is 200 export pixels, the target crop pad is 24, and the marks crop pad is 120; at most two edge checks per item; a crop over half the full image's tokens is skipped; 40 candidates per item, each one OCR line; the job starts after OCR and after the note panel closes; the search line can be screen text from outside the marks; the review page saves no verdicts.

## Open questions

None left for Drew. The builder check on 2026-10-24 raised five points. Two were Drew's (crops first, and the marks crop with images off). Three were settled above (the job trigger, the marks crop pad, and one OCR line per candidate).

## Left to the builder

- Package layout (settled 2026-10-24). Pure geometry and candidates are in `FeedbackKit` (`ItemCrop.swift`, `AnchorCandidates.swift`). The job is `Packages/JevKit/Sources/JevKit/Jobs/CropsAnchorsJob.swift`, the one file the base gave this feature, with its own test file. JevKit depends on FeedbackKit (the base's choice). The app glue belongs to the base.
- The shared focus helper: move the focus box code out of `PreviewCrop` into an internal helper that both use. The note panel preview must not change. Its tests prove it.
- Thresholds (`target_shown`, Box confidence, edge yes, `anchor_fits`, Choice confidence). Start at 0.5 and tune each on shadow data.
- Crop from the full-resolution capture in memory, in place of the exported PNG. It is sharper for full-screen Retina captures. Build it only if shadow data shows blurry crops.
- Retry policy, timeouts, and the parallel request cap come from the base.
