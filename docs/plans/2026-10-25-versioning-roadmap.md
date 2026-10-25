# Versioning and release roadmap

Date: 2026-10-25. Owner: Drew. The decisions are in [docs/decisions/2026-10-25-versioning-and-releases.md](../decisions/2026-10-25-versioning-and-releases.md). This plan turns them into milestones. Nothing here is built yet.

## Where we are

If Nextshot went to market today, the build would be 0.3.0. The history reads:

| Version | What people got | Date |
|---|---|---|
| 0.1.0 | The first shared DMG, labeled 2026.10.22 | 2026-10-22 |
| 0.2.0 | Rounds, flags, and the round rename, labeled 2026.10.24 | 2026-10-24 |
| 0.3.0 | The in-place DMG installer and update, labeled 2026.10.25 | next release |

The site shows "Version 2026.10.24" and has served 45 downloads to people (27 for 2026.10.22, 18 for 2026.10.24).

## What the user sees

Seamless for the user is the first test of every step. This is the target journey.

| Moment | Today | After M2 | After M3 |
|---|---|---|---|
| First install | Open the DMG, double-click or drag, answer Open once, grant screen recording once | Same | Same |
| Learning that a new version exists | Drew tells them | Drew tells them | The app says "Version 0.4.0 is available" |
| Updating | Download the new DMG, double-click the app on the image, answer Install | Same, with a clean file name | One click on "Install and Relaunch" |
| After an update | Screen recording grant stays | Same | Same |
| Wrong build, need to go back | Ask Drew for the old file | Download from `/releases/` | Same |
| Which version do I have? | Menu line, for example "Nextshot 2026.10.24 (524)" | "Nextshot 0.3.0 (625)" | Same |

The version string reads the same in five places: the menu line, the DMG volume name, the DMG file name, the site, and the changelog.

## Milestones

Names follow the `Mn: Title Case Name` rule. The order follows the dependencies.

### M1: Versioning Foundation

Goal: one trunk, one number source, and a Dev app that cannot disturb the production app. Ships no DMG.

| Task | Size | Done when |
|---|---|---|
| Fast-forward `main` to `feature/feedback-sessions`. Retarget open PRs to `main`. Update AGENTS.md and the memory note about the worktree base. | S | `git rev-list --left-right --count origin/main...origin/feature/feedback-sessions` prints `0 0`. A new PR defaults to `main`. |
| Add `VERSION` (0.3.0 for the first release, set to 0.2.0 until then) and rewrite `scripts/nextshot-version.sh` to read it. | S | A build shows `0.2.0-dev (N)` in the Nextshot Dev menu line. |
| Switch `LaunchPlan` to compare the build number first. Add the cases: 0.3.0 (625) beats 2026.10.24 (524), and the reverse exits. | S | `LaunchPlanTests` pass with the new cases. |
| Create Nextshot Dev: a second spec in `scripts/`, new bundle ID, name, icon badge, and a separate URL scheme. Change `build-local.sh` to install it as `~/Applications/Nextshot Dev.app`. | M | Both apps run one after the other. Each keeps its own screen recording grant across a rebuild. |
| Move the flags script default domain to the Dev bundle ID. Replace the six hardcoded bundle ID strings in loggers with `Bundle.main.bundleIdentifier`. | S | `scripts/nextshot-flags.sh list` shows the Dev app's flags. `FeatureFlagsTests` pass. |
| Add the `schemaVersion` guard: a copy refuses rounds from a newer schema and says why. | S | A test with a round at schema +1 shows the message and loads nothing. |
| Set `remote.upstream.tagOpt` to `--no-tags`. Add a test or script check that no Nextshot tag lacks the `nextshot-v` prefix. | S | `git fetch upstream` adds no tags. |
| Move the two Capso 1.2.5 DMGs out of `build/releases` into `build/releases/legacy/`. | S | `site/deploy.sh --stage-only` picks no 1.2.5 file. |
| Write `CHANGELOG.md` in Keep a Changelog 1.1.0 format, with 0.1.0, 0.2.0, and an `Unreleased` section. Log the new root files in FORK_NOTES. | S | The file exists and lists the three versions. |

