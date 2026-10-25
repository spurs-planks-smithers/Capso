# Lanes and priority: design (draft)

Date: 2026-10-24. Status: approved (Drew, 2026-10-24). Issue: #69 (parent #34). Flag: `promptLanes` (off, shadow, on), with the sub-flags `lanesOrder` and `lanesSplit` (#94, 2026-10-25). Related docs: `docs/superpowers/specs/2026-10-25-jev-sub-flags-design.md` (sub-flags), `docs/plans/2026-10-24-jev-image-ideas.md` (ideas 11 and 12), `docs/superpowers/specs/2026-10-24-jev-handoff-design.md` (Jev design), `docs/superpowers/specs/2026-10-24-jev-base-design.md` (the base), `docs/superpowers/specs/2026-10-24-feature-flags-design.md` (flags).

## Intent

A large round gives the agent a long, flat list. Blockers sit next to nits, and a one-word rename sits next to a design question. The strong model that Drew pastes into does all of it, at the strong model's price.

Lanes and priority label each item after its capture is saved. At round end, the copied round prompt gets one new section at its end. It lists every item once, in two lanes. Each lane lists its items worst first:

- Lane A, exact edits: the note gives every change as an exact value, and the change is small. The agent hands these to a subagent on a fast, low-cost model as one batch.
- Lane B, needs judgment: everything else. The agent plans these itself, worst first.

