# License path, November 9, 2026

**Status: options drafted. The decision is pending. Drew makes it.** This record does not pick a path, and no part of it should be read as settled or as legal advice.

### Why this is open

Nextshot is a fork of [lzhgus/Capso](https://github.com/lzhgus/Capso), which is licensed under the Business Source License 1.1. The roadmap's M5 gate says "The license path is decided and carried out", due by 0.8. 0.8.0 shipped on 2026-11-08. **The gate is overdue.**

Three things depend on the answer and cannot proceed without it:

- a paid tier of any kind;
- the Terms of Service page;
- the price, and whether there is one.

The answer also decides whether Nextshot can keep shipping at all, which makes it larger than a pricing question.

### What the underlying license says

These are readings of the text in the repository and of the public BSL, not legal conclusions.

| Item | Reading | Confidence |
| --- | --- | --- |
| License | Business Source License 1.1, upstream Capso's | Verified in the repo |
| Change Date | 2029-04-08 | Verified in the repo |
| Change License | Apache 2.0 on the Change Date | Verified in the repo |
| Additional Use Grant | Personal use, internal organizational use, and non-commercial distribution | Verified in the repo |
| What that likely bars | Selling Nextshot as a competing screen-capture product, because a paid tier is commercial use outside the grant | **Inferred. Needs a lawyer.** |
| Trademark and logo | The BSL grants no right to Capso's name or logo, which is why Nextshot has its own mark | Verified in the repo (`docs/decisions/2026-10-22-nextshot-icon.md`) |
| Contributions | `CONTRIBUTING.md` states contributions are licensed under BSL 1.1 | Verified in the repo |

Two things follow that are worth stating plainly, because they are often assumed away:

1. **BSL is not open source on day one.** It is source-available. The Apache 2.0 conversion in 2029 is a real future grant, but until then the Additional Use Grant is the whole of the permission, and it is narrow.
2. **A paid tier is probably the specific thing the grant excludes.** The grant covers personal use and internal organizational use; a commercial distribution is neither. This is the crux of the decision and the one place where a lawyer's opinion matters more than any reading here.

### The defect that shipped, and its fix

This section records a defect that was live when this record was written and is now fixed. It is kept because the fix is part of the license path's history, and because the decision below is still open.

**As it stood.** The repository `LICENSE` file was **4 bytes containing the literal text `TBD`**. Commit `a069ecb` ("Update LICENSE", 2026-10-29) removed 71 lines of Capso's BSL 1.1 text and replaced them with that placeholder. `scripts/release-notarized.sh` copies `$repo/LICENSE` into `App/Contents/Resources/LICENSE.txt`, so **Nextshot 0.8.0, which shipped 2026-11-08, carries a license file that says "TBD"**. There was no `NOTICE` file, `CONTRIBUTING.md` still told contributors their work was licensed under BSL 1.1, and neither the site nor the guides credited the upstream author or named the license.

That was a compliance problem independent of which path this record chooses, for three reasons. The BSL requires the license to travel with copies of the Licensed Work. Its terms keep the licensor's and the Licensed Work's identity intact. And removing the license text outright is worse than an undecided path, because it leaves a recipient of the binary with no license at all.

**As it stands, 2026-11-09.** Branch `fix/restore-license-text`, commit `6de8a22` ("fix: restore the Business Source License text and credit upstream"), restores it:

- `LICENSE` is byte-identical to the pre-`a069ecb` BSL 1.1 text.
- A new `NOTICE` credits `lzhgus` and links the upstream repository.
- `scripts/release-lib.sh` gained `license_ready()`, and the `scripts/release.sh` preflight now refuses to run when the license text is missing, so the placeholder cannot ship again through the release command.
- `scripts/test-release.sh` has 10 new assertions guarding it (22 tests pass).
- `CHANGELOG.md` carries an `Unreleased` / `Fixed` line.

This record treats the text as restored from that branch onward. One consequence to keep straight: **0.8.0 is still out there carrying "TBD."** The fix changes what the next release ships, not what the last one did. Nothing here is republished — a released file is never replaced — so the remedy for 0.8.0 is the next release, plus the Sparkle path in M3 reaching people who already installed it.

None of this settles the question below. Restoring the text keeps the status quo honest; it does not decide whether Nextshot stays on the BSL, buys a grant, or is rebuilt. That decision is Drew's and is still pending.

### The three options

#### (a) Stay BSL 1.1 with the Apache 2.0 conversion, and ship free forever

Keep the upstream license. Drop any paid tier. Nextshot stays free for personal and internal use, and becomes Apache 2.0 in 2029 by operation of the same license.

**What it costs.** No revenue from the app, ever. The site stays free, which it already is. Hosting, notarization, and Drew's time are unpaid. Every future idea that needs money — a paid tier, a team plan, support contracts — is closed off until 2029 unless the license changes.

**What it preserves.** The simplest possible legal position: the code is used exactly as its licensor allows, and no permission is needed from anyone. It also matches what the product already says. The site's footer reads "Free for personal and internal use", which is close to the grant's own words. This is the only option with zero legal work and zero dependency on another person.

**What it forecloses.** A commercial launch before 2029. If Nextshot later wants to charge, the decision has to be reopened from scratch.

#### (b) Negotiate a commercial grant from the upstream maintainer

Ask lzhgus for a separate commercial license or an amended Additional Use Grant that permits selling Nextshot.

**What it costs.** A negotiation with one person, on his schedule, for a grant he has no obligation to give. Possibly money, possibly a revenue share, possibly nothing if he declines. Realistically this is weeks to months, and it can end in "no" with nothing to show. It also creates a continuing dependency: the terms are whatever the two of you agree, and they need to be written down well enough to survive a later disagreement.

**What it preserves.** The current codebase, with no rebuild. If lzhgus agrees, this is the cheapest path to a paid tier by a wide margin.

**What it risks.** The ask is unusual. It is a request to compete with the licensor's own product in the licensor's own category, using the licensor's code. A refusal is the likely outcome and should be planned for rather than discovered.

#### (c) Clean-room rebuild the parts that must be relicensed

Rewrite the portions of the codebase whose license blocks the intended use, so the result is unencumbered.

**What it costs.** The most work by far, measured in months. `App/Sources/` is the substantial upstream-derived half of the product — the capture pipeline, the annotation editors, the recording stack, OCR, the settings and menu bar shell. Nextshot's own work is one half; the other half is inherited. A clean-room rebuild means reproducing a mature macOS capture and annotation app from a specification, with the associated risk of regressing behavior that already works and is already tested.

**What it preserves.** Full freedom afterward. No permission needed, no ongoing dependency, and the result can be licensed however Drew wants.

**What it risks.** Months of work that ships no user-visible improvement during a period when, by the roadmap's own numbers, the product needs distribution work more than it needs legal freedom. It also has to be done carefully to be worth anything: a rebuild that copies upstream structure is not clean-room and gains nothing.

### Recommendation

**Not a decision, but a ranking for Drew to react to.**

If the goal is a paid product in the next year, **(b) before (c)**. Asking lzhgus costs one message and can be done in parallel with everything else; a rebuild cannot start sensibly until the ask has failed. Doing (c) first would spend months buying freedom that (b) might have granted for free.

If the goal is to keep improving the app for the people already using it, **(a)**. It requires no one's permission, it matches what the site already promises, and the M5 gate closes with a dated note that says "free". It also leaves the door open: (a) is reversible in 2029 by the license's own terms, and reversible earlier if Drew later negotiates.

The honest observation is that the distribution numbers argue for (a) right now. 157 downloads lifetime and 1 to 4 people a day does not describe a product with a pricing problem; it describes one with a reach problem. A paid tier is a way to earn from demand that does not yet exist.

### What would change the recommendation

- **Evidence of willingness to pay.** People asking to pay, or a competitor charging successfully for this class of tool. This moves (b) to the front.
- **A "no" from lzhgus.** Retires (b). The choice becomes (a) or (c), and (a) is free.
- **A lawyer's reading that a paid tier is inside the Additional Use Grant.** Retires the problem entirely. This is the single highest-value thing to check, because it is cheap and could collapse the whole question.
- **A partner, an acquisition conversation, or outside investment.** Any of these forces the license question and generally favors (c).
- **The 2029 Change Date arriving with the product still alive.** (a) resolves itself into Apache 2.0 with no action.

### What is needed to close the gate

1. A lawyer's opinion on whether a paid tier falls inside or outside the Additional Use Grant. Nothing else should be decided before this, because it is cheap and may make the choice trivial.
2. The `LICENSE` file restored to correct text. Independent of the decision.
3. Drew's choice, written into this record with a date.

### Notes

- Nothing here is legal advice. Every reading of the BSL above should be confirmed by counsel before 1.0.
- The upstream project's own position on forks selling competing products has not been tested, and this record does not speculate about it.
- If (b) is pursued, the conversation is with one person and the request is concrete: an amended grant, or a commercial license, that permits a paid Nextshot.
