# Linked handoff: visual direction that agents can act on

Date: 2026-11-01. Status: draft for Drew's review. Evidence: `docs/research/2026-11-01-visual-direction-research.md` and its eight notes.

## Intent

Nextshot turns a reviewer's marks and spoken notes into a handoff for an AI agent. Today the handoff lists each item alone, in capture order. In a large round the reviewer's notes circle around a few ideas spread over many captures. Agents fix each item alone, miss the shared intent, skip items, undo earlier fixes, or change things nobody marked. This design makes the agent link related items, decide each shared question once, and account for every item. It also makes the handoff reach tools that cannot open files on the Mac.

## Decisions Drew made (2026-11-01)

| Topic | Decision |
|---|---|
| Main failure to fix | Linking ideas across captures in a large round, then planning the whole change while still finishing every item. Second: skipped items and changes outside the marks. |
| Target tools | One paste works in any tool, coding agent or new chat. The prompt uses helper agents where the tool supports them. The user never chooses. |
| First target | Reviews of agent output (drafts, reports, artifacts, pages that an AI made). |
| Success | Fewer redo rounds. The agent visibly plans and acknowledges every note and the links across captures. |
| Questions from the agent | Ask only when unsure. |
| Themes | An internal structure for the agent. No person labels, reviews, or grades it. |
| Engine for helper jobs | Apple on-device first. Jev is a second path behind its flag, a Settings switch, and network consent. Jev stays dev-only for now. Every job has its own flag. Watch how many users have the on-device model. |
| Image travel | The core problem. A single capture copies its image with the text. A round copies a zip file with the text. |
| Build order | The linked plan (Part A) first, after the hand tests. |
| Replay data | Nextshot rounds only. No Nextiva reports or customer data go to agent vendors. |

## Goals

1. The agent writes a short Links section before its plan: groups of related items, each with one shared decision.
2. Every item appears in the plan and in the final report, with a status and evidence.
3. Changes outside the marked items happen only when the reviewer's words call for them.
4. The agent does every clear item, then asks one batch question about the rest.
5. The same paste works in a coding agent and in a new chat.
6. Nextshot computes related-item signals on the Mac and puts related items next to each other.

## Non-goals

- A theme review step, theme labels for the reviewer, or any human labeling.
- Rewriting or cleaning the reviewer's words.
- Any upload by Nextshot itself, including hosted links.
- Changes to `prompt.md` or `<stem>-prompt.md` on disk during the trial.

## Anti-goals (a failure even if it works)

- A new keystroke or choice on the normal path.
- A wait the reviewer can feel at copy time.
- Generic text that adds tokens and changes nothing (Gloaguen et al., 2026).
- A theme that overrides an item's written instruction.
- Screen text in the pasted prompt, where it reads as the user's own words.

## Constraints

