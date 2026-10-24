# One-breath notes, shadow test: design (draft)

Date: 2026-10-24. Status: draft for Drew's review. Issue: #40 (parent #34). Flag: `oneBreath` (off or shadow). Depends on the Jev base (#36) and the flag registry (#35).

Terms used in this document:

| Term | Meaning |
| --- | --- |
| Answer | The text of one note step: one circle's instruction, or the general note. |
| One-breath answer | One answer that gives instructions for two or more circles. |
| Part | One piece of an answer that the split code makes. A part is an exact substring of the answer. |
| Circle mention | A number at the start of a part that names a circle, for example `2.` or "Two,". |
| Review file | A Markdown file in the round folder for Drew to read. No prompt points to it. |

## Decisions log

- 2026-10-24: Drew prefers one step per circle for a capture with three or more circles (interview).
- 2026-10-24: the shadow test gets its input from a trial. Drew speaks one-breath answers on purpose on a few real captures. Nextshot checks every answer (interview).
- 2026-10-24: the report is one review file in each round folder, written automatically after each capture (interview). This needs a Jev base change, because the base writes only `jev.json` in shadow. The request went to the Jev base session on 2026-10-24.
- 2026-10-24: build or stop: build a real one-breath mode only if Drew finds one breath faster after 5 or more trial captures, and at least 95% of parts are right (interview).
- 2026-10-24: correction to the line above: the bar is 90%, not 95%. Five captures with three circles give about 15 parts, and 95% would allow no mistake. 90% allows one (Drew, after the builder check).
- 2026-10-24: Drew approved this spec, with the calls listed under "Left to the builder".
- 2026-10-24: Wispr Flow writes a spoken list as a numbered list (Drew's test, below). The split code treats a numbered line as the strongest circle mention.

## Intent

Nextshot must be built for dictation first (Drew, 2026-10-24). Today the note panel asks one question per circle. A one-breath answer ("one, brighter; two, remove the line") could fill several circles with one utterance and one Return.

This issue does not build that mode. It measures whether Nextshot could split such an answer correctly, with no change to the note panel. The result is a build-or-stop recommendation for a real one-breath mode.

## What Drew's real notes show

Source: the 9 rounds in `~/Library/Application Support/Nextshot`, read on 2026-10-24. They hold 101 answers.

- No answer is a one-breath answer. Drew answers one circle per step, as the panel asks.
- Numbers in answers usually mean something else: "footnote number one", "page 3", "where the 2 is", "3 out of 5", "invoices 1 and 2".
- A loose splitter (any number that matches a circle on the capture) misfires on 6 of 101 answers (6%). A strict splitter (a number at the start of a sentence or line, or after "circle", "number", "item", or "badge") misfires on 0.
- No answer holds a spoken self-correction such as "blue, no, gray". "Instead of X, call it Y" appears 5 times. It asks for a change and does not correct the speaker.
- Answers are often long (up to about 1,400 characters) and hold several sentences about one circle. Some hold their own bullet lists of steps.

Drew's Wispr Flow test (2026-10-24). He spoke: "One, make the title brighter. Two, remove the line under it. Three, move the button left." Wispr Flow wrote:

```text
1. Make the title brighter.
2. Remove the line under it.
3. Move the button left.
```

So a dictated one-breath answer arrives as a numbered Markdown list, one item per line. The note panel keeps line breaks (real answers hold them).

## Research

| Source | Finding | What it means here |
| --- | --- | --- |
| Wispr Flow, "Why Flow" page, and reviews | Flow handles self-corrections in its post-processing. "5 pm, no actually 6 pm" arrives as "6 pm". | Most self-corrections never reach Nextshot. The self-correction question is a cheap measurement, not a core part. |
| Shriberg's disfluency structure, as used in the DISCO corpus paper (2023) | A self-repair has a reparandum (the words replaced), an optional interregnum ("no", "I mean"), and a repair. Correction tools delete the first two. | Nextshot keeps all words (Drew's rule). It only marks which clause is the repair. |
| SPM split-parsing method (ACL 2023 industry track) | For an utterance with several intents, split it into single-intent sub-sentences first, then parse each one. | Code splits the answer first. Jev then judges each part on its own. |
| Talon voice community (chaining issue 1458) | Users chain several voice commands in one utterance with a spoken separator word ("then", "over"). | A clear separator makes a split reliable. Wispr's numbered lines act as that separator. |
| Rasa forum (form filling) | A slot-filling bot fills only the active form when one utterance holds values for several forms. | Today's panel works the same way: one step is active. One-breath is the several-forms case. |

