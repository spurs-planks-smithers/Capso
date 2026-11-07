# Linked plan prompt on by default, November 6, 2026

Issue 261. The `linkedPlan` flag shipped off in both channels (PR 262, 2026-11-01). Drew decided on 2026-11-06 to turn it on in both channels for release 0.8.0.

### Decision

Copied prompts use the linked layout by default. This covers the round prompt, the capture prompt, and the selection prompt.

- A ledger lists every item in the reviewer's own words.
- With three or more items, a Links step groups related items under one shared decision, and the plan table has a group column.
- The plan table has the columns item, group, place, and change.
- The agent asks one batch question at the end for anything unclear.
- The report repeats the ledger and gives evidence per item.
- There is no Verify section and no lanes section.

The files on disk (`prompt.md`, `<stem>-prompt.md`) and the zip README stay in the classic layout. The flag is not a Jev flag and not dev-only.

### Evidence

The replay of 2026-11-01 (`docs/evals/2026-11-01-linked-plan-replay.md`) used 4 saved rounds, 2 agents, and 3 runs per cell. The report holds numbers only.

| Bar | Claude | Codex | Result |
| --- | --- | --- | --- |
| Ledger coverage, 100% in every run | 100.0% | 100.0% | pass |
| Tokens, linked over today (bar 1.3) | 1.09 times | 0.84 times | pass |
| Group fit, linked against today (model-judged) | 3.47 against 2.45 | 3.35 against 3.13 | pass |
| Question bar (90%), linked | 16.7% | 41.7% | fail |

- The question bar passes only when no question names an id. The 4 rounds hold 21 items and none lacks an instruction, so a needed question cannot be told from noise.
- Claude also fails under today's prompt (25.0%). Codex passes under today's prompt (100.0%).
- Codex asks id-naming questions in 7 of 12 linked runs against 0 of 12 today.
- Drew accepted the failed question bar on 2026-11-06.

### Copy changes after the replay

Three changes came after the runs. None was re-measured.

- The Plan step gained the sentence "Make no edit before this table is in your reply."
- A capture with no items and no note gets a line that tells the agent to ask.
- The selection ledger heading lost the word "below".

A second run of the 24 linked runs on the final prompt is appended to the report before the merge.

### Windows

The Windows app has no copy-prompt path. Its only `PromptBuilder` callers write files on disk (`BundleTextRenderer`) and zips (`ZipText`, `ZipWriter`). A search of `Windows/` on 2026-11-06 found no clipboard call. These files stay classic, and `GoldenParityTests` covers them. So no C# port is needed now. Port the layout when Windows copies prompts.

This replaces the Constraints lines of the design (`docs/superpowers/specs/2026-11-01-visual-direction-handoff-design.md`) that ask for the port before the flag turns on.

### Rollback

- One Mac: `scripts/nextshot-flags.sh set linkedPlan off`. For the production app, add `NEXTSHOT_FLAGS_DOMAIN=com.drewschulz.nextshot`.
- Everyone: set `releaseDefault: .off` in `FeatureFlags.swift` and ship a PATCH. A released file is never replaced.

### Open

- The paste hand tests belong to Part C of the design (`pasteAttachments`), not to this flag.
- The `releasedInBuild` number (924) is a guess at the 0.8.0 release commit's build. Nothing reads it at run time. Check it when the release is cut.
- The replay harness asks for a Links section even for rounds with fewer than three items. The app prompt drops that step below three items, as the 2-item round of the replay shows.
