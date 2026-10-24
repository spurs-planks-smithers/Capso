# Jev image features in Nextshot: brainstorm

Date: 2026-10-24. Status: brainstorm only. No code changed.

## What TypeSafe shipped

Jev is TypeSafe's System One model. It takes a state and typed questions (Choice, Score, Noul) and returns typed answers with probabilities. It does not write text.

Jev 1.14 shipped on 2026-10-14 (blog post "Jev: For the builders AND dreamers"). It adds three "danger zone" features. Each one turns on with its own request header.

| Feature | Header | What it does |
| --- | --- | --- |
| Images | `TypeSafe-Danger-Zone-Images: true` | An image can go anywhere text can go: in the state, in a question's instructions, or in its criteria (for example, a Choice option defined by example pictures). Jev 1.13 and 1.14 both accept images. |
| Box | same header | A new question type. It returns one bounding box (top, bottom, left, right as fractions of the image) and a confidence. Jev 1.14 only. |
| Long context | `TypeSafe-Danger-Zone-Long-Context: true` | Raises the per-request and per-question limits from 64k and 32k tokens to 262k tokens. Slower and less accurate. |

Other 1.14 facts:

- `jev-latest` and `jev-preview` both point to `jev-1.14.0`. Changes are small and broad, with the largest gain in languages other than English.
- Price: $0.042 per million input tokens. Output tokens are free. Images bill as input tokens.
- An opt-in lets TypeSafe use queries to find model faults. TypeSafe does not train on queries. Zero data retention is for enterprise customers only.
- TypeSafe calls images and Box "dreamer-ready", not production-ready. Accuracy on images is lower than on text. The docs advise the simplest possible questions.

Image rules that matter for Nextshot:

- PNG or JPEG only. Each side must be 280 to 1568 pixels. The API rejects an image outside the limits and never resizes it. A full Retina capture must be scaled down first. A small circle crop must be padded or scaled up.
- Put an image that several questions use in the state once. Each reference in instructions adds another copy of the image to the tokens.
- A Box question always returns a box. There is no "not found" answer. Ask a Noul in the same request ("Is there a ... in `shot`?") and ignore the box when the Noul is low.
- One box per question. To check a box, crop to it and ask one Noul per edge ("Does the target continue past the left edge?"). In TypeSafe's test this caught 30 of 36 cut-off crops.
- Patterns from the docs: compare against a known picture, define options by example pictures, ask what changed between frames, look closer only when needed, search a large image by tiles, and find where something is with Box.

## Test on 2026-10-24

