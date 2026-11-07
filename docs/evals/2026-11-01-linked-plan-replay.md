# Linked plan replay: results, 2026-11-01

Replay of today's copied prompt against the `linkedPlan` prompt (issue #261, design Part D in `docs/superpowers/specs/2026-11-01-visual-direction-handoff-design.md`). Four saved Nextshot rounds, two agents, two prompt variants, three runs per cell: 48 runs, all with status ok. The runs started at 15:14 PST and ended at 16:37 PST on 2026-11-01. Scored with `scripts/replay/score.py`. This report holds numbers only: no reviewer words and no agent text. A re-run on the final prompt (2026-11-06) is the last section.

## Result

- 3 of the 4 scored bars pass for `linked` on both agents: ledger coverage, tokens, and group fit.
- The question bar fails for `linked` on the formal definition, for both agents. Claude passes in 16.7% of `linked` runs and in 25.0% of `today` runs, so Claude fails under both prompts. Codex passes in 41.7% of `linked` runs and in 100.0% of `today` runs, a drop that comes from `linked`. The bar is 90%.
- The Codex change is measured: id-naming questions rise from 0 of 12 runs to 7 of 12, and runs with any question paragraph rise from 3 of 12 to 9 of 12.
- The bar passes only when no question names an id. It cannot tell a needed question from noise here, because no item lacks an instruction and no round has conflict labels (0 of 21 items).
- Coverage: `linked` lists every id in all 24 runs. `today` misses one id in 1 of 24 runs.
- Tokens: Claude `linked` uses 1.09 times the tokens of `today` (bar 1.3). Codex `linked` uses 0.84 times.
- Group fit (model-judged): Claude 3.47 against 2.45, Codex 3.35 against 3.13. Both are above `today`.
- Cross-capture groups (no bar): the line count is 0.25 per run for Claude `linked` against 0.75 for `today`, and 0.58 against 0.00 for Codex. The counts are small and the parser is a heuristic (see Limits).

## What was run

| round | captures used | items | items with no instruction | repository commit |
|---|---|---|---|---|
| 2026-10-22-1609-feedback | 2 | 3 | 0 | bcad196 |
| 2026-10-24-1631-feedback | 3 | 9 | 0 | 9beb0ad |
| 2026-10-24-1823-feedback | 2 (captures 3 and 4 only) | 2 | 0 | 2930a9a |
| 2026-10-27-0939-feedback | 5 (4 hold items) | 7 | 0 | 9d2e59e |

The repository commit is the last commit of origin/main before the round started. Each agent had read-only access to a worktree at that commit.

| role | model | tool |
|---|---|---|
| Claude agent | claude-opus-5-5 | Claude Code 2.1.307 |
| Codex agent | gpt-6.1-sol, reasoning effort medium | codex-cli 0.164.0-alpha.11.1 |
| Judge of Claude answers | gpt-6.1-sol | Codex, empty scratch folder, the replay read profile |
| Judge of Codex answers | claude-sonnet-5-5 | Claude Code, no tools, no MCP, empty scratch folder |

- Harness: `scripts/replay/replay.py`, last changed in commit `b655021`.
- Prompt tool: `nextshot-prompt` for the `linked` prompts was built from the working tree just before commit `b4857a2` (16:25 PST). It rendered the `linked` prompts at 16:26 PST with `--linked`. The `today` prompts were rendered at 15:45 PST. Rendered again with that binary, all 4 `today` prompts are byte-identical to the saved ones.
- 2 of the 48 run files carry no tool version: round 2026-10-22-1609-feedback, run 1, both agents, `today`. They were written at 15:14 and 15:15 PST, before the 15:45 `today` render and before tool versions were recorded. The byte check does not cover their prompt. The other 46 files name the versions above.
- Rerun: `python3 -I scripts/replay/score.py build/replay/2026-11-01`. With every judge result cached in `judge-*.json` beside the runs, a rerun makes no vendor call and needs no `--yes`. A missing judge result needs `--yes`, and the script exits with status 3 without it. `--no-judge` skips measure 5 and writes `score-nojudge.json`, not `score.json`.

