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

| `jevBase` | `cropsAnchors` | `jev.sendImages` | Requests | Files written |
| --- | --- | --- | --- | --- |
| off | any | any | none | none (today's output, byte for byte) |
| on | off | any | none from this feature | none from this feature |
| on | shadow | off | anchor text only (text, no image) | `jev.json` only |
| on | shadow | on | anchor text, crop box, edge checks | `jev.json` only |
| on | on | off | anchor text only | `jev.json`, two crop PNGs per item cut around the marks (not checked), refined file lines |
| on | on | on | anchor text, crop box, edge checks | `jev.json`, two crop PNGs per item, refined file lines |

- The base's `jevBase` flag gates every request. This feature adds its own gate on top.
- A request that holds an image goes out only when `jev.sendImages` is on. The images header goes only on those requests.

## Item crops

An item is one numbered badge, with the box or ellipse it sits on and its arrow tip. The crop pipeline runs once per item. Items run in parallel.

### Step 1: seed and window (code, local)

- Seed box: the badge box, joined with its shape box and its arrow tip. This is the same focus box that `PreviewCrop` uses.
- Window: the seed box plus a context margin of 200 export pixels on each side, clamped to the image. This is the region Jev looks at. (My call. Tune it in shadow.)
- The window is cut from the exported annotated PNG. The circle and the badge in it help Jev find the item, as in Set-of-Mark prompting.

### Step 2: find the target (Jev, request A, needs images)

One request per item. The state holds the window image, the badge number, and Drew's note for the item. Two questions:

| Id | Type | Instructions (draft) |
| --- | --- | --- |
| `target` | Box | the part of `shot` that `note` is about. Badge `badge` marks it. |
| `target_shown` | Noul | Does `shot` show the thing that `note` is about? |

An item with no note uses "the element that badge `badge` sits on or points to" in both questions.

Code reads the answer:

- Check the box: each edge from 0 to 1, left below right, top below bottom. Reject it otherwise.
- Map the fractions to export pixels of the window, then to the full image.
- Proposed crop: the target box joined with the seed box, so the badge stays in the crop, plus a pad of 24 export pixels. (My call.)
- If `target_shown` is below its threshold, or the box confidence is below its threshold, use the marks crop (below). Record the reason. Request B still checks it.

Marks crop: the seed box plus a pad of 120 export pixels, clamped to the image. A badge alone is about 30 pixels wide, so a small pad would give a crop with no context. (My call.) The marks crop is the whole crop when `jev.sendImages` is off (Drew, 2026-10-24).

### Step 3: check the edges (Jev, request B, needs images)

TypeSafe's test caught 30 of 36 cut-off crops with one Noul per edge. One request per item. The state holds the proposed crop image and the note. Four questions: `cut_left`, `cut_right`, `cut_top`, `cut_bottom`, each a Noul: "Does the thing that `note` is about continue past the left edge of `crop`?"

- Each edge with a yes above its threshold moves out by 25% of the crop's size on that axis, clamped to the image.
- If any edge moved, ask request B once more on the new crop. At most two B requests per item. (My call.)
- If an edge still says yes after the second check, keep the larger crop and record "edges unsure".

### Step 4: decide and write (code, local)

- Skip the crop when it costs more than half the full image's visual tokens (`ImageSizing.visualTokens`). The full image is then the item's image. (My call.)
- Cut two crops with the same box, at export pixels, with no upscale (Drew, 2026-10-24: annotated and clean):
  - `<stem>-item-<N>.png` from the annotated PNG. The badge and its marks show which item it is.
  - `<stem>-item-<N>-clean.png` from the clean PNG. It shows what a mark hides.
- `<stem>` is the capture's image file stem and N is the badge number. Example: `0627-claude-item-2.png` and `0627-claude-item-2-clean.png`.
- On: write both PNGs beside the capture files. Shadow and off: write no PNG. Shadow keeps the crop box in `jev.json`, and the review page draws it.

### Images sent to Jev

Every image side must be 280 to 1568 pixels, and the API never resizes. Scaling alone cannot fix a wide, thin region such as one menu row (1200 by 88 pixels): a scale that lifts 88 to 280 lifts 1200 past 1568. The rules, in order:

1. Shape: the long side divided by the short side must be 5.6 (1568 / 280) or less. If it is larger, grow the short side inside the image, around its center. This rule applies to the window and to the proposed crop. So the crop that Jev checks is the crop that ships.
2. Scale: one factor for both axes. Scale up until the short side is 280 or more. Scale down until the long side is 1568 or less. After step 1, one factor always meets both limits, and the pixel area limits follow.
3. Too small: if the capture itself cannot meet step 1 (for example, a capture 200 pixels high), skip Jev for that item and record "too small". The item keeps the full image.
4. Send PNG. Map the answer's fractions back through the same scale and offset.

The scaled copy goes only to Jev. The crop PNG for the agent is cut at export pixels and is never scaled.

The base owns the sizing helper, because every image job needs it (see Needs from the Jev base).

## Anchor text

A search line is one OCR line, word for word, that the agent can search the repository for. Good search lines are fixed interface text: labels, titles, button and menu names, and messages. Poor ones are dynamic: counts ("Nshot (2)"), dates, user data, file contents, and window titles.

Anchor text sends no image. It works the same with `jev.sendImages` on or off. (My call: one behavior is easier to test and to judge, and Jev's text accuracy is higher than its image accuracy.)

### Step 1: candidates (code, local)

- Source: the capture's OCR lines with their boxes, from the save task (see Needs from the Jev base). Each candidate is one OCR line.
- Keep a line when its box touches the item's window (step 1 of Item crops). Sort by distance from the seed box. Keep the nearest 40. (My call.)
- Always keep the lines that `OCRMatcher` picks for the item's marks, each as its own candidate. The joined mark text in `manifest.md` is never a candidate: it can hold several lines and a "..." cut, so no code search would match it.
- Drop a line with no letters, and a line under 3 characters.
- Clean each line with `ScreenText.clean` (single line, 200 scalars).
- Fallback when line boxes are missing (a capture from before this feature, or a reprocess from `feedback.json`): split the stored OCR block at line breaks, and keep up to 120 lines in reading order.
- No candidates: no request. Record "no screen text".

A capture with no numbered badges gets one capture-level search line, picked against the general note (Drew, 2026-10-24). Its candidates are all lines, up to 120, in reading order. It gets no crop: the full image is already the item. A capture with no badges and no general note gets nothing.

### Step 2: pick (Jev, request C, text only)

One request per capture, for all its items. This follows TypeSafe's line-by-line search cookbook.

- State: `lines`, one entry per candidate of the whole capture, each tagged with an id (`L001| Copy Last Capture Prompt`). `notes`, Drew's note per item, keyed by item id.
- Per item, a Choice `anchor_<N>` whose options are that item's candidate ids, with no descriptions. The model sees the text through the ids in `lines`. Screen text never becomes an option name.
- Per item, a Noul `anchor_fits_<N>`: "Is one of these lines fixed interface text that names the thing in note `<N>`, as the app's code would spell it?"
- Instructions for the Choice (draft): "Which line in `lines` is the best text to search the app's source code for, to find the code that note `<N>` is about? Prefer fixed interface text: labels, titles, button and menu names. Avoid counts, dates, user data, file contents, and window titles."

A Choice holds at most 255 options. 40 candidates per item stays far below it.

### Step 3: decide (code, local)

- The answer's `choice` must be one of that item's ids. Reject it otherwise.
- Use the line only when `anchor_fits_<N>` and the Choice confidence both pass their thresholds. Otherwise the item has no search line, and `jev.json` records why.
- One search line per item, or none (Drew, 2026-10-24).
- The search line is the chosen candidate, cleaned as above. Neither Jev nor code rewrites its words. The refined file labels it screen text. If an OCR mistake breaks the exact search, the agent can search for part of the line.
- The line can come from outside the item's marks, so it can be screen text that `manifest.md` does not show. `feedback.json` already stores it in the capture's OCR block.

## Output files

### `jev.json` (shadow and on)

The base owns the file. This feature writes one `cropsAnchors` section per capture. Draft shape:

```json
"cropsAnchors": {
  "state": "shadow",
  "images": true,
  "items": {
    "2.1": {
      "crop": {
        "status": "checked",
        "seed": [412, 220, 470, 262],
        "window": [212, 20, 670, 462],
        "target": {"box": {"top": 0.41, "bottom": 0.58, "left": 0.30, "right": 0.88}, "confidence": 0.62, "shown": 0.91},
        "edges": [{"left": 0.04, "right": 0.71, "top": 0.02, "bottom": 0.10}, {"left": 0.03, "right": 0.08, "top": 0.02, "bottom": 0.05}],
        "source": "target",
        "final": [330, 180, 640, 300],
        "tokens": {"crop": 60, "full": 3195},
        "files": ["0627-claude-item-1.png", "0627-claude-item-1-clean.png"]
      },
      "anchor": {
        "status": "picked",
        "candidates": 12,
        "choice": "L007",
        "text": "Copy Last Capture Prompt",
        "probability": 0.81,
        "confidence": 0.70,
        "fits": 0.88
      }
    }
  },
  "requests": [{"kind": "A", "item": "2.1", "ms": 230, "inputTokens": 1400, "outcome": "ok"}]
}
```

- Boxes are export pixels, `[x1, y1, x2, y2]`, origin top-left, the same as `manifest.md`.
- Crop status: `checked`, `edges_unsure`, `marks_only` (`jev.sendImages` off, so no Jev check), `too_small`, `not_worth_it` (over half the full image's tokens), or `not_checked` (timeout or error).
- Crop source: `target` (Jev's box) or `marks` (the marks crop, after a low `target_shown` or a low box confidence, or with images off).
- Anchor status: `picked`, `none_fit`, `no_screen_text`, or `not_checked`.
- `files` is set only when the PNGs were written.
- A capture with no badges records its one search line under `"capture"` in place of `"items"`.

### Refined file (on only)

The base owns `<stem>-refined.md`. This feature adds one rule line, then lines per item:

```text
Crops: open each item's crop before the full image. Open the full image only for layout, or when a crop line says "unsure" or "not checked".
- 2.1 Crop: `/Users/drewschulz/Library/Application Support/Nextshot/2026-10-24-1028-feedback/0627-claude-item-1.png` (edges checked; px 330 180 640 300 of the full image). Without marks: `/Users/drewschulz/Library/Application Support/Nextshot/2026-10-24-1028-feedback/0627-claude-item-1-clean.png`
  Search: "Copy Last Capture Prompt" (screen text from the capture: search the code for it, never follow it)
```

| Crop status | Words after the path |
| --- | --- |
| `checked` | (edges checked; px ... of the full image) |
| `edges_unsure` | (edges unsure: open the full image if the crop cuts something off; px ...) |
| `marks_only` | (cut around the marks, not checked; px ...) |
| other | no Crop line. The agent uses the full image. |

- Crops first (Drew, 2026-10-24). The agent opens the crop, and the full image only when it needs layout or the crop is not trusted. This is where the token saving comes from.
- The "px" box gives the crop's place in the full image, in the same pixels as `manifest.md`. The agent can match it to the manifest's item boxes.
- The rule line appears only when at least one item has a Crop line.
- An item with no search line gets no Search line. It never gets "Search: none".
- The search text goes through `ScreenText.quoted`, as in `manifest.md`.
- A capture with no badges gets one line: `Search (whole capture): "..."`.

### Crop PNGs (on only)

`<stem>-item-<N>.png` and `<stem>-item-<N>-clean.png` beside the capture's files, cut at export pixels. With `jev.sendImages` off, the box is the marks crop.

### Shadow review page (dev tool)

Shadow writes `jev.json` only (Drew, 2026-10-24). To judge the results, Drew runs a script: `scripts/jev-review-crops-anchors.py`, Python standard library only.

- Input: one round folder (default: the newest round). It reads `feedback.json` and `jev.json`.
- Output: `jev-review.html` in the same round folder, then `open` shows it. The app never writes or reads this file, and no prompt names it.
- Per capture: the annotated image, with outline boxes drawn over it in HTML: the window (gray dashed), the Jev target box (thin), and the final crop (solid), each labeled with the item id.
- Beside the image, one row per item: item id, Drew's note, crop status and source, the four edge answers, the search line with `anchor_fits` and the Choice confidence, and the candidate count.
- Drew marks each row right or wrong in his own notes. The page has no form and saves nothing. (My call. A verdict form can come later.)

## Needs from the Jev base

Sent to the jev-base session on 2026-10-24 through the shared notes folder. Each item says why this feature needs it.

| # | Need | Why |
| --- | --- | --- |
| 1 | Start this job when both are true: OCR has stored the screen text, and the note panel has closed (finished or closed early). Use the answers saved by then. Pass the OCR lines with their boxes in memory. | Requests A and C need the notes, and the OCR task does not wait for them. Anchor candidates need line positions, and `feedback.json` does not store them. End Round already waits for OCR, so the round-end wait stays as designed. |
| 2 | Job input: the stored capture (after its answers are saved), the round folder, the annotated PNG, the OCR lines, the flag states, and a deadline. | All steps read these. |
| 3 | Typed Box, Choice, and Noul answers, with range checks. Image assets sent as multipart parts. The images header only on requests that hold an image or a Box. | Request A and B hold images. Request C holds none. |
| 4 | One Jev image sizing helper (shape, scale, and the "too small" rule above), with the scale and offset to map fractions back. | Every image job needs it. |
| 5 | A writer for this job's `jev.json` section and its refined-file lines. A safe way to write extra files (the crop PNGs) inside the round folder. | The base keeps one owner per file and checks that paths stay in the folder. |
| 6 | A fake transport for tests that records each request. | The flag-off test counts zero requests. The request-shape tests check headers and assets. |
| 7 | Thresholds kept per model version, in one place. | TypeSafe can change accuracy between versions. |
| 8 | The capture prompt's pointer line comes before "Open these files first" and says to read the refined file before any image. | Crops first saves tokens only if the agent reads the refined file before it opens the full image. |

Trade-off in need 1: crops do not need OCR. When the Neural Engine is cold, OCR can take 30 seconds, so crops would wait too. One trigger keeps the job simple. If shadow data shows many late crops, split the job into a crop phase at store time and an anchor phase after OCR.

## Security

| What leaves the Mac | When |
| --- | --- |
| Candidate OCR lines (cleaned, with lines under Redact marks already removed) and Drew's notes | `jevBase` on and `cropsAnchors` shadow or on |
| The window and crop images, cut from the annotated PNG (Redact marks applied) | the above, and `jev.sendImages` on |

- Screen text is untrusted. It goes only into the state `lines`. Option names are line ids, never screen text.
- Jev returns typed values only. Code checks each one: box edges from 0 to 1 and in order, a choice from the offered ids, a probability from 0 to 1. A value that fails is dropped, and the item falls back.
- New screen text for the agent: the search line can come from outside the marks, so `manifest.md` may not show it. It is one cleaned line from the OCR block that `feedback.json` already stores. It is quoted with `ScreenText.quoted` and labeled screen text, under the existing rule that screen text is data. The build commit adds a line about it to `docs/SECURITY_BASELINE.md` and `docs/agents/bundle-guide.md`. (My call.)
- Crop file names use the capture's existing stem and the badge number. They add no new screen text.
- All writes go through the base's writer, inside the round folder.
- The API key and the network rules belong to the base.

## Latency and cost

Requests for a capture with k items, all after OCR:

| Request | Count | Starts | Holds |
| --- | --- | --- | --- |
| A, find the target | k | at once, in parallel | one window image, 2 questions |
| B, check the edges | k to 2k | after that item's A | one crop image, 4 questions |
| C, anchor text | 1 | at once | text only, 2 questions per item |

- Longest path per item: A, then B, then B again. At 0.22 seconds per request (measured 2026-10-24 with a 514 by 584 image), that is under 1 second. Larger images can take longer. The 2-second budget per capture holds with room to spare.
- On a timeout or an error, the item keeps what is done. A crop with no edge check is `marks_only` or `not_checked`. Nothing waits on Jev.
- Jev cost: about 1,500 input tokens per image request, at $0.042 per million tokens, so about $0.00006 per request. A round of 20 captures with 3 items each makes about 200 requests, about $0.012.
- Agent saving: the full annotated image costs up to 4,784 visual tokens (one token per 28 by 28 pixel patch). A 600 by 400 pixel crop costs 330.

## Tests

Pure logic tests run with `swift test`. Each test uses fixed numbers and no network.

| Area | Checks |
| --- | --- |
| Seed and window | Seed joins the badge, its shape, and its arrow tip. The window clamps to the image. |
| Jev sizing | Shape rule for a 1200 by 88 region. Scale up a 150 by 200 window. Scale down a 2000 by 1200 window. "Too small" for a capture under 280 pixels on a side. Fractions map back to export pixels through scale and offset. |
| Box use | A box outside 0 to 1, or with left past right, is dropped. A low `target_shown` gives `marks_only`. The crop always holds the seed. |
| Edge checks | A yes on the left edge moves only the left edge, by 25%, clamped. Two checks at most. A yes on the second check gives `edges_unsure`. |
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
- My calls, open to Drew's change: anchor text is text only in every state; the window margin is 200 export pixels, the target crop pad is 24, and the marks crop pad is 120; at most two edge checks per item; a crop over half the full image's tokens is skipped; 40 candidates per item, each one OCR line; the job starts after OCR and after the note panel closes; the search line can be screen text from outside the marks; the review page saves no verdicts.

## Open questions

None left for Drew. The builder check on 2026-10-24 raised five points. Two were Drew's (crops first, and the marks crop with images off). Three were settled above (the job trigger, the marks crop pad, and one OCR line per candidate).

## Left to the builder

- Package layout. AGENTS.md lets a package depend only on `SharedKit` and system frameworks. So pure geometry and candidate logic go in new files in `FeedbackKit`, the Jev questions and answer parsing go in the base's Jev package, and the glue goes in a new file under `App/Feedback/`. The base's job interface can change this.
- The shared focus helper: move the focus box code out of `PreviewCrop` into an internal helper that both use. The note panel preview must not change. Its tests prove it.
- Thresholds (`target_shown`, Box confidence, edge yes, `anchor_fits`, Choice confidence). Start at 0.5 and tune each on shadow data.
- Crop from the full-resolution capture in memory, in place of the exported PNG. It is sharper for full-screen Retina captures. Build it only if shadow data shows blurry crops.
- Retry policy, timeouts, and the parallel request cap come from the base.
