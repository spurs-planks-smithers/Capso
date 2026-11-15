# Prompt: one app per Mac, three build channels

Copy everything below the line into an agent session in the other app's repository. It sets up the build and install standard that Nextshot uses (PR spurs-planks-smithers/Capso#301, 2026-11-14). Replace nothing by hand: the agent asks for each value it needs.

---

Set up a standard for local builds and releases in this repository. The goal: each Mac runs one copy of this app, and Spotlight shows that one copy. Follow the standard below. Adapt only the commands to this project's build tool.

## Step 0: Ask before you build

Read the repository first: build scripts, project files, signing setup, and release steps. Then ask me these questions in one batch, with your recommended answer first:

1. The app's display name and its bundle ID prefix (for example `com.example.myapp`).
2. Which Mac is the development Mac, and which Mac is the approved test Mac for release candidates and production.
3. The version scheme. Recommend SemVer (`MAJOR.MINOR.PATCH`) with a `VERSION` file that holds the last released version.
4. Whether the app is signed with a Developer ID and notarized for release, or not yet.

Report any place where the current code differs from this standard before you change it.

## Step 1: Three channels, two identities

| Channel | Purpose | Bundle ID | Version text | Signature | Installed where |
|---|---|---|---|---|---|
| Dev | Daily use and local testing on the development Mac | `<prefix>.dev` | `X.Y.Z-dev` | Apple Development | `/Applications/<Name> Dev.app` on the development Mac only |
| RC (release candidate) | Final test of the next release | `<prefix>` | `X.Y.Z-rc.N` | Developer ID, notarized | `/Applications/<Name>.app` on the test Mac only |
| Production | The released app | `<prefix>` | `X.Y.Z` | Developer ID, notarized | `/Applications/<Name>.app` on the test Mac and on users' Macs |

Rules:

- Dev has its own bundle ID. So it has its own settings domain, its own privacy permissions (screen recording, camera, and similar), its own URL scheme (`<name>-dev://`), and its own Keychain items where that applies. It never claims the production app's links.
- The Dev app file name is stable: `<Name> Dev.app`. Never put a version in the file name.
- RC and production share one bundle ID and one install path on the test Mac. An RC install replaces production. The final release replaces the RC.
- On the development Mac, the RC and production exist only as DMG files in `build/releases/`. Never install or run them there.
- The build number is the commit count on HEAD, so it only rises when releases come from `main`. Dev adds `-dev` to the last released version.
- Show the channel, version, and build number in the app itself, for example as the first line of the app's menu: `<Name> Dev 0.8.0-dev (934)`.

## Step 2: Build output stays out of Spotlight

- Spotlight indexes every `.app` on disk. It skips any folder whose name ends in `.noindex`, and it does not index the inside of an `.xcarchive` package.
- Send all build output to `build/local.noindex` (Dev builds) and `build/release.noindex` (release builds). This includes Xcode's DerivedData path, export folders, and staging folders.
- Write finished DMG and zip files to `build/releases/`. Spotlight lists apps, not the apps inside DMG files.
- A failed release build leaves nothing in `build/releases/`. Build into the work folder first, then move the finished files.

## Step 3: Install script for Dev

Write `scripts/build-local.sh [Release|Debug] [--no-install]`:

1. Build the Dev app into `build/local.noindex`.
2. Verify the built app: the bundle ID is `<prefix>.dev`, the version ends in `-dev`, and the URL scheme is the Dev scheme. Stop on any mismatch.
3. Before you replace `/Applications/<Name> Dev.app`, check that the installed copy also has the Dev bundle ID. Never overwrite a different app.
4. Quit the running Dev copy, install the new copy, and open it by its full path.
5. Remove any old Dev copy in `~/Applications`, but only when its bundle ID is the Dev ID. Unregister it from Launch Services with `lsregister -u` first.
6. Run the scrub (Step 5) for this checkout only.
7. Print the installed version and build number.

`--no-install` builds and verifies only.

Install to `/Applications`, not `~/Applications`. Finder's sidebar shows `/Applications`. An "open at login" check that uses `SMAppService` needs the app directly in an Applications folder, so never use a versioned subfolder.

## Step 4: Launch helper

Write `scripts/<name>-local.py` with two commands:

- `check`: fail when any app with the production bundle ID is installed on the development Mac, or when the Dev app is missing or has the wrong identity.
- `open`: verify the installed Dev app's bundle ID, then open it by its exact path.

Never launch by the generic app name, the production bundle ID, or the production URL scheme. Launch Services can pick a different copy.

## Step 5: Scrub script