One request to `jev-1.14.0` with the image `.github/assets/menubar.png` (514 by 584 pixels, upstream's public capture menu) and six questions. The same request without the header returned HTTP 400: "Images are experimental. Send the header TypeSafe-Danger-Zone-Images: true to use them."

| Question | Type | Answer | Correct? |
| --- | --- | --- | --- |
| What kind of interface is this? | Choice | menu, confidence 1.0 | Yes |
| Which row is highlighted? | Choice | Capture Area, 0.99 | Yes |
| Box: the Record Screen row | Box | top 0.51, bottom 0.58, left 0.12, right 0.91, confidence 0.45 | Yes. The row sits at about 0.51 to 0.57 of the height. |
| Box: the part the note is about (note: "the shortcut hints on the right are hard to read, make them brighter") | Box | the shortcut glyphs on the Capture Area row, confidence 0.21 | Partly. The hints fill a whole column, and one box holds one target. The low confidence shows this. |
| Does the image show what the note describes? | Noul | 0.93 | Yes |
| How clear is the change the note asks for? (vague, partial, clear) | Score | 1.98 of 2, confidence 0.97 | Yes |

Round trip: 0.22 seconds for all six answers. Usage: 1,481 input tokens, so about $0.00006 per request. A 20-capture round with three items each and one request per item costs less than one cent.

## The local-only rule

The project's agent instructions say feedback code adds no network code and no outbound requests. Every in-app idea below breaks that rule. Captures also hold private screen content (Nextiva data, email, code).

Two lanes keep the choice open:

- Handoff lane: a separate tool outside the app (a CLI or an agent skill) reads a finished bundle, calls Jev, and writes `refined-prompt.md` next to `prompt.md`. Nextshot stays local-only. Drew runs the tool, so he decides what leaves the Mac.
- Live lane: an opt-in package inside the app, off by default, with its own Keychain key and a per-round consent. Only this lane can react while Drew types notes. It needs a change to the local-only rule and the security baseline.

## Why speed matters during notes

- 0.22 seconds is shorter than the pause between Return and the first word of the next answer. A nudge can appear before Drew starts the next step, with no spinner.
- One request carries many questions at no extra output cost, so a single call can check note clarity, note-to-circle match, and intent together.
- Dictation (Wispr Flow) pastes a whole answer at once. One check runs per answer, not per keystroke.
- A slow model would need a "checking" state, and Drew would learn to skip it. A fast check can stay silent when the note is good and speak only when it finds a gap.

## Ideas

Lane: Live means inside the app (needs the opt-in package). Handoff means the separate tool.

| # | Idea | Stage | Lane | What Jev judges | Value |
| --- | --- | --- | --- | --- | --- |
| 1 | Note coach | Note panel | Live | Score: vague, partial, or clear. Noul: does the note name a change? Image: the circle crop. | A gray hint ("Name the change: brighter, move, remove?") under a vague answer. The newest real capture (2026-10-24, 10:28) sent two items with no instruction. |
| 2 | Wrong-badge check | Note panel | Live | Noul: does the circle crop show what the note describes? Box: where the note points, compared in code with the circle. | Catches a note typed against the wrong badge before it reaches the agent. |
| 3 | Intent chips | Note panel, before typing | Live | Choice over intents (bug, copy change, spacing or layout, color or contrast, remove, add, question, keep) from the crop. | One tap fills the item type. The note can then be short. |
| 4 | Follow-up question | Note panel | Live | Nouls: does the note state the expected result? For a bug, does it say how to reproduce it? | The panel adds one optional step only for the item that lacks it. Research finds that steps to reproduce and expected results help developers most and are what reporters leave out. |
| 5 | Uncircled-mention finder | General note step | Live | Noul: is the thing the general note names in the capture? Box: where it is. | Offers a ghost circle ("Add as item 4?") for something Drew mentioned but did not mark. |
| 6 | Design-rule pre-marks | Editor opens | Live | One Noul per house rule (italics, middots, a tag larger than its text, a dash or blank in an empty table cell, one word alone on a last line, text overflow). Box for each hit. Criteria can hold example pictures from past captures. | Suggests marks for Drew's recurring complaints before he draws them. One key accepts a mark. |
| 7 | Anchor text pick | Capture prompt | Handoff | Choice over the capture's OCR lines: which line names the item best? | The prompt says "Search the repo for: Copy Last Capture Prompt" instead of a dump of all OCR text. The agent finds the file faster. |
| 8 | Item crops | Capture prompt | Handoff | Box around each item with its context. Edge Nouls check the crop. | Each item gets a small, sharp image. The full image becomes a fallback. Fewer image tokens for the agent, and better reading of small text. |
| 9 | Duplicate merge | Round prompt | Handoff | Noul per item pair, with both crops and both notes: same change on the same element? | One item with "seen in 2.1, 5.3, 7.2" replaces three. The agent does not make the same edit three times. |
| 10 | Conflict flag | Round prompt | Handoff | Noul per item pair: do the notes ask for opposite changes to the same element? | An "Ask Drew first" block at the top of the prompt. |
| 11 | Priority order | Round prompt | Handoff | Scores for severity (blocker, bug, polish, nit) and size (one line to many files). Weights stay in code. | Blockers first, grouped by area. Drew can switch to "bugs only" with no new Jev call. |
| 12 | Fast and slow lanes | Round prompt | Handoff | Choice: mechanical (exact copy, color, or spacing value) or needs judgment. | Two prompts: a batch of mechanical edits for a cheap model, and a plan-first prompt for a strong model. |
| 13 | Repo and skill router | Round prompt | Handoff | Choice over Drew's repos from the window title, app, and image. Choice over skills or agents (designer, executor, question for Drew). | One packet per repo. Each agent gets only its own items. |
| 14 | Visual recheck | After the agent works | Handoff | Box finds the old region in a new capture. Noul per item: does `after` make the change the note asks for, compared with `before`? | A done or not-done table with evidence, checked against the screen and not only the agent's report. |
| 15 | Injection and data guard | Before handoff | Handoff | Noul on OCR text: does it hold an instruction aimed at an AI agent? Noul and Box: does the capture show an email, phone number, account number, or face? | Flags prompt injection in screen text and blurs private data in the agent copy. The image check sends the capture out, so the text check on local OCR runs first. |

## A refined round prompt (mockup)

```text
<feedback_round items="9 (from 12 captured)">
Ask first (conflicts): 2.1 vs 4.3, both change the Recent row height.
Lane A, mechanical (send to a fast model):
- 1.2 copy change. Search: "Copy Last Capture Prompt". Crop: 1028-claude-item-2.png
- 3.1 color or contrast. Search: "No active round". Seen in 3.1, 6.2, 7.1.
Lane B, needs judgment (plan first):
- 5.1 layout, severity bug. Search: "All Rounds". Crop: 1105-nshot-item-1.png
Verify: run the Nextshot recheck on each item and paste its table.
</feedback_round>
```

## First experiment

Update (Drew, 2026-10-24): Nextshot runs Jev itself, in the background after each capture, with every feature behind an off, shadow, or on flag. The design draft is `docs/superpowers/specs/2026-10-24-jev-handoff-design.md`. The plan below was the first proposal.

Build the handoff lane first, as a small Python script in the `jev` lab repo. Run it on three to five real bundles, with Drew's approval for each one, because the images leave the Mac. Measure ideas 1, 7, 8, and 9 against Drew's own judgment. Then decide whether the live lane earns a change to the local-only rule.

## Other projects

| Project | Use of Jev images |
| --- | --- |
| `jev` (lab) | Add an images lesson: Box, image criteria, and the "what changed" pattern. The safest place to learn. |
| `augustine` (lawn notes) | Score levels defined by example lawn photos. "What changed" between dated photos. Box for brown patches. |
| `computer-use` (lab) | Box as a fast grounding step before a click. A Noul on two frames: did the click change the screen? |
| `customer-reports`, decks, the `pdf-polish` check | Render each page to PNG. One Noul per deck rule (overflow, one word on a last line, middots, italics). Box to show where. |
| `berthhq` | Check tenant photo uploads: upright, shows a vessel, no text baked in. |

## Sources

- TypeSafe docs: [Images](https://docs.typesafe.ai/images), [Box](https://docs.typesafe.ai/primitives/box), [Models](https://docs.typesafe.ai/models), and the [Jev 1.14 post](https://typesafe.ai/blog/jev-1-14).
- Zimmermann, Bettenburg, and others, [What Makes a Good Bug Report?](https://thomas-zimmermann.com/publications/files/zimmermann-tse-2010.pdf) (TSE 2010): steps to reproduce help developers most and are hardest for users to supply.
- Song and others, [Toward Interactive Bug Reporting (BURT)](https://2022.esec-fse.org/details/fse-2022-research-papers/53/Toward-Interactive-Bug-Reporting-for-Android-App-End-Users) (FSE 2022): guided reporting with instant quality checks gave fewer missing and wrong steps.
- Yang and others, [Set-of-Mark Prompting](https://arxiv.org/abs/2310.11441) (2023): numbered marks on an image improve a model's grounding. Nextshot's counter badges already do this.
- Zhang and others, [MLLMs Know Where to Look](https://arxiv.org/abs/2502.17422) (ICLR 2025): a crop of the relevant region improves the reading of small details.
- Duan and others, [UICrit](https://arxiv.org/abs/2407.08850) (UIST 2024): design critiques tied to bounding boxes. Separate calls for critique and location gave better boxes.
- [LikeThis!](https://arxiv.org/abs/2603.04245) (2026): screenshot plus comment, turned into concrete suggestions, gave feedback that developers rated more actionable.
- Wang and others, [SETU](https://www.eecs.yorku.ca/~wangsong/papers/ist19-1.pdf) (IST 2019): 82% of crowdtest reports were duplicates. Screenshot plus text features beat text alone.
- Cooper and others, [TANGO](https://arxiv.org/abs/2101.09194) (ICSE 2021): OCR text plus visual features found duplicate video bug reports.
- Liu and others, [Lost in the Middle](https://arxiv.org/abs/2307.03172) (TACL 2024): models use the start and end of a long context better than the middle.
