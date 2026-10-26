# Versioning and release roadmap

Date: 2026-10-25. Owner: Drew. The decisions are in [docs/decisions/2026-10-25-versioning-and-releases.md](../decisions/2026-10-25-versioning-and-releases.md). This plan turns them into milestones. Nothing here is built yet.

## Where we are

Nextshot 0.3.0 shipped on 2026-10-25. The history reads:

| Version | What people got | Date |
|---|---|---|
| 0.1.0 | The first shared DMG, labeled 2026.10.22 | 2026-10-22 |
| 0.2.0 | Rounds, flags, and the round rename, labeled 2026.10.24 | 2026-10-24 |
| 0.3.0 | The in-place DMG installer and update (build 751) | 2026-10-25 |

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

The command runs these steps and stops at the first failure. Build and check come before the question, so nothing is public until Drew answers. The steps as built (the first draft put the archive before the question):

1. **Preflight.** HEAD is `main` and equals `origin/main`. The tree is clean. Tests pass for FeedbackKit, JevKit, and CapsoTests. JevKit also passes in Release (`swift test -c release -Xswiftc -enable-testing --package-path Packages/JevKit`), because an optimizer bug lost a dupes result in Release only on 2026-10-25 and every Debug test passed. The Developer ID certificate, the notary profile, the GitHub route, and R2 are ready. `CHANGELOG.md` has an entry under Unreleased.
2. **Bump.** Drew names the bump (`patch`, `minor`, `major`, or `X.Y.Z`). With no name, the command suggests one from the commit prefixes since the last tag and stops. It moves `Unreleased` to the new version with today's date, writes `VERSION`, commits `chore: release X.Y.Z`, and tags `nextshot-vX.Y.Z`. Both stay local.
3. **Build.** `scripts/release-notarized.sh`: sign, notarize, staple, DMG, zip.
4. **Check.** Stapled ticket, Gatekeeper, and a mount test: bundle ID, version, build, and signature of the app inside the image.
5. **Ask once.** The version, build, hash, and notes. Anything but `y`, a closed stdin, or no terminal stops the run, and the local commit and tag are undone.
6. **Archive, push, promote.** Upload the files to R2 and read the DMG back. Push `main` and the tag. Point `latest.json` at the new record. Run the smoke test. If it fails, `latest.json` goes back to the version it replaced.

Status on 2026-10-25, branch `feature/one-command-releases`:

| Task | Size | State |
|---|---|---|
| Serve `/releases/<file>` from R2 with Range support. Make `/download`, the page, and `/stats` follow `latest.json`. | M | Done. Rehearsed against a simulated bucket, then deployed to nextshot.dev on 2026-10-25 from commit 93be021 (PR #108, not yet merged). The live smoke test passed all 16 checks. |
| Group `/stats` by the new version strings. | S | Needs no change: `/stats` groups by the stored version, so 0.3.0 and 2026.10.24 are separate rows. |
| Write `scripts/release.sh` with `--dry-run`. | L | Built. The dry run works on the real repo. The full run (build, notarize, push) is untested: it needs `main` and a real release. |
| `scripts/release.sh --promote <version>` for rollback. | S | Built and rehearsed: rollback, a declined question, no terminal, an unknown version, and a failed smoke test that restores the earlier pointer. |
| `site/deploy.sh` deploys the page only. | S | Done. It ran against Cloudflare on 2026-10-25 (with the live video and poster, `--poster build/site-poster.jpg`: a plain run would replace the poster). The token can deploy a Worker with an R2 binding. |
| `scripts/release.sh --import-legacy` archives a date build. | S | Done. Rehearsed, then used on 2026-10-25 for the real bucket. |
| Create the bucket `nextshot-releases`, give the token R2 permission limited to it. | M | Done 2026-10-25. The bucket exists (created through the Cloudflare connector). The token reads, writes, and deletes there, a 13 MB round trip works, and the other two buckets answer 403. R2 goes through the S3 interface (see `docs/site.md`, "Cloudflare access"). |
| Import the 2026.10.24 DMG into the real bucket and point `latest.json` at it, then deploy the Worker. | M | Done 2026-10-25, each step on Drew's yes. The bucket holds the DMG (SHA-256 and size match the local file), its checksum, its record, and `latest.json`. The import used `--no-smoke`, because the old Worker had no `latest.json` route. nextshot.dev now serves from the bucket. |
| Run the bridge test: install the 2026.10.24 build, then run the 0.3.0 image copy. | M | Done 2026-10-25 on m5pro, in a scratch folder so the daily copy stayed untouched. The 2026.10.24 (524) app ran from a scratch folder. The 0.3.0 (751) image copy logged `Launch plan for build 0.3.0 (751): offerInstall` and asked "Nextshot 2026.10.24 (524) is open. Nextshot quits it, replaces it in test-app, and opens the new version." After Install, the 524 copy was gone, 0.3.0 (751) ran from the same path (`Launch plan ...: run`), and the image ejected itself. The installed app is Developer ID signed, and Gatekeeper accepts it as Notarized Developer ID. The rounds folder matched a backup file for file. Not repeated: the Safari quarantine "Open" prompt (tested for 524 to 619, 620, 621 on 2026-10-25) and the Screen Recording grant. |
| Cut 0.3.0 with the command. | S | Done 2026-10-25 on Drew's yes. #107, #108, and the site review (#110) were in `main` first. The tests, the build, notarization, the DMG checks, the R2 archive, the push, the tag `nextshot-v0.3.0`, the promote, and the 16-check smoke test of the live site all passed. 0.3.0 is build 751, commit c23afe6, SHA-256 6f66e436cc941b82e74e8554ac01e59c9f292f138acc30cb4994620c3858a9ad. The command ran from a worktree on `main`. |

If #108 changes in review, deploy the Worker again with `site/deploy.sh`, because the live Worker is the code of commit 93be021. To undo the deploy: `wrangler rollback`.

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
| The version drop from 2026.10.24 to 0.3.0 confuses a version-first comparison in old copies. | Old copies have no `LaunchPlan`. The new copy on the image does the replacing and compares builds. The bridge test proved it on 2026-10-25: 751 beat 524 although the version text fell from 2026.10.24 to 0.3.0. |
| `SUPublicEDKey` in Info.plist is an upstream file. | Log the edit. Keep it a one-line change at the hook point. |
| One person holds all the signing keys. | M4 backs them up and writes the recovery steps. |
| The DMG grows past 25 MiB. | R2 has no such limit. The Worker streams from R2. |
| The license may bar a paid launch. | The 1.0 gate decides it by 0.8. The numbering works with any answer. |

## Open questions

- Sparkle update file: the zip or the DMG. Decide in M3.
- Release notes tone and length. Draft them with the first release.
- Whether the Dev app shows a visible "Dev" badge in the menu bar mark. The plan assumes yes.
