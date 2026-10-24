# Nextshot feature flags across versions (draft)

Date: 2026-10-24. Status: approved design (Drew, 2026-10-24). Built in the orchestration session, not in a feature session.

## Decisions log

- 2026-10-24: flag state is local only. No remote flag file (Drew).
- 2026-10-24: Jev features stay in dev builds only until there is a key plan for other people's Macs (Drew).
- 2026-10-24: the orchestration session builds the flag registry. A separate session builds the shared Jev base (Drew).

## What a feature flag is

A feature flag is a named switch in the code. At run time, the app reads the switch and runs the new code path only when the switch is on. The new code ships inside the app either way. The flag decides whether it runs.

## The constraint

- Nextshot has no automatic updates. Sparkle is off (issue #4). People install each new DMG by hand, so different Macs run different versions for a long time.
- The local-only rule allows no network call except the Jev package to `api.typesafe.ai`. So no server can change a flag on a Mac that already runs Nextshot.
- Result: a flag's state on a Mac can come only from the installed version's code and from that Mac's own settings.

## Where a flag's state comes from

Nextshot reads three layers, in order. The first layer that gives a value wins.

| Layer | Who sets it | Visible to users? | Example |
| --- | --- | --- | --- |
| 1. Local override | Drew, with `scripts/nextshot-flags.sh` (it runs `defaults write`) | No | `scripts/nextshot-flags.sh set noteCoach on` |
| 2. Channel default | The code, per build channel | No | `noteCoach`: dev = shadow, release = off |
| 3. Off | Built in | No | any flag with no entry |

The channel is the kind of build:

- dev: `scripts/build-local.sh` (Apple Development signing), Xcode builds, and test builds.
- release: `scripts/release-notarized.sh` (Developer ID signing, the DMG on nextshot.dev).

The app can read the channel from its own code signature, so the build scripts and the upstream Info.plist need no change. The builder confirms this.

## Rollout across versions

A version is the DMG that a person installed. Each DMG carries the flag defaults that were in the code when it was built.

| Stage | Dev default | Release default | What people see |
| --- | --- | --- | --- |
| 1. Building | off or shadow | off | Nothing. The code is inside the DMG but never runs. |
| 2. Drew tests | shadow or on (or a local override) | off | Nothing. |
| 3. Released | on | on, from build N | People who install build N or later get the feature. Older installs stay as they were. |
| 4. Cleanup | flag removed | flag removed | The feature is plain code. Remove the flag two releases after stage 3. |

- To turn a feature on for everyone: change its release default, then ship a new DMG.
- To turn it off for everyone: ship a new DMG with the default off. There is no remote off switch. A Mac on an old DMG keeps the old default until its owner installs a new one.
- One person can turn a flag on or off at any time with a local override. Only someone with Terminal access does this.
- Because there is no remote off switch, every feature stays in stage 2 until it has passed Drew's own use with the flag on.

## Rules each flag follows

- One registry, in one file. Each entry has: the key, the GitHub issue, the states it allows (off, shadow, on), the dev default, the release default, and the build number where the release default turned on.
- New flags start with the release default off. A test fails if a release default is on without a "released in build" number.
- With every flag off, Nextshot sends no network request and writes the same files as today. A test proves both.
- No flag shows in the release app's interface. The dev build can show flag states in the menu's gray build line, for example "Nextshot 2026.10.24 (520) dev, 2 flags on".
- The Jev features stay dev-only until there is a plan for a TypeSafe key on other people's Macs. Drew's key must never ship inside a DMG.

## Not chosen now

- A remote switch file on nextshot.dev. It would allow a remote off switch and gradual rollout, but it adds a network call at every launch, changes the local-only rule again, and does nothing for Macs on old versions. Revisit when Nextshot has more users or Sparkle (issue #4).
