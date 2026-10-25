# Nextshot DMG: install and update

Date: 2026-10-25. Decided by Drew, from feedback round `2026-10-25-0637-feedback` (items 1.1 to 1.4).

## Decision

- The DMG window shows the instruction in its background: "Drag Nextshot to Applications", an arrow, and "Already installed? Double-click Nextshot here to update."
- The DMG window shows no `LICENSE.txt`. The zip has none beside the app either. The license ships inside the app, at `Contents/Resources/LICENSE.txt` (Drew chose "remove from installer only").
- The volume name holds the version, as the top row of the Nshot menu does, for example `Nextshot 2026.10.24 (524)`.
- An update starts from the copy on the image. A double-click on it shows "Install Nextshot ...?". Install quits the running copy, replaces it in place, and opens the new copy.
- The newest build wins at launch. An older copy that starts finds a newer one and exits. A newer copy asks older copies to quit.
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

Not tested: a notarized DMG with the quarantine flag, so neither App Translocation nor a second Gatekeeper prompt after the install.

## Later

Backlog [spurs-planks-smithers/Capso#88](https://github.com/spurs-planks-smithers/Capso/issues/88): the running copy offers the update when a newer image mounts, so no double-click is needed, and a Gatekeeper check with a real download. Self-serve updates over the network stay in [spurs-planks-smithers/Capso#4](https://github.com/spurs-planks-smithers/Capso/issues/4).
