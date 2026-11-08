# Linked plan prompt on by default, November 6, 2026

Issue 261. The `linkedPlan` flag merged off in both channels (PR 262, 2026-11-06; the replay ran on 2026-11-01). Drew decided on 2026-11-06 to turn it on in both channels for release 0.8.0.

### Decision

Copied prompts use the linked layout by default. This covers the round prompt, the capture prompt, and the selection prompt.

- A ledger lists every item in the reviewer's own words.
- With three or more items, a Links step groups related items under one shared decision.
- The plan table has the columns item, group, place, and change (item, place, and change below three items).
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

Three changes came after the first runs. The re-run below exercised the Plan step sentence. The ask line and the selection heading are in the final prompt, but these four rounds do not exercise them (no replayed capture lacks both an item and a note, and the replay uses the round prompt, not the selection prompt).

- The Plan step gained the sentence "Make no edit before this table is in your reply."
- A capture with no items and no note gets a line that tells the agent to ask.
- The selection ledger heading lost the word "below".

### Re-run on the final prompt (2026-11-06)

The 24 linked runs were repeated on the final prompt: same rounds, models, and run counts, all 24 ok. The today baseline is the 2026-11-01 runs, not re-run. Drew chose default-on after the first replay. The re-run changes none of the pass or fail verdicts. Report section: "Re-run on the final prompt (2026-11-06)" in `docs/evals/2026-11-01-linked-plan-replay.md`.

- Coverage: 100.0% for both agents.
- Tokens, linked over today: Claude 1.02 times, Codex 1.22 times (bar 1.3; the Codex tool version differs). Codex was 0.84 times in the first run.
- Group fit: Claude 3.00 against 2.45, Codex 3.75 against 3.13.
- Question bar: Claude 0.0%, Codex 50.0%, against 90%. It fails again.
- The Codex tool version also changed between the runs. The cause of the Codex token rise (tool version, final prompt text, or chance) is not known.

### Windows

The Windows app has no copy-prompt path. Its only `PromptBuilder` callers write files on disk (`BundleTextRenderer`) and zips (`ZipText`, `ZipWriter`). A search of `Windows/` on 2026-11-06 found no clipboard call. These files stay classic, and `GoldenParityTests` covers them. So no C# port is needed now. Port the layout when Windows copies prompts.

The design (`docs/superpowers/specs/2026-11-01-visual-direction-handoff-design.md`) asks for the port before a flag turns on, in Constraints and Left to the builder. That rule stays for the day Windows copies prompts. The port is deferred because Windows has no copy path today.

### Rollback

- One Mac: `scripts/nextshot-flags.sh set linkedPlan off`. For the production app, add `NEXTSHOT_FLAGS_DOMAIN=com.drewschulz.nextshot`.
- Everyone: set `releaseDefault: .off` in `FeatureFlags.swift` and ship a PATCH. A released file is never replaced.

### Open

- Hand tests T1, T4, and T6 (design, Proposed order step 1) are not done. T4 matters here: it finds the pasted-text length at which Claude chat turns a paste into an attachment, and the linked prompt is longer than the classic one. Run them before the 0.8.0 release. Drew decides whether they block the release.
- Release prep: before `scripts/release.sh`, add the UTC date line under `## 0.8.0` in `site/guides/src/content/docs/release-notes.mdx` (format as the neighbors). Raise `reviewedFor` on `release-notes.mdx` and, after the Dev app check, on `first-handoff.mdx`, `connect-agent.mdx`, and `troubleshooting.mdx`. Recheck the marker (`git rev-list --count HEAD` at the release commit) and the release-notes bullets against the final CHANGELOG line. A Guides-only deploy between the merge and the 0.8.0 release would publish 0.8.0 text to 0.7.0 users.
- The `releasedInBuild` number (924) is a guess at the 0.8.0 release commit's build. Nothing reads it at run time. Check it when the release is cut.
- 2026-11-08 (Drew, issue 281): `scripts/release.sh` now writes the UTC date line under `## 0.8.0` and sets the marker to the release commit's build. The two hand steps above (the date line and the marker check) are no longer needed. The `reviewedFor` raises stay by hand. Drew also decided on 2026-11-08 that hand tests T1, T4, and T6 do not block 0.8.0.
- The replay harness asks for a Links section even for rounds with fewer than three items. The app prompt drops that step below three items, as the 2-item round of the replay shows.
