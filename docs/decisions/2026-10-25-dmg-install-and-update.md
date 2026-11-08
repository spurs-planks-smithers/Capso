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

## A drag over a running copy (2026-11-07)

Drew, feedback round `2026-11-07-1613-feedback`, items 1.1 and 2.1: a drag to Applications while an older Nextshot runs must work as a double-click does. Drew dragged 0.7.0 over a running 0.6.0 on a production Mac and got "The operation can't be completed because the item is in use".

### Decision

- The running copy watches for mounted disk images (`DiskImageWatcher`). An image counts when it is a disk image (DiskArbitration model "Disk Image"), it holds an app with this bundle ID and a higher build, and that app passes a strict signature check against the running copy's designated requirement (same bundle ID, same signer).
- The running copy waits until no capture is open, no round end runs, and saves finish. Then it opens the copy on the image through Launch Services with `--nextshot-update-from <pid>`.
- That copy quits the running copy first, then asks "Install Nextshot ...?". The text says the old version quit and that a drag also works.
- While the dialog is open, the copy on the image checks the install place twice a second. When it finds its own build and code hash there in two checks in a row, the drag is done. It closes the dialog, sets the "user approved" quarantine bit, opens the new copy, and exits. A copy that Finder is still writing fails the signature check.
- Install runs the existing install. Not Now opens the old copy again, which then ejects the image.
- When the last open fails (Launch Services reports an error), the copy on the image keeps running instead of exiting, so the user always has a Nextshot running.
- Accepted limits: a capture started while the Gatekeeper prompt for the image copy is open is lost when that copy quits the old one. If the user quits the image copy while its dialog is open, no Nextshot runs until the next launch.
- A copy from before this change (0.7.0 and earlier) has no watcher. A drag over it still fails, and the DMG text "Already installed? Double-click Nextshot here to update." stays for those users. The fix works for updates from the first release that has it.

### Why

| Finding | Evidence |
|---|---|
| Updaters replace a running Mac app with a second process that waits for the app to quit (Sparkle's installer, LetsMove, relauncher helpers). Finder has no such step. | [Apple Developer Forums 110810](https://developer.apple.com/forums/thread/110810), [LetsMove](https://github.com/MacPass/LetsMove) |
| Nextshot starts no child process (`NetworkSourceScanTests`). The newer copy on the image is a second process that Launch Services can open. | The scan test bans `Process(` and `NSTask`. |
| The running copy must quit before Finder's Replace, so it cannot ask first. | Issue #88 planned "the running copy asks, then opens the image copy". A drag during that question still fails. |
| Listing every mounted volume waited on a macOS privacy prompt for external drives. The disk image check reads no files, so it runs first, in the watcher and in the launch-time eject. | 2026-11-07 test: the eject thread stopped in `app(onVolume:)` with LaCie and ccc_backup mounted. |
| `Bundle(url:)` keeps the first Info.plist it reads for a path, so it cannot see a dragged copy. `DiskImageInstaller.info(of:)` reads the file each time. | Foundation caches bundles by path. |

### Tested

`scripts/test-dmg-drag-update.sh` compiles the real install files into a harness app with its own bundle ID (`com.drewschulz.nextshot.installtest`), as builds 100 and 101 signed with the Apple Development identity. It uses real mounts, Finder's copy with replacing, and Launch Services. On m5pro, macOS 27.0, two runs on 2026-11-07:

| Case | Result, both runs |
|---|---|
| control: build 100 runs without the watcher, Finder replace | Refused, -8087 "in use" |
| drag: build 100 runs, image mounts, Finder replace | Replaced. Build 101 runs from the install place. Image ejected. |
| install: the same, click Install | Build 101 runs. Image ejected. |
| not-now: the same, click Not Now | Build 100 runs again. Image ejected. |
| same-build: build 101 runs, its own image mounts | No hand-off. The same process keeps running. |

Not covered by the harness: the quarantine and Gatekeeper prompt of a downloaded release DMG, the busy wait during an open capture, and a drag with the mouse. The release check on another Mac covers them (Drew's test steps in the PR).

## Later

Backlog [spurs-planks-smithers/Capso#88](https://github.com/spurs-planks-smithers/Capso/issues/88): item 1 (offer the update when a newer image mounts) is done by the section above, with the hand-off order changed so a drag works. Its Gatekeeper check is done (the table above). Self-serve updates over the network stay in [spurs-planks-smithers/Capso#4](https://github.com/spurs-planks-smithers/Capso/issues/4).
