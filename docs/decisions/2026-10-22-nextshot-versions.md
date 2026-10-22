# Nextshot versions and updates

Date: 2026-10-22. Decided by Drew.

## Decision

- Updates stay manual. Each person installs a new notarized DMG over the old app. Sparkle stays off. Self-serve updates are backlog issue [spurs-planks-smithers/Capso#4](https://github.com/spurs-planks-smithers/Capso/issues/4).
- Nextshot gets its own version numbers, so people can tell builds apart. Before this, every build said 1.2.5 (66), upstream's numbers.

## Scheme

| Field | Value | Example |
|---|---|---|
| Version (`CFBundleShortVersionString`) | Date of the HEAD commit, year.month.day | 2026.10.22 |
| Build (`CFBundleVersion`) | Commit count on HEAD | 489 |

`scripts/nextshot-version.sh` computes both. `scripts/build-local.sh` and `scripts/release-notarized.sh` pass them to xcodebuild, so only the Nextshot build changes. Upstream's `project.yml` keeps Capso's numbers.

## Why this scheme

- **No manual bump.** Every release gets a new number by itself, so no one can forget a bump.
- **Plain to read.** A newer date is a newer build. Employees can compare dates without a changelog.
- **Two builds on one day** still differ, by build number and by the commit in the DMG's file name.
- **Ready for Sparkle.** The build number rises with each commit on a branch, as Sparkle requires.
