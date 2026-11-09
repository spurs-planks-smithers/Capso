# Releasing Nextshot

The runbook for cutting a version, recovering the signing setup, and rolling back. The reasons are in `docs/decisions/2026-10-25-versioning-and-releases.md`, and the milestones are in `docs/plans/2026-10-25-versioning-roadmap.md`. This page is the how.

A release is one command run from a terminal. It never runs in CI, and no automated job can publish: the command asks a question on the terminal, and anything but `y` stops it.

## Before the release

| Check | Why |
| --- | --- |
| The tree is clean and HEAD is on `main`, equal to `origin/main` | The command refuses otherwise. Run it from a worktree on `main` when other sessions share the checkout. |
| `CHANGELOG.md` has at least one line under `Unreleased` | The Bump step moves those lines into the new version. The command stops if the section is empty. |
| The Guides release notes have a `## X.Y.Z` heading for the new version | The command dates that heading. Missing it fails the Guides step, which reports partial success and leaves the app flow alone. |
| `scripts/local-signing.env` holds `DEVELOPMENT_TEAM` | The file is untracked and git-ignored, so a fresh worktree or clone needs its own copy. |
| The Developer ID certificate and the notary profile are ready | `scripts/release.sh` preflights both and names the fix when one is missing. See recovery below. |
| The Cloudflare token is in the Keychain | The item is `CLOUDFLARE_API_TOKEN_NEXTSHOT`. |
| `github-route status` exits zero | Every push needs it. |

Run `scripts/release.sh` with no argument to see the suggested bump from the commit prefixes since the last tag, and change nothing.

## Cut a release

```bash
scripts/release.sh patch          # or minor, major, or an exact X.Y.Z
scripts/release.sh --dry-run patch # preflight and the plan, no tests, build, or DMG check
```

`major` works only from 1.0.0 on. Type `1.0.0` yourself when the decision to launch is made.

The command runs seven steps and stops at the first failure:

1. **Preflight.** Branch, tree, tests (FeedbackKit, JevKit in Release, CapsoTests), the certificate, the notary profile, R2, the GitHub route, the changelog entry, and the license text. `license_ready` fails the run when `LICENSE` no longer carries the Business Source License terms, because the image copies that file into the app and a placeholder would ship inside every DMG.
2. **Bump.** Moves `Unreleased` to the new version with the UTC date of the run, writes `VERSION`, sets each flag marker above the last release's build to the new build (`scripts/release-markers.py`), dates the Guides release notes, then makes the commit `chore: release X.Y.Z` and the tag `nextshot-vX.Y.Z`. **Both stay local.** It commits named paths with `git add -f`, so an ignored `docs/` folder does not stop it.
3. **Build.** `scripts/release-notarized.sh`: sign, notarize, staple, DMG, zip.
4. **Check.** The stapled ticket, Gatekeeper, and a mount test on the app inside the image: bundle ID, version, build, signature.
5. **Ask once.** The version, build, hash, and notes. A closed stdin, no terminal, or anything but `y` stops here and undoes the local commit and tag. Keys typed before the question are flushed first.
6. **Archive and push.** Upload to R2, read the DMG back, push `main` and the tag, point `latest.json` at the new record, run the smoke test. A failed push prints the exact recovery command.
7. **Publish the site.** Deploys the staged Guides and page. A Guides failure restores only the Worker and stops, leaving the verified app live.

The command asks for nothing else. Everything public happens after step 5.

## After the release

- The DMG and zip are in `build/releases/` and archived in R2 under `releases/`.
- `latest.json` points at the new record, and `nextshot.dev/download` serves it.
- Record the real numbers in a release note like `docs/plans/2026-11-08-v0.8.0-release.md`: version, build, commit, tag, timestamps, DMG size and SHA-256, both notarization ids, the R2 and smoke results, and what was deliberately left undone.
- A published file is never replaced. A bad build gets a new PATCH number.

## Recover the signing setup

Three separate credentials are needed, and only the first is in the repository.

### The Developer ID certificate

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

The certificate and its private key are backed up as a `.p12` in 1Password. To restore on a new Mac:

1. Open the `.p12` from 1Password and add it to the login keychain.
2. Confirm it appears in `security find-identity -v -p codesigning` with the team ID that `scripts/local-signing.env` names.
3. Sign a throwaway app and check it with `codesign -dv`. A working certificate reports "Notarized Developer ID" after stapling, and Gatekeeper accepts the app with no network.

