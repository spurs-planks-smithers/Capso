# Nextshot DMG: install and update

**Correction, 2026-10-28:** The m5pro production tests below are historical. Drew's 2026-10-27 rule permits only Nextshot Dev there. Use this installer on another approved Mac. Keep production archives as distribution artifacts on m5pro. Follow [[local-development]].

Date: 2026-10-25. Decided by Drew, from feedback round `2026-10-25-0637-feedback` (items 1.1 to 1.4).

## Decision

- The DMG window shows the instruction in its background: "Drag Nextshot to Applications", an arrow, and "Already installed? Double-click Nextshot here to update."
- The DMG window shows no `LICENSE.txt`. The zip has none beside the app either. The license ships inside the app, at `Contents/Resources/LICENSE.txt` (Drew chose "remove from installer only").
- The volume name holds the version, as the top row of the Nshot menu does, for example `Nextshot 2026.10.24 (524)`.
- An update starts from the copy on the image. A double-click on it shows "Install Nextshot ...?". Install quits the running copy, replaces it in place, and opens the new copy.
- When the copy on the image is not newer, it says "Nextshot is up to date." with both versions. OK brings the running copy to the front. Install Anyway replaces it, for a move back from a trial build. Before this, the copy exited with no word, and a double-click seemed to do nothing (live test, 2026-10-25).
- The installed copy gets the "user approved" bit in its quarantine flag. The user already said Open to the same notarized app on the image. Without the bit, Gatekeeper asked "Are you sure you want to open it?" a second time (live test, 2026-10-25).
- The newest build wins at launch. An older copy that starts finds a newer one and exits. A newer copy asks older copies to quit. Newest means the later version date, then the higher build number. The build number alone fails across branches: on 2026-10-25 a local trial build was 665 and the release from a later commit was 618. **Replaced the same day** by [2026-10-25-versioning-and-releases.md](2026-10-25-versioning-and-releases.md): trial builds are now Nextshot Dev with its own bundle ID, so only releases from `main` meet, and the higher build number alone decides. The version text breaks a tie only.
- The installed copy ejects every mounted disk image that holds a Nextshot.app with its bundle ID. Old installers no longer pile up under Locations in Finder.
- dmgbuild makes the image, not create-dmg.

## Why

| Finding | Evidence |
|---|---|
| Finder cannot replace a running app. A drag over a running Nextshot fails, so a drag can never give a seamless update. | Finder's duplicate with replacing over a running test app: "The operation can't be completed because the item is in use" (-8087). After the app quit, the same command replaced it. Tested on m5pro, macOS 27.0.1. |
| A newly opened copy never ran while an old one was open. | The old `SingleInstanceGuard` kept the oldest copy and exited the new one, whatever its build. |
| create-dmg lost the background picture. | It scripts Finder to lay out the window. With "Prefer tabs when opening documents" set to Always (Drew's setting on both Macs), Finder opened that window as a tab, and the `.DS_Store` file got no background. dmgbuild writes the `.DS_Store` file itself. |
| The background must be light. | Finder draws a window that has a background picture in light mode, with black labels, whatever the system appearance. |
| The text must sit near the top. | When Finder opens the image as a tab, the window keeps the old window's size and can cut off the bottom of the picture. |

## How it works

- `scripts/brand/make_dmg_background.swift` draws the picture at 1x and 2x into one TIFF. `scripts/dmg-settings.py` holds the window and icon layout. `scripts/release-notarized.sh` runs both.
- `App/Feedback/LaunchPlan.swift` holds the rules, Foundation only. `SingleInstanceGuard` applies them at launch. `DiskImageInstaller` shows the dialog, copies the app, and ejects old images.
- The installer copy opens the installed copy through Launch Services with `--nextshot-installed-by <pid>`, and the new copy waits for that process to exit. A child process (a relaunch shell script) would break the local-only rule that `NetworkSourceScanTests` enforces.
- A copy counts as an installer copy when its volume is read-only. That covers a disk image and App Translocation.

## Tested

A scratch test app compiled from the three fork files, with its own bundle ID, on 2026-10-25:

| Case | Result |
|---|---|
| Build 1 runs, build 2 starts from a folder | Build 1 quit. Build 2 runs. |
| Build 2 runs, build 1 starts | Build 1 exits. |
| Build 1 runs, build 1 on an image starts | The image copy exits. |
| Build 1 runs, build 2 on an image starts, Install | Build 1 quit. Build 2 replaced it in place and runs. Both test images ejected. An image with another bundle ID stayed mounted. |

Real notarized releases on m5pro, each DMG copied with a Safari quarantine flag, over the copy in `~/Applications`:

| Update | Prompts | Result |
|---|---|---|
| 2026.10.24 (524) to 619 | Open, Install, screen recording | Installed and ejected both DMGs. The recording prompt came from the signature switch (see below). |
| 619 to 620 | Open, Install, a second Open | Grant kept: 620 read screen content at launch. The second Open came from the copied quarantine flag, which lacked the "user approved" bit. 620 wrote the #84 manifest ("n/a (round is active)"). |
| 620 to 621 | Open, Install | Grant kept. No second prompt: Gatekeeper let the installed copy run 0.4 seconds after the copy. |

The DMG copy ran from `/Volumes`, not from an App Translocation path.

## Historical screen recording findings, 2026-10-25

Before the Dev identity split on 2026-10-25, Apple Development builds and Developer ID releases shared `com.drewschulz.nextshot`. Switching signatures requested screen access again. Captures without a working grant showed blank images. The current local script uses `com.drewschulz.nextshot.dev` and the Dev-only URL scheme.

On 2026-10-25, resetting ScreenCapture printed 15 lines for the production bundle ID. That output counts reset messages, not independently verified app registrations. "Quit & Reopen" and a `nextshot://` link both started a trial copy from DerivedData. The Dev-only launch helper now opens the installed app by its exact path.

## Later

Backlog [spurs-planks-smithers/Capso#88](https://github.com/spurs-planks-smithers/Capso/issues/88): the running copy offers the update when a newer image mounts, so no double-click is needed. Its Gatekeeper check is done (the table above). Self-serve updates over the network stay in [spurs-planks-smithers/Capso#4](https://github.com/spurs-planks-smithers/Capso/issues/4).