## 1. Ledger coverage

The share of the round's item ids found in the answer as a stand-alone id. Bar: 100% in every run. The bar is written for `linked`. The `today` rows apply the same rule only as a reference.

| agent | variant | runs | mean coverage | runs below 100% | bar |
|---|---|---|---|---|---|
| Claude | today | 12 | 99.1% | 1 | fail |
| Claude | linked | 12 | 100.0% | 0 | pass |
| Codex | today | 12 | 100.0% | 0 | pass |
| Codex | linked | 12 | 100.0% | 0 | pass |

The one run below 100% is Claude `today`, round 2026-10-24-1631-feedback, run 3. It lists 8 of 9 ids. It names the ids of capture 2 as one range, so 2.2 is not listed. A range counts as a miss.

## 2. Cross-capture groups

Lines of the groups section that hold ids from 2 or more captures. A table row, a bullet, or a numbered line counts. No bar.

| agent | variant | runs | group lines per run | runs with no groups section | loose count per run |
|---|---|---|---|---|---|
| Claude | today | 12 | 0.75 | 2 | 1.00 |
| Claude | linked | 12 | 0.25 | 0 | 1.17 |
| Codex | today | 12 | 0.00 | 8 | 0.50 |
| Codex | linked | 12 | 0.58 | 0 | 0.00 |

- Group lines in all: Claude `today` 9, Claude `linked` 3, Codex `today` 0, Codex `linked` 7.
- The loose count is a supplementary upper bound: every line outside a table that holds ids from 2 or more captures, in any part of the answer. It includes question and report lines.
- The linked prompt of round 2026-10-24-1823-feedback has no Links step, because the round has 2 items. The replay line still asks for a Links section. In all 6 `linked` runs of that round the Links section holds code locations and no item ids, so those runs score 0 lines.

## 3. Question precision

The last paragraph with a question mark, and the ids it names. Bar: the paragraph names only ids that have no instruction, in at least 90% of runs. A run with no question paragraph, or with one that names no id, passes. The bar is written for `linked`. The `today` rows apply the same rule only as a reference.

| agent | variant | runs | with a question paragraph | question paragraph is a table | name ids | pass | pass share | bar |
|---|---|---|---|---|---|---|---|---|
| Claude | today | 12 | 12 | 0 | 9 | 3 | 25.0% | fail |
| Claude | linked | 12 | 12 | 0 | 10 | 2 | 16.7% | fail |
| Codex | today | 12 | 3 | 0 | 0 | 12 | 100.0% | pass |
| Codex | linked | 12 | 9 | 0 | 7 | 5 | 41.7% | fail |

- The 4 rounds have 21 items and none lacks an instruction (counted from the data). The bar therefore passes only when no question names an id. The result says how often an agent names an id when it asks. It does not say whether the question was needed.
- Claude fails under both prompts (25.0% under `today`, 16.7% under `linked`). Its fail is not specific to `linked`. It names ids in 10 of 12 runs under `linked` and 9 of 12 under `today`.
- Codex drops from 100.0% under `today` to 41.7% under `linked`. This drop is specific to `linked`.
- Codex asks far more id-naming questions under `linked`: 7 of 12 runs against 0 of 12 under `today`. Runs with any question paragraph rise from 3 of 12 to 9 of 12.
- The linked Questions step asks the agent to ask when two readings lead to different work, and to name all of their ids. The prompt therefore asks for part of what the formal bar counts as a failure, because the bar counts only empty or conflicting items as valid questions.

## 4. Tokens

Total is input plus output, from the run file. Bar: the mean total of `linked` is at most 1.3 times `today`, per agent.

