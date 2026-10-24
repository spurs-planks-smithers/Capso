# Note coach: design (draft)

Date: 2026-10-24. Status: approved (Drew, 2026-10-24). Code waits for the Jev base (#36) job interface. Sub-issues: #61 (job, rule, and tests), #62 (accuracy test), #63 (shadow run, paste test, and on decision). Issue: #37 (parent #34). Flag: `noteCoach` (off, shadow, on). Related docs: `docs/superpowers/specs/2026-10-24-jev-handoff-design.md` (Jev design), `docs/superpowers/specs/2026-10-24-feature-flags-design.md` (flags), `docs/plans/2026-10-24-jev-image-ideas.md` (idea 1).

## Intent

A note that names no change makes the coding agent guess. The note coach labels each item's note after a capture is saved. For a vague note, it tells the agent to ask the reviewer first. For a question, it tells the agent to answer and change no code. It never changes the note, never adds a keystroke, and never makes Drew wait.

## What Drew's past notes show

Measured on 2026-10-24 from the 9 bundles in `~/Library/Application Support/Nextshot`. The script read `feedback.json` locally. Nothing left the Mac. This repository is public, so this section gives counts and generic examples only, never note text.

A capture counts as a test when its notes or image show a test of Nextshot itself: placeholder text ("asdf", "this is my first note"), a demo pricing page, or a capture made while a session walked Drew through a live check. Drew confirms or corrects this split (see Open questions).

| Set | Items | Empty note | Vague note | Asks the agent for an answer | Names a change | Median words |
| --- | --- | --- | --- | --- | --- | --- |
| Real feedback | 66 | 2 (3.0%) | 0 (0%) | 10 (15.2%) | 54 (81.8%) | 34 |
| Tests of Nextshot | 35 | 15 (42.9%) | 17 (48.6%) | 0 | 3 (8.6%) | 5 |

Findings:

1. Drew's real notes are long and specific. The shortest real note has 7 words. None is vague.
2. The real gap is the empty note: 2 of 66 items. Code finds an empty note with no model. The prompt already handles it: it prints "(no instruction)", lists the item under "Items with no instruction", and tells the agent to ask before it changes the item (`PromptBuilder.rules`).
3. The capture from 2026-10-24 10:28 that issue #37 cites ("two items with no instruction") was a test. Its image shows a session's live-check steps ("Drag over any small area", "Press Return at each note question, or Esc to skip it").
4. 10 of 66 real items ask the agent for an answer, not a change: "What does this setting mean?", "Tell me what to put in this field." A check for "names a change" says no to each of them. The line "Ask Drew first: the note names no change" would then be wrong on 15% of real items. The design must keep questions apart from vague notes.
5. Test captures hold almost all vague and empty notes. They make a good labeled test set for the Jev job: placeholder text must score vague.

## Research

Four searches on 2026-10-24 on how tools judge or coach the quality of feedback and bug reports.

| Source | What it found | What it means for the note coach |
| --- | --- | --- |
| Krause and others, Critique Style Guide (CHI 2017) | A model found text features, such as specificity, that predict how helpful design feedback is. A style guide built on those features raised the rated helpfulness of new feedback. | Specificity is the main quality signal. One score for it is enough. |
| Ngoon and others, CritiqueKit (CHI 2018) | Feedback quality has three parts: specific, actionable, and justified. Adaptive guidance improved the feedback of novice reviewers. | "Names a change" is the actionable part. Drew's notes already carry the reason, so "justified" adds little. |
| Chaparro and others, Detecting Missing Information in Bug Descriptions (FSE 2017) | Tools can detect when a bug report leaves out the observed behavior, the expected behavior, or the steps to reproduce. | The two checks map to "names the problem" (observed) and "names the change" (expected). |
| Demystifying Feature Requests (RE 2025) | A model found ambiguous and incomplete feature requests and wrote clarifying questions for them. | Supports the "ask first" action. Nextshot asks through the agent, after the capture, not through a pop-up. |
| CLAMBER benchmark (2024) | Current large models are weak at finding ambiguous requests on their own. | Measure precision on Drew's own notes before the on state. Keep the threshold high. |
| ImproBR (2026) | A detector found missing parts of bug reports, and a model rewrote them. | Rewriting is an anti-goal here. Drew's words stay exact. The note coach only labels. |

Most tools coach while the person types. Nextshot's design rules forbid that for the first build (no new keystroke, no live hint). The note coach therefore coaches the agent, not the reviewer: the agent asks the reviewer in its own chat.

## Definitions

Each item is one numbered badge. Its note is the badge's `instruction` in `feedback.json`. The capture's general note is context only. The coach never labels it.

| Label | Meaning (Drew, 2026-10-24) | Decided by | Example (made up) |
| --- | --- | --- | --- |
| empty | The note is missing, or holds only white space. | Code | (no note) |
| vague | The note names no problem, names no change, and asks no question. | Jev, then a code rule | "fix this", "hmm", "look at this", "asdf", "second note" |
| partial | The note names a problem with the marked item, but not the change. | Jev | "this is cut off", "this number is wrong" |
| question | The note asks for information, an explanation, advice, or text to write, and names no change. | Jev, then a code rule | "what does this setting do?", "tell me what to put in this field" |
| clear | The note names the change. A note that asks a question and also names a change ("if it is redundant, remove it") is clear. | Jev | "make this column 50% narrower" |
| not checked | Jev gave no answer: a timeout, an error, no key, no network, or a flag off. | Code | n/a |

Only vague and question items change the on-state output. Partial items pass as they are: the agent can infer the change from the problem (Drew, 2026-10-24).

## The Jev job

One request per item that has a note. My call: one request per item keeps each note apart from the others, so Jev cannot mix up two notes. The requests run in parallel. Each costs about $0.00002 at the 2026-10-24 price.

State (named JSON fields):

- `note`: the item's note, exact.
- `general_note`: the capture's general note, exact, or empty.

The first build sends text only, even with `jev.sendImages` on (Drew, 2026-10-24). The circle crop comes later as its own step, after the text accuracy test. That step adds `crop` to the state, names it in the `clarity` instructions, and runs the accuracy test again with images.

Never in the state: window titles, OCR text, file names, or paths. They are screen text and can hold an injection. They also add nothing to a clarity judgment.

Questions (three, the simplest that answer the rule):

| Id | Type | Instructions | Criteria |
| --- | --- | --- | --- |
| `clarity` | Score | How clearly does `note` tell a developer what to do about the marked item? `general_note` is context from the same reviewer. Words like "this" or "here" refer to the marked item. | 0: names no problem, names no change, and asks no question ("fix this", "hmm", "look at this", "asdf"). 1: names a problem with the item but not the change ("this is cut off", "this number is wrong"). 2: names the change, or asks a clear question ("make this 50% wider", "rename this to Invoice Detail", "what does this setting do?"). |
| `names_change` | Noul | Does `note` ask for a change to the marked item? | true: names something to add, remove, move, resize, rename, recolor, reword, or fix. false: only describes, praises, or asks a question. |
| `asks_answer` | Noul | Does `note` ask for information, an explanation, advice, or text to write? | true: the reviewer wants an answer or a draft. false: the reviewer wants only a change, or nothing. |

The code rule (thresholds start at TypeSafe's suggested 0.7 and 0.3; the accuracy test sets the final values):

- vague: `clarity` level 0 probability ≥ 0.7, `names_change` < 0.3, and `asks_answer` < 0.3.
- question: `asks_answer` ≥ 0.7 and `names_change` < 0.3.
- Any other answer: no line. `jev.json` records the label from the highest `clarity` level (partial or clear) and every probability. My call.

The code checks each answer's type and range before use. An answer outside 0 to 1, or a missing answer, makes the item not checked.

## Behavior per flag state

The coach runs only when both `jevBase` and `noteCoach` are on or in shadow. `jevBase` off means no request, whatever `noteCoach` says.

| `noteCoach` | Requests | `jev.json` | Refined file | Prompts and note panel |
| --- | --- | --- | --- | --- |
| off | none | no note coach entry | no note coach line | unchanged, byte for byte |
| shadow | one per item with a note | one entry per item: label, every probability, model, time in ms, and what the on state would write | no note coach line | unchanged |
| on | same as shadow | same as shadow | one line per vague, question, or empty item | the note panel is unchanged. The prompts change only through the base's pointer to the refined file. |

Lines in `<capture>-refined.md` (on state only). Drew's note stays exact on the line above them.

- vague: "Ask the reviewer first: the note names no change." (wording, Drew, 2026-10-24)
- question: "Answer this item. Change no code." (Drew, 2026-10-24)
- empty: "Ask the reviewer first: the item has no note." My call: code writes it with no Jev call, so the refined file is complete on its own. The plain prompt already says the same.

Failure: a timeout, an error, no key, or no network makes the item not checked. Nextshot writes no line for it and never waits. The round-end wait is the base's 500 ms limit.

Trigger: the job starts on the base's trigger, after the note panel closes. A panel closed early (close button, End Round, or a new capture) gives the answers saved by then. The job writes its refined lines once. It does not rewrite them for a late answer. My call.

Which text wins: the capture prompt tells the agent to apply the feedback to the code. A refined line must override that for its item. The base's pointer line carries this rule for every feature: "Lines in the refined file override the Goal and Work method for their item." This feature does not edit `PromptBuilder`. The request to the base is in the shared session notes. If the base declines, the fallback is one sentence in `PromptBuilder.rules` that shows only in the on state.

## Files and hook points

The base (#36) defines the job interface, the refined-file writer, and `jev.json`. This feature adds only new files:

- the job: request building and answer parsing.
- the rule: answers to a label, pure code with no network.
- the line text for each label.
- tests for each of the above.

The only shared edit is the job's registration at the hook point that the base names. No upstream file changes. The builder puts each file where the base's interface says and records the paths here.

## Tests

1. Flag off: with `noteCoach` off and `jevBase` on, a fake transport records zero requests, and `jev.json`, the refined file, and every prompt match the output with no Jev code, byte for byte.
2. `jevBase` off with `noteCoach` on: zero requests.
3. Request content: the state holds `note` and `general_note` exactly as typed. It never holds a window title, OCR text, a path, or an image, even with `jev.sendImages` on. The request has no images header. An empty note makes no request.
4. Rule: fixed answer sets map to each label, including values at each threshold and answers out of range.
5. Shadow: writes `jev.json` entries and no refined line.
6. On: writes the exact line for each label. The note text above it is unchanged.
7. Failure: a timeout or an error marks the item not checked and writes no line.

Test fixtures use made-up notes only. The repository is public.

## Accuracy test (before the on state)

Drew approved this on 2026-10-24: send note text to Jev, text only, no images, no window titles.

- Set: the 66 real notes, the 20 filled test notes, and 50 made-up notes: 30 vague, 8 partial, 6 question, and 6 clear, written in Drew's dictation style.
- Labels: the note-coach session labeled the real notes by reading them. Drew confirms the 10 question labels before the run, so the test does not only compare one model with another. My call.
- Key: Nextshot's own TypeSafe key, which the base session adds. The `jev` lab key may carry only made-up or public data, so it is not used.
- TypeSafe keeps each request. It does not train on them. Drew confirmed the text send with this fact on 2026-10-24.
- Pass: no real note labeled vague, at least 80% of the made-up and test vague notes labeled vague, and at least 8 of the 10 real question items labeled question.
- The labeled set and the results stay out of this public repository, in `build/jev-eval/` of the main checkout (git ignores `build/`). The spec records counts only. My call.
- The harness is a later step (sub-issue B). It needs the base's client and key.

## Rollout and kill rule

1. Build with `noteCoach` off in both channels. A test proves the off state changes nothing.
2. Drew sets shadow with `scripts/nextshot-flags.sh set noteCoach shadow` once the base works on his Mac.
3. Run the accuracy test. Set the thresholds from it.
4. Paste test (Drew, 2026-10-24): one capture with a vague item and a question item, pasted into Claude Code. The agent must ask the reviewer about the vague item and answer the question item with no code edit. On 2026-10-21 an agent skipped a softer rule, so file tests alone do not prove this.
5. On only when the accuracy test and the paste test pass, and Drew agrees. The release default stays off. Jev features are dev-only.
6. Kill rule: if the on state puts a wrong line on a real item twice, set it back to shadow and retune. If shadow finds no vague or question item in 10 real rounds, the coach stays in shadow and the next feature takes its slot.

Metrics, from `jev.json`: the share of empty, vague, and question items per round, Jev time per item, and the share of items not checked.

## Open questions

None open. Drew answered every question that changes what gets built on 2026-10-24.

## Decisions log

- 2026-10-24: build small, shadow first. Empty notes need no Jev call. The on state waits for shadow data (Drew).
- 2026-10-24: vague means the note names no problem, no change, and no question. Partial notes get no line (Drew).
- 2026-10-24: question items get "Answer this item. Change no code." in the on state (Drew).
- 2026-10-24: send note text to Jev for an accuracy test, text only (Drew).
- 2026-10-24: the line says "Ask the reviewer first", not "Ask Drew first" (Drew).
- 2026-10-24: every capture listed as a test is a test, so the counts stand (Drew).
- 2026-10-24: the first build sends text only. The crop is a later step (Drew).
- 2026-10-24: a real paste test gates the on state (Drew).
- 2026-10-24: Drew confirmed the text send after he learned that TypeSafe keeps each request (Drew).

## Left to the builder

- File paths and type names, from the base's job interface.
- The final thresholds, from the accuracy test.
- The later crop step: reuse the shared image sizing helper (base or issue #38). Each side must be 280 to 1568 pixels.

## Sources

- Krause and others, [Critique Style Guide: Improving Crowdsourced Design Feedback with a Natural Language Model](https://spdow.ucsd.edu/publication/critique-style-guide-improving-crowdsourced-design-feedback-with-a-natural-language-model) (CHI 2017).
- Ngoon and others, [Interactive Guidance Techniques for Improving Creative Feedback](https://research.adobe.com/publication/interactive-guidance-techniques-for-improving-creative-feedback) (CHI 2018), [paper](https://d.ucsd.edu/srk/papers/2018/CritiqueKit-CHI2018.pdf). The classifier detail (specific, actionable, justified) comes from the review [Systematic Review of Approaches to Improve Peer Assessment at Scale](https://arxiv.org/pdf/2001.10617).
- Chaparro and others, Detecting Missing Information in Bug Descriptions (ESEC/FSE 2017), summarized in [Automated Management of Bug Reports](https://computing.unl.edu/colloquium/2018-2019/oscar-chaparro/).
- [Demystifying Feature Requests: Leveraging LLMs to Refine Feature Requests in Open-Source Software](https://arxiv.org/abs/2507.13555v1) (RE 2025).
- [CLAMBER: identifying and clarifying ambiguous information needs](https://arxiv.org/abs/2405.12063v2) (2024).
- [ImproBR: Bug Report Improver Using LLMs](https://www.alphaxiv.org/abs/2604.26142.md) (2026).
- TypeSafe docs: [Score](https://docs.typesafe.ai/primitives/score), [Noul](https://docs.typesafe.ai/primitives/noul).