## Goals, non-goals, and anti-goals

Goals:

- Measure how often code splits a one-breath answer at the right places, and how often each part gets the right circle.
- Measure how often code splits a normal answer by mistake (a false split).
- Give Drew one review file per round that he can read in a minute.
- End with a build-or-stop recommendation, by the rule in the decisions log.

Non-goals:

- Any change to the note panel, the prompts, `prompt.md`, or the capture prompt files.
- An `on` state. The registry allows `oneBreath` off or shadow only.
- Ordinal words ("first, second") as circle mentions. They usually list steps for one circle. Jev's per-answer question (below) still reports an answer that code misses.

Anti-goals (a failure even if it works):

- A changed answer. Every part is an exact substring of Drew's words.
- A new keystroke, a wait, or a pop-up on the normal path.
- A request with `oneBreath` off, or an image sent without `jevSendImages`.

## How the shadow test works

The job runs after each capture, in the Jev base runner, inside the base's 2-second budget per capture. It reads the capture's answers from `context.capture`: each circle's `instruction` and the general `note`.

### 1. Find circle mentions (code)

The split code looks for circle mentions only at a part start: the start of the answer, the start of a line, or after a sentence end (`.`, `!`, `?`, `;`, `:` followed by a space).

| Strength | Form | Example |
| --- | --- | --- |
| Strong | A list number at a line start: `N.`, `N)`, or `N:` | `2. Remove the line under it.` (Wispr's form) |
| Strong | "Circle", "number", "item", or "badge", then a number | `Circle two, remove the line.` |
| Medium | A number word or digit alone at a part start, then `,`, `:`, or `.` | `Two, remove the line.` (raw spoken form) |

- A number is a digit from 1 to 99, or a number word from "one" to "twenty".
- A digit form needs a space or the line end after its `.`, `)`, or `:`. So "3.5 seconds" and "10:30" are not mentions.
- A mention counts only if its number is a circle on this capture. On a capture with circles 1 and 2, `3.` is not a mention.
- The code sees a one-breath answer when it finds mentions of two or more different circles. Strong and medium mentions split the same way. The review records each mention's strength, so the trial shows whether medium mentions cause false splits (my call).
- The 0-of-101 count above came from a broader rule than this one. The builder runs the final Swift code on the real rounds once, as a local check. Drew's notes never go into a committed test.

### 2. Split the answer (code)

- A part runs from one mention to the next mention. Sentence ends inside a part do not split it, because one circle's answer often holds several sentences.
- Text before the first mention is a lead part with no circle, for example "Here are my notes."
- The same circle can get two parts ("1. ... 2. ... 1. also ...").
- Each part is a range of the original answer. The parts joined in order give back the exact answer. A test proves this.
- The code also records simple signals for the review: the step where Drew gave the answer, whether the list starts at 1, and whether the mentions cover every circle on the capture. A list of steps given at circle 3's step ("1. Rename it. 2. Make it bold.") looks like a one-breath answer to code. These signals and Jev help tell the two apart.

The split code is pure Swift with no Jev and no network. It lives in FeedbackKit, so a future one-breath mode in the panel can use it without JevKit.

### 3. Pick each part's badge (Jev)

One request per capture holds all of the job's questions.

| Question | Type | Asked for | Data sent |
| --- | --- | --- | --- |
| Does this answer give separate instructions for two or more numbered circles? | Noul | every answer of a capture with two or more circles | reviewer text, and the list of circle numbers |
| Which circle does this part give an instruction for? Options: one per circle, plus "none: a general remark". | Choice | every part of an answer that code split | reviewer text; the circle crops with `jevSendImages` on; each circle's OCR text with screen-text consent |

- The per-answer Noul gives a second opinion on the code's detection. It also finds one-breath answers that code missed.
- A capture with fewer than two circles cannot hold a one-breath answer, so it gets no request (my call, 2026-10-24, during the build). This also sends less of Drew's text.
- Without images or screen text, Jev knows only Drew's words. The Choice then mostly checks the number in the part. The review file says which data Jev had.
- A crop that several questions use goes in the state once, as a named field. Each extra reference in an instruction adds another copy of the image to the tokens (TypeSafe's image guidance).
- My call: Jev's pick counts when its top probability is 0.8 or more. Below that, the review file shows "unsure". The threshold lives in the job file and changes after the trial data.

### 4. Self-corrections (Jev)

- Code looks for a correction cue in each part: "no,", "actually", "I mean", "wait", "scratch that", or "sorry".
- For a part with a cue, code splits the part into clauses at commas and at the cue. Jev gets a Choice over the clauses: "Which clause states the final request?"
- The answer is a clause number. Nextshot keeps every word and only records which clause is the final ask.
- Wispr Flow removes most spoken self-corrections before the text arrives, so this question will rarely run. It stays because it costs almost nothing and covers typed notes.

### 5. Write `jev.json`

- The base runner records every answer of every request in `jev.json`. The job adds nothing else to it.
- `jev.json` never holds notes. The question names carry only positions, for example `answer.c3.multi` (the Noul for circle 3's answer), `part.c1.p2.badge` (the Choice for part 2 of circle 1's answer), and `part.c1.p2.final` (the self-correction Choice).
- The split is a pure function of the answer text and the job version. A later reader can rebuild each part from `feedback.json` and match it to its answers by position.

### 6. The review report

The job returns a Markdown section for its capture. The base writer keeps one file per round, `oneBreath-review.md`, with one section per capture in capture order, and writes it in shadow (the base change Drew chose on 2026-10-24). The exact file name follows the base's naming rule.

- The first line says: "Review file for Drew. Agents: do not act on this file."
- The file holds Drew's words, circle numbers, and probabilities. It never holds screen text, so it shows no window title and no OCR text.
- A capture section shows an answer in full when code or Jev calls it one-breath, or when its capture has a circle with no answer. A trial capture always has empty circles (Drew presses Esc for them), so the file also shows a trial answer that both code and Jev missed. That makes missed splits visible (my call).
- Every other answer appears only as a count.
- Each shown answer gets a table with one empty Fix column for Drew. A blank Fix means code got the part right. Otherwise Drew writes the right circle number, or "split" when the part boundary is wrong. One column gives code accuracy and Jev accuracy, because Jev's pick is compared with the right circle (my call).
- When Jev fails (timeout, error, no network), the job still returns the section with the code columns and "Jev: not checked (reason)". The code split comes first and never waits on Jev (my call).
- A runner skip before the job starts (no key, a pause, no consent) leaves no section. The trial step 0 below checks the key first.
- The base writer replaces a capture's section on a rerun.
- If the base does not add the review hook, a command rebuilds the same file from `feedback.json` and `jev.json`, with the same split code (fallback, my call).

Example:

```text
## Capture 3 (10:42), 3 circles

Answer at circle 1's step. Code: one-breath, 3 parts. Jev: one-breath, 0.97. Jev had: words and crops.

| Part | Drew's words | Code | Jev | Fix |
| --- | --- | --- | --- | --- |
| 1 | 1. Make the title brighter. | circle 1 | circle 1, 0.98 | |
| 2 | 2. Remove the line under it. | circle 2 | circle 2, 0.95 | |
| 3 | 3. Move the button left. | circle 3 | unsure (circle 1, 0.55) | |

2 other answers: normal (code and Jev agree).
```

- The file prints no accuracy total, because only Drew's Fix marks give it. A session tallies the marks across rounds at the end of the trial.

## Flag behavior

| `jevBase` | `oneBreath` | What happens |
| --- | --- | --- |
| off | any | Nothing. No request, no `jev.json`, no review file. |
| on | off | The runner does not pick the job. No one-breath request, no review file. Other jobs run as their own flags say. |
| on | shadow | The job runs after each capture. `jev.json` gets its answers, and the review file gets a section. No prompt changes. |
| on | on (override) | Not allowed. `FlagResolver` ignores the override, so the flag stays at its default, off. |

- Turn the trial on: `scripts/nextshot-flags.sh set jevBase on`, then `scripts/nextshot-flags.sh set oneBreath shadow`.
- Turn it off: `scripts/nextshot-flags.sh reset oneBreath`.
- A flag change takes effect at the next capture (base rule).

## Privacy and requests

- The job sends Drew's words by default. Reviewer text needs no extra consent in the base design.
- Circle crops go out only with `jevSendImages` on. Each circle's OCR text goes out only with `jevSendScreenText` on.
- The job's `requires` is empty, so it runs with reviewer text alone. It adds crops or OCR text only when `context.allowed` holds `.images` or `.screenText`. Every string is typed (`JevValue.reviewer`, `.screen`, `.code`), so the base's asker refuses a request that holds a kind without consent.
- The job asks Jev only through `context.jev`. It builds no URL and no request, and it writes no file (base rules).
- The review file sits in the round folder with `feedback.json`, which already holds the same words.

## Latency and cost

- No time on the normal path. The job runs in the background after the capture prompt is on the clipboard.
- One request per capture. A request holds at most (circles + 1) Nouls plus one Choice per part. The measured round trip for six questions was 0.22 seconds (2026-10-24), well inside the 2-second budget.
- Cost: about 1,500 input tokens per request with images, so about $0.00006 per capture (measured price $0.042 per million input tokens). Text-only requests cost less.
- The job never needs the round-end wait. Its output only goes to `jev.json` and the review file, which no prompt reads.

## Tests

Split code (FeedbackKit, no Jev):

- Wispr's numbered list splits into one part per line, each with its circle.
- The raw spoken form ("One, ... Two, ...") and "Circle two" forms split the same way.
- Two mentions on one line ("1. Brighter. 2. Remove the line.") split at the second mention.
- No split for real false-hit patterns, written as new test strings: "footnote number one", "on page 3", "where the 2 is", "3 out of 5", "invoices 1 and 2".
- No split when only one circle is mentioned, or when a number is not a circle on the capture.
- Ordinals ("First, ... Second, ...") and bullet lists (`- `) do not split.
- The parts joined in order equal the original answer, for every test string.
- Lead text, a repeated circle, and correction cues are found.

Job (JevKit, after the base lands, with the base's stub transport):

- With `oneBreath` off, the runner sends no request and writes no review file. Output files stay byte-identical.
- In shadow, one request per capture, with the expected question names.
- No question name or `jev.json` field holds note text.
- An image or screen-text field is sent only when `allowed` holds that kind.
- The review section matches a fixed expected text for a fixed answer and fixed stub answers.

## Build tasks

Each task is a sub-issue of #40.

| Task | Needs | Files |
| --- | --- | --- |
| 1. Split code and its tests | nothing, can start now | new `Packages/FeedbackKit/Sources/FeedbackKit/OneBreathSplitter.swift` and its test file |
| 2. The `oneBreath` job: questions, question names, consent checks, flag-off test | the Jev base (#36) | the base's stub `OneBreathJob.swift` and a new test file in JevKit |
| 3. The review section and the per-round review file | the base's shadow review hook | the job file; the hook itself is in the base |
| 4. The trial: Drew's captures, the review, the build-or-stop recommendation | tasks 1 to 3 in a dev build | the review files, a session note, a comment on #40 |

## The trial

Drew runs the trial in a dev build with `jevBase` on and `oneBreath` in shadow.

0. A session first checks that Nextshot's TypeSafe key is in the Keychain and that a test capture writes a review section.
1. Capture an area with three or more circles, as usual.
2. At the first circle's step, speak every circle's answer in one breath: "One, ... Two, ... Three, ...".
3. Press Return. Then press Esc for each remaining step.
4. Do this on 5 or more captures, over normal rounds. Answer every other capture as usual.
5. Open the round folder (Option+Shift+O) and read `oneBreath-review.md`. Fill the Fix column, or tell a session which parts are wrong.

The trial adds Esc presses only on trial captures. The prompt still works: the whole answer stays under circle 1, and the agent reads the numbers in it.

## A future one-breath mode (mockup)

This mode is not planned. It is here so the build-or-stop decision has a concrete picture.

- No new key. One step per circle stays the default.
- When the split code finds a one-breath answer, the panel lists the parts under the answer field, each with its circle number. The code split is local and instant, so nothing waits on Jev.
- Return saves each part to its circle. The panel then goes to the next step that has no answer, usually the general note.
- The arrow keys still move between steps. A filled circle's step shows its part, so Drew can fix one part.
- Jev checks the circles in the background, as in the shadow test. A disagreement would need an `on` state, which this issue does not add.

```text
+--------------------------------------------------------------+
| Circle 1 (1 of 3): what should change?                       |
| +----------------------------------------------------------+ |
| | 1. Make the title brighter.                              | |
| | 2. Remove the line under it.                             | |
| | 3. Move the button left.                                 | |
| +----------------------------------------------------------+ |
|   (1) Make the title brighter.                               |
|   (2) Remove the line under it.                              |
|   (3) Move the button left.                                  |
| Return saves 3 answers. Arrow keys go back and forward.      |
| +----------------------------------------------------------+ |
| |              preview: circle 1 with its context          | |
| +----------------------------------------------------------+ |
+--------------------------------------------------------------+
```

## Build-or-stop rule

Build a real one-breath mode only if all four hold:

1. After 5 or more trial captures with three or more circles, Drew finds one breath faster (Drew's rule, 2026-10-24).
2. At least 90% of trial parts are right: the right boundaries and the right circle, judged by Drew in the review files (Drew's rule, 2026-10-24).
3. The split code alone reaches that 90%. The real mode splits at Return, so it cannot wait on Jev. If only code plus Jev reach 90%, the mode cannot be built as drawn (my call).
4. Code splits no more than 1% of normal answers (my call). Today's count is 0 of 101.

Current lean (2026-10-24): stop. Drew prefers one step per circle. The trial can change this.

## Left to the builder

- The exact Jev question wording and option text, within the base's prompting rules.
- How the crops sit in the state.
- The clause rules for self-corrections.
- The review section's exact layout, within the example above.

Calls I made, for Drew to check:

- The split code lives in FeedbackKit, not JevKit.
- Ordinal words do not count as circle mentions. Strong and medium mentions split the same way.
- Jev's pick counts at a top probability of 0.8 or more.
- One Fix column in the review file. A blank Fix means code got the part right.
- An answer shows in full when its capture has a circle with no answer, so a missed trial answer is visible.
- When Jev fails, the review section still shows the code split.
- If the base adds no review hook, a command rebuilds the review file instead.
- Rule 3 and rule 4 of the build-or-stop rule.

## Sources

- Wispr Flow, [Why Flow](https://wisprflow.ai/why-flow): self-corrections handled in post-processing.
- Letterly, [Wispr Flow review](https://letterly.app/blog/wispr-flow-review/): a reviewer's "5 pm, no actually 6 pm" example.
- Bhat and others, [DISCO: a large scale human annotated corpus for disfluency correction](https://arxiv.org/abs/2310.16749) (2023): the reparandum, interregnum, and repair structure (Shriberg, 1994).
- [SPM: a split-parsing method for joint multi-intent detection and slot filling](https://aclanthology.org/2023.acl-industry.64/) (ACL 2023 industry track).
- talonhub/community, [issue 1458](https://github.com/talonhub/community/issues/1458): chaining voice commands with "then" and "over".
- Rasa forum, [Is it possible to fill multiple forms with one utterance?](https://forum.rasa.com/t/is-it-possible-to-fill-multiple-forms-with-one-utterance/25656)
- TypeSafe, [Images](https://docs.typesafe.ai/images): put an image that several questions use in the state once.
- Jev base design (#36), `docs/superpowers/specs/2026-10-24-jev-base-design.md` on the Jev base branch: the job interface, `jev.json`, and the budgets.
