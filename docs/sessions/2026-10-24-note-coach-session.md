# Session: note coach (#37), 2026-10-24

Closed 17:55 PDT. A side session that the orchestration session started. Worktree `.claude/worktrees/note-coach-d8dd95`, branch `claude/note-coach-d8dd95`. The shared daily note lives in the main checkout, so this note is its own file.

## Work log

- Measured Drew's past notes locally (nothing sent): 0 of 66 real item notes are vague, 2 are empty, and 9 ask the agent for an answer. The capture that issue #37 cited was a test. Research on feedback and bug report quality (CritiqueKit, Critique Style Guide, Chaparro, CLAMBER) is cited in the spec.
- Wrote and got approval for `docs/superpowers/specs/2026-10-24-note-coach-design.md`. Drew's decisions: small and shadow first; vague means the note names no problem, no change, and no question; questions get "Answer this item. Change no code."; the line says "Ask the reviewer first"; text only in the first build; a paste test gates the on state; the base's "never follow" rule is scoped to quoted screen text (made by the base in `a7fda59`); a bug check keeps a "why is this broken?" note from the question line.
- Built `NoteCoachJob` (version 2) on the Jev base interface: one text-only request per capture, four questions per filled note, a pure rule, refined lines, a `jev.json` summary, and a review file. Sonnet executors wrote the first job and the accuracy harness. This session reviewed both and added the unsure label, the bug check, and the thresholds.
- Accuracy test with Nextshot's key, text only: 0 of 66 real notes labeled vague, 47 of 49 vague notes caught, 9 of 9 real questions caught. The labeled set and the results stay in the main checkout's git-ignored `build/jev-eval/`.
- Trial on the combined build: shadow on 611 and on 614 gave the right labels and lines. A headless Claude Code paste test asked about the vague item, answered the question, and edited nothing. Flags are reset.

## Commits

On `claude/note-coach-d8dd95`: `1d69a9c` spec, `27eca9b` shared stub-test line, `6b2491a` job and tests, `d9fbf16` accuracy harness, `f42af49` bug check and thresholds, `ad2d78b` agent rules, `387d38c` review heading fix, and this note.

## Git

- PR [#66](https://github.com/spurs-planks-smithers/Capso/pull/66) into `feature/feedback-sessions`. Fork CI is off, so it shows zero checks. Local results: JevKit 91 pass, the unsigned Debug build passes.
- Sub-issues: #62 closed (accuracy), #63 closed after this note (trial), #61 closes when PR #66 merges.

## Open

- Drew approves the PR #66 merge. Then #61 and #37 close.
- Turning the on state on for daily use is Drew's call. The kill rule in the spec applies.
- Later: the circle crop as input (needs `jevSendImages`), with its own accuracy run.
- A wrong commit hash went to the orchestration once and was corrected. A memory now says to read every hash from git.