| agent | variant | runs | mean input | mean output | mean total |
|---|---|---|---|---|---|
| Claude | today | 12 | 276,401 | 5,618 | 282,020 |
| Claude | linked | 12 | 300,017 | 6,337 | 306,354 |
| Codex | today | 12 | 226,199 | 1,576 | 227,775 |
| Codex | linked | 12 | 189,947 | 1,659 | 191,606 |

| agent | total, linked over today | output only, linked over today | bar |
|---|---|---|---|
| Claude | 1.09 times | 1.13 times | pass |
| Codex | 0.84 times | 1.05 times | pass |

Claude input counts include cache reads. Codex input counts include cached input. Compare only within one agent.

## 5. Group fit

One judge call per run, from the other vendor, blind to the variant. The judge lists each group of the answer and rates it from 1 to 5. 5 means one decision fits every item. 1 means the items need different changes. Bar: the mean rating of `linked` is at least the mean of `today`, per judged agent. The mean is over all groups of all runs in the cell.

| judged agent | variant | runs judged | judge failed | runs with groups | groups | mean rating | ratings 1, 2, 3, 4, 5 |
|---|---|---|---|---|---|---|---|
| Claude | today | 12 | 0 | 10 | 20 | 2.45 | 10, 3, 1, 0, 6 |
| Claude | linked | 12 | 0 | 9 | 17 | 3.47 | 5, 2, 0, 0, 10 |
| Codex | today | 12 | 0 | 9 | 15 | 3.13 | 0, 6, 4, 2, 3 |
| Codex | linked | 12 | 0 | 9 | 20 | 3.35 | 0, 7, 2, 8, 3 |

| judged agent | mean rating, linked | mean rating, today | bar |
|---|---|---|---|
| Claude | 3.47 (17 groups) | 2.45 (20 groups) | pass |
| Codex | 3.35 (20 groups) | 3.13 (15 groups) | pass |

All 48 judge calls returned usable JSON on the first attempt. 0 runs were excluded.

Supplementary, no bar: the groups that span 2 or more captures, which are the point of linking.

| judged agent | variant | cross-capture groups | mean rating |
|---|---|---|---|
| Claude | today | 10 | 3.50 |
| Claude | linked | 6 | 5.00 |
| Codex | today | 4 | 4.00 |
| Codex | linked | 10 | 3.20 |

Supplementary, no bar: the mean rating per round (number of groups in brackets).

| round | agent | today | linked |
|---|---|---|---|
| 2026-10-22-1609-feedback | Claude | 1.00 (1) | n/a (0) |
| 2026-10-22-1609-feedback | Codex | n/a (0) | n/a (0) |
| 2026-10-24-1631-feedback | Claude | 1.00 (7) | 1.71 (7) |
| 2026-10-24-1631-feedback | Codex | 2.17 (6) | 2.67 (9) |
| 2026-10-24-1823-feedback | Claude | 5.00 (3) | 5.00 (3) |
| 2026-10-24-1823-feedback | Codex | 4.00 (3) | 3.67 (3) |
| 2026-10-27-0939-feedback | Claude | 2.89 (9) | 4.57 (7) |
| 2026-10-27-0939-feedback | Codex | 3.67 (6) | 4.00 (8) |

## Bars at a glance

The bars are written for `linked`. This table shows the `linked` result. The `today` rows in the sections above apply the same rule only as a reference.

| bar | Claude, `linked` | Codex, `linked` |
|---|---|---|
| 1 coverage, 100% in every run | pass (0 of 12 runs below) | pass (0 of 12 runs below) |
| 2 cross-capture groups | no bar | no bar |
| 3 questions name only unanswered items, in 90% of runs | fail (16.7%; `today` 25.0%) | fail (41.7%; `today` 100.0%) |
| 4 tokens, at most 1.3 times `today` | pass (1.09 times) | pass (0.84 times) |
| 5 group fit, at least `today` | pass (3.47 against 2.45) | pass (3.35 against 3.13) |

## Limits

