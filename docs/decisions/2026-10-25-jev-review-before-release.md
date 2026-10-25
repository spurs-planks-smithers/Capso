# Jev features: a dev-build review before any release

Date: 2026-10-25. Decided by Drew. Part of #34.

## Context

On 2026-10-25 a notarized test DMG, build 700 (`Nextshot-2026.10.25-e9e33da.dmg`), was made from `trial/combined-1025`. That branch merged `trial/zip-jev-combined`, so the DMG holds the job code of three Jev features whose PRs are still open: duplicates and conflicts (PR #68), lanes and priority (PR #82), and injection and data guard (PR #83). Their flags read off in a release build, but the code ships.

## Decisions

1. **No unreviewed Jev feature goes into a release build.** Drew's words: "Don't put any of the new features in the new build. We're going to review them comprehensively in a dev build and decide which to include."
2. **Build 700's DMG is never published.** It stays a local test (Drew chose "Never publish it").
3. **PRs #68, #82, and #83 stay open until Drew's dev-build review.** A feature PR merges only after the review keeps it.
   - Correction (Drew, 2026-10-25, about 1:10 pm): PR #68 merged at 12:48 pm on Drew's word in the dupes session. Drew then ruled that the dupes offline eval (`docs/evals/2026-10-24-dupes-conflicts-eval.md`) counts as its review. PRs #82 and #83 still stay open until the review.
   - Correction (Drew, 2026-10-25, evening): merge every Jev PR now (#83, #97, #99, #98, #82), ready for tonight's versioning and release work. Drew's words: "All of these features need to be off for the foreseeable future by feature flags." Every Jev flag and sub-flag defaults off in dev and release builds and is dev-only, so a release build cannot turn one on. The dev-build review still decides which features ever turn on.
4. **Every Jev feature gets sub-feature flags.** Each sub-flag defaults off, is dev-only, and runs at the lower of its own state and its parent's. Design: `docs/superpowers/specs/2026-10-25-jev-sub-flags-design.md`.
5. **New Jev feature sessions wait for the review.** The repo and skill router (idea 13) and the wrong-badge check (idea 2) start after it (Drew chose "After the review").

## Consequences

- A public DMG for nextshot.dev comes from a branch without the unmerged Jev work.
- The review build is one dev build from `integration/jev-trials`. It installs after Drew's DMG installer test.
- A DMG rebuilt today from a branch with fewer commits has a build number below 700. On a Mac that runs build 700, it says "up to date" and does not install (`LaunchPlan` compares the version date, then the build number).
