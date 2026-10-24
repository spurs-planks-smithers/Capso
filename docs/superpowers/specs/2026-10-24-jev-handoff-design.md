# Jev in Nextshot: product and design (draft)

Date: 2026-10-24. Status: approved direction (Drew, 2026-10-24). Each session refines its part with Drew. Tracking: issue #34 (parent), #35 flags, #36 Jev base, #37 note coach, #38 crops and anchor text, #39 duplicates and conflicts, #40 one-breath notes. The idea list is in `docs/plans/2026-10-24-jev-image-ideas.md`.

## Intent (Drew, 2026-10-24)

- Every Jev feature sits behind a feature flag, so each one can be turned on or off. These are first tests and prototypes, but they are meant to be built out.
- Latency, simplicity, and ease of use come first. Nextshot must feel barely there. It must become second nature, like hotkeys, a trackpad, a keyboard, and dictation.
- Build Nextshot for dictation first. Many users are moving to it.
- First ideas: note coach (1), crops and anchor text (7, 8), and duplicates and conflicts (9, 10).
- Visual recheck (14) moves to its own feature set, built later: [Signoff, issue #33](https://github.com/spurs-planks-smithers/Capso/issues/33) (working name). The agent's edits can take minutes, hours, or days, so a recheck needs its own trigger and flow.
- Nextshot runs Jev at the end of each capture, in the background, while Drew moves on to the next capture.
- One-breath notes (idea 16): shadow test first.

## Rule change (Drew, 2026-10-24)

The project's agent instructions say: "Feedback code adds no network code, no outbound requests, and no sockets." Drew's decision to run Jev inside Nextshot changes this rule. Drew confirmed the new wording on 2026-10-24. It goes into the agent instructions in the first build commit:

- Only the Jev package makes outbound requests. It calls only `api.typesafe.ai`. It runs only when a Jev flag is on.
- All other feedback code stays local.
- The security baseline (`docs/SECURITY_BASELINE.md`) changes in the same commit.

## Goals

- Better agent results on the first pass, from the same capture effort.
- Smaller, clearer prompt packages for large rounds.
- Measured accuracy on Drew's own captures before any feature changes a prompt.

## Non-goals for the first build

- Checks while Drew types a note (the live hint in the mockup). Checks start only after a capture is saved.
- Writing or rewriting notes. Jev only selects, orders, groups, and labels.
- Replacing the coding agent's own judgment.

## Anti-goals (a failure even if it works)

- A new keystroke on the normal path.
- A wait that Drew can feel, a spinner, or a pop-up.
- A changed note. Drew's words stay exact.
- A capture image that leaves the Mac without consent.
- A feature that cannot be turned off without data loss.

## Design rules

1. No new keystroke on the normal path. Today's path is: Option+Shift+F, drag, mark, Command+S, answer each step, paste. Jev adds nothing to it.
2. Silent when right. Show only a gap, and only above a confidence threshold.
3. Never wait on Jev. Each step has a time budget. On a timeout, an error, or no network, the plain result goes through, and the bundle records "not checked".
4. Speak or type, same result. The unit is one utterance. Every hint is a question that Drew can answer by voice.
5. Drew's words stay exact. The agent sees the original note and Jev's labels next to it.
6. Reversible and visible. `prompt.md` and the capture prompt files stay as they are. Jev writes `jev.json` (every answer with its probability) and refined files beside them.
7. Local unless Drew says so. Every flag starts at off. Images need their own consent flag.

## The background pipeline

1. Drew finishes the last note step. Nextshot stores the capture and copies the capture prompt at once, as today.
2. A background task starts for that capture. It sends one request per job and runs the jobs in parallel.
3. Jobs per capture: note coach, crops and anchor text, and duplicate and conflict checks against the earlier items of the round. Each item pair runs once, when its later item arrives.
4. Results go to `jev.json` and to `<capture>-refined.md`. In shadow mode, only `jev.json` is written.
5. The capture prompt points to the refined file: "If `<capture>-refined.md` exists, read it first." The agent reads files seconds after the paste, so the refined file is usually there. If not, the agent uses the plain files.
6. Round end (Option+Shift+R) builds the round prompt from the refined results that are ready. It waits at most 500 ms for a capture that is still running. After that, the capture goes in plain and is marked "not refined". Option+Shift+R already waits for saves in progress, so this adds no new kind of wait.

## Flags

- Each feature has three states: off, shadow, and on. Shadow runs Jev and writes `jev.json` but changes no prompt. On also writes the refined files and uses them in prompts.
- Flags live in the app's defaults domain, `com.drewschulz.nextshot`.
- Keys: `jev.noteCoach`, `jev.cropsAnchors`, `jev.dupesConflicts` (each off, shadow, or on), `jev.oneBreath` (off or shadow), `jev.sendImages` (on or off), `jev.model` (pinned to `jev-1.14.0`), and one threshold per feature.
- A Labs section in Settings shows the flags (see the mockup from 2026-10-24). Until it exists, `defaults write` sets them.
- Guard: with every flag off, Nextshot sends no request, and its output is byte-identical to today's. A test proves both.

## Latency budgets

| Moment | Today | Added by Jev | Budget | If over budget |
| --- | --- | --- | --- | --- |
| Return in a note step | instant | 0 | n/a | n/a |
| Capture prompt copy | instant, before OCR | 0 | n/a | n/a |
| Background refine, per capture | not present | parallel requests, 0.22 s each (measured 2026-10-24) | 2 s | capture marked "not refined" |
| Round end, Option+Shift+R | waits for saves | waits for a running refine | 500 ms | capture goes in plain |

## Behavior per feature

- Note coach (1). Scores each note: vague, partial, or clear. In shadow, it records each vague or missing note. On: a vague item gets "Ask Drew first: the note names no change" in the refined file.
- Crops and anchor text (7, 8). Writes one padded, edge-checked crop per item and one "Search:" line per item, chosen from the capture's OCR lines. The full image stays as a fallback.
- Duplicates and conflicts (9, 10). Code first keeps only pairs with the same app or window title, so the pair count stays small. A merge keeps every original note and lists "Seen in". A conflict goes to an "Ask first" block at the top of the round prompt.
- Visual recheck (14). Not in the first build. See issue #33.
- One-breath notes (16), shadow only. When a dictated answer mentions more than one circle, Jev records how it would split the answer by badge. Nothing in the panel changes. Drew reviews the splits before any UI work.

## Dictation first (all of Nextshot)

- Clipboard collision. Wispr Flow pastes through the clipboard, so a dictated note can replace the copied capture prompt. My call for the first build: no change. The refined content lives in files that the prompt points to, so a re-copy (Option+Shift+C) still gets the refined path.
- Self-corrections. "Make it blue, no, gray": Jev picks the final value. The prompt keeps all the words and marks the final ask.
- Spoken pointing. "This one" or "the button above it" resolves through the circle. Without a circle, Box finds it (idea 5).
- Hints are spoken questions, never buttons.

## Metrics and kill rule

- First-pass done rate per item, from Drew's verdict (and from Signoff, issue #33, once it exists).
- Follow-up rounds per round.
- Agent input tokens per round, images and text.
- Share of items that are vague or have no instruction (note coach in shadow).
- Jev precision on duplicate and conflict pairs against Drew's labels. Crop coverage from the edge checks.
- Background refine time per capture, and the share of captures that miss the budget.
- Kill rule: a feature that adds a visible step, or that does not raise the first-pass done rate, stays off.

## Risks

- TypeSafe calls images and Box "dreamer-ready". Accuracy and the request format can change. Pin the model and keep thresholds per model version.
- Captures can hold Nextiva customer data. Images go out only with `jev.sendImages` on. With it off, jobs send OCR text and notes only. TypeSafe does not train on requests. Zero data retention needs an enterprise plan.
- Each image side must be 280 to 1568 pixels. Scale and pad before sending.
- Nextshot needs its own TypeSafe key in the Keychain (the add-secret skill), not the `jev` lab key.
- No network, or TypeSafe down: every job skips quietly, and the prompts stay plain.

## Decisions log

- 2026-10-24: every Jev feature behind an off, shadow, or on flag (Drew).
- 2026-10-24: Nextshot runs Jev in the background after each capture (Drew).
- 2026-10-24: one-breath notes get a shadow test first (Drew).
- 2026-10-24: new local-only rule wording confirmed (Drew).
- 2026-10-24: visual recheck moves to issue #33, a separate feature set with a better name (Drew).
- 2026-10-24: a separate session builds the shared Jev base first: the TypeSafe client, the background job runner, the refined-file writer, and `jev.json`. Each feature session builds only its own job on top of it. The base must be designed rigorously and securely, and its session challenges Drew toward best practices. This is Drew's first production use of a model like Jev (Drew).
- 2026-10-24: flags are local only, and Jev features stay in dev builds only. See `docs/superpowers/specs/2026-10-24-feature-flags-design.md` (Drew).

## Left to the builder

- A new package `Packages/JevKit` (Foundation only): the HTTP multipart client, the request and answer types, and the jobs. The App/Feedback layer starts the jobs after a capture is stored.
- Crops reuse the existing `PreviewCrop` logic. File names, retry policy, and thresholds come after the shadow data.
