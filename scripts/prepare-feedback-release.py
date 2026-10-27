#!/usr/bin/env python3
"""Prepare the support flag for 0.5.0 without committing or releasing."""

import argparse
import re
import subprocess
import sys
from pathlib import Path

TARGET = "0.5.0"
PREVIOUS = re.compile(r"0\.4\.(0|[1-9][0-9]*)")
FLAG_PATH = Path("Packages/FeedbackKit/Sources/FeedbackKit/FeatureFlags.swift")
SPEC = re.compile(
    r"(?P<prefix>case \.supportSubmission:\s*\n\s*"
    r"FlagSpec\(issue: 0, allowedStates: \[\.off, \.on\], devDefault: )"
    r"(?P<dev>\.off|\.on)(?P<middle>, releaseDefault: )"
    r"(?P<release>\.off|\.on)(?P<build>, releasedInBuild: )"
    r"(?P<marker>nil|[0-9]+)(?P<suffix>\))"
)


def git(*args):
    result = subprocess.run(
        ["git", *args], capture_output=True, text=True, stdin=subprocess.DEVNULL
    )
    if result.returncode:
        raise ValueError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--plan", action="store_true", help="report only (default)")
    modes.add_argument("--apply", action="store_true", help="edit only the support flag")
    modes.add_argument("--verify", action="store_true", help="check the committed activation before release")
    args = parser.parse_args()
    root = Path(git("rev-parse", "--show-toplevel"))
    if Path.cwd().resolve() != root.resolve():
        raise ValueError("Run from the repository root.")
    source_path = root / FLAG_PATH
    source = source_path.read_text()
    matches = list(SPEC.finditer(source))
    if len(matches) != 1 or source.count("case .supportSubmission:") != 1:
        raise ValueError("Expected exactly one unchanged supportSubmission spec shape.")
    match = matches[0]
    count = int(git("rev-list", "--count", "HEAD"))
    problems = []
    if git("branch", "--show-current") != "main":
        problems.append("checkout must be main")
    if git("status", "--porcelain", "--untracked-files=all"):
        problems.append("working tree must be clean")
    if git("rev-parse", "HEAD") != git("rev-parse", "refs/remotes/origin/main"):
        problems.append("HEAD must equal origin/main; fetch origin first")
    if not PREVIOUS.fullmatch((root / "VERSION").read_text().strip()):
        problems.append("VERSION must remain 0.4.x, below target 0.5.0")
    if git("tag", "--list", f"nextshot-v{TARGET}"):
        problems.append(f"nextshot-v{TARGET} already exists; never replace a release")
    if args.verify:
        if (match["dev"], match["release"], match["marker"]) != (".on", ".on", str(count + 1)):
            problems.append("activation defaults or build marker differ; expected on/on and HEAD count + 1")
    elif (match["dev"], match["release"], match["marker"]) != (".off", ".off", "nil"):
        problems.append("supportSubmission must still be off/off with no released-in build")
    print(f"Target: {TARGET}; HEAD count: {count}")
    if not args.apply and not args.verify:
        print(f"Planned marker: {count + 2} (activation commit + normal release commit)")
        print("Apply blocked: " + "; ".join(problems) if problems else "Ready to apply after the release graph is frozen.")
        return
    if problems:
        raise ValueError("; ".join(problems))
    if args.verify:
        print(f"Verified: release build must be {count + 1}. Run the normal release command next, with no other commits.")
        return
    replacement = (
        match["prefix"] + ".on" + match["middle"] + ".on" + match["build"]
        + str(count + 2) + match["suffix"]
    )
    updated = source[:match.start()] + replacement + source[match.end():]
    # This replacement changes only the uniquely matched flag spec.
    source_path.write_text(updated)
    print(f"Applied only {FLAG_PATH}; releasedInBuild={count + 2}.")
    print("Review the diff. Commit this activation once. Do not add any other commits before release.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as error:
        print(f"prepare-feedback-release: {error}", file=sys.stderr)
        sys.exit(1)