Order inside M1: trunk first, then `VERSION` and `LaunchPlan`, then the Dev app, then the rest.

### M2: One-Command Releases

Goal: `scripts/release.sh` takes a bump and ends with a live, archived, rollback-ready version.

The command runs these steps and stops at the first failure.

1. **Preflight.** HEAD is `main` and equals `origin/main`. The tree is clean. Tests pass for FeedbackKit, JevKit, and CapsoTests. The Developer ID certificate, the notary profile, and the R2 token exist.
2. **Bump.** The command proposes a bump from the commit prefixes since the last tag. Drew confirms. It writes `VERSION`, moves `Unreleased` to the new version with today's date, commits `chore: release X.Y.Z`, and tags `nextshot-vX.Y.Z`.
3. **Build.** Archive, sign, notarize, staple, and pack the DMG and the zip. This reuses the work in `scripts/release-notarized.sh`, with names from `VERSION`.
4. **Archive.** Upload the DMG, the zip, the checksum, and the notes to R2 under `releases/`. Verify the uploaded hash.
5. **Check.** Run `stapler validate`, `spctl`, and a mount test on the archived DMG.
6. **Ask once.** The command prints the version, the build, the notes, and the hash. Drew answers yes or no.
7. **Promote and push.** The command writes `latest.json` in R2, pushes `main` and the tag, and runs the live smoke test.

| Task | Size | Done when |
|---|---|---|
| Create the R2 bucket and bind it to the Worker. Serve `/releases/<file>` from R2 with Range support. Make `/download` follow `latest.json`. | M | `curl` on `/download` redirects to the file named in `latest.json`. The hash matches. |
| Group `/stats` by the new version strings. Keep the legacy date versions as their own rows. | S | `/stats` shows 0.3.0 apart from 2026.10.24. |
| Write `scripts/release.sh` with the seven steps and a `--dry-run` that stops before step 4. | L | A dry run on a scratch clone prints the plan and changes no remote. |
| Add `scripts/release.sh --promote <version>` to point `latest.json` at an older version. | S | A rollback test flips `/download` back and forth in under a minute. |
| Replace the date glob in `site/deploy.sh` with the pointer file. The script then deploys the page only. | S | A page change deploys without touching a DMG. |
| Run the bridge test: install the 2026.10.24 build, then run the 0.3.0 image copy. | M | The 2026.10.24 copy quits. 0.3.0 replaces it in place and opens. The old image ejects. Screen recording stays granted. |
| Cut 0.3.0 with the command. | S | nextshot.dev shows "Version 0.3.0". The R2 archive holds the file, the zip, and the checksum. |
| Move the two shipped date DMGs to `releases/legacy/` in R2. | S | The old links, if any, still resolve. |

Until M2 ends, a release uses the existing scripts with the new names, by hand. Drew can do that for 0.3.0 if the command is late.

### M3: Automatic Updates

Goal: a person who installed 0.3.x or later gets new versions without a new download.

Findings first. The app already carries the Sparkle framework, an `UpdateManager`, and a Preferences update screen. Info.plist holds Capso's `SUPublicEDKey` and no `SUFeedURL`. The fork must not trust Capso's key, because Nextshot does not hold the matching private key.

| Task | Size | Done when |
|---|---|---|
| Make a Nextshot EdDSA key pair with Sparkle's tool. Store the private key in the Keychain as `SPARKLE_ED_PRIVATE_KEY_NEXTSHOT`. Back it up in 1Password. | S | The public key is in hand. A restore test signs a file. |
| Replace `SUPublicEDKey` and add `SUFeedURL` (`https://nextshot.dev/appcast.xml`) for the production target only. Log the Info.plist edit in FORK_NOTES. | S | The Dev app has no feed. The production app has one. `UpdateManagerTests` pass. |
| Have the release command sign the zip, write `appcast.xml` with the build number and the notes, and upload it. | M | `appcast.xml` validates with Sparkle's tool. |
| Turn automatic checks on for production. Add the "Check for Updates" menu row if it is missing. | S | A production 0.4.0 copy offers 0.4.1 within a day of the release. |
| Test the full path: 0.3.0 installs, 0.4.0 publishes, the app updates itself, and the screen recording grant stays. | M | Two real releases update in place with no prompt beyond Sparkle's own. |

