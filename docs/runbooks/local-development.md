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

The helper opens `~/Applications/Nextshot Dev.app` by its exact path. It verifies the bundle ID, Dev version, URL scheme, and signature. Never use `open -a Nextshot`, the production bundle ID, or `nextshot://` for local tests.

The build and release scripts call the same machine check. On m5pro, it refuses installed production copies and running production artifacts. It also refuses Nextshot History Review. Failed process reads stop the check. It never uninstalls an app automatically. The helper does not intercept direct Finder launches or arbitrary shell commands.

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
