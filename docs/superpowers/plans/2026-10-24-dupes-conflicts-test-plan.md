# Duplicates and conflicts: test plan

Date: 2026-10-24. Status: draft for Drew's approval. Issues: #39, #58 (shadow run), #60 (trial). Spec: `docs/superpowers/specs/2026-10-24-dupes-conflicts-design.md`.

## Why a new test

- Round `2026-10-24-1801` (build 614): Drew put "bigger", "smaller", and "larger" on three badges of one capture. The job sent nothing, because it compared only items of different captures. Drew then chose to compare items inside one capture too (commit `2930a9a`, not in the trial app yet).
- Round `2026-10-24-1823` (build 616): 4 captures, 6 pairs, 3 requests of 88 to 272 ms. Jev called all 6 pairs duplicates (sameAsk 1.69 to 1.97, opposite 0.09 or less). Captures 1 and 2 show the Claude window. Captures 3 and 4 show the Nextshot page in Chrome. Drew could not say whether the 4 pairs across the two apps are right.
- So the trial had no known answer. A test that decides whether the feature goes on needs cases whose answer is written down before the run, and a count of right and wrong calls.

## What I can run myself

| Step | Who | How |
| --- | --- | --- |
| Make test screens | me | Local HTML pages, rendered to PNG by a headless browser (Playwright). Each element's box comes from the page. No private data. |
| Build rounds, run the job, call TypeSafe | me | An opt-in live test in JevKit with Nextshot's own key, like `scripts/jev-live-test.sh`. |
| Count right and wrong calls | me | The test writes a results file and a report. |
| Draw a selection in Nextshot | Drew only | Computer use cannot be granted for Nextshot, and the shell cannot send mouse events (measured 2026-10-21). |

Part A runs with no app, no flags, and no hands. Part B needs Drew for about 3 minutes.

## Part A: a live test with known answers

### Test screens

Four HTML pages, rendered at 1440 by 900 pixels:

| Page | Window title | Elements |
| --- | --- | --- |
| Settings | Account settings | page title, Save button, Email row, Delete link |
| Pricing | Choose a plan | page title, three plan cards, Buy button |
| Menu | Nshot menu | five menu rows, each with a gray hotkey on the right |
| Dashboard | Weekly usage | page title, bar chart, table header |

Every page uses the app name Safari. Each item gets a badge and a rectangle on its element, as Nextshot stores them. The screen text under a mark is the element's own text, as OCR would give it.

### Cases

Each case is two entries (capture, element, note) and its expected call. The expected calls are fixed before the first run and never change after it.

| Group | Pairs | Example | Expected |
| --- | --- | --- | --- |
| D: same change, same element, other words | 12 | Settings title: "Make the title bigger" and "Increase the font size of the page title" | duplicate |
| X: same change, other element or page | 8 | "Make this title bigger" on Settings and on Pricing (the round 1823 case) | different |
| O: one ask holds part of the other | 6 | "Show the hotkey in gray on the right" and "Show the hotkey in gray on the right, and make the whole row taller" | overlap |
| C: opposite changes, same element | 10 | bigger and smaller; remove the Buy button and rename it; green and blue | conflict |
| U: unrelated | 6 | "Fix the typo in Wednesday" and "Make the chart taller" | different |
| B: same element, changes that can both be done | 4 | "Make the title bold" and "Make the title blue" | different |
| P: opposite changes, different elements | 4 | "Make this title bigger" on Settings and "Make this title smaller" on Pricing | different |
| S: inside one capture | 6 | badges 1 and 2 on one title: "bigger" and "smaller" (the round 1801 case) | per case |
| N: general note and item | 4 | general note "Make every page title bigger" and item "Make the title bigger" | per case |

That is 60 pairs: 13 duplicates, 13 conflicts, 8 overlaps, and 26 different. A separate reviewer checked every expected call before any run (2026-10-24). It agreed with 45 of the first 48. The 3 ambiguous cases (N3, O3, X7) were reworded, and groups B and P and 4 more duplicate and conflict cases were added at its request.

Seven X and S cases use the same words for two different elements. With notes only (arm A1), nothing tells them apart from a duplicate. So A1 is expected to fail them. That result shows whether notes alone may ever produce a "make the change once" line.