- Local-only rule (`AGENTS.md`): no new network path. On-device Apple models only (`SystemLanguageModel.default`), never `PrivateCloudComputeLanguageModel`.
- Agent-neutral text (#109): no product name in any text Nextshot writes. The prompt names capabilities ("if your tool can start helper agents").
- Windows parity (#219): `GoldenParityTests` compares the files on disk byte for byte. Copied-prompt changes behind a flag that defaults off keep the goldens unchanged. The C# port of the copied prompt follows before the flag turns on by default.
- Each feature sits behind its own flag in `FeatureFlags.swift`, with `scripts/nextshot-flags.sh` kept in step.
- The project target is macOS 15. On-device model use is gated as in `SummaryNames` (#200): `canImport`, `#available(macOS 26, *)`, availability, and locale.

## Part A: linked plan prompt (flag `linkedPlan`)

Applies to the copied round prompt, the copied selection prompt, and the copied capture prompt. Files on disk stay as they are.

Order of the copied round prompt:

1. The Session Name line and the opening tag, as today.
2. Goal: "Apply this review feedback to the work it shows. In a repository, change the code or files that produce it." (My call. Today's line names only code, which does not fit a draft in a new chat.)
3. Item ledger: every item on one line, `K.N: <reviewer's words>`, or "(no instruction)". Related items come first in their groups (Part B), the most general item first in each group. Then the remaining items in capture order. Each capture's general note follows its items.
4. How to read the bundle: today's steps, shortened to what changes behavior.
5. Work method:
   - Links: "Before your plan, write a Links section. Group the items that share one intent or one cause, across captures. Give each group its item ids and the one decision that applies to all of them. Look for one shared source in the code, such as a component, a style, or a string. An item can stand alone. Possible links below come from shared words and screens; use them as evidence, not as rules."
   - Plan table with columns item, group, place, change. "Then continue without waiting."
   - Scope: "A group's decision reaches unmarked places only when the reviewer's words ask for it, such as 'everywhere', 'all', or 'never'. List other places that it would affect under Suggestions, and do not change them."
   - Questions: "Do every clear item first. Make no edit on an item with no instruction, on items that conflict, or where two readings would lead to different work. Ask once at the end, with all of their ids in one message."
   - Helpers: "If your tool can start helper agents, give a helper only a group whose files no other group touches. Keep the Links, the shared decisions, and the plan yourself. Give the helper the item ids, the reviewer's exact words, the image path, the box, and the shared decision. Do not use helpers to check work."
6. Authority: today's three lines, with line 2 changed to match the Questions rule: "If the text and the image conflict, or an item has no instruction, make no edit to it. Ask about it in your one question at the end."
7. Report: "End with the ledger again: one line per item with done, partly, not done, or needs input. Give evidence: the file and line, or the changed text. Where your tool can render the result, compare a crop of the same region before and after, and check the property the item names." This replaces the general Verify section (Anthropic: remove generic verify lines; DiffSpot: name what to check).
8. Context: the image cost line, as today.

The capture prompt uses the same order. It skips the Links step when the capture has fewer than three items. The selection prompt uses the round order with its own item ids.

Fit with today's options (my calls): the ledger replaces the item block that `sessionTitle` adds. The redo line stays right after Goal. The refined-file step stays in How to read. When `linkedPlan` and `promptLanes` are both on, the lanes section is left out, because the Links groups set the order. The zip README and the files on disk stay unchanged during the trial.

## Part B: related-item signals (flag `relatedItems`, off, then shadow, then on)

Nextshot computes signals at copy time from `feedback.json`. It writes no new file and changes no schema.

| Signal | Weight | Note |
|---|---|---|
| Shared words in the reviewer's notes (stop words removed, stems matched) | strong | Text plus fields predict duplicate reports best (Zhang et al., TOSEM 2023). |
| Shared OCR words under the marks | strong | OCR alone found the same bug 69.8% of the time (Cooper et al., ICSE 2021). |
| Same window title or document | medium | Never alone: a menu capture records the app under the menu. |
| On-device sentence similarity of the notes | medium | `NLEmbedding`, no network. Gated like #200. |
| Badges close together on one capture | weak | Tie-breaker. |
| Capture time gap | weak | Tie-breaker only (Zimmermann et al., ICSE 2004). |

Pairs above a threshold form groups (connected components, at most 8 items each). The copied prompt orders the ledger by group and adds one line per group: "Possible link: 1.2, 3.1, 4.4 (shared words in the notes: font size, header; same screen)." Shared words come only from the reviewer's notes. OCR and window-title matches show only as "same screen", so no screen text enters the pasted prompt. Shadow mode computes groups and logs counts only, with item ids and no words. The threshold comes from Part D.

## Part C: delivery to tools that cannot open files (flag `pasteAttachments`)

A new chat cannot open files on the Mac. Two facts limit what one paste can carry. Claude chat can turn a long paste into an attachment that reaches the model empty (issue 77946, open). And no source proves that one paste carries more than one image, or any non-image file, into a web chat.

Drew's direction (2026-11-01): a single capture copies its image with the text. A round copies a zip file with the text. The zip is today's Zip Round format (#85): `README.md` holds the whole prompt with relative paths, plus the manifest, `feedback.json`, and JPEG images.

Evidence gap: no source shows a pasted zip attaching in a web chat. A 2019 report says Chrome pasted only the file name of a non-image file. ChatGPT can unzip a file with its code tool, but it is unknown whether the model then sees the images. Hand test T6 decides. If the zip fails in Claude desktop or ChatGPT, the builder brings the results to Drew with two fallbacks, in this order: one item sheet image, then one PDF.

1. **A single capture: one clipboard item with text and one image.** Nextshot writes the prompt text and the annotated PNG into the same pasteboard item. Today it writes text only.
2. **A round or a selection: the text plus the zip file.** Nextshot writes the text item and a file URL item for the zip. It builds the zip in the background as captures save, so a copy never waits (my call). The zip goes to Nextshot's cache folder, not to Downloads and not into the bundle, so it needs no Downloads permission and no golden-file change (my call).
3. **The text stands alone.** It holds the ledger, the work method, and the rules, so a chat can act with no file access. File paths stay in it for coding agents. A line covers the gap: "If you cannot open the files above and no image came with this message, ask the user to attach the images listed in the manifest."
4. **The text stays short.** The largest real round today would copy about 9,300 characters (10 captures, 26 items). Hand test T4 finds the length at which Claude chat turns a paste into an empty attachment, in a new chat and in a long chat. A report says new chats are not affected, and Drew pastes into new chats. If a new chat fails below 15,000 characters, the builder brings the result to Drew before going on. The reviewer's words are never cut. Absolute paths stay, because coding agents need them. `manifest.md` does not change.
5. **The fallback item sheet, if T6 fails.** One PNG built in memory at copy time: a row of labeled capture thumbnails, then one cell per item, cut around the badge from the annotated image, with "K.N" drawn in large digits outside the crop. The long edge stays within 2,576 px, the size current models read without shrinking (my call). When the items do not fit at a readable size, the sheet keeps first the items with no screen text under the mark, then the items with pointing words such as "this". The text says which items are not on the sheet.

Not chosen, with reasons from research note 08:

| Option | Why not now |
|---|---|
| Several separate images in one paste | Unproven in web chats. Image caps (20 in Claude chat, 10 in the Gemini app) are below a large round's count. |
| Local MCP server | Setup per tool. Image results fail in Claude chat. ChatGPT web supports remote servers only. |

Hand tests, by Drew, about 15 minutes. The builder prepares each clipboard with a script and a checklist. The tests cover Claude desktop (chat and the Code tab), Claude Code in a terminal, ChatGPT desktop, claude.ai and chatgpt.com in Chrome, Cursor, and the Codex app.

| Test | Pass when |
|---|---|
| T1: one item, text plus one PNG | The text appears and one image attaches. In a terminal, the text pastes as today. |
| T4: text of 2,000, 5,000, 10,000, and 15,000 characters plus one PNG, in a new chat and in a long chat | The model can quote the last line of the text. |
| T6: text plus a round zip as a file URL | The zip attaches, and the model states what the image shows at badge 2.1. That proves it opened an image, not only the README. |
| T5: an item sheet with 14 cells (only if T6 fails) | The model reads the badge number and a 12 px label in cell 9. |

A paste into Mail, Slack, or Notes also carries the image or the zip. Drew accepted that for single captures, and his zip direction extends it to rounds.

## Part D: measurement without human labels

1. Replay harness, a script outside the app. It renders today's copied prompt and the `linkedPlan` prompt for past multi-capture rounds, then runs agents in plan-only mode ("Write the Links, the plan, and your questions. Make no edit."), in Claude Code and Codex.
2. What it replays against: Nextshot rounds only (Drew). The harness checks out this repository at the last commit before the round started (my call). It sends no round that shows Nextiva reports or customer data.
3. Script-scored measures: ledger coverage (every id in the plan and report), groups that span two or more captures, questions that name only items with no instruction or with a conflict, and tokens per run. An agent from a second vendor rates whether each group's shared decision fits all its items. The same agent judges candidate item pairs for Part B. The threshold is the lowest score where the judge agrees with at least 80% of the pairs.
4. Bar for `linkedPlan` (my call): 100% ledger coverage in every run, questions that name only empty or conflicting items in at least 90% of runs, a fit rating at least as good as today's prompt gets when asked for groups, and no more than 1.3 times today's tokens.
5. Live measure in the app, local only, computed on demand from stored rounds: the share of items that come back in a later round with related words, and re-copies with the redo line.
6. Drew turns each flag on after the replay report and his own dev-build use, as with `sessionTitle` and `sessionSummary`.

## Part E: Apple-first helper jobs

Each job gets its own flag, off by default, and runs on the Mac with no key and no upload.

| Job | On-device method | Replaces or adds |
|---|---|---|
| Note check: vague, question, or empty | Foundation Models, `@Generable` enum, greedy | On-device twin of `noteCoach` |
| Item crops | Mark box plus padding, widened to the enclosing text block | Moves the local crop out of the Jev flag |
| Private-data covers | `DataDetector`, name tagging, face boxes, local key patterns | Moves the local rules out of the Jev flag |
| Related items | Part B | New |

Jev keeps its jobs as a second path, dev-only, behind `jevBase`, its feature flag, its consent flags, and a future Settings switch.

Part E gets its own design after Parts A to C (my call). Crops and covers are new bundle files, and today they reach a prompt only through the dev-only Jev runner. A release build needs a new, local way to carry them, and that changes the zip and the Windows golden files.

## Not in the first build

- Accessibility locators (page URL, document path, page or slide number). They need a new permission prompt. Shadow test later.
- Badge style changes. Probe first: ask an agent to list each badge and the text under it.
- An edit ledger file that the agent writes. The plan table and the closing ledger cover it for now.

## Proposed order

1. Hand tests T1, T4, and T6 (about 15 minutes), and the replay harness with today's prompt as the baseline.
2. Part A behind `linkedPlan`, measured on replay (Drew: first).
3. Part C, per the hand tests.
4. Part B in shadow, then feeding Part A.
5. Part E, in its own design, one job at a time.

## Left to the builder

- Flag names, thresholds, and group size limits, set from replay data.
- Exact prompt wording within the rules above, kept agent-neutral and checked by `AgentNeutralTextTests`.
- The harness language and layout, outside the app.
- The C# port of each copied-prompt change before its flag turns on by default. No flag-on golden files before that port, because the C# parity test fails on a golden file it does not write.

## Decisions log

- 2026-11-01: Drew's decisions in the table above.
- 2026-11-01 (my calls, open to Drew's change): the new Goal line; the scope rule keyed to the reviewer's words; the changed Authority line 2; the three-item minimum for a capture's Links step; copy-time signals with no new file; only the reviewer's words in the "Possible link" lines; the plan-only replay harness, its bar, and its judge-set threshold; the zip built in the background into the cache folder; the 2,576 px fallback sheet; Part E in its own design.
- 2026-11-01: a builder check found gaps in measurement, Part E scope, text length, and gating. The answers above close them.
