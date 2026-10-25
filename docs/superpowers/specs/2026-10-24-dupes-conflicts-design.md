# Duplicates and conflicts in a feedback round: design (draft)

Date: 2026-10-24. Status: draft, interview done (Drew, 2026-10-24). Issue: [#39](https://github.com/spurs-planks-smithers/Capso/issues/39), part of [#34](https://github.com/spurs-planks-smithers/Capso/issues/34). Flag: `dupesConflicts` (off, shadow, on). Depends on the flag registry (#35, built) and the Jev base (#36). The base's job interface is commit `d1de328` on branch `claude/jev-base-38834c`.

Related docs: `docs/superpowers/specs/2026-10-24-jev-base-design.md` (the base: job interface, runner, refined files, consent flags), `docs/superpowers/specs/2026-10-24-jev-handoff-design.md` (the shared Jev design), `docs/superpowers/specs/2026-10-24-feature-flags-design.md`, and `docs/plans/2026-10-24-jev-image-ideas.md` (ideas 9 and 10).

## Intent

A large round repeats the same ask in more than one capture. Sometimes two notes ask for opposite changes to the same element. The agent then makes the same edit twice, or it picks one note and drops the other with no word to Drew.

This feature finds both cases in the background, after each capture is saved. Jev compares each new entry with the earlier entries of the round. In the on state, the refined files tell the agent three things: ask the user first about a conflict, make a repeated change once, and check the code where two asks may overlap. Drew's words stay exact. Every note stays in the bundle.

## What Drew's rounds show

A scan of the 9 rounds in `~/Library/Application Support/Nextshot` on 2026-10-24 found:

| Round | Captures | Items with a note | Pairs across captures | Pairs with the same app or window |
| --- | --- | --- | --- | --- |
| 2026-10-21-1236 (test, Preview) | 10 | 24 | 245 | 245 |
| 2026-10-22-1839 (real) | 4 | 18 | 115 | 20 |
| 2026-10-20-2159 (test) | 8 | 14 | 72 | 39 |
| 2026-10-21-1541 (real) | 6 | 14 | 71 | 38 |

- The pair count stays small. The largest round has 245 pairs. A text check per pair costs little (see Latency and cost).
- The app filter misses real overlaps. In round 2026-10-22-1839, item 3.2 asks for the Copy Session Prompt hotkey "in light gray text to the right" in the menu. Item 4.2 asks for the same hotkey "in light gray text, right-aligned" in the same menu. Capture 3 came from Claude and capture 4 from Microsoft Outlook. The Nshot menu and help box show over whatever app is in front, so the app name and the window title name the app under the menu, not the menu.
- The OCR text under both marks is empty or noise ("e, has", ""). A text-match filter on OCR would also miss this pair.
- Same kind of change, different element: in round 2026-10-21-1541, item 2.1 says "Similar to the previous page, the XBert opportunity here needs to be called out". Item 1.2 asks for the same kind of change on another page. This is not a duplicate. The agent must do both. The questions must keep this case apart from a duplicate.
- A general note can hold a whole-app ask. The note of capture 4 in round 2026-10-22-1839 asks to rename "session" to "round" everywhere.

## Goals, non-goals, and anti-goals

Goals:

- The agent makes each repeated change once and knows every place it was seen.
- The agent asks Drew before it edits either side of a conflict.
- Measured precision on Drew's own rounds before the flag goes to on.

Non-goals for the first build:

- Pairs across rounds. Copy N Selected (the selection prompt) gets nothing new, as in the base.
- Any change while Drew types a note. Checks start after a capture is saved.
- Writing or rewriting notes. Jev only labels pairs. Code writes every line the agent sees.

Anti-goals (a failure even if it works):

- A new keystroke, a wait, a spinner, or a pop-up.
- A changed or dropped note. Nothing leaves `manifest.md`, `feedback.json`, or the capture prompts.
- A line that makes the agent skip a change on a different element (the 1.2 and 2.1 case). No line ever says "skip".
- A capture image or screen text that leaves the Mac without its consent flag.
- Any request or any changed file with the flag off.

## Terms

| Term | Meaning |
| --- | --- |
| Entry | One numbered item with a note (K.N), or one general note of a capture (K.note). An item with no instruction is not an entry. |
| New entry | An entry of the capture whose job runs now. |
| Earlier entry | An entry of a capture with a lower index in the same round, or an entry before the new entry in its own capture (items by badge, then the general note). Captures of a resumed round count. |
| Pair | One new entry and one earlier entry. Each pair inside a capture runs once: 1.2 with 1.1, never 1.1 with 1.2. |
| Duplicate | Both entries ask for the same change to the same element. |
| Overlap | Jev cannot say that the pair is the same ask or a different ask, or one entry holds part of the other. |
| Conflict | Both entries ask for changes to the same element that cannot both be done. |

## How a check runs

### When

1. Drew finishes the note steps. Nextshot stores the capture and copies the capture prompt, as today.
2. The base runner starts the jobs when the notes are final and the screen text is stored. The runner decides this for every job, also for a note panel closed early.
3. This job builds the pairs of the new capture, sends its requests through `context.jev`, applies the decision rules, and returns its lines.
4. Each pair runs once, in the job of the capture that holds its later entry. A capture's job compares with captures of a lower index and with the earlier entries of its own capture, so a pair never comes up again, also after Resume Round. The job needs no earlier results.
5. Pairs inside one capture count too (Drew, 2026-10-24). In the trial, Drew put "bigger", "smaller", and "larger" on three badges of one capture. A dictated note can contradict an earlier badge of the same capture. Two entries of one capture always count as the same source for images.
6. One request can fail (timeout, offline, server). The job catches the error and keeps the answers of the other requests. It adds one capture line that names the entries it could not check. A failed request does not retry inside the job, except through the base's own retries.

### Which pairs go to Jev

- Every new entry pairs with every earlier entry of the round (Drew, 2026-10-24). This replaces the "same app or window title" filter of the handoff design for text checks. The evidence is the 3.2 and 4.2 pair above.
- Images go only to pairs whose two captures have the same app name or the same window title. Code compares the names on the Mac. A missing name on either side counts as not the same.
- An entry with no text is skipped.

### Data kinds and consent

The base gives every value a kind, and the client refuses a request with a kind that has no consent (base spec, "Typed content and consent").

| Data | Kind | Sent when |
| --- | --- | --- |
| Drew's notes (item instructions and general notes) | reviewer | always, with the job's flag at shadow or on |
| Screen text under a mark (OCR, at most 200 characters) and the app name | screen | `jevSendScreenText` is on |
| Item crops and whole captures | image | never (Drew, 2026-10-24, after the live eval). The image code stays for a later choice. |
| Window titles | screen | never: code uses them only on the Mac |

- `requires` is `[.screenText]` (job version 2). The runner skips the job with reason `consent` when `jevSendScreenText` is off. The live eval of 2026-10-24 (`docs/evals/2026-10-24-dupes-conflicts-eval.md`) showed why: with notes alone, duplicate precision was 0.53 and conflict precision 0.80, because notes cannot tell two elements apart when the words match. With screen text, both were 1.00.
- The job removes `.images` from the allowed kinds before it builds a request, so it sends no image even when `jevSendImages` is on for another feature.
- A K.note entry sends its note only. A general note has no mark, so it has no screen text under a mark. With images, it uses the whole capture.

### The Jev questions

- One request per new entry, at most 8 per capture. The base allows 16 HTTP attempts per capture, retries included, so half stay free for retries. A capture with more than 8 entries puts two or more entries in one request.
- The state stays small: `new`, an array with the new entry (or entries). Each entry has its `note` (reviewer text) and, with consent, its `screen_text` and `app` (screen text) and its `crop` (image).
- Each earlier entry gets two questions. The earlier note sits in the question's instructions object, next to the question text. This is the "Structured instructions" pattern of the TypeSafe Noul page, which checks a record against possible duplicates. TypeSafe notes that accuracy shifts as the state grows, so the state holds only the new entry.
- The base forbids screen text in instructions. So the earlier entries' screen text and crops go in the state, under `earlier_screen_text` and `earlier_crops`, keyed by a code-built key such as `e3_2` (from the numbers 3 and 2, never from screen text). The question names its key by path.
- When screen text is in the state, each question starts with `JevPrompting.screenTextNotice`.
- Images: at most 6 earlier crops per request, newest first. Other same-app pairs go text only.
- Question ids are `<new id>.vs.<earlier id>.sameAsk` and `<new id>.vs.<earlier id>.opposite`, for example `4.2.vs.3.2.sameAsk`. They start with the item id, as the base asks. The review script reads the pair from the id.

The two questions:

1. `sameAsk` (Score, three levels). "How do the review note in `new[0]` and the earlier review note relate as change requests?"
   - Level 0: "They ask for different changes, or for changes to different elements. This includes the same kind of change on a different element, page, or screen."
   - Level 1: "They overlap. Part of one ask is in the other, or they may be about the same element. A person should check."
   - Level 2: "They ask for the same change to the same element."
2. `opposite` (Noul). "Do the review note in `new[0]` and the earlier review note ask for changes to the same element that cannot both be done?" Criteria true: "for example, larger and smaller, remove it and rename it, or two different values for the same setting." Criteria false: "different elements, changes that can both be done, or one note adds detail to the other."

The TypeSafe entity alignment cookbook uses this shape: a three-level Score whose middle level goes to a person, so no threshold has to be fitted. The issue text said "a Noul per pair". The Score is my call. It gives the overlap level that Drew chose for the check line. Both questions ride in one request, so the request count stays the same.

### Decision rules

Code applies these rules. The thresholds live in the job file, next to the questions, as the base requires.

| Jev answers | Outcome |
| --- | --- |
| `opposite` 0.7 or more | Conflict, whatever `sameAsk` says. |
| `sameAsk` 1.5 or more | Duplicate. |
| `sameAsk` from 0.5 to less than 1.5 | Overlap. |
| `sameAsk` less than 0.5 | Different. Nothing shows. |

- The Score cut points (0.5 and 1.5) round to the nearest level, as in the cookbook. The level wording moves pairs between levels, not a tuned number.
- 0.7 is the TypeSafe starting point for a Noul yes. `opposite` from 0.3 to 0.7 stays in `jev.json` only.
- A conflict wins over a duplicate, because a false "same ask" would hide a real choice.

### Lines for each new entry

A job never reads another job's output, and it sees only its own capture's answers. So it cannot join pairs from earlier captures into groups. Each new entry gets its own lines instead:

- At most one duplicate line, in the round scope. It names every earlier entry that the new entry repeats, and the captures they come from.
- At most one overlap line, in the entry's own scope (the item, or the capture for a K.note). It names every earlier entry that may overlap.
- One conflict line per conflict pair, in the round scope.
- The base writer puts a capture's round lines at the top of its own refined file and at the top of `refined.md`. So a duplicate or a conflict needs no second line in the item's section.
- The writer cuts a label at 300 characters. A long list splits into several lines of at most 300 characters, so no entry is cut off.

A chain still shows. If 5.3 repeats 2.1, the job of capture 5 says so. If 7.2 repeats 2.1 and 5.3, the job of capture 7 names both.

## Output for each flag state

| State | Requests | `jev.json` | Refined files | Copied prompts | `prompt.md`, capture prompt files, `manifest.md` |
| --- | --- | --- | --- | --- | --- |
| off | none | nothing for this job | nothing for this job | as today | as today, byte for byte |
| shadow | yes | answers and timings (the runner writes them) | nothing for this job | as today | as today, byte for byte |
| on | yes | answers and timings | this job's lines in `refined.md` and `<capture>-refined.md` | the base's pointer lines | as today, byte for byte |

- The base writes `jev.json`. It holds answers, timings, and the job's summary, never notes, screen text, or images.
- The summary (shadow and on) holds code-only facts: `flagged`, one `{"pair": "4.2.vs.3.2", "outcome": "duplicate"}` per pair that is not different, and `notChecked`, one `{"entry": "4.3", "reason": "timeout"}` per entry whose request failed. The review script reads it, so it needs none of the job's thresholds.
- Every id, key, question, and label is `JevCodeText`: literals and numbers only (base change of 2026-10-24). Drew's notes go out only as reviewer text, and screen text only as screen text. The compiler enforces this.
- In on, the base adds one pointer line to each copied prompt, when `jevBase` is on and at least one feature is on (base spec, "Prompt pointer lines"). This feature adds no prompt text of its own.
- Every Jev flag needs `jevBase` on, and every Jev flag is dev-only (base decisions, 2026-10-24).

## What the agent sees

These examples use the real 3.2 and 4.2 pair, rated as an overlap, and a made-up conflict and duplicate. Lines hold ids and code words only: no screen text, no file names, and no quoted notes. The agent reads each note in `manifest.md`. Its capture prompt names that file.

The round section at the top of `refined.md` (on only) holds the conflicts and the duplicates. Drew chose this place on 2026-10-24. The round prompt points to `refined.md`, and the agent reads it before its plan table:

```text
Round:
- Same ask: 4.3 repeats 1.4 (captures 1 and 4). An earlier paste may have made this change. Check the code, and make the change once. Each note is in manifest.md.
- Ask first: 4.5 and 2.1 ask for opposite changes to the same element. Read both in manifest.md. Ask the user which one wins before you edit either. 4.5 is newer.
```

The refined file of capture 4 (`<stem>-refined.md`) starts with the same two round lines, because the writer puts each capture's round lines at the top of its own file. A single capture paste reads only this file. The section of capture 4 then holds the overlap line, in that file and in `refined.md`:

```text
Item 4.2:
- 4.2 may overlap with 3.2. Read 3.2 in manifest.md. An earlier paste may have done part of it. Check the code before you edit twice.
```

- Every line names its own entry first, so it reads the same in the round section, in a capture section, and alone.
- K.note entries use the capture scope. A line names a note as "the general note of capture 4", for example "The general note of capture 4 may overlap with 2.1."
- Overlaps show only in the capture section. A round line for each overlap would add noise.
- When a request fails, a capture line says "Not checked for repeats: 4.2 and 4.3 (timeout)."
- The base writes "Not refined: duplicates and conflicts (timeout)" when the whole job fails.

## What the base provides

The base job interface (commit `d1de328`) covers every need of this feature:

| Need | Base part |
| --- | --- |
| Every earlier capture, with notes, marks, and screen text | `JevJobContext.round`, read from `feedback.json` when the job starts |
| Item ids (K.N) | `FeedbackItems.split(capture)`, public in the base |
| Requests with many questions, in parallel, inside the deadline | `context.jev` (`JevAsker`), with caps of 16 HTTP attempts per capture (retries included) and 4 at the same time |
| Code-only facts for the review script | `JevJobOutput.summary`, written to `jev.json` in shadow and on |
| Crops sized for Jev | `context.images.image(of:region:)`. The job computes each item's region with the `PreviewCrop` rules. |
| Consent for screen text and images | `context.allowed`, and the client's kind check |
| Lines for the round and for each item | `JevRefinedLine` with scope `.round`, `.capture`, or `.item(badge:)` |
| Answers recorded in `jev.json` | the runner, for every request |
| Pointer lines in the copied prompts | `PromptBuilder` with `refined: true` |
| No request with `jevBase` off | the base's guard test |

This feature edits only `Packages/JevKit/Sources/JevKit/Jobs/DupesConflictsJob.swift` and adds its own test file, as the base requires. It adds the review script under `scripts/`.

## Sub-flags (Drew, 2026-10-25)

Every Jev feature gets sub-flags, each off by default and dev-only (`docs/superpowers/specs/2026-10-25-jev-sub-flags-design.md`, #94). A sub-flag runs at the lower of its own state and its parent's. The runner applies that cap and gives the job `context.optionModes`.

| Sub-flag | Question it needs | Shadow | On |
| --- | --- | --- | --- |
| `dupesMerge` | `sameAsk` | summary in `jev.json` only | "Same ask" round lines and "may overlap" item lines |
| `dupesConflict` | `opposite` | summary in `jev.json` only | "Ask first" round lines |

- The job declares `options = [.dupesMerge, .dupesConflict]` and reads each part's capped mode.
- A part that is off asks no question and writes nothing. With both parts off, the job sends no request.
- The guard (my call): with `dupesMerge` not off and `dupesConflict` off, the job still asks `opposite` in the same request. A pair at 0.7 or more then gets no "Same ask" line and no conflict line. This keeps the rule that a conflict wins over a duplicate, so the merge never tells the agent to make one change for two opposite asks. It adds no request and about 40 tokens per pair.
- The summary lists only the outcomes of parts that are not off.
- The job version goes to 3, so the review script never mixes these answers with version 2 answers.
- Trial steps change: `scripts/nextshot-flags.sh feature dupesConflicts on` sets the parent and both sub-flags, then `set dupesConflict off` (for example) turns one part off.

## Latency and cost

- Requests per capture: one per new entry, at most 8. A capture with 4 items and a note sends 5 requests, 4 at a time.
- Time: Jev answered six questions in 0.22 s on 2026-10-24. A request with 60 questions (30 earlier entries) is larger. The 2 s budget per capture is shared with the other jobs of the capture. The builder measures the time on a real round in shadow.
- Cost, notes only: about 240 input tokens per pair. A 20-capture round with 4 entries per capture has about 3,000 pairs, so about 0.7M tokens, or about $0.03 at $0.042 per million input tokens. Output tokens are free. The base's guard of 1,000 requests per day is far above one round's need (about 80 requests).
- Screen text and images raise the cost. Images go only to same-app pairs. The builder measures the tokens per crop.
- Nothing waits on this job. The capture prompt is copied before it starts. Round end waits at most 500 ms (the base's rule).

## Tests

This is Drew's personal fork, so tests cover the business logic only. The base's tests cover the flag guard, the consent check, and the writer.

- Entries: items with a note and general notes become entries. An item with no instruction is skipped.
- Pairs: only with captures of a lower index. Images only for the same app or window. A missing name is not a match.
- Consent: with only reviewer text allowed, the request holds no screen kind and no image kind.
- Requests: the state and the questions for a fixed round match a stored copy. Each question id parses back to one pair.
- Failure: one failed request leaves the other answers in use and adds the "Not checked" line.
- Decision rules: the edges at 0.49, 0.5, 1.49, 1.5, and 0.7. A conflict wins over a duplicate.
- Lines: a duplicate that names two earlier entries, an overlap, a conflict, a K.note entry, and an entry with nothing to say. The lines for a fixed round match stored copies.
- Summary: `flagged` lists each pair that is not different, in entry order, and `notChecked` lists each failed entry with its reason.
- Code text: the job's copy of the screen-text notice matches the base's, and each failure reason has a name.
- Long lists: 48 earlier entries split into lines of at most 300 characters, and every entry is named.
- In the real runner with a stubbed transport: with `dupesConflicts` or `jevBase` off, no request goes out, no key is read, and no Jev file is written. Shadow records both answers and writes no refined file. On shows a duplicate's round line once in `refined.md` and once in the capture's file. By default the request body holds Drew's note and no app name, window title, or screen text.

## Shadow review and the bar for on

- A review script (Drew, 2026-10-24): `scripts/nextshot-jev-review.sh dupes`. It reads `jev.json` and `feedback.json` in each round folder. It takes each pair's outcome from the job's summary. It lists each flagged pair (duplicate, overlap, or conflict) that has no label yet. It also counts the entries that were not checked.
- For each pair it prints both ids, both notes, and Jev's call. Drew presses y (right), n (wrong), or s (skip).
- Labels go to `jev-labels.json` in the round folder, next to `jev.json`. A deleted round takes its labels with it.
- At the end, the script prints the count and the share right for duplicates, overlaps, and conflicts, across all rounds.
- The bar (Drew, 2026-10-24): at least 10 labeled duplicate calls with at most 1 wrong, and the same for conflict calls. Both checks must pass before the flag moves to on. Overlap labels show in the report, but they are not part of the bar. A wrong overlap line costs the agent one look at the code.
- Few rounds may hold a true conflict. If conflicts stay under 10 labels after about two weeks of rounds, Drew decides whether duplicates go on alone. That would need a second flag.
- Shadow sends Drew's notes to TypeSafe. Shadow changes no prompt. It does not keep data local.

## Research

Light research on 2026-10-24 (four searches). The findings that shape this design:

- Duplicates are common in crowdtesting, and screenshots help. SETU found 82% of crowdtest reports were duplicates. Screenshot plus text features beat text alone. Later work notes that screenshot similarity helps less when many screens look alike, which is the case for one app's menus. So text checks run on every pair, and images are an extra for same-app pairs.
- Group, then summarize. CTRAS (ICSE 2019) joins duplicate crowdtest reports into groups and writes one summary per group. The duplicate line names every earlier entry it repeats, which is the same idea at the size of one entry.
- Two stages are the standard pattern. Cupid (2023) puts ChatGPT behind a classic retrieval step, and it still reaches only 0.60 to 0.65 recall at 10. A cheap first step plus a model judgment is normal. Here the round is small, so the first step only drops entries with no text.
- Trackers suggest. A person decides. Find Duplicates for Jira shows a short list of possible duplicates while a user writes a new issue. This supports a check line for an unsure pair instead of a merge.
- A wrong merge costs more than a missed one. The TypeSafe entity alignment cookbook adds a middle Score level that goes to a person for this reason.
- Conflicts are harder than duplicates. In requirements engineering, conflict detection scored lower than other tasks with natural language inference (Fazelnia and others, RE 2024). ALICE (TU Berlin) found 60% of contradictions with formal logic plus an LLM and beat an LLM alone. So conflicts use a high bar (0.7), go to Ask first and never to an automatic choice, and the review measures precision before on.

## Decisions log

- 2026-10-24: every earlier entry of the round pairs with each new entry. Images go only to same-app or same-window pairs. This replaces the app filter of the handoff design for text checks (Drew).
- 2026-10-24: an overlap gets a check line. Only a clear duplicate gets a "make the change once" line (Drew).
- 2026-10-24: the capture refined file names repeats and conflicts with earlier captures, for single capture pastes (Drew).
- 2026-10-24: shadow results are reviewed with a script that saves y or n labels (Drew).
- 2026-10-24: the bar for on is 10 labeled calls with at most 1 wrong, for duplicates and conflicts each (Drew).
- 2026-10-24: general notes join the pairs as K.note entries (Drew).
- 2026-10-24: items inside one capture are compared too, after the trial showed three asks about one element in one capture. This replaces the earlier call "no pairs inside one capture" (Drew).
- 2026-10-24: after the live eval (60 labeled cases, 726 requests), the check sends notes and screen text, and no images. Notes alone failed the bar. Notes and screen text met it with no wrong duplicate or conflict call. Images raised recall a little at about 5.7 times the tokens (Drew).
- 2026-10-24: Ask first and Same ask lines go in the round section at the top of `refined.md`, as the approved base spec says. The handoff design said "at the top of the round prompt". The base spec wins (Drew).

My calls (Drew can change any of them):

- A three-level Score plus a Noul per pair, in place of two Nouls.
- One request per new entry. The new entry sits in the state, and each earlier note sits in its own questions' instructions.
- At most 6 earlier crops per request.
- No capture note as context for an item. A general note is an entry of its own.
- The cut points 0.5, 1.5, and 0.7, and a conflict wins over a duplicate.
- Lines per new entry in place of groups across captures. A job cannot read earlier captures' answers.
- Overlaps in the entry's section only. Conflicts and duplicates in the round scope only, which the writer shows at the top of both files.
- A list longer than 300 characters splits into several lines.
- Lines hold ids only. The agent reads each note in `manifest.md`. This keeps screen text and file names out of the labels.
- No pairs across rounds.
- The "earlier paste" sentence shows only when a line names an entry from an earlier capture. Entries of one capture go out in one paste.
- A failed request is named in a "Not checked" line and does not retry inside the job.
- The duplicate line says "check the code, and make the change once". It never says "skip".

## Open questions

None for Drew now. If the base changes its job interface in a way that changes what Drew sees, this session asks him again.

## Left to the builder

- The exact question wording, after a check on three real rounds in shadow.
- How two entries share a request when a capture passes the request cap.
- The crop region for an item: the `PreviewCrop` rules or the crop from #38, whichever is public first.
- The review script language. It uses only tools that ship with macOS and Xcode, and it makes no network request.

## Sources

- TypeSafe: [Knowledge graph entity alignment](https://docs.typesafe.ai/cookbooks/entity_alignment), [Noul](https://docs.typesafe.ai/primitives/noul), [Images](https://docs.typesafe.ai/images).
- Wang and others, [SETU](https://www.eecs.yorku.ca/~wangsong/papers/ist19-1.pdf) (IST 2019), and [Cutting Away the Confusion From Crowdtesting](https://deepai.org/publication/cutting-away-the-confusion-from-crowdtesting) (the earlier TSDetector work).
- Hao and others, [CTRAS: Crowdsourced Test Report Aggregation and Summarization](https://2019.icse-conferences.org/details/icse-2019-Technical-Papers/5/CTRAS-Crowdsourced-Test-Report-Aggregation-and-Summarization) (ICSE 2019).
- Zhang and others, [Cupid: Leveraging ChatGPT for More Accurate Duplicate Bug Report Detection](https://arxiv.org/abs/2308.10022) (2023).
- [Find Duplicates for Jira: Create Issue, Instant Duplicates List](https://activitytimeline.atlassian.net/wiki/spaces/FDD/pages/47029912/Create+Issue+-+Instant+Duplicates+List).
- Fazelnia and others, [Lessons from the Use of Natural Language Inference (NLI) in Requirements Engineering Tasks](https://arxiv.org/abs/2405.05135) (RE 2024).
- Gärtner and Göhlich, [Automated requirement contradiction detection through formal logic and LLMs](https://depositonce.tu-berlin.de/items/235b411d-8c87-486f-bdb4-15cadc989427) (TU Berlin, 2024).
