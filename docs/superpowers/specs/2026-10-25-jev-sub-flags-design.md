# Jev sub-feature flags: design

Date: 2026-10-25. Part of #34. Builds on the flag design (`2026-10-24-feature-flags-design.md`) and the Jev base (`2026-10-24-jev-base-design.md`).

## Why

Drew will review every Jev feature in one dev build, then decide which parts to keep (Drew, 2026-10-25). He asked that "all of these need to be behind feature flags with sub-feature flags as well" and that the default "need to be off on all of these new features". A sub-flag lets him turn on one part of a feature, for example the conflict flag without the duplicate merge, and judge it alone.

## Decisions

| Decision | Who |
| --- | --- |
| Every Jev feature gets sub-flags, with the split in the table below. | Drew, 2026-10-25 |
| A sub-flag defaults off in dev and release, is dev-only, and allows off, shadow, and on. | Drew, 2026-10-25 |
| A sub-flag runs at the lower of its own state and its parent's state (off, then shadow, then on). | Drew, 2026-10-25 |
| The sub-flags reuse the job option hook that data guard added in `bc53a43` (`JevJob.options`, `JevJobContext.optionModes`). This PR ports its generic part unchanged. | orchestration call |
| The runner applies the cap, so a job never compares states itself. | orchestration call |
| A job sends no request when every sub-flag that needs Jev is off after the cap. | orchestration call |
| The flags script gets a `feature` command that sets or resets a parent and all its sub-flags in one step. | orchestration call |
| Each sub-flag carries its parent's issue number. | orchestration call |

## The split

| Feature | Parent flag | Sub-flags | Where it lands |
| --- | --- | --- | --- |
| Note coach (#37) | `noteCoach` | `noteCoachVague`, `noteCoachQuestion`, `noteCoachEmpty` | this PR |
| Crops and search lines (#38) | `cropsAnchors` | `cropsItemCrops`, `cropsSearchLines` | this PR |
| Duplicates and conflicts (#39) | `dupesConflicts` | `dupesMerge`, `dupesConflict` | registry in this PR, job gating in PR #68 |
| Lanes and priority (#69) | `promptLanes` | `lanesOrder`, `lanesSplit` | PR #82 |
| Injection and data guard (#70) | `dataGuard` | `dataGuardContact`, `dataGuardNumbers`, `dataGuardSecrets`, `dataGuardFaces` (exist on PR #83), `dataGuardInjection` (new) | PR #83 |

`promptLanes` and `dataGuard` are not on `feature/feedback-sessions` yet, so their sub-flags register on their own branches.

## What each sub-flag gates

- `noteCoachVague`: the "Ask the reviewer first: the note names no change." line for a vague note.
- `noteCoachQuestion`: the "Answer this item. Change no code." line for a question.
- `noteCoachEmpty`: the "Ask the reviewer first: the item has no note." line for an empty note. It needs no Jev request.
- `cropsItemCrops`: the two crop PNGs per item (`<stem>-item-<N>.png` and `-clean.png`) and their lines in the refined file.
- `cropsSearchLines`: the search line per item. It still needs `jevSendScreenText`.
- `dupesMerge`: the merged item with "seen in" references.
- `dupesConflict`: the "Ask Drew first" conflict block.
- `lanesOrder`: the severity order (worst first) in the "Order and lanes" section.
- `lanesSplit`: the lane A and lane B split for a fast and a strong model.
- `dataGuardInjection`: the flag on screen text aimed at an AI agent.

## How the states combine

- The runner reads each option flag once, when the capture starts, with the other flags (as `bc53a43` does).
- `optionModes[sub]` = the lower of the sub-flag's state and the job flag's state. Order: off, shadow, on.
- Shadow writes the sub-feature's answers to `jev.json` and the job's review file only. On also writes its refined lines. The files on disk (`prompt.md`, `<stem>-prompt.md`) never change.
- A parent with every sub-flag off after the cap runs nothing. The runner does not start the job, so there is no key read, no stored work, no request, no file, and no round-end wait. This replaces the first draft, "runs the job but produces nothing", after a review on 2026-10-25.
- `JevGate` follows the same rule. A job with options runs only when an option is shadow or on after the cap, and its prompts point to refined files only when its flag is on and an option is on. A parent in on with every sub-flag in shadow runs and records, and changes no copied prompt.
- A sub-flag alone, with its parent off, runs nothing.
- App code that reads a sub-flag directly (lanes builds its section at round end) uses one shared helper with the same rule: `FlagResolver.effectiveState(of:...)` in FeedbackKit, and `Flags.effectiveState(.name)` in the app.

## Registry

- `FlagSpec` gets `parent: FeatureFlag?` (nil for a parent or a consent flag). `FeatureFlag.subFlags(of:)` lists a parent's sub-flags in registry order.
- In the enum, a parent's sub-flags come right after the parent, so `list` shows them together.
- `FeatureFlagsTests` proves: every sub-flag is dev-only, defaults off in both channels, allows off, shadow, and on, has a parent, and carries its parent's issue. The cap holds for all nine state pairs.

## Flags script

- `scripts/nextshot-flags.sh feature <parent> <state>` sets the parent and each sub-flag to that state. It refuses a flag that is not a parent with sub-flags.
- `scripts/nextshot-flags.sh feature <parent> reset` removes the overrides of the parent and of each sub-flag.
- The `FLAGS=` line keeps one entry per flag, in registry order. The test that compares it with the registry still applies.

## Trial steps change

A feature now needs its parent and its sub-flags. Docs that say `set noteCoach shadow` change to `feature noteCoach shadow`. AGENTS.md, the bundle guide, and each feature's design doc get the new line.

## Out of scope

- Any interface for flags. Flags stay hidden.
- Any change to release defaults. Every flag stays off in release, and every Jev flag stays dev-only.
