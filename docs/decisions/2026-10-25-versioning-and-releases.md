# Nextshot versions and releases

**Correction, 2026-10-28:** Drew's 2026-10-27 rule permits only Nextshot Dev on m5pro. Production apps remain distribution artifacts there. Production installer checks require another approved Mac. This supersedes earlier instructions for local production checks. Follow [[local-development]].

Date: 2026-10-25. Decided by Drew in an interview session. This record replaces the "Scheme" section of [2026-10-22-nextshot-versions.md](2026-10-22-nextshot-versions.md) (date versions). The roadmap that carries it out is [docs/plans/2026-10-25-versioning-roadmap.md](../plans/2026-10-25-versioning-roadmap.md).

## Decision

| Topic | Decision |
|---|---|
| Numbering | SemVer 2.0.0, `MAJOR.MINOR.PATCH`. The number stays below 1.0.0 until the commercial launch. |
| First numbered release | 0.3.0. The changelog back-fills 0.1.0 (the 2026.10.22 build) and 0.2.0 (the 2026.10.24 build). No tags for those two. |
| Stage names | None. No Alpha or Beta word in the app, the DMG, or the site. The number carries the stage. |
| Build number | The commit count on `main` at the release commit. It only rises, because releases come only from `main`. |
| Trunk | `main`. It is fast-forwarded to `feature/feedback-sessions`. New PRs target `main`. |
| Tags | `nextshot-vX.Y.Z`, annotated, on the release commit. Capso's 65 tags (v0.9.3 to v1.2.5) stay untouched. |
| Cadence | Drew decides. One release command. No schedule. |
| Who releases | Only Drew, from his Mac. The signing certificate and the notary profile stay in his Keychain. |
| Your Mac | A separate app, Nextshot Dev, with its own bundle ID. It is the daily driver. It shares the rounds folder with the production app. |
| Audience | Anyone with the link. The site keeps its noindex header. |
| Archive | A private Cloudflare R2 bucket. The Worker serves every download. All versions stay. |
| Updates | Sparkle before 1.0. Manual DMG updates until then. |
| License | A named 1.0 gate, decided by 0.8. |

## Why

| Finding | Evidence |
|---|---|
| Date versions repeat. Three DMGs shared the version 2026.10.25. | `build/releases`: 73e99d2, 4ac4c2e, 0e66c27 |
| A date version cannot say "not yet 1.0". | Drew: 1.0 is when he starts to commercialize. |
| `main` was a frozen copy of upstream. | `origin/main` was at Capso's 1.2.5 release (2026-10-20), 216 commits behind `feature/feedback-sessions`. Every merged PR targeted `feature/feedback-sessions`. |
| The commit count broke across branches. | A trial build was 665 while a later release was 618 ([DMG decision](2026-10-25-dmg-install-and-update.md)). |
| One bundle ID for two kinds of build caused the grant re-asks and the overwrites. | Memory notes: signature switch, parallel local builds, installed build branch. |
| Capso's tags would collide with Nextshot tags. | 65 tags exist from v0.9.3 to v1.2.5. Nextshot reaches 0.9.x and 1.0.0. |
| The site picks a DMG by file time and a date-shaped name. | `site/deploy.sh` globs `Nextshot-20*.dmg`. |
| The license limits a paid 1.0. | Capso's Additional Use Grant bars a "Screen Capture Service". Change Date 2029-04-08. This reading is not legal advice. Get counsel before 1.0. |

## How a number is made

Two fields, two jobs.

| Field | Plist key | Example | Job |
|---|---|---|---|
| Version | `CFBundleShortVersionString` | 0.4.0 | What people read. Sparkle shows it. |
| Build | `CFBundleVersion` | 631 | What machines compare. Sparkle and `LaunchPlan` use it. |

- The `VERSION` file at the repo root holds the last released version. Only the release command edits it.
- A production build uses `VERSION` as it is. A Nextshot Dev build shows `VERSION` plus `-dev`, for example `0.3.0-dev (631)`.
- `scripts/nextshot-version.sh` reads `VERSION` and counts commits. The date no longer feeds the version.

### Bump rules

| Change since the last release | Bump | Example |
|---|---|---|
| Fixes only, nothing new to see | PATCH | 0.3.0 to 0.3.1 |
| A new thing a person can do | MINOR | 0.3.1 to 0.4.0 |
| A feature flag turns on in release | MINOR | 0.4.0 to 0.5.0 |
| A changed shortcut, folder, or format | MINOR | 0.5.0 to 0.6.0 |
| A new permission request | MINOR | 0.6.0 to 0.7.0 |
| A breaking change below 1.0 | MINOR | SemVer 2.0.0 item 4 allows it |
| The commercial launch | 1.0.0 | Drew decides |
| A change that ships hidden (flag stays off, docs, tests, scripts) | none | no release needed |

The release command reads the conventional commit prefixes since the last tag. A `feat:` suggests MINOR. A `fix:` suggests PATCH. Drew confirms or overrides.

## Names

| Item | Pattern | Example |
|---|---|---|
| DMG file | `Nextshot-<version>.dmg` | `Nextshot-0.4.0.dmg` |
| Zip file (Sparkle later) | `Nextshot-<version>.zip` | `Nextshot-0.4.0.zip` |
| Checksum | `<file>.sha256` | `Nextshot-0.4.0.dmg.sha256` |
| Volume name | `Nextshot <version> (<build>)` | `Nextshot 0.4.0 (631)` |
| Menu line in the app | `Nextshot <version> (<build>)` | `Nextshot 0.4.0 (631)` |
| Git tag | `nextshot-v<version>` | `nextshot-v0.4.0` |
| Archive path in R2 | `releases/<file>` | `releases/Nextshot-0.4.0.dmg` |
| Download links | `/download` is the latest. `/releases/<file>` is exact. | `nextshot.dev/releases/Nextshot-0.4.0.dmg` |

- The commit hash is out of the file name. It lives in `latest.json` and in the release notes.
- A pre-release, if one ever ships, follows SemVer: `Nextshot-0.5.0-rc.1.dmg`.
- Nobody renames a published file. A bad build gets a new PATCH.
- The two shipped date builds stay under their original names in `releases/legacy/`. Their plists say 2026.10.22 and 2026.10.24.

## Channels and identity

| | Production | Nextshot Dev |
|---|---|---|
| App name | Nextshot | Nextshot Dev |
| Bundle ID | `com.drewschulz.nextshot` | `com.drewschulz.nextshot.dev` |
| Signature | Developer ID Application | Apple Development |
| Build channel | `release` | `dev` |
| Made by | the release command | `scripts/build-local.sh` |
| Installed at | Another approved Mac, never m5pro | `~/Applications/Nextshot Dev.app` |
| Updates | Sparkle (from M3) | none |
| Feature flags | Jev flags stay off | Jev flags run here |

- Each copy has its own screen recording grant. A grant lasts from one production release to the next, and from one dev build to the next.
- `LaunchPlan` compares copies with the same bundle ID only. A production install never quits Nextshot Dev.
- Both apps claim the global hotkeys. On m5pro, install and run only Nextshot Dev. Run production release checks on another approved Mac.
- Both apps write rounds to `~/Library/Application Support/Nextshot`. A copy refuses rounds with a newer `schemaVersion`.

## Not decided yet

- The Sparkle update file: the zip or the DMG. The decision comes in M3.
- Whether Nextshot Dev gets a badge on its icon and a separate URL scheme. The plan assumes yes.
- When GitHub Actions turns on for tests only (M4).