Since 2026-10-25 (#94), two sub-flags turn these two parts on one at a time, so Drew can judge each alone: `lanesOrder` gives the worst-first order, and `lanesSplit` gives the lane A and lane B split. The text above describes both on. See "Sub-flags" below.

The feature never changes a note, never adds a keystroke, and never makes Drew wait. Drew still pastes one prompt.

## What Drew's past rounds show

Measured on 2026-10-24 from the 17 rounds in `~/Library/Application Support/Nextshot`. The script read `feedback.json` locally. Nothing left the Mac. This repository is public, so this section gives counts only, never note text.

| Measure | Result |
| --- | --- |
| Rounds | 17 |
| Items (numbered badges) | 137 |
| Real feedback items (the note coach's split, see its spec) | about 66 |
| Real rounds with 16 or more items | 3 (26, 16, and 18 items) |
| Real rounds with 3 or fewer items | 4 |

The session read the real notes and sorted them by hand. These are first counts, not labels. The accuracy test (below) makes the labeled set.

| Kind of real item | Count | Example (made up) |
| --- | --- | --- |
| Exact edit: quoted new text, a removed sentence, an exact size | about 22 (one third) | "Rename this column to Voice Minutes" |
| Asks for an answer or a draft | 9 | "What does this setting do?" |
| Needs judgment: layout, design, data checks, research | about 35 | "Make this card read as the main opportunity" |

Findings:

1. Order and lanes matter only in large rounds. Three real rounds hold 16 or more items. In a round of three items, the agent reads the whole list at once.
2. One real item in three is an exact edit. That share is large enough for a fast lane.
3. Many notes mix an exact edit with a judgment call, for example a rename plus a move. A mixed note must go to lane B.
4. Some exact edits are large: "rename X to Y everywhere" touches many files and needs care with code names. Size must gate lane A, not only exactness.
5. Few real items are bugs. About 4 of 66 report a broken or wrong result, for example two numbers that do not match across pages. Severity order puts these few at the top of a long list.

## Research

Four searches on 2026-10-24 on how teams route coding work between strong and cheap models, and how they order long task lists for a model.

| Source | What it found | What it means for lanes |
| --- | --- | --- |
| Aider, architect mode (2024) and R1 plus Sonnet (2025) | A strong model plans the change, and a second model writes the file edits. R1 as architect with Sonnet as editor set a new top score on Aider's polyglot benchmark at 14 times less cost than the earlier o1 result. o1 with Sonnet did no better than o1 alone. | Plan with the strong model, edit with a cheaper one. The split saves cost. It does not always raise quality, so lane A holds only edits that need no plan. |
| RouteLLM (LMSYS, 2024) | A trained router sent each query to a strong or a weak model. Cost fell by more than 2 times on general benchmarks with no loss in quality. Coding tasks were not in the test set. | Routing works, but its savings on code must be measured on our own items. Keep the lane A rule strict, and measure it (accuracy test, paste test). |
| Claude Code docs, subagents | Subagents can "Control costs by routing tasks to faster, lower-cost models like Haiku". The main agent can pass a `model` for each subagent call. | One prompt is enough. The main agent reads the lanes and starts the cheaper subagent itself. Drew pastes once. |
| Anthropic, long context tips; Liu and others, Lost in the Middle (TACL 2024) | Queries at the end of a long prompt raised response quality by up to 30% in Anthropic's tests. Models use the start and the end of a long context better than the middle. | Rules stay at the top of the prompt. The ordered task list goes at the end. |

## Definitions

Each item is one numbered badge. Its note is the badge's `instruction` in `feedback.json`. The capture's general note is context only. The job never labels it.

Severity (a Jev Score, four levels). The levels follow Drew's own marks in the label review (Drew, 2026-10-24). Job version 3.

| Level | Name | Meaning |
| --- | --- | --- |
| 3 | blocker | A feature fails, does not work, or shows wrong data. |
| 2 | bug | The screen says something false or misleading, but the feature works. |
| 1 | polish | The change improves the look, the layout, or the wording, including cut-off text, uneven sizes, or inconsistent terms. Nothing is false or broken. |
| 0 | nit | A small taste preference. The screen works and reads well without it. |

Size (a Jev Score, four levels):

| Level | Name | Meaning |
| --- | --- | --- |
| 0 | one line | One value, word, or sentence in one place. |
| 1 | one file | A few related edits in one place, for example one component or one page. |
| 2 | several files | Edits in a few files or places. |
| 3 | many files | A change across the app, the repository, or every page ("everywhere", "all templates"). |

Kind (a Jev Choice, two options):

| Option | Meaning |
| --- | --- |
| `exact` | Every change in the note is exact: new text given in full, a named color, a size or spacing number, or one named element to remove. A developer makes no design or product choice. |
| `judgment` | At least one change needs a choice: make something clearer, better, or consistent, pick a layout, research, explain, or answer a question. A note that names no concrete change ("fix this", "look at this") is `judgment` too (my call, from the builder check). So is a note that mixes an exact value with a vague ask, such as a number for the text but only "larger" for the box (Drew, 2026-10-24, job version 3). |

Lanes (decided by code from the three answers):

| Lane | Rule |
| --- | --- |
| A, exact edits | `exact` probability 0.9 or more, size one line or one file, and severity polish or nit. Drew chose "exact and small only" first, then "polish and nit only" after the accuracy test (both 2026-10-24). |
| B, needs judgment | Every other rated item. |
| not rated | An answer is missing or out of range, the job failed or did not run for the capture, or the capture was still running at round end. Listed at the end of lane B. |
| ask first | The note is empty. Code decides this with no Jev question. |

The accuracy test set the threshold at 0.9 for `jev-1.14.0` (see Accuracy test results). The start value was 0.8.

## The Jev job

`PromptLanesJob` (id `promptLanes`, version 4) runs on the base's trigger, after the note panel ends and OCR is stored. It sends one request per capture when at least one item has a note and `lanesOrder` or `lanesSplit` is shadow or on after the cap. A capture whose notes are all empty sends nothing. With both sub-flags off, the gate (`JevGate.runs`) does not plan the job, so nothing is sent or recorded. The job guards itself too: it returns nothing and sends nothing. Version 3 came from the accuracy test. Version 4 (2026-10-25, #94) adds the sub-flags and leaves the questions as they were, so a record from version 3 is no longer used.

The request holds reviewer text only, even with `jevSendImages` or `jevSendScreenText` on. `requires` is empty. Severity, size, and kind come from the words of the note. A picture adds little to them, and text keeps the data that leaves the Mac small. My call, as the note coach did.

State (named JSON fields), the same shape as the note coach:

- `general_note`: the capture's general note, exact, or empty.
- `items`: one entry per item with a note, in badge order. Each entry has `item` (code text, for example "1.2") and `note` (the note, exact).

Never in the state: window titles, OCR text, app names, file names, paths, or images.

Questions, three per item with a note. Ids start with the item id, as the base requires. Each question names its item's place in the state (`items[i].note`), so Jev judges one note per question.

| Id | Type | Instructions | Levels or options |
| --- | --- | --- | --- |
| `K.N.severity` | Score, 4 levels | How serious is the problem that `items[i].note` describes? `general_note` is context from the same reviewer. | The four severity levels above, nit first, each with a made-up example. |
| `K.N.size` | Score, 4 levels | How much code will a developer likely change to do what `items[i].note` asks? | The four size levels above, one line first, each with a made-up example. |
| `K.N.kind` | Choice | Can a developer do every change in `items[i].note` with no design or product choice? | `exact` and `judgment`, as defined above. |

The code rule (pure code, in the job file, next to the questions):

- Severity is the most likely level. A tie takes the higher level, so a doubt never lowers severity.
- Size is the most likely level. A tie takes the larger size.
- Lane A needs `exact` at 0.9 or more, size level 0 or 1, and severity level 0 or 1 (nit or polish).
- Any other rated item is lane B.
- A missing answer, a Score without four levels, or a number that is not finite or is outside 0 to 1 makes the item not rated.

The job returns:

- No refined lines and no files. The capture prompt has no use for a lane. The plan exists only for the whole round (next section).
- A summary for jev.json, one field per item, keyed by the item id: `lane` (`A`, `B`, `askFirst`, or `notRated`), `severity` (0 to 3), and `size` (0 to 3). Severity and size are absent when the item is not rated or has no note. Code-only values, so jev.json holds no note text.
- A review section for `jev-review/promptLanes.md`: one line per item with its lane, its severity and size names with their probabilities, the `exact` probability, and the note on one line. For Drew only.

The job never sees its flag state, as the base requires. Shadow and on run the same questions and write the same summary.

## The round plan

The base runs each job on one capture and never lets a job read the other captures' answers. Order and lanes need every capture's labels, so they are built at round end, in code, from jev.json.

`PromptLanesPlan` (a new file in `Packages/JevKit/Sources/JevKit/Jobs/`) reads the round from `feedback.json` and the summaries from `jev.json`. It returns a `PromptLanes` value, a new FeedbackKit type that `PromptBuilder` renders. FeedbackKit cannot import JevKit, so the type holds only item ids and level names.

Rules:

1. Every item of the round appears exactly once: in lane A, in lane B, or on the Ask first line.
2. A capture's labels count only from a `promptLanes` record with status `done` and the current `PromptLanesJob.version` (1 at first). A question change raises the version, so old labels never mix with new ones. Shadow and on records both count, so a flag change in the middle of a round keeps the earlier labels. My call.
3. The item set and the empty notes come from `feedback.json`, with `FeedbackItems.split`, as the note coach does. So an empty note goes to Ask first even when its capture's record failed.
4. A capture with no such record, a failed record, or a capture still running at round end puts each of its items with a note in lane B as not rated.
5. Order in each lane: severity, highest first. Inside one severity, capture order, then badge order, so the items of one screen stay together (Drew, 2026-10-24: "Severity, then capture"). Not rated items come last in lane B, in capture order.
6. Weights stay in code. Size does not change the order. It only gates lane A.
7. The plan reads no network and sends nothing. It is a pure function of the two files, so a test can give it fixed files.

The gate: `PromptLanesPlan.forPrompt(round:file:flags:)` returns nil unless `jevBase` is on, `promptLanes` is on, and at least one of `lanesOrder` and `lanesSplit` is on. The app passes `Flags.effectiveState`, so a sub-flag counts at the lower of its own state and the state of `promptLanes`. The sub-flags pick the layout (see Sub-flags). The gate also returns nil when no item of the round is rated, so a round where every request failed gets no lanes section. Shadow never changes a prompt, and a sub-flag in shadow adds nothing to it.

The base's own gate stays as it is, except that a job with options counts only when one of them is on after the cap (#96). With `promptLanes` on and a lanes sub-flag on, the base adds its refined pointer lines to the copied prompts and waits its 500 ms at round end, as it does for every feature in the on state. The round-end wait is needed: it lets the last capture's labels reach jev.json. This job writes no refined lines, so `-refined.md` and `refined.md` appear only when another feature writes lines, or when this job fails ("Not refined: promptLanes (timeout)"). Both pointers say "if it exists", so the agent loses nothing. My call, from the builder check: a lanes-only gate would change four base files for a small gain.

## The round prompt in the on state

The plan goes at the end of the copied round prompt, after Context and before the closing tag (Drew, 2026-10-24: "Copied prompt"). The rules stay at the top. The ordered task list sits at the end, where the research says a model reads best. Each line holds the item id and its labels only. The notes stay in `manifest.md`, as today (Drew, 2026-10-24: "Id and labels only").

Example for a made-up round of 8 items:

```text
Order and lanes:
These labels come from an automated model. The reviewer's words win. Each item appears once.
Lane A, exact edits. After your plan table, hand these items to a subagent on a fast, low-cost model as one batch, with each item's instruction from manifest.md and its file from your plan table. In Claude Code, set the subagent's model to haiku. With fewer than three items, do them yourself. Check each edit before you start lane B.
- 3.2 polish, one line
- 9.6 polish, one line
- 2.2 nit, one file
Lane B, needs judgment. Plan these yourself, in this order:
- 4.1 bug, several files
- 5.2 bug, one file
- 2.1 polish, one file
- 7.1 not rated
Ask first: 4.5 (no instruction).
Start with lane A. Then work lane B from the top.
```

- An empty lane prints "Lane A, exact edits: none." or "Lane B, needs judgment: none." and no instruction sentence.
- The Ask first line shows only when an item has no note. It repeats the Authority line "Items with no instruction", so the task list is complete on its own.
- The model name "haiku" is my call. Claude Code's docs give Haiku as the low-cost example. Other agents ignore the sentence.
- "With fewer than three items, do them yourself" is my call. A subagent costs a context of its own, and one small edit does not pay for it.
- The Work method, Verify, and Report sections stay as they are. Their plan table and per-item report still cover every item.
- If another feature also adds a section to the end of the round prompt, the lanes section goes last, so the task list stays at the end.

Which copies get the section:

| Copy | Section | Wait |
| --- | --- | --- |
| Copy Prompt and End Round (Option+Shift+R) | yes | the base's 500 ms settle, then the plan reads jev.json |
| Copy Round Prompt in Recent | yes, when jev.json has labels | none |
| Capture prompt, Copy Last Capture Prompt | no | none |
| Copy N Selected | no | none |
| `prompt.md` on disk | never | n/a |

## Sub-flags (#94)

Drew asked for sub-flags on 2026-10-25. The design is `docs/superpowers/specs/2026-10-25-jev-sub-flags-design.md`.

- `lanesOrder` gates the severity order, worst first.
- `lanesSplit` gates the lane A and lane B split for a fast and a strong model.
- Both are dev-only, start off in both channels, and allow off, shadow, and on. Each runs at the lower of its own state and the state of `promptLanes`. Alone, a sub-flag runs nothing.
- One request per capture gives the ratings for both parts. So the job sends one request when either sub-flag is shadow or on, and none when both are off.
- A sub-flag in shadow writes the same `jev.json` and `jev-review/promptLanes.md`. It never changes a prompt.

The copied round prompt gets the section for the sub-flags that are on. The title says what the section holds:

| `lanesOrder` | `lanesSplit` | Section | What it holds |
| --- | --- | --- | --- |
| on | on | Order and lanes | The section in the example above: lane A and lane B, each worst first. |
| on | off | Order | One list of every rated item, worst first (severity, then capture, then badge). Not rated items come last. No lanes, no subagent sentence, and no start line. |
| off | on | Lanes | Lane A and lane B, each in capture order (capture, then badge). Not rated items stay in lane B, in that order. The text makes no claim about order. |
| off | off | none | The prompt is unchanged. |

Example of the Order section for the same made-up round:

```text
Order:
These labels come from an automated model. The reviewer's words win. Each item appears once.
Plan and work these items in this order, worst first:
- 4.1 bug, several files
- 5.2 bug, one file
- 2.1 polish, one file
- 3.2 polish, one line
- 9.6 polish, one line
- 2.2 nit, one file
- 7.1 not rated
Ask first: 4.5 (no instruction).
```

- Every section shows the same entry lines (item id, severity name, size name) and the same Ask first line. Each item appears once.
- The Lanes section differs from the example above in two lines. Lane B reads "Lane B, needs judgment. Plan these yourself:" with no "in this order". The last line reads "Start with lane A. Then work lane B." with no "from the top".
- `PromptLanes` carries the layout (`orderAndLanes`, `order`, or `lanes`). In the `order` layout the one list is `laneB` and `laneA` is empty.
- The app reads the sub-flags with `Flags.effectiveState`, and the runner applies the same cap before it gives the job its option modes.

## Behavior per flag state

The job runs only when `jevBase` is on, `promptLanes` is shadow or on, and `lanesOrder` or `lanesSplit` is shadow or on after the cap. `jevBase` off means no request, whatever `promptLanes` says.

| `promptLanes` | Requests | `jev.json` | Review file | Copied round prompt |
| --- | --- | --- | --- | --- |
| off | none | no promptLanes entry | none | unchanged, byte for byte |
| shadow or on, both sub-flags off | none | no promptLanes entry (the gate plans no job) | none | unchanged |
| shadow | one per capture with a filled note | the runner's record with every answer, and the summary | `jev-review/promptLanes.md` | unchanged |
| on | same as shadow | same as shadow | same as shadow | the section for the sub-flags that are on, at the end |

Failure: a timeout, an error, no key, or no network ends the job. The runner records it as not refined. The plan puts that capture's items in lane B as not rated. Nextshot never waits beyond the base's 500 ms at round end.

## Files and hook points

The base (#36) registered `PromptLanesJob()` and wrote its stub (commit `2539f9c`). No upstream file changes.

| File | Change |
| --- | --- |
| `Packages/JevKit/Sources/JevKit/Jobs/PromptLanesJob.swift` | Fill in: request, rule, summary, review. |
| `Packages/JevKit/Sources/JevKit/Jobs/PromptLanesPlan.swift` | New: jev.json and the round to `PromptLanes`, and the flag gate. |
| `Packages/FeedbackKit/Sources/FeedbackKit/PromptLanes.swift` | New: the `PromptLanes` type and its prompt lines. |
| `Packages/FeedbackKit/Sources/FeedbackKit/PromptBuilder.swift` | Shared: `render` gets `lanes: PromptLanes? = nil`. With nil, the output is byte-identical to today. With a value, its lines go after Context. |
| `App/Feedback/FeedbackJev.swift` | Shared fork file: one method that reads jev.json and returns the plan, or nil. |
| `App/Feedback/FeedbackController.swift` | Shared fork file: the two round prompt copies pass the plan. |
| `AGENTS.md`, `docs/agents/bundle-guide.md` | One bullet each for the new section. |
| Tests | New: `PromptLanesJobTests.swift`, `PromptLanesPlanTests.swift` (JevKit), `PromptLanesTests.swift` (FeedbackKit). |
| `scripts/prompt-lanes-eval.sh`, `PromptLanesAccuracyTests.swift` | New: the accuracy test, as the note coach's. |

The base test `registryStubsSendNothing` runs only stub jobs (`version == 0`). The filled job has version 1, so that test needs no edit.

## Tests

1. Flag off: with `promptLanes` off and `jevBase` on, a stub transport records zero requests, and `PromptLanesPlan.forPrompt` returns nil. The same with `jevBase` off and `promptLanes` on.
2. Shadow: the plan gate returns nil, so the copied prompt is unchanged. The runner records the answers and the summary, and no refined line.
3. Prompt unchanged: `PromptBuilder.render` with `lanes: nil` matches today's output byte for byte. The existing prompt tests prove it.
4. Request content: one request per capture. The state holds each note and the general note exactly, as reviewer text. It never holds a window title, OCR text, a path, or an image, even with both consent flags on. A capture with only empty notes sends nothing.
5. Rule: fixed answer sets map to each lane, including values at each threshold, ties, and answers that are missing or out of range.
6. Plan: every item appears exactly once. Order follows severity, then capture, then badge. Not rated items come last. A failed or missing record puts its items in lane B. An empty note goes to Ask first. A record of another job version counts as not rated.
7. Section text: the exact lines for a made-up round, an empty lane A, an empty lane B, and a round with no rated item (no section).
8. Failure: a transport error records the job as not refined, and the plan lists that capture's items as not rated.

9. Sub-flags (#94): the registry rules for `lanesOrder` and `lanesSplit` (parent, issue, dev-only, off by default, allowed states). The job with each sub-flag on, in shadow, and off: one request when either is shadow or on, none when both are off, and an empty output. The cap: a sub-flag under a parent in shadow runs in shadow, and a sub-flag alone runs nothing. The gate: the parent on with both sub-flags off plans no job, and a prompt points to refined files only with a sub-flag on. The plan and the section text for each of the four combinations: both on is today's section, order only is one list worst first, split only is two lanes in capture order, and neither gives no section. Every item appears once in every layout.

Test fixtures use made-up notes only. The repository is public.

## Accuracy test (before the on state)

Drew approved this on 2026-10-24: send note text to Jev, text only, with Nextshot's key ("Yes, text only"). No images, no window titles, no screen text. TypeSafe keeps each request and does not train on it.

- Set: the about 66 real notes and about 40 made-up notes, written in Drew's dictation style, with a spread of severities, sizes, and kinds.
- Labels: this session labels each real note for kind, size, and severity by reading it. Drew confirms the lane A labels and the bug and blocker labels, the two that change the prompt most.
- The labeled set and the results stay out of this public repository, in `build/jev-eval/` of the main checkout (git ignores `build/`). The spec records counts only.
- Harness: `scripts/prompt-lanes-eval.sh <set file>` runs the opt-in suite `PromptLanesAccuracyTests` with Nextshot's key. It writes `prompt-lanes-results.json` (labels and numbers, no note text) next to the set file. The test gives the job both sub-flags as on, as a trial with `feature promptLanes on` does.

Pass bars:

| Check | Bar | Why |
| --- | --- | --- |
| Lane A precision, real notes | at least 90% of real items in lane A are labeled exact and small | A wrong lane A gives judgment work to a weak model. |
| Blockers in lane A | 0 | A blocker always gets the strong model. |
| Lane A recall, real notes | at least 50% of real exact and small items reach lane A | Below this, the lane saves too little to be worth a subagent. |
| Bug recall, real notes | every real item labeled bug or blocker is rated bug or blocker | The few bugs must reach the top. |
| Vague notes in lane A, made-up and test notes | 0 | A note that names no change needs the reviewer, not a fast model. |

A failed bar changes the threshold or the question text, then the test runs again. A question change raises the job version. The final threshold goes into the job file with the date and the model.

When: the build and the PR use the start threshold 0.8 and include the harness. The accuracy run and Drew's label check come after the build and before the on step of the trial. They gate the on state, not the PR. My call, as the note coach did it (#62 before #63).

## Accuracy test results (2026-10-24)

Model `jev-1.14.0`. Each run sent 213 notes (72 real, 65 test, 76 made-up), text only. Each run took about 6 s and 118,000 to 131,000 input tokens (about half a cent), with no errors and no retries. Three runs in all.

| Step | Change | Answer key | Result |
| --- | --- | --- | --- |
| Run 1 | Start questions, threshold 0.8 | Claude's | 4 of 5 bars pass. Bug recall 6 of 7. Jev scored plain removals as judgment (exact about 0.2 to 0.5). Three question examples copied test notes. |
| Run 2 | Removal examples in the `exact` option. No example copies a test note. Job version 2. | Claude's | 5 of 5 bars pass: precision 10 of 11, recall 10 of 18, bug recall 7 of 7. |
| Drew's review | Drew checked 30 labels on a local review page. | Drew's | 11 labels changed: 6 lane A items to lane B, 3 bugs to blockers, 2 bugs to polish. Jev already matched Drew on 5 of the 6 lane changes. Run 2 against Drew's key: precision 9 of 11 (82%), because two notes mix an exact value with a vague ask. |
| Run 3 | Severity levels follow Drew's line. A mixed exact and vague note is judgment. Job version 3. | Drew's | The mixed notes left lane A. One made-up wrong-number fix was rated bug and reached lane A, so the blocker bar failed. |
| Final rule | Lane A: `exact` 0.9 or more, polish or nit only. Recomputed from the run 3 answers, with no new send. | Drew's | 5 of 5 bars pass (below). |

| Check | Bar | Final result |
| --- | --- | --- |
| Lane A precision, real notes | at least 90% | 7 of 7 (100%) |
| Blockers in lane A | 0 | 0 |
| Lane A recall, real notes | at least 50% | 7 of 12 (58%) |
| Bug recall, real notes | all | 5 of 5 |
| Vague notes in lane A | 0 | 0 of 65 |

All three sets together: 16 of 16 lane A items are right.

Limits:

- The rule and the threshold were set on the same 72 real notes they are graded on, and only 12 of them belong in lane A. The trial (#74) and the kill rule are the real check.
- Jev still rates some polish items as bugs. In run 3, 5 of the 9 real items that Jev called a bug or blocker are bugs or blockers in Drew's key. This affects only the order inside a lane.
- The labeled sets, the review page, and the results stay in the main checkout's git-ignored `build/jev-eval/`.

## Rollout and kill rule

1. Build with `promptLanes` off in both channels. A test proves the off state changes nothing.
2. Run the accuracy test. Set the threshold from it.
3. Trial on the orchestration session's combined build. Shadow first: `scripts/nextshot-flags.sh feature promptLanes shadow` sets `promptLanes` and both sub-flags. Run one real round of at least 6 items, then Drew reads `jev-review/promptLanes.md`.
4. On: `scripts/nextshot-flags.sh feature promptLanes on`, then the same kind of round, copied with Option+Shift+R. The copied prompt must hold the "Order and lanes" section, and every item once. To judge one part, Drew runs `set promptLanes on` and sets one sub-flag to on, for example `set lanesOrder on`. The prompt then holds the "Order" or the "Lanes" section.
5. Paste test: the copied prompt into Claude Code (a strong main model) in a scratch clone. Pass: the agent writes the plan table, starts one subagent with a smaller model for lane A, and plans lane B itself. Evidence: the transcript's subagent call and its model. On 2026-10-21 an agent skipped a softer rule, so file tests alone do not prove this.
6. On for daily use only when the accuracy test and the paste test pass, and Drew agrees. The release default stays off. Jev features are dev-only.
7. Kill rule: if Drew finds a wrong lane A item twice in real rounds, set the flag back to shadow and retune. If shadow puts fewer than 15% of real items in lane A over 5 real rounds, drop the lane split and keep the order only: set `lanesSplit` off and `lanesOrder` on.

Metrics, from jev.json and the copied prompts: the share of items in each lane per round, the share not rated, Jev time per capture, and Drew's verdict on lane A edits.

## Open questions

None open. Drew answered every question that changes what gets built on 2026-10-24.

## Decisions log

- 2026-10-24: the order and the lanes go at the end of the copied round prompt, not only in refined.md (Drew).
- 2026-10-24: one prompt. The agent hands lane A to a subagent on a fast, low-cost model. No second prompt, no new keystroke (Drew).
- 2026-10-24: order inside a lane is severity, then capture, then badge (Drew).
- 2026-10-24: lane A takes only exact and small items: `exact` at 0.8 or more, size one line or one file, never a blocker (Drew).
- 2026-10-24: the accuracy test sends note text to Jev, text only, with Nextshot's key (Drew).
- 2026-10-24: each lane line shows the item id and its labels. Notes stay in manifest.md (Drew).
- 2026-10-24: the job sends reviewer text only, even with the consent flags on (my call).
- 2026-10-24: the job writes no refined lines. The plan is built at round end from jev.json summaries, because a job sees one capture (my call).
- 2026-10-24: shadow and on records both feed the plan, so a flag change in the middle of a round keeps the earlier labels (my call).
- 2026-10-24: the section names haiku for Claude Code, and says to do fewer than three lane A items without a subagent (my call).
- 2026-10-24: not rated items go last in lane B. Empty notes go on an Ask first line (my call).
- 2026-10-24 (builder check): the base's refined pointer and round-end wait stay as they are for this feature. No lanes-only gate (my call).
- 2026-10-24 (builder check): a note that names no concrete change is `judgment`, and the accuracy test checks that no vague note reaches lane A (my call).
- 2026-10-24 (builder check): the accuracy run gates the on state, not the PR. The plan uses the job's current version, not a fixed number (my call).
- 2026-10-24 (final review): the lane A sentence also hands over each item's file from the plan table, because the subagent has no image (my call).
- 2026-10-24 (accuracy test): one tuning run (job version 2) with removal examples and no copied test notes (Drew).
- 2026-10-24 (label review): Drew corrected 11 of Claude's 30 labels. His key replaces Claude's (Drew).
- 2026-10-24 (label review): severity levels follow Drew's line. Blocker: a feature fails or shows wrong data. Bug: the screen says something false. Polish includes cut-off text, uneven sizes, and inconsistent terms. A mixed exact and vague note is judgment. Job version 3 (Drew).
- 2026-10-25 (#94): `lanesOrder` and `lanesSplit` are sub-flags of `promptLanes` (Drew, in the sub-flags design). The section is named for the parts that are on: "Order and lanes", "Order", or "Lanes". Neither on gives no section (orchestration call).
- 2026-10-25 (#94): one request still gives the ratings for both parts, and the job sends none when both are off. Job version 4 (orchestration call).
- 2026-10-25 (#94): every section keeps the entry lines with severity and size names, so the sub-flags change only the order and the grouping (my call).
- 2026-10-25 (#94): with `lanesOrder` alone, not rated items come last. With `lanesSplit` alone, they stay in lane B in capture order (my call).
- 2026-10-24 (label review): lane A takes only polish and nit, with `exact` at 0.9 or more. This replaces "never a blocker" (Drew).

## Left to the builder

- Type and function names inside the new files.
- The exact question text and examples, within the definitions above. The accuracy test may change them.
- The final threshold, from the accuracy test.

## Sources

- Aider, [Separating code reasoning and editing](https://aider.chat/2024/09/26/architect.html) (2024) and [R1+Sonnet set SOTA on aider's polyglot benchmark](https://aider.chat/2025/01/24/r1-sonnet.html) (2025).
- LMSYS, [RouteLLM: An Open-Source Framework for Cost-Effective LLM Routing](https://lmsys.org/blog/2024-07-01-routellm/) (2024), and the paper [RouteLLM: Learning to Route LLMs with Preference Data](https://arxiv.org/abs/2406.18665).
- Anthropic, [Claude Code subagents](https://code.claude.com/docs/en/subagents), read 2026-10-24.
- Anthropic, [Long context prompting tips](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/long-context-tips).
- Liu and others, [Lost in the Middle: How Language Models Use Long Contexts](https://arxiv.org/abs/2307.03172) (TACL 2024).
- TypeSafe docs: [Score](https://docs.typesafe.ai/primitives/score), [Choice](https://docs.typesafe.ai/primitives/choice).