- 3 runs per cell, 4 rounds, 21 items. Runs of one round are not independent. Read the differences as direction, not proof.
- Measure 3 cannot separate a needed question from noise here. The rounds hold no item without an instruction (0 of 21) and no labeled conflict, so the bar passes only when no question names an id. The design bar also allows items with a conflict. This replay has no conflict labels. The failed bar is a measured result on the formal definition.
- The linked Questions step asks the agent to ask when two readings lead to different work, and to name all of their ids. The prompt therefore asks for part of what the formal bar counts as a failure, because the bar counts only empty or conflicting items as valid questions.
- The replay worktrees sit inside this checkout, under `build/replay/worktrees`. Claude Code may therefore have loaded this checkout's `AGENTS.md` and parent instruction files as well. Both variants saw the same files (`AGENTS.md` differed only by the final docs commit, which came after the runs), so the comparison is not biased. The phrase "a worktree at that commit" may still overstate what Claude saw. This is not verified.
- The group parser is a heuristic. It looks for a heading that starts with Links, Group, or Related. It counts list and table lines until the next section.
- It misses groups that an agent writes as plain sentences (8 of 12 Codex `today` runs had no groups section).
- It does not expand a range such as 2.1 to 2.3.
- It finds no group in a Links section that holds no ids (round 2026-10-24-1823-feedback, 6 of 6 `linked` runs).
- Token counts include caches (see measure 4). They also depend on how much of the repository an agent chose to read.
- The judge is a model, so the ratings are model-judged estimates. Claude answers and Codex answers have different judges, so compare `linked` with `today` within one agent only.
- The judge sees the whole answer, so it can tell the layout even though it gets no variant label.
- The judge listed 59 single-item entries as groups. They are dropped, because one item always fits itself. Dropped per cell: Claude `today` 10, Claude `linked` 20, Codex `today` 13, Codex `linked` 16. The judge also counts groups inside one capture, so the group counts differ from the parser counts in measure 2.
- Ratings cluster by round. In round 2026-10-24-1631-feedback all 7 Claude `today` groups are rated 1.
- Plan-only runs. The score does not test whether a plan is correct or whether a change works.
- All 4 rounds come from one reviewer and one app.

## Prompt changes after the replay

After the runs, three copy changes were made. The Plan step gained the sentence "Make no edit before this table is in your reply." A capture with no items and no note gets a line that tells the agent to ask. The selection ledger heading lost the word "below". The re-run of 2026-11-06 (last section) exercised the Plan step sentence. The ask line and the selection heading are in the final prompt, but these four rounds do not exercise them: no replayed capture lacks both an item and a note, and the replay uses the round prompt, not the selection prompt. The first replay used the round prompt as built at `b4857a2` and is plan-only, so the first change does not affect what it measured.

## Decision for Drew

Keep `linkedPlan` off, or try it in the Dev build?

Bars that passed for `linked`: ledger coverage (every `linked` run lists every id), tokens (uses 1.09 times the tokens of `today` for Claude, 0.84 times for Codex, bar 1.3), and group fit (3.47 against 2.45 for Claude, 3.35 against 3.13 for Codex).

Bar that failed for `linked`: question precision, on the formal definition. The bar passes only when no question names an id. Claude passes in 16.7% of `linked` runs and in 25.0% of `today` runs, so Claude fails under both prompts. Codex passes in 41.7% of `linked` runs and in 100.0% of `today` runs, so its drop comes from `linked`. The design goal is to ask only when unsure.

The Codex change is measured. Id-naming questions rise from 0 of 12 runs to 7 of 12. Runs with any question paragraph rise from 3 of 12 to 9 of 12.

Not decided by the data: whether the extra questions are needed. No item lacks an instruction (0 of 21) and no round has conflict labels. The cross-capture group counts are small (4 to 10 groups per cell) and point both ways.

