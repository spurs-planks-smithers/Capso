#!/usr/bin/env python3
"""List and scrub Nextshot app copies so Spotlight shows one Nextshot Dev.

Spotlight indexes every .app on disk. Build folders, old release exports, and
other worktrees leave many copies named Nextshot. Only the installed copy,
/Applications/Nextshot Dev.app, is kept.

Spotlight skips a folder whose name ends in .noindex. Build scripts write there,
so new copies stay out of Spotlight. This script removes the older copies that
were built before that rule.

Commands:
  list    Show every copy: status, channel, version, build, path.
  check   Same table. Exit 1 when a Spotlight-visible stale copy exists.
  scrub   Dry run. Add --apply to remove the stale copies that sit in a
          worktree build folder. Add --this-checkout to touch only this repo.

A copy outside a worktree build folder (for example /Applications or a mounted
disk image) is listed as "manual" and never removed.
"""

import argparse
import os
import pathlib
import plistlib
import shutil
import subprocess
import sys
from typing import NamedTuple

ID_PREFIX = "com.drewschulz.nextshot"
DEV_ID = "com.drewschulz.nextshot.dev"
PRODUCTION_ID = "com.drewschulz.nextshot"
REVIEW_ID = "com.drewschulz.nextshot.historyreview"
# The one Nextshot app on m5pro (Drew, 2026-11-14). The RC and production apps
# live only on the approved second Mac.
KEEP = pathlib.Path("/Applications/Nextshot Dev.app")
LSREGISTER = ("/System/Library/Frameworks/CoreServices.framework/Frameworks/"
              "LaunchServices.framework/Support/lsregister")
# Xcode keeps thousands of intermediate files in these. They hold no app copy.
SKIP_DIRS = {"node_modules", ".git", ".build", "SourcePackages", "Intermediates.noindex",
             "ModuleCache.noindex", "Index.noindex", "SDKStatCaches.noindex", "Logs"}


class App(NamedTuple):
    path: pathlib.Path
    identifier: str
    version: str
    build: str

    @property
    def channel(self):
        if self.identifier == DEV_ID:
            return "dev"
        if self.identifier == REVIEW_ID:
            return "history-review"
        if self.identifier == PRODUCTION_ID:
            return "rc" if "-rc" in self.version else "production"
        return "other"


