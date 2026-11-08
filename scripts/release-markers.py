#!/usr/bin/env python3
"""Fork: the flag marker and release-notes date steps of a Nextshot release.

scripts/release.sh calls this before the release commit, so the commit holds
the real numbers (issue 281, Drew, 2026-11-08).

Usage:
  release-markers.py list LAST NEW [FILE]
      Print "<flag> <old> -> <new>" for each marker that `set` would change.
  release-markers.py set LAST NEW [FILE]
      Set each `releasedInBuild: N` with N above LAST to NEW.
  release-markers.py notes-check VERSION [FILE]
      Exit 0 when the release notes have a "## VERSION" heading.
  release-markers.py notes-date VERSION DATE [FILE]
      Write "Month D, YYYY (UTC)" under "## VERSION". DATE is YYYY-MM-DD.

LAST is the build of the last release tag. NEW is the build of the release
commit. A marker above LAST belongs to this release: a person writes any
number above LAST, and the release sets the real one. A marker at or below
LAST belongs to an earlier release and stays.

The flags FILE defaults to Packages/FeedbackKit/Sources/FeedbackKit/FeatureFlags.swift.
The notes FILE defaults to site/guides/src/content/docs/release-notes.mdx.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FLAGS_FILE = ROOT / "Packages/FeedbackKit/Sources/FeedbackKit/FeatureFlags.swift"
NOTES_FILE = ROOT / "site/guides/src/content/docs/release-notes.mdx"
MARKER = re.compile(r"releasedInBuild: ([0-9]+)")
CASE = re.compile(r"^\s*case \.([A-Za-z0-9_]+)")
SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
DATE = re.compile(r"^([0-9]{4})-([0-9]{2})-([0-9]{2})$")
DATE_LINE = re.compile(r"^[A-Z][a-z]+ [0-9]{1,2}, [0-9]{4} \(UTC\)$")
MONTHS = ["January", "February", "March", "April", "May", "June", "July",
          "August", "September", "October", "November", "December"]


def die(message):
    print(f"release-markers: {message}", file=sys.stderr)
    sys.exit(1)


def build_number(text):
    if not text.isdigit() or int(text) <= 0:
        die(f"'{text}' is not a build number")
    return int(text)


def changes(lines, last, new):
    """(line index, flag name, old value) for each marker above LAST."""
    found = []
    flag = "?"
    for index, line in enumerate(lines):
        case = CASE.match(line)
        if case:
            flag = case.group(1)
        for match in MARKER.finditer(line):
            old = int(match.group(1))
            if old > last and old != new:
                found.append((index, flag, old))
    return found


def flags_command(command, args):
    if len(args) not in (2, 3):
        die("list and set take LAST NEW [FILE]")
    last, new = build_number(args[0]), build_number(args[1])
    if new <= last:
        die(f"the new build {new} is not above the last release build {last}")
    path = pathlib.Path(args[2]) if len(args) == 3 else FLAGS_FILE
    if not path.is_file():
        die(f"no file at {path}")
    lines = path.read_text().splitlines(keepends=True)
    found = changes(lines, last, new)
    if command == "list":
        for _, flag, old in found:
            print(f"{flag} {old} -> {new}")
        return
    for index, _, _ in found:
        lines[index] = MARKER.sub(
            lambda m: f"releasedInBuild: {new}" if int(m.group(1)) > last else m.group(0),
            lines[index])
    path.write_text("".join(lines))
    print(f"release-markers: set {len(found)} marker(s) to {new}")


def heading_index(lines, version):
    for index, line in enumerate(lines):
        if line.rstrip("\n") == f"## {version}":
            return index
    return None


def notes_command(command, args):
    if command == "notes-check":
        if len(args) not in (1, 2):
            die("notes-check takes VERSION [FILE]")
        version, rest = args[0], args[1:]
    else:
        if len(args) not in (2, 3):
            die("notes-date takes VERSION DATE [FILE]")
        version, date, rest = args[0], args[1], args[2:]
    if not SEMVER.match(version):
        die(f"'{version}' is not MAJOR.MINOR.PATCH")
    path = pathlib.Path(rest[0]) if rest else NOTES_FILE
    if not path.is_file():
        die(f"no file at {path}")
    lines = path.read_text().splitlines(keepends=True)
    start = heading_index(lines, version)
    if start is None:
        die(f"{path.name} has no '## {version}' heading")
    if command == "notes-check":
        return
    match = DATE.match(date)
    if not match:
        die(f"'{date}' is not YYYY-MM-DD")
    year, month, day = (int(part) for part in match.groups())
    if not 1 <= month <= 12 or not 1 <= day <= 31:
        die(f"'{date}' is not a real date")
    text = f"{MONTHS[month - 1]} {day}, {year} (UTC)\n"
    # The first line after the heading's blank line is the date, as in the
    # neighbors. Replace a date that is there, else insert one.
    probe = start + 1
    while probe < len(lines) and lines[probe].strip() == "":
        probe += 1
    if probe < len(lines) and DATE_LINE.match(lines[probe].strip()):
        lines[probe] = text
    else:
        lines[start + 1:start + 1] = ["\n", text]
    path.write_text("".join(lines))
    print(f"release-markers: dated {version} {text.strip()}")


def main(argv):
    if not argv:
        die("give a command: list, set, notes-check, or notes-date")
    command, args = argv[0], argv[1:]
    if command in ("list", "set"):
        flags_command(command, args)
    elif command in ("notes-check", "notes-date"):
        notes_command(command, args)
    else:
        die(f"unknown command '{command}'")


if __name__ == "__main__":
    main(sys.argv[1:])
