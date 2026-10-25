# Session: lanes and priority (#69), 2026-10-24

A side session that the orchestration session started. Worktree `.claude/worktrees/crops-anchors-067aa9`, branch `claude/prompt-lanes-9d7023`. The shared daily note lives in the main checkout, so this note is its own file.

## Work log

- Measured Drew's past rounds locally (nothing sent): 17 rounds, 137 items, about 66 real. Three real rounds hold 16 or more items. About one real item in three is an exact edit, 9 ask for an answer, and about 4 report a bug.
- Research (Aider architect mode, RouteLLM, Claude Code subagents, Anthropic long context tips, Lost in the Middle) is cited in the spec. Claude Code's docs confirm that the main agent can pass a `model` for each subagent call.
- Wrote and got approval for `docs/superpowers/specs/2026-10-24-prompt-lanes-design.md`. Drew's decisions: the plan goes at the end of the copied round prompt; one prompt, and the agent hands lane A to a subagent on a fast, low-cost model; order is severity, then capture; lane A takes only exact, small edits that are not blockers; the accuracy test sends note text only; each lane line shows the item id and its labels.
- A builder check found three gaps. All were settled as my calls in the spec: the base's refined pointer stays as it is, a note with no concrete change is judgment, and the accuracy run gates the on state, not the PR.
- Built with subagent-driven development on Sonnet: `PromptLanesJob` (one text-only request per capture, three questions per item, a pure lane rule, a summary, and a review file), then `PromptLanesPlan` and `PromptLanes` (the Order and lanes section, built at round end from `jev.json`). Each task passed a task review.
- An Opus whole-branch review found no behavior bug. It found that the accuracy harness the spec promises was missing. The fix pass added `scripts/prompt-lanes-eval.sh` and `PromptLanesAccuracyTests`, and five text fixes. The lane A sentence now also hands over each item's file from the plan table (my call, dated in the spec).

## Commits

On `claude/prompt-lanes-9d7023`: `9109b99` spec draft, `bedd18d` spec approved, `a8b5912` merge of `feature/feedback-sessions`, `df046a6` build plan, `0eaa281` job, `c8f6887` plan and prompt section, `efcfcc2` agent docs, `731c108` accuracy harness, `7e4069e` review fixes, and this note.

## Checks

- JevKit 179 of 179 and FeedbackKit 241 of 241 pass. The live accuracy suite is skipped without its set file.
- The unsigned Debug build passes.
- With `promptLanes` off, no request goes out, and `PromptBuilder.render` output is byte-identical.

## Open

- #73: build the labeled set in the main checkout's `build/jev-eval/`, run `scripts/prompt-lanes-eval.sh`, Drew confirms the lane A and bug labels, then set the threshold.
- #74: the trial on the orchestration session's combined build: shadow, on, and a paste test that checks the agent starts one smaller-model subagent for lane A.
- Drew approves the PR merge. Then #69 closes, when all its sub-issues are closed.