Rules that never change once a build with them ships: the bundle ID, the feed URL, and the EdDSA public key. A lost private key strands every installed copy.

People on 0.3.0 and earlier update by hand once, to the first Sparkle build.

### M4: Collaborator Readiness

Goal: another person can contribute and Drew can still release.

| Task | Size | Done when |
|---|---|---|
| Add `docs/releasing.md`: the runbook, the recovery steps for the certificate and the keys, and the rollback steps. | S | A second person can follow it on paper. |
| Add a PR rule: a user-facing change adds one line under `Unreleased` in `CHANGELOG.md`. Check it in a PR template. | S | The template shows the line. |
| Turn on GitHub Actions for tests only: FeedbackKit, JevKit, and the CI package set. No signing in CI. | M | A PR shows a test result. |
| Back up the Developer ID certificate (.p12) and the notary credentials in 1Password. | S | A restore test on a clean Keychain signs an app. |
| Add `CODEOWNERS` so `scripts/release.sh`, `VERSION`, and `CHANGELOG.md` need Drew's review. | S | A PR that edits `VERSION` asks Drew. |
| Decide whether a CI release job is worth its risk. | S | A short note in `docs/decisions/`. |

### M5: 1.0 Readiness

Goal: every gate is true. Then Drew decides the date. 1.0.0 is a decision, not an event the scripts trigger.

| Gate | Check |
|---|---|
| The license path is decided and carried out: a commercial grant from lzhgus, the clean-room rebuild, or staying free. Decided by 0.8. | A signed grant, a rebuilt codebase, or a dated note that says "free". |
| Sparkle updated at least two real releases in place. | The M3 test, repeated on a clean Mac. |
| The scope is frozen: every flag is on in release, removed, or documented as dev-only for good. | `FeatureFlag` has no entry with an open decision. |
| No open `sev-blocker` or `sev-bug` issue. | `gh issue list` with those labels returns nothing. |
| Terms, price, and support are written. | A page on the site and a support address. |
| The previous release updates to 1.0.0 with no prompt beyond Sparkle's. | A recorded test. |

Expected path (a guide, not a promise): 0.3 is the numbered start, 0.4 adds Sparkle, 0.8 holds the license decision, 0.9 freezes scope, 1.0.0 launches.

### Later

- Delta updates in Sparkle, when download size starts to matter.
- A CI release job.
- A Windows build, with its own version line.
- A beta channel in the appcast for testers.

## Release day, as it will read

| Step | Command or action |
|---|---|
| Decide | Drew picks the moment. |
| Run | `scripts/release.sh`. Notarization is the slow part. |
| Confirm | Drew reads the version, notes, and hash, and answers yes. |
| Check | The command's live smoke test passes. Drew installs the DMG on a Mac and sees the new version in the menu. |
| Tell | Drew shares the link, or Sparkle does it after M3. |

A bad release gets a rollback first (`--promote` the old version), then a new PATCH. Nobody edits a published file.

## Risks

| Risk | Plan |
|---|---|
| Fast-forwarding `main` is a push. | Ask Drew at the start of M1. Run `github-route status` first. |
| The first production DMG on Drew's Mac replaces a dev-signed copy that has the production bundle ID. | Expect one more screen recording prompt, once. After that, the split removes the prompts. |
| The version drop from 2026.10.24 to 0.3.0 confuses a version-first comparison in old copies. | Old copies have no `LaunchPlan`. The new copy on the image does the replacing and compares builds. The bridge test proves it. |
| `SUPublicEDKey` in Info.plist is an upstream file. | Log the edit. Keep it a one-line change at the hook point. |
| One person holds all the signing keys. | M4 backs them up and writes the recovery steps. |
| The DMG grows past 25 MiB. | R2 has no such limit. The Worker streams from R2. |
| The license may bar a paid launch. | The 1.0 gate decides it by 0.8. The numbering works with any answer. |

## Open questions

- Sparkle update file: the zip or the DMG. Decide in M3.
- Release notes tone and length. Draft them with the first release.
- Whether the Dev app shows a visible "Dev" badge in the menu bar mark. The plan assumes yes.