A certificate that expires or is revoked cannot be repaired locally. Revoke and reissue it from the Apple Developer account, then update the 1Password backup. **Every copy already installed keeps working**, because the stapled ticket is offline; only new builds need the new certificate.

### The notary credentials

The notary profile is a Keychain item, not a file. Check it with:

```bash
xcrun notarytool history --keychain-profile apple-notary
```

To restore it, with an app-specific password from the Apple ID account page:

```bash
xcrun notarytool store-credentials apple-notary \
  --apple-id <developer Apple ID> --team-id <team ID>
```

`scripts/release.sh` passes this profile through. `--profile NAME` picks a different one.

### The Cloudflare token

The item is `CLOUDFLARE_API_TOKEN_NEXTSHOT`, read by `scripts/release-lib.sh`. Its R2 permission is limited to the `nextshot-releases` bucket, so it cannot touch anything else in the account. Store it with `keychain-store.sh CLOUDFLARE_API_TOKEN_NEXTSHOT`, or:

```bash
security add-generic-password -s CLOUDFLARE_API_TOKEN_NEXTSHOT -w '<token>'
```

If the token is lost, issue a new one in the Cloudflare dashboard with the same bucket-only scope. Nothing is lost with the old token; it only stops the release.

### The Sparkle key, from M3 on

The EdDSA private key lives in the Keychain as `SPARKLE_ED_PRIVATE_KEY_NEXTSHOT` and is backed up in 1Password. **A build that has shipped a feed cannot recover from a lost key**: the published public key is baked into every installed copy, so a new keypair strands them. Before the first Sparkle build, the key can still be replaced.

## Roll back

A rollback points `/download` at an older, already-archived release. It changes nothing about the app code, and it never edits or deletes a published file.

```bash
scripts/release.sh --promote 0.7.0
```

It asks before changing anything, then rewrites `latest.json`. The same command is the recovery path for any bad release.

| Situation | What to do |
| --- | --- |
| A release built, pushed, and promoted, but it is wrong | `scripts/release.sh --promote <previous version>`. Then fix the cause and cut a new PATCH. |
| A release failed in step 6 after the push | The command prints `Fix the problem, then run: scripts/release.sh --promote <new>`. |
| The smoke test failed during the release | The command already restored `latest.json` to the version it replaced. Confirm with `site/smoke.sh`. |
| The site or Guides deploy is wrong | `site/deploy.sh --deploy-staged <artifact>` republishes the exact earlier artifact, or `wrangler rollback` undoes a Worker version. This does not touch the app pointer. |
| The DMG itself is broken | Do not replace it. Promote the previous version and cut a new PATCH. |

After a rollback, anyone who already installed the bad build keeps it. On a Mac where the app has a feed, the next promoted appcast entry updates them; before M3 they install the promoted DMG by hand.

## Rehearse without publishing

`NEXTSHOT_R2_LOCAL=<folder>` makes `--promote` and `--import-legacy` use a simulated bucket in that folder, with no Cloudflare account involved. A real release refuses to run with it set.

```bash
NEXTSHOT_R2_LOCAL=/tmp/rehearsal scripts/release.sh --promote 0.7.0
```

Point `wrangler dev --persist-to /tmp/rehearsal` at the same folder to read the simulated bucket.

## What is deliberately not automated

Signing and notarization never run in CI. The certificate, the notary profile, and the Cloudflare token are one person's, and the release command asks a real question before publishing anything. CI runs tests only.

The license gate in preflight is not a leftover check and must not be removed. `LICENSE` looks like an unused file to anyone reading the tree, because nothing in the app loads it, but `scripts/release-notarized.sh` copies it into the app as `Contents/Resources/LICENSE.txt`. A preflight that cannot be skipped is the only thing that keeps a placeholder out of a DMG: it caught nothing when it was written, which is the point.

`.github/workflows/build-release.yml` is upstream Capso's workflow. It triggers on `v*` tags, this fork tags `nextshot-v*`, and every repository it names is `lzhgus`'s. It has never run here and is being retired. It was never this fork's release path.

## See also

- `docs/plans/2026-10-25-versioning-roadmap.md` — the milestones and what is still open.
- `docs/decisions/2026-10-25-versioning-and-releases.md` — the number rules and the file names.
- `docs/runbooks/local-development.md` — building and running Nextshot Dev locally.
- `docs/site.md` — the Worker, R2, and the site deploy.