1. **Try it in the Dev build (Recommended).** Coverage, tokens, and group fit passed. The question bar failed, and the Codex rise is measured: id-naming questions rise from 0 of 12 runs to 7 of 12, and runs with any question paragraph from 3 of 12 to 9 of 12. Only your own rounds can show whether the extra questions are needed. Turn on `linkedPlan` in Nextshot Dev only. Release stays off. Watch the end-of-answer questions in your own rounds, and count how many turned out to be unnecessary. If most are noise, turn it off again.
2. **Keep it off.** Choose this if you read the Codex rise as a regression. The replay shows that rise: Codex passes the question bar in 100.0% of `today` runs and in 41.7% of `linked` runs.

## Re-run on the final prompt (2026-11-06)

The 24 `linked` runs were repeated on the final prompt: the same 4 rounds, the same models (the Codex tool version differs), 3 runs per cell. All 24 runs have status ok. Scored on 2026-11-06 at 20:50 PST with `scripts/replay/score.py` (`build/replay/2026-11-06/score.json`). This section holds numbers only: no reviewer words and no agent text. Every number and table above is the first run and stays as it was. The Decision for Drew section above is the state of 2026-11-01.

### Result

- Coverage, tokens, and group fit pass for `linked` on both agents, as in the first run. The Codex token ratio (1.22 times) compares runs on different Codex tool versions.
- The question bar fails for `linked` on both agents, as in the first run. Claude passes in 0.0% of `linked` runs (first run 16.7%). Codex passes in 50.0% (first run 41.7%). The bar is 90%.
- No pass or fail verdict changes between the first run and the re-run.

### What differs from the first run

| item | first run (2026-11-01) | re-run (2026-11-06) |
|---|---|---|
| `linked` prompt | round prompt as built at `b4857a2` | final prompt, with the three copy changes |
| `today` baseline | 24 runs on 2026-11-01 | the same 24 runs, copied into the new folder with their cached judge results, not re-run |
| Claude agent | claude-opus-5-5, Claude Code 2.1.307 | same |
| Codex agent | gpt-6.1-sol, codex-cli 0.164.0-alpha.11.1 | gpt-6.1-sol, codex-cli 0.166.0-alpha.6 |
| Judge of Claude answers | gpt-6.1-sol | same |
| Judge of Codex answers | claude-sonnet-5-5 | same |
| repository commits | bcad196, 9beb0ad, 2930a9a, 9d2e59e | same |

- The `today` prompt is the classic prompt of 2026-11-01. Main changed it after that date in one way: round names are five words or fewer (PR 263). This changes the text of the first `Session Name:` line only. So the `today` baseline differs from today's classic prompt in that line.
- The first line of the re-run `linked` prompts also differs from the first run's `linked` prompts, because PR 263 (five-word round names) landed between the runs. It changes the `linked` prompts the same way as the `today` baseline.
- The `linked` prompt is the final one. The replay uses the round prompt, so the selection heading change is not exercised. No replayed capture lacks both an item and a note, so the ask line for such a capture is not exercised either.
- Prompt tool: `nextshot-prompt` for the re-run `linked` prompts was built from main at `95b671d` (the PR 262 merge `b80f1c0` plus PR 274), on branch `feature/linked-plan-default-on` before the default-on commits. The flag change does not affect that tool.
- The harness final line still asks for a Links section for the 2-item round, as before.
- The `today` Codex runs used the older Codex tool version (11 of 12 files name it, and the other carries no version, as in the first run). The 12 new `linked` Codex runs used the newer one.
- 24 new judge calls returned usable JSON on the first attempt. 0 runs were excluded. The 24 `today` judge results are the cached ones from 2026-11-01.
- Rerun: `python3 -I scripts/replay/score.py build/replay/2026-11-06`. With every judge result cached, a rerun makes no vendor call.

### 1. Ledger coverage and 4. Tokens

Coverage bar: 100% in every run. Token bar: the mean total of `linked` is at most 1.3 times `today`, per agent. Total is input plus output. Compare token counts only within one agent.

