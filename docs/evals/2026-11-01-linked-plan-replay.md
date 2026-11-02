# Linked plan replay: results, 2026-11-01

Replay of today's copied prompt against the `linkedPlan` prompt (issue #261, design Part D in `docs/superpowers/specs/2026-11-01-visual-direction-handoff-design.md`). Four saved Nextshot rounds, two agents, two prompt variants, three runs per cell: 48 runs, all with status ok. The runs started at 15:14 PST and ended at 16:37 PST on 2026-11-01. Scored with `scripts/replay/score.py`. This report holds numbers only: no reviewer words and no agent text.

## Result

- 3 of the 4 scored bars pass for `linked` on both agents: ledger coverage, tokens, and group fit.
- The question bar fails for `linked`: 16.7% of Claude runs and 41.7% of Codex runs pass, against a bar of 90%. The bar cannot pass on these rounds. No item lacks an instruction (0 of 21 items), so every question that names an id fails.
- Coverage: `linked` lists every id in all 24 runs. `today` misses one id in 1 of 24 runs.
- Tokens: Claude `linked` costs 1.09 times `today` (bar 1.3). Codex `linked` costs 0.84 times.
- Group fit (model-judged): Claude 3.47 against 2.45, Codex 3.35 against 3.13. Both are above `today`.
- Cross-capture groups (no bar): the lines count is 0.25 per run for Claude `linked` against 0.75 for `today`, and 0.58 against 0.00 for Codex. The counts are small and the parser is a heuristic (see Limits).

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
- Prompt tool: `nextshot-prompt` at commit `b4857a2` for the `linked` prompts (rendered 16:26 PST, `--linked`). The `today` prompts were rendered at 15:45 PST. Rendered again with the `b4857a2` tool, all 4 `today` prompts are byte-identical to the saved ones.
- 2 of the 48 run files (both `today`) carry no tool version. The other 46 name the versions above.
- Rerun: `python3 -I scripts/replay/score.py build/replay/2026-11-01`. The judge results are cached in `judge-*.json` beside the runs, so a rerun makes no vendor call.

## 1. Ledger coverage

The share of the round's item ids found in the answer as a stand-alone id. Bar: 100% in every run.

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

The last paragraph with a question mark, and the ids it names. Bar: the paragraph names only ids that have no instruction, in at least 90% of runs. A run with no question paragraph, or with one that names no id, passes.

| agent | variant | runs | with a question paragraph | question paragraph is a table | name ids | pass | pass share | bar |
|---|---|---|---|---|---|---|---|---|
| Claude | today | 12 | 12 | 0 | 9 | 3 | 25.0% | fail |
| Claude | linked | 12 | 12 | 0 | 10 | 2 | 16.7% | fail |
| Codex | today | 12 | 3 | 0 | 0 | 12 | 100.0% | pass |
| Codex | linked | 12 | 9 | 0 | 7 | 5 | 41.7% | fail |

- The 4 rounds have 21 items and none lacks an instruction (counted from the data). The bar therefore reduces to "no question names an id". The result says how often an agent names an id when it asks. It does not say whether the question was needed.
- Codex asks far more id-naming questions under `linked`: 7 of 12 runs against 0 of 12 under `today`.
- Claude names ids in 10 of 12 runs under `linked` and 9 of 12 under `today`.

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

| bar | Claude | Codex |
|---|---|---|
| 1 coverage, 100% in every run | pass (0 of 12 runs below) | pass (0 of 12 runs below) |
| 2 cross-capture groups | no bar | no bar |
| 3 questions name only unanswered items, in 90% of runs | fail (16.7%) | fail (41.7%) |
| 4 tokens, at most 1.3 times `today` | pass (1.09 times) | pass (0.84 times) |
| 5 group fit, at least `today` | pass (3.47 against 2.45) | pass (3.35 against 3.13) |

## Limits

- 3 runs per cell, 4 rounds, 21 items. Runs of one round are not independent. Read the differences as direction, not proof.
- Measure 3 is degenerate here. The rounds hold no item without an instruction and no labeled conflict, so the bar cannot separate a needed question from a noisy one. The design bar also allows items with a conflict. This replay has no conflict labels.
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

## Decision for Drew

Keep `linkedPlan` off, or try it in the Dev build?

Bars that passed: ledger coverage (every `linked` run lists every id), tokens (1.09 times for Claude, 0.84 times for Codex, bar 1.3), and group fit (3.47 against 2.45 for Claude, 3.35 against 3.13 for Codex).

Bar that failed: question precision. Claude passes in 16.7% of `linked` runs and Codex in 41.7%, against a bar of 90%. This bar cannot pass on these 4 rounds, because no item lacks an instruction. It still shows one change: Codex asks an id-naming question in 7 of 12 `linked` runs and in 0 of 12 `today` runs.

Not decided by the data: whether the extra questions are needed. The cross-capture group counts are small (4 to 10 groups per cell) and point both ways.

1. **Try it in the Dev build (Recommended).** The measured bars pass or are degenerate, and the cost is low. Turn on `linkedPlan` in Nextshot Dev only. Release stays off. Watch the end-of-answer questions in your own rounds. If most of them are noise, turn it off again.
2. **Keep it off.** Choose this if you read the extra Codex questions as a regression. The data gives no measured reason to choose it. It only delays your own check.
