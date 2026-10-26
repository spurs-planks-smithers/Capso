# Jev dev-build review: checklist

For Drew, 2026-10-25. Every Jev PR is merged into `feature/feedback-sessions` (Drew, 2026-10-25 evening), and every Jev feature is off by its flags for the foreseeable future. Each flag and sub-flag defaults off and is dev-only, so a release DMG reads it as off. This review decides, per feature and per sub-flag, which parts ever turn on. Use a dev build (`scripts/build-local.sh`), never a release DMG, because a release build ignores every Jev override.

## How to turn a feature on

Run the flags script from the repository root, on a checkout that has the sub-flags (`main` since 2026-10-25). Set one feature at a time, and reset it before the next.

```bash
scripts/nextshot-flags.sh set jevBase on
```

- A whole feature: `nextshot-flags.sh feature <parent> shadow`, then `feature <parent> on`, then `feature <parent> reset`.
- One part only: after `feature <parent> on`, run `set <sub-flag> off` for the parts you want to hide.
- Consent: `set jevSendScreenText on` sends screen text, and `set jevSendImages on` sends images. Both are off unless you set them.
- At the end: `reset jevBase` and any consent flag you set.
- Shadow writes only `jev.json` and `jev-review/<job>.md` in the round folder. On also changes the copied prompts.

## The features

| Feature | Parent flag | Sub-flags | Consent it needs | Status |
| --- | --- | --- | --- | --- |
| Note coach (#37) | `noteCoach` | `noteCoachVague`, `noteCoachQuestion`, `noteCoachEmpty` | none | PR #66; sub-flags (PR #97) not tried live yet |
| Crops and search lines (#38) | `cropsAnchors` | `cropsItemCrops`, `cropsSearchLines` | search lines: screen text; Jev crop check: images | PR #65; sub-flags (PR #97) not tried live yet |
| Duplicates and conflicts (#39) | `dupesConflicts` | `dupesMerge`, `dupesConflict` | screen text (required) | PR #68, Release fix PR #99; Part B passed on build 723 |
| Lanes and priority (#69) | `promptLanes` | `lanesOrder`, `lanesSplit` | none | PR #82; trial #74 passed |
| Injection and data guard (#70) | `dataGuard` | `dataGuardInjection`, `dataGuardContact`, `dataGuardNumbers`, `dataGuardSecrets`, `dataGuardFaces` | local rules: none; Jev checks: screen text, images | PR #83; trial #80 passed (local rules only) |

One-breath notes (#40) stays paused, with its flag locked off.

## What each part does, and where to look

| Sub-flag | In on, it adds | Look at |
| --- | --- | --- |
| `noteCoachVague` | "Ask the reviewer first: the note names no change." | `<stem>-refined.md` |
| `noteCoachQuestion` | "Answer this item. Change no code." | `<stem>-refined.md` |
| `noteCoachEmpty` | "Ask the reviewer first: the item has no note." | `<stem>-refined.md` |
| `cropsItemCrops` | two crop PNGs per item | `<stem>-item-<N>.png`; shadow: `scripts/jev-review-crops-anchors.py` |
| `cropsSearchLines` | one search line per item | `<stem>-refined.md` |
| `dupesMerge` | "Same ask" and "may overlap" lines | round section of `refined.md` |
| `dupesConflict` | "Ask first" lines | round section of `refined.md` |
| `lanesOrder` | items worst first | the copied round prompt |
| `lanesSplit` | lane A (small exact edits, for a fast model) and lane B | the copied round prompt |
| `dataGuardInjection` | a warning about screen text aimed at an AI agent | `<stem>-refined.md` |
| `dataGuardContact`, `Numbers`, `Secrets`, `Faces` | solid covers in `<stem>-covered.png` | the covered PNG |

## Open points from the trials

1. Lanes: the haiku subagent path (3 or more lane A items) was not tried live.
2. Lanes: 1.6 (the logo link) rated blocker. A missing link may be a bug on your scale.
3. Lanes: notes with exact copy text rated low on exact (0.17, 0.34).
4. With a feature on, a copied prompt can name a refined file that no job wrote. The prompt says "if it exists", so an agent skips it.
5. Data guard: the Jev questions (screen text, images) were not tried. Window and tab titles stay uncovered by design.
6. Note coach and crops with their new sub-flags: not tried live.

## After the review

- To keep a part: it stays as it is, off by default. Turning one on for other people needs a key plan for their Macs and a release default with a released-in build number (see the flag design).
- To drop a part: leave its flag off. Removing its code is a separate change.
- Before any trial build, run the JevKit tests in Release too (`swift test -c release -Xswiftc -enable-testing --package-path Packages/JevKit`). A Release-only bug lost dupes results on 2026-10-25.
