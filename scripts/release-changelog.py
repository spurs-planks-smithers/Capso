#!/usr/bin/env python3
"""Fork: the CHANGELOG.md steps of a Nextshot release (scripts/release.sh).

Usage:
  release-changelog.py check [FILE]                 exit 0 when Unreleased has a bullet
  release-changelog.py rotate VERSION DATE [FILE]   Unreleased becomes VERSION
  release-changelog.py notes VERSION [FILE]         print the notes of VERSION

FILE defaults to CHANGELOG.md next to the scripts folder. The format is Keep a
Changelog 1.1.0: a "## [Unreleased]" heading, then "## [X.Y.Z] - YYYY-MM-DD"
headings, newest first.
"""
import pathlib
import re
import sys

DEFAULT_FILE = pathlib.Path(__file__).resolve().parent.parent / "CHANGELOG.md"
UNRELEASED = "## [Unreleased]"
SEMVER = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
DATE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$")


def die(message):
    print(f"release-changelog: {message}", file=sys.stderr)
    sys.exit(1)


def section(lines, heading_prefix):
    """The (start, end) line numbers of the lines under a heading, or None."""
    for index, line in enumerate(lines):
        if line.startswith(heading_prefix):
            end = len(lines)
            for later in range(index + 1, len(lines)):
                if lines[later].startswith("## ["):
                    end = later
                    break
            return index + 1, end
    return None


def read(path):
    try:
        return pathlib.Path(path).read_text(encoding="utf-8").split("\n")
    except OSError as error:
        die(f"cannot read {path}: {error}")


def bullets(lines, bounds):
    start, end = bounds
    return [line for line in lines[start:end] if line.startswith("- ")]


def check(path):
    lines = read(path)
    bounds = section(lines, UNRELEASED)
    if bounds is None:
        die(f"no '{UNRELEASED}' heading in {path}")
    if not bullets(lines, bounds):
        die("Unreleased has no entry. Add one line for each change a person can see.")


def rotate(version, date, path):
    if not SEMVER.match(version):
        die(f"'{version}' is not MAJOR.MINOR.PATCH")
    if not DATE.match(date):
        die(f"'{date}' is not YYYY-MM-DD")
    lines = read(path)
    if section(lines, f"## [{version}]") is not None:
        die(f"{path} already has a section for {version}")
    bounds = section(lines, UNRELEASED)
    if bounds is None:
        die(f"no '{UNRELEASED}' heading in {path}")
    if not bullets(lines, bounds):
        die("Unreleased has no entry. Add one line for each change a person can see.")
    index = bounds[0] - 1
    lines[index : index + 1] = [UNRELEASED, "", f"## [{version}] - {date}"]
    pathlib.Path(path).write_text("\n".join(lines), encoding="utf-8")


def notes(version, path):
    lines = read(path)
    bounds = section(lines, f"## [{version}]")
    if bounds is None:
        die(f"no section for {version} in {path}")
    text = "\n".join(lines[bounds[0] : bounds[1]]).strip()
    if not text:
        die(f"the section for {version} is empty")
    print(text)


def main(argv):
    if len(argv) >= 2 and argv[1] == "check" and len(argv) <= 3:
        check(argv[2] if len(argv) == 3 else DEFAULT_FILE)
    elif len(argv) >= 4 and argv[1] == "rotate" and len(argv) <= 5:
        rotate(argv[2], argv[3], argv[4] if len(argv) == 5 else DEFAULT_FILE)
    elif len(argv) >= 3 and argv[1] == "notes" and len(argv) <= 4:
        notes(argv[2], argv[3] if len(argv) == 4 else DEFAULT_FILE)
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main(sys.argv)