| agent | variant | runs | mean coverage | runs below 100% | mean input | mean output | mean total |
|---|---|---|---|---|---|---|---|
| Claude | today | 12 | 99.1% | 1 | 276,401 | 5,618 | 282,020 |
| Claude | linked, first run | 12 | 100.0% | 0 | 300,017 | 6,337 | 306,354 |
| Claude | linked, re-run | 12 | 100.0% | 0 | 279,961 | 6,603 | 286,564 |
| Codex | today | 12 | 100.0% | 0 | 226,199 | 1,576 | 227,775 |
| Codex | linked, first run | 12 | 100.0% | 0 | 189,947 | 1,659 | 191,606 |
| Codex | linked, re-run | 12 | 100.0% | 0 | 275,193 | 3,311 | 278,504 |

| agent | total, linked over today: first run | total: re-run | output only: first run | output only: re-run | bar |
|---|---|---|---|---|---|
| Claude | 1.09 times | 1.02 times | 1.13 times | 1.18 times | pass |
| Codex | 0.84 times | 1.22 times | 1.05 times | 2.10 times | pass |

### 3. Question precision

The last paragraph with a question mark, and the ids it names. Bar: the paragraph names only ids that have no instruction, in at least 90% of runs. The 4 rounds hold 21 items and none lacks an instruction (counted from the data). The bar therefore passes only when no question names an id.

| agent | variant | runs | with a question paragraph | question paragraph is a table | name ids | pass | pass share | bar |
|---|---|---|---|---|---|---|---|---|
| Claude | today | 12 | 12 | 0 | 9 | 3 | 25.0% | fail |
| Claude | linked, first run | 12 | 12 | 0 | 10 | 2 | 16.7% | fail |
| Claude | linked, re-run | 12 | 12 | 0 | 12 | 0 | 0.0% | fail |
| Codex | today | 12 | 3 | 0 | 0 | 12 | 100.0% | pass |
| Codex | linked, first run | 12 | 9 | 0 | 7 | 5 | 41.7% | fail |
| Codex | linked, re-run | 12 | 7 | 0 | 6 | 6 | 50.0% | fail |

- Claude names ids in all 12 `linked` runs of the re-run, against 10 of 12 in the first run and 9 of 12 under `today`.
- Codex names ids in 6 of 12 `linked` runs of the re-run, against 7 of 12 in the first run and 0 of 12 under `today`. Runs with any question paragraph are 7 of 12, against 9 of 12 and 3 of 12.
- The linked Questions step tells the agent to name the ids of the items it asks about. Id-naming questions are therefore the intended behavior, and the bar counts them as failures. The bar cannot tell a needed question from noise here.

### 5. Group fit

One judge call per run, from the other vendor, blind to the variant, as in the first run. Bar: the mean rating of `linked` is at least the mean of `today`, per judged agent.

| judged agent | variant | runs judged | judge failed | runs with groups | groups | mean rating | ratings 1, 2, 3, 4, 5 |
|---|---|---|---|---|---|---|---|
| Claude | today | 12 | 0 | 10 | 20 | 2.45 | 10, 3, 1, 0, 6 |
| Claude | linked, first run | 12 | 0 | 9 | 17 | 3.47 | 5, 2, 0, 0, 10 |
| Claude | linked, re-run | 12 | 0 | 9 | 18 | 3.00 | 8, 1, 0, 1, 8 |
| Codex | today | 12 | 0 | 9 | 15 | 3.13 | 0, 6, 4, 2, 3 |
| Codex | linked, first run | 12 | 0 | 9 | 20 | 3.35 | 0, 7, 2, 8, 3 |
| Codex | linked, re-run | 12 | 0 | 9 | 16 | 3.75 | 0, 3, 1, 9, 3 |

Both re-run means are above `today`: Claude 3.00 against 2.45, Codex 3.75 against 3.13. Claude is below its first run (3.47). Codex is above its first run (3.35).

Supplementary, no bar: group lines per run from the parser, and the groups that span 2 or more captures (model-judged).

