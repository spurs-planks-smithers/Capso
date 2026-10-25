# Session: injection and data guard (#70), 2026-10-24

A side session that the orchestration session started. Worktree `.claude/worktrees/note-coach-d8dd95`, branch `claude/data-guard-0cc5bf`, from `jev/next-base` at `2539f9c`. The shared daily note lives in the main checkout, so this note is its own file.

## Work log

- Read the Jev base design and threat model, the merged jobs, issues #34 and #70, and the TypeSafe guardrails cookbook. Four searches on screenshot prompt injection (AgentTypo, SnapGuard, "The Attacker Moves Second"), redaction (Unredacter, Depix), and local detection (Presidio). The spec cites them.
- Interviewed Drew in four rounds. His decisions: Jev Nouls and Box questions on the image, behind `jevSendImages`; solid boxes, not blur; four kinds (contact, numbers, secrets, faces), secrets added to the issue's list; one off, shadow, on sub-flag per kind; warn and continue on injection, with no quote; covered copy plus a "never copy private data" rule; a review page in this build; a separate issue (#81) for the prompt gap; chat-app captures stay quiet through a `chat` Noul. Drew approved the spec.
- Wrote and committed `docs/superpowers/specs/2026-10-24-data-guard-design.md`, with the threat model: what the guard catches, what it cannot catch, and how it fails safe.
- Built the local detectors and masking, the face finder (Apple Vision) and solid covers, the kind flags and the job options hook, and the job. A Sonnet executor wrote the review page script in its own worktree. This session reviewed it and merged its commit.
- Security choices made while building: a strong local hit cannot be cleared by Jev; the image sent to Jev has every local find drawn over, whatever the kind flags; the image stays home when private screen text has no box, or when the face finder fails (found by the automated security review); no rule uses bare "agent" or "AI", because Nextiva's contact center screens use those words for people; test keys are built at run time, so git-secrets never sees a key-shaped literal.
- An Opus security review (read only) found one high and eight lower issues, and all are fixed in `24e4eb9`. High: a slow Jev request at the 2 s deadline made the runner drop the whole output, local results included, so the request now gives up 400 ms early. Others: OCR lines the runner cut at 200 scalars hid their ends, the window title reached Jev, four phrasings and wrapped or Cyrillic text got past the strong rules, a card or IBAN followed by more digits was missed, a partial covered copy claimed to be complete, shadow review text said "covered", the account pattern backtracked on long space runs, and the review script followed a symlink.
- The orchestration session approved the shared-file edits. The kind flags and the options hook are one commit on `jev/next-base`, `bc53a43`, and the branch was restacked on it. The Jev base spec's decisions log records the rule change. The old tip is kept as `backup/data-guard-pre-restack`.

## Commits

On `claude/data-guard-0cc5bf`, read with `git log 2539f9c..HEAD`.

## Tests

- JevKit: 194 tests pass, 51 of them for the data guard and 5 for the options hook. FeedbackKit: 227 tests pass.
- The review script: the executor's synthetic-round check passes, and a symlinked output file is refused with the link's target unchanged.
- The unsigned Debug build from `AGENTS.md` passes.
- Fork CI is off, so the PR shows zero checks. Zero checks is not a pass.

## Open

- Trial on the orchestration session's combined build (#80): shadow first, then Drew decides on per kind.
- Follow-up #81: the copied prompts name the covered copy, and item crops get covers.
