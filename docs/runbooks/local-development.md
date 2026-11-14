# Local Nextshot development

Policy confirmed by Drew on 2026-10-27. Scripts and runbooks enforce it from 2026-10-28.

## Machine policy

On m5pro, install and run only Nextshot Dev. Its bundle ID is `com.drewschulz.nextshot.dev`. Its version ends in `-dev`. It claims only `nextshot-dev://`.

Never install or launch production Nextshot or Nextshot History Review on m5pro. This includes copies in DerivedData, build folders, and mounted disk images. Older plans that open `Nextshot.app` are superseded by this runbook.

Both channels claim the same shortcuts and share saved rounds. A second channel can interfere with testing. Keep production validation on another approved Mac.

## Build and open

Check the machine before every local app test:

```sh
python3 -I scripts/nextshot-local.py check
```

Build the signed Dev app when code changes require a build:

```sh
scripts/build-local.sh Release
```

`Release` enables compiler optimization. It still builds Nextshot Dev. `Debug` also builds Dev. Add `--no-install` to verify a build without replacing the installed Dev app.

Open the installed app through the identity guard:

```sh
python3 -I scripts/nextshot-local.py open
```

The helper opens `/Applications/Nextshot Dev.app` by its exact path. It verifies the bundle ID, Dev version, URL scheme, and signature. Never use `open -a Nextshot`, the production bundle ID, or `nextshot://` for local tests.

The build and release scripts call the same machine check. On m5pro, it refuses installed production copies and running production artifacts. It also refuses Nextshot History Review. Failed process reads stop the check. It never uninstalls an app automatically. The helper does not intercept direct Finder launches or arbitrary shell commands.

## Keep Spotlight clean (release playbook step)

Added 2026-11-14 (Drew). Spotlight showed many Nextshot apps: every old build, every worktree build, and the 2026.10.25 export. Search showed no build number, so the newest Dev copy was hard to find.

Where each build lives (Drew, 2026-11-14):

| Build | m5pro | Approved second Mac | In Spotlight on m5pro |
|---|---|---|---|
| Dev (`com.drewschulz.nextshot.dev`) | `/Applications/Nextshot Dev.app` | not installed | one result |
| Release candidate (production ID, `X.Y.Z-rc.N`) | DMG file only, `build/releases/Nextshot-X.Y.Z-rc.N.dmg` | `/Applications/Nextshot.app` | no app result |
| Production (`com.drewschulz.nextshot`) | DMG file only, `build/releases/Nextshot-X.Y.Z.dmg` | `/Applications/Nextshot.app` | no app result |
| Build output | `build/local.noindex`, `build/release.noindex` | n/a | none |

Rules:

- On m5pro, `/Applications` holds one Nextshot app, Nextshot Dev, and Spotlight shows only that app. Until 2026-11-14 Dev lived in `~/Applications`. `build-local.sh` removes that old copy.
- The release candidate and production share one slot on the second Mac. A release candidate install replaces production there, and the final release replaces the release candidate.
- The Dev app keeps the name `Nextshot Dev.app`. A version in the name would break a Dock pin on each build (Drew chose the stable name).
- Build scripts write app copies only into folders whose names end in `.noindex`: `build/local.noindex` and `build/release.noindex`. Spotlight skips these folders. A new build adds no search result.
- `scripts/build-local.sh` and `scripts/release.sh` run `scripts/nextshot-scrub.py scrub --apply --this-checkout`. It removes the older copies that sit in this checkout's `build/` folder and unregisters them from Launch Services.

Commands:

```sh
python3 -I scripts/nextshot-scrub.py list
python3 -I scripts/nextshot-scrub.py scrub
python3 -I scripts/nextshot-scrub.py scrub --apply
```

`list` shows status, channel (dev, rc, production), version, build, whether Spotlight sees the copy, and the path. `scrub` is a dry run until you add `--apply`. Without `--this-checkout` it covers every worktree of this repository. It keeps `/Applications/Nextshot Dev.app`. It never removes a running copy, a copy in an Applications folder, a copy on a mounted disk image, or a published DMG. It lists those as `manual` with the reason.

The gray text in Spotlight is not a field in the app. Spotlight takes the app name from the file name. For some copies outside an Applications folder, it shows the containing folder name, for example `export`. It shows no gray text for an app directly in `/Applications` or `~/Applications`. A probe on 2026-11-14 set `CFBundleDisplayName` to "Nextshot Dev 0.8.0-dev (932)", and `kMDItemDisplayName` stayed "Nextshot Dev.app". A versioned subfolder would show gray text, but "Open at login" needs the app directly in an Applications folder (`LoginStartupController.isInstalledSignedApp`). So the setup uses one Spotlight result instead of gray text. Read the version and build in the Nshot menu's first line, in `list`, or at the end of `build-local.sh`.

## Distribution checks

The release scripts may build, sign, notarize, mount, inspect, and archive distribution files on m5pro. They must not install or launch the production app there. `scripts/local-project.yml` is a production archive spec despite its legacy name. Local development uses `scripts/dev-project.yml`.

Installer interaction and production screen-access checks require another approved Mac. Preserve released DMGs and zip files. Never replace a published release.

## Remove a conflicting copy

Read its bundle ID before removal. Production uses `com.drewschulz.nextshot`. History Review uses `com.drewschulz.nextshot.historyreview`. Quit that copy, then move only its app bundle to Trash. Unregister its exact path with Launch Services. Preserve Nextshot Dev, its permissions, settings, saved rounds, and History.

When an uninstall leaves the production screen-access entry behind, reset only that identity:

```sh
tccutil reset ScreenCapture com.drewschulz.nextshot
```

Verify System Settings still lists Nextshot Dev with screen access enabled. Run the machine check again. Cleanup requires the user's uninstall request. A normal build never resets permissions or deletes stored data.