| agent | variant | group lines per run | cross-capture groups | mean rating |
|---|---|---|---|---|
| Claude | today | 0.75 | 10 | 3.50 |
| Claude | linked, first run | 0.25 | 6 | 5.00 |
| Claude | linked, re-run | 0.33 | 7 | 4.29 |
| Codex | today | 0.00 | 4 | 4.00 |
| Codex | linked, first run | 0.58 | 10 | 3.20 |
| Codex | linked, re-run | 0.42 | 9 | 3.44 |

### Bars at a glance

| bar | Claude, `linked` re-run | Codex, `linked` re-run |
|---|---|---|
| 1 coverage, 100% in every run | pass (0 of 12 runs below) | pass (0 of 12 runs below) |
| 2 cross-capture groups | no bar | no bar |
| 3 questions name only unanswered items, in 90% of runs | fail (0.0%; first run 16.7%) | fail (50.0%; first run 41.7%) |
| 4 tokens, at most 1.3 times `today` | pass (1.02 times) | pass (1.22 times; Codex tool version differs) |
| 5 group fit, at least `today` | pass (3.00 against 2.45) | pass (3.75 against 3.13) |

### Reading

- The pattern of the first run holds. Coverage, tokens, and group fit pass for both agents. The question bar fails for both.
- The question bar is worse for Claude under the final prompt (0.0% against 16.7%). For Codex it is 50.0% against 41.7%.
- Codex token use rose against the first `linked` run: mean total 278,504 against 191,606, and output 2.10 times `today`. The ratio of 1.22 times still passes the 1.3 bar (Codex tool version differs). The possible causes are the Codex tool version, the final prompt text, or chance. With 3 runs per cell, the data cannot say which.
- The Codex ratio compares `linked` runs on one tool version with `today` runs on another.

### Limits

- Same limits as the first run: 3 runs per cell, 4 rounds, 21 items, a heuristic group parser, token counts that include caches, a model judge (ratings are model-judged estimates), and plan-only runs. Runs of one round are not independent. Read the differences as direction, not proof.
- The `today` baseline was not re-run, and its prompt differs from today's classic prompt in the `Session Name:` line (see above).
- The judge listed 35 single-item entries as groups in the new `linked` runs (Claude 20, Codex 15). They are dropped, as in the first run.
- The group lines per run (0.33 and 0.42) are small counts from a heuristic parser (4 and 5 lines in all).

## Paste check in a Claude desktop session (2026-11-07)

One hand paste of a copied round prompt into a Claude desktop session. It is not hand test T1, T4, or T6. Those tests have their own runbook and no results yet.

- **Build and flag:** Nextshot Dev 0.7.0-dev (923), built from main at `535204f`. No `flag.linkedPlan` override was set (`scripts/nextshot-flags.sh list` shows none, and `defaults read` finds no key). The default (`.on`) chose the linked layout.
- **Round:** `2026-11-07-0551-feedback`, 1 capture, 3 items. All three notes were remarks about the test. None asked for a change.
- **Layout in the paste:** it matches Part A of the design spec at each point the spec names. It has a Session Name line, the opening tag, Goal, the item ledger, the bundle-reading steps, Links, a plan table with the columns item, group, place, and change, Scope, Questions, Helpers, Authority, and a report that repeats the ledger. It has no Verify section and no lanes section. It names no agent product (#109).
- **Render check:** `nextshot-prompt round ... --linked` renders the same round from the code. It matches the paste line for line, except line 1. The paste carries the on-device summary name, and the command renders the cut name, because the command has no model.
- **Files on disk:** `0551-claude-prompt.md` stayed classic (file column, Verify section).
- **Whole paste:** the text arrived whole, up to the last line.
- **Receiving session:** it wrote Links and a plan table first, made no edit, and asked one question that named all three item ids, as the Questions step asks.
- **Not covered:** group quality on a round with related items (the three items formed one group with no shared decision), a paste with an image, and a long chat. The question bar from the replay stays open.