def read_app(path):
    """Return the app at path when its bundle ID is a Nextshot ID, else None."""
    try:
        with (path / "Contents/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
    except (OSError, plistlib.InvalidFileException):
        return None
    identifier = info.get("CFBundleIdentifier", "")
    if not isinstance(identifier, str) or not identifier.startswith(ID_PREFIX):
        return None
    return App(path, identifier, str(info.get("CFBundleShortVersionString", "?")),
               str(info.get("CFBundleVersion", "?")))


def is_hidden(path):
    """True when Spotlight skips the path.

    Spotlight skips a folder whose name ends in .noindex, and it does not index
    the contents of an .xcarchive package. An archive also keeps a release's
    debug symbols, so its app copy is never removed.
    """
    return any(part.endswith((".noindex", ".xcarchive")) for part in path.parts)


def is_under(path, folder):
    try:
        path.resolve().relative_to(folder.resolve())
        return True
    except ValueError:
        return False


def walk_apps(root, max_depth=12):
    """Yield each .app under root. Never descend into an app or a skipped folder."""
    if not root.is_dir():
        return
    base = len(root.parts)
    for current, dirs, _files in os.walk(root, followlinks=False):
        here = pathlib.Path(current)
        if len(here.parts) - base >= max_depth:
            dirs[:] = []
            continue
        keep = []
        for name in dirs:
            if name.endswith(".app"):
                yield here / name
            elif name not in SKIP_DIRS:
                keep.append(name)
        dirs[:] = keep


def spotlight_paths():
    """Paths Spotlight reports for any Nextshot bundle ID. Empty on failure."""
    query = f"kMDItemCFBundleIdentifier == '{ID_PREFIX}*'"
    try:
        out = subprocess.run(["/usr/bin/mdfind", query], capture_output=True,
                             text=True, timeout=30, check=True).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    return [pathlib.Path(line) for line in out.splitlines() if line.strip()]


def mounted_image_apps():
    """Apps at the top of each mounted volume, such as an open DMG.

    It never walks a volume: /Volumes/Macintosh HD points back to the boot disk,
    and a backup volume holds a full copy of it.
    """
    volumes = pathlib.Path("/Volumes")
    if not volumes.is_dir():
        return []
    return [app for volume in volumes.iterdir() if volume.is_dir() and not volume.is_symlink()
            for app in volume.glob("*.app")]


def discover(roots, extra_paths=()):
    seen = {}
    candidates = [p for root in roots for p in walk_apps(root)] + list(extra_paths)
    for path in candidates:
        app = read_app(path)
        # One entry per real file, so a second path never removes it twice.
        key = str(path.resolve())
        if app is not None and key not in seen:
            seen[key] = app
    return sorted(seen.values(), key=lambda a: (a.channel, a.version, str(a.path)))


def decide(app, keep, build_dirs, running):
    """Return keep, hidden, running, remove, or manual for one app copy."""
    if app.path == keep:
        return "keep"
    if is_hidden(app.path):
        return "hidden"
    if app.path.is_symlink():
        return "manual"
    if not any(is_under(app.path, build) for build in build_dirs):
        return "manual"
    if app.path in running:
        return "running"
    return "remove"


def manual_reason(app, status):
    if status == "running":
        return "quit it first"
    if app.channel != "dev":
        return "m5pro allows only Nextshot Dev, remove it by hand"
    if app.path.parent == pathlib.Path.home() / "Applications":
        return "old Dev location, scripts/build-local.sh removes it"
    return "remove it by hand"


def running_app_paths():
    try:
        out = subprocess.run(["/bin/ps", "-ww", "-axo", "comm="], capture_output=True,
                             text=True, timeout=30, check=True).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    found = set()
    for line in out.splitlines():
        marker = ".app/Contents/MacOS/"
        if marker in line:
            found.add(pathlib.Path(line.strip().split(marker)[0] + ".app"))
    return found


def worktree_roots(repo):
    roots = [repo]
    try:
        out = subprocess.run(["/usr/bin/git", "-C", str(repo), "worktree", "list", "--porcelain"],
                             capture_output=True, text=True, timeout=30, check=True).stdout
    except (OSError, subprocess.SubprocessError):
        return roots
    for line in out.splitlines():
        if line.startswith("worktree "):
            path = pathlib.Path(line[len("worktree "):])
            if path not in roots and path.is_dir():
                roots.append(path)
    return roots


def print_table(rows):
    header = ("STATUS", "CHANNEL", "VERSION", "BUILD", "SPOTLIGHT", "PATH")
    table = [header] + rows
    widths = [max(len(r[i]) for r in table) for i in range(len(header) - 1)]
    for row in table:
        cells = [row[i].ljust(widths[i]) for i in range(len(header) - 1)]
        print("  ".join(cells + [row[-1]]))


def plan(roots, keep, build_dirs, running, extra_paths=()):
    apps = discover(roots, extra_paths)
    return [(app, decide(app, keep, build_dirs, running)) for app in apps]


def show(entries):
    rows = []
    for app, status in entries:
        spot = "hidden" if is_hidden(app.path) else "visible"
        rows.append((status.upper(), app.channel, app.version, app.build, spot, str(app.path)))
    if not rows:
        print("No Nextshot app copies found.")
        return
    print_table(rows)


def remove_app(path):
    if not path.exists():
        return
    subprocess.run([LSREGISTER, "-u", str(path)], capture_output=True, check=False)
    shutil.rmtree(path)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("list", help="show every Nextshot app copy")
    commands.add_parser("check", help="list, and exit 1 when a visible stale copy exists")
    scrub = commands.add_parser("scrub", help="remove stale copies from build folders")
    scrub.add_argument("--apply", action="store_true", help="remove them (default is a dry run)")
    scrub.add_argument("--this-checkout", action="store_true",
                       help="touch only this repository's build folder")
    args = parser.parse_args(argv)

    repo = pathlib.Path(__file__).resolve().parent.parent
    scope = [repo] if getattr(args, "this_checkout", False) else worktree_roots(repo)
    build_dirs = [root / "build" for root in scope]
    scan_roots = [pathlib.Path("/Applications"), pathlib.Path.home() / "Applications"]
    scan_roots += build_dirs
    running = running_app_paths()
    if running is None:
        print("nextshot-scrub: process list unavailable. Nothing is removed.", file=sys.stderr)
        return 1
    entries = plan(scan_roots, KEEP, build_dirs, running,
                   spotlight_paths() + mounted_image_apps())

    show(entries)
    if not any(app.path == KEEP for app, _ in entries):
        print(f"\nNote: {KEEP} is not installed. Run scripts/build-local.sh.")
    stale = [(a, s) for a, s in entries if s in {"remove", "running", "manual"}]

    if args.command == "list":
        return 0
    if args.command == "check":
        removable = sum(1 for _, s in stale if s == "remove")
        if stale:
            print(f"\n{len(stale)} stale copy or copies are visible to Spotlight.")
        if removable:
            print(f"Remove {removable} with: python3 -I scripts/nextshot-scrub.py scrub --apply")
        for app, status in stale:
            if status != "remove":
                print(f"left {app.path} ({status}: {manual_reason(app, status)})")
        return 1 if stale else 0

    removable = [a for a, s in entries if s == "remove"]
    if not args.apply:
        print(f"\nDry run. {len(removable)} copy or copies would be removed. Add --apply to remove them.")
    else:
        for app in removable:
            remove_app(app.path)
            print(f"removed {app.path}")
        print(f"\nRemoved {len(removable)} copy or copies.")
    skipped = [(a, s) for a, s in stale if s in {"running", "manual"}]
    for app, status in skipped:
        print(f"left {app.path} ({status}: {manual_reason(app, status)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