Write `scripts/<name>-scrub.py`, Python standard library only, run with `python3 -I`:

- Commands:
  - `list`: one row per copy, with status, channel, version, build, Spotlight visible or hidden, and path.
  - `check`: the same table, and exit 1 when Spotlight can see a stale copy.
  - `scrub`: a dry run by default. `--apply` removes copies. `--this-checkout` limits it to this repository.
- Find copies:
  - Walk `/Applications`, `~/Applications`, and the `build/` folder of each git worktree (`git worktree list --porcelain`).
  - Add every path that `mdfind "kMDItemCFBundleIdentifier == '<prefix>*'"` returns.
  - Add the `.app` files at the top level of each mounted volume in `/Volumes`.
  - Never walk a whole volume. `/Volumes/Macintosh HD` points back to the boot disk, and a backup volume holds a full copy of it.
  - Skip `node_modules`, `.git`, `.build`, `SourcePackages`, and Xcode's `Intermediates.noindex`, `ModuleCache.noindex`, `Index.noindex`, `SDKStatCaches.noindex`, and `Logs` folders.
  - Never descend into an `.app`. Remove duplicate paths by their resolved path.
- Read each `Contents/Info.plist`. Keep only bundle IDs that start with the prefix. Set the channel from the bundle ID and the version: dev, rc (production ID with `-rc` in the version), production, or other.
- Decide each copy in this order:
  1. `keep`: the installed Dev app.
  2. `hidden`: any path part ends in `.noindex` or `.xcarchive`. An archive keeps a release's debug symbols, so never remove it.
  3. `manual`: a symlink, or anything outside a worktree `build/` folder (Applications folders, mounted DMGs, other places). Print the reason: on the development Mac, a production or RC copy says "this Mac allows only <Name> Dev, remove it by hand".
  4. `running`: the copy is running (check with `ps -axo comm=`). Print "quit it first".
  5. `remove`: everything else.
- To remove a copy: skip a path that is already gone, run `lsregister -u` on it, then delete the folder.
- If the process list fails, remove nothing and exit 1.
- `build-local.sh` and the release script run `scrub --apply --this-checkout` after each build. The release script does not fail when the scrub fails.

## Step 6: Release script

Write or update `scripts/release.sh <patch|minor|major|X.Y.Z>`:

- Run only from `main` when it equals `origin/main`, with a clean tree.
- Run all tests first, including the scrub tests (Step 7).
- Raise `VERSION`, build in `build/release.noindex`, sign, notarize, and staple. Write `build/releases/<Name>-X.Y.Z.dmg`.
- Tag `<name>-vX.Y.Z`, never a bare `vX.Y.Z`.
- Never replace a released file. A bad build gets a new PATCH number.
- Name an RC file `<Name>-X.Y.Z-rc.N.dmg`. Install it only on the test Mac.

## Step 7: Tests

Write `scripts/test-<name>-scrub.py` with `unittest`, using fake `.app` folders in a temporary directory:

- the decisions: keep, remove (old Dev and old production copies in `build/`), hidden (`.noindex` and `.xcarchive`), and manual (a mounted volume copy, and an old `~/Applications` Dev copy)
- an app with another bundle ID is never listed
- a running copy is never removed
- `remove_app` deletes only its own folder
- a symlink is manual
- two paths to one app give one entry
- the channel detection for dev, rc, and production
- a text check that the build scripts write to `build/local.noindex` and `build/release.noindex`

## Step 8: Document the standard

Add a "Where each build lives" table and the scrub commands to the project's local development runbook and to `AGENTS.md`. Record these facts there:

- Spotlight's gray text under an app is a hint about its folder, not an app field. Changing `CFBundleDisplayName` does not change it, and an app directly in Applications shows none. So read the version from the app's own menu or from `<name>-scrub.py list`, never from Spotlight.
- A privacy permission follows the bundle ID and the code signature, not the path. A move to `/Applications` keeps it. A switch between signatures for one bundle ID asks again.

## Step 9: Verify

1. The scrub tests pass.
2. `scripts/build-local.sh Release` installs `/Applications/<Name> Dev.app`, and the app's menu shows the new build number.
3. `mdfind "kMDItemCFBundleIdentifier == '<prefix>*'"` returns only `/Applications/<Name> Dev.app`.
4. `<name>-scrub.py check` exits 0.
5. `ls /Applications` shows `<Name> Dev.app`.
6. Each privacy permission the app uses still works after the move, tested with one real action.

Work on a feature branch. Stage files by explicit path. Show me the scrub dry-run list before the first `scrub --apply`, and ask before you remove anything outside a `build/` folder.