Two real pairs from Drew's rounds can join them, with their notes only (see Decisions):

- Items 3.2 and 4.2 of round `2026-10-22-1839`: overlap (the same menu hotkey, from Claude and Outlook).
- Items 1.2 and 2.1 of round `2026-10-21-1541`: different (the same kind of change on another page).

### Arms

Each case runs in four arms:

| Arm | Sent to TypeSafe | Shipped? |
| --- | --- | --- |
| A1 | notes only | yes, the default |
| A2 | notes and screen text | yes, with `jevSendScreenText` |
| A3 | notes, screen text, and images for same-source pairs | yes, with both consent flags |
| A4 | as A3, plus images for every pair | no, an experiment for the X cases |

Each arm runs 3 times, to measure stability: the share of cases with the same call in all three runs.

### Variants

The test stores every answer, so code variants are scored from the same answers, with no new request:

- V1: the job as built.
- V2: a duplicate between two different sources (different app and different window title) becomes an overlap. The agent then gets a "check the code" line, never "make the change once".
- V2w: as V2, but a duplicate stays only when both entries are in one capture or have the same window title. Two pages of one app then count as different sources.
- V3: the duplicate cut point at 1.6 and at 1.7, in place of 1.5.

### What it measures

- Precision: of the pairs called duplicate, the share that are duplicates. The same for conflicts.
- Recall: of the true duplicates, the share called duplicate. The same for conflicts.
- A table of expected call by actual call, per arm and variant.
- Stability across the three runs.
- Time and input tokens per request.

### Harness

- A new opt-in suite `DupesConflictsLiveEval` in `Packages/JevKit/Tests/JevKitTests/`. It runs only with `NEXTSHOT_JEV_EVAL=1` and a key, through a new script `scripts/jev-eval-dupes.sh` that reads the Keychain item `TYPESAFE_API_KEY_NEXTSHOT` and never prints it.
- Cases and PNGs live in `Packages/JevKit/Tests/JevKitTests/Fixtures/dupes-eval/`. The suite builds rounds in a temporary folder, runs `DupesConflictsJob` through a real `JevClient` for each arm, and writes `results.json` and `report.md`.
- It never touches the installed app, the flags, or `~/Library/Application Support/Nextshot`.
- Each case runs alone, as one round with one pair, so one request per case, arm, and run: 60 cases, 4 arms, and 3 runs make 720 requests, plus 6 for the real pairs. At about 1,500 input tokens each, that is about 1.1M tokens, or about $0.05 at $0.042 per million input tokens.

### Pass rule

- The feature goes to on only when the chosen arm and variant meet Drew's bar for duplicates and for conflicts: at most 1 wrong call in 10.
- No X case may be called a duplicate in the shipped arm and variant. An X duplicate tells the agent to make one change where two are needed.
- If V2 meets the bar and V1 does not, the job ships V2.
- If no arm meets the bar for conflicts, conflicts stay in shadow. Duplicates can go on alone, with a second flag (Drew's call, as the spec says).

## Part B: one capture in the app (Drew, about 3 minutes)

After the orchestrator gives the app turn back and the trial app has commit `2930a9a`:

1. I set `jevBase` on, `dupesConflicts` on, and the consent flags of the arm that passed Part A.
2. I open the Settings test page in Safari.
3. Drew makes one capture of its title with three badges: "Make the title bigger", "Make the title smaller", and "Make the title larger". Then Option+Shift+R.
4. I check `jev.json` (1.2 vs 1.1, 1.3 vs 1.1 and 1.2), the round section of `refined.md` (an Ask first line for 1.2 and 1.1, and a Same ask line for 1.3 and 1.1), the copied prompt (the base's pointer line), and `prompt.md` (unchanged).
5. I reset every flag and tell the orchestrator.

## Order

1. Drew approves this plan and the decisions below.
2. I build the test screens, the cases, the suite, and the script. A separate reviewer checks the expected calls before any run.
3. I run Part A and write the report under `docs/`.
4. Drew reads the report and chooses the arm and variant.
5. Part B, when the app turn is free.
6. Drew decides on the flag's release state.

## Decisions for Drew

- May the two real pairs from his rounds join Part A? Their notes go to TypeSafe.
- Part A runs with no app and no flags. Part B needs the app turn and about 3 minutes of Drew's time.
