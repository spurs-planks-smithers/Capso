#!/usr/bin/env python3
"""Check local Nextshot use and open only the installed Nextshot Dev app."""

import argparse
import pathlib
import plistlib
import re
import socket
import subprocess
import sys

DEV_ID = "com.drewschulz.nextshot.dev"
PRODUCTION_ID = "com.drewschulz.nextshot"
REVIEW_ID = "com.drewschulz.nextshot.historyreview"


def app_info(path):
    try:
        with (path / "Contents/Info.plist").open("rb") as stream:
            info = plistlib.load(stream)
        if not isinstance(info, dict):
            raise ValueError(f"Invalid app identity: {path}")
        return info
    except (OSError, plistlib.InvalidFileException) as error:
        raise ValueError(f"Cannot read app identity: {path}") from error


def verify_dev_app(path):
    info = app_info(path)
    if info.get("CFBundleIdentifier") != DEV_ID:
        raise ValueError(f"Local testing requires {DEV_ID}: {path}")
    if not info.get("CFBundleShortVersionString", "").endswith("-dev"):
        raise ValueError(f"Local testing requires a -dev version: {path}")
    schemes = {scheme for entry in info.get("CFBundleURLTypes", [])
               for scheme in entry.get("CFBundleURLSchemes", [])}
    if not schemes or schemes != {"nextshot-dev"}:
        raise ValueError(f"Dev must claim only nextshot-dev://: {path}")


def installed_apps(root):
    if not root.exists():
        return
    for path in root.iterdir():
        if path.is_dir():
            if path.suffix.lower() == ".app":
                yield path
            elif not path.is_symlink():
                yield from installed_apps(path)


def check_local_policy(host, roots, running_apps):
    if host.lower().split(".")[0] != "m5pro":
        return
    paths = [path for root in roots for path in installed_apps(root)]
    for path in paths + list(running_apps):
        try:
            identifier = app_info(path).get("CFBundleIdentifier")
        except ValueError:
            if path.name in {"Nextshot.app", "Nextshot History Review.app"}:
                raise
            continue
        if identifier in {PRODUCTION_ID, REVIEW_ID} or path.name == "Nextshot History Review.app":
            raise ValueError(f"m5pro permits only Nextshot Dev. Remove the installed copy or quit the running copy: {path}")


def running_app_paths(output):
    if not output.strip():
        raise ValueError("No process inventory returned. Local app safety is unverified.")
    running = []
    for line in output.splitlines():
        match = re.match(r"(.+\.app)/Contents/MacOS/", line.strip())
        if match:
            running.append(pathlib.Path(match.group(1)))
    return running


def check_machine():
    # On macOS, comm returns the executable path without its arguments.
    # Unlimited width keeps long worktree paths intact.
    result = subprocess.run(["/bin/ps", "-ww", "-axo", "comm="], check=True,
                            capture_output=True, text=True)
    check_local_policy(socket.gethostname(),
                       [pathlib.Path("/Applications"), pathlib.Path.home() / "Applications"],
                       running_app_paths(result.stdout))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("check", help="Refuse installed or running production copies on m5pro")
    commands.add_parser("open", help="Verify and open ~/Applications/Nextshot Dev.app")
    verify = commands.add_parser("verify", help="Check a built app's Dev identity")
    verify.add_argument("app", type=pathlib.Path)
    args = parser.parse_args()
    try:
        if args.command == "verify":
            verify_dev_app(args.app)
            print(f"Verified Nextshot Dev identity: {args.app}")
        else:
            check_machine()
            if args.command == "open":
                app = pathlib.Path.home() / "Applications/Nextshot Dev.app"
                verify_dev_app(app)
                subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
                subprocess.run(["/usr/bin/open", str(app)], check=True)
            print("Local app policy passed. Use only Nextshot Dev on m5pro.")
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"nextshot-local: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
