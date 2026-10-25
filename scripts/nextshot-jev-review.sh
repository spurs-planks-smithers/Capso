#!/bin/bash
# Fork: review the shadow answers of a Jev job. Label each flagged call right
# or wrong, then print the share right and whether the job meets the bar for on.
#
# It reads jev.json and feedback.json in each round folder and writes
# jev-labels.json next to them. It sends nothing over the network.
#
# Usage: scripts/nextshot-jev-review.sh dupes            label new calls, then report
#        scripts/nextshot-jev-review.sh dupes --report   report only
#
# NEXTSHOT_ROUNDS_DIR replaces the rounds folder. Use it to try the script on
# test data.
set -euo pipefail

root="${NEXTSHOT_ROUNDS_DIR:-$HOME/Library/Application Support/Nextshot}"

# The job writes each flagged pair's outcome in the summary of its jev.json
# record, so this script needs none of the job's thresholds.

# The bar for on (Drew, 2026-10-24): at least BAR_MIN labeled calls with at
# most BAR_MAX_WRONG wrong, for duplicates and for conflicts.
BAR_MIN=10
BAR_MAX_WRONG=1

usage() {
  echo "Usage: $0 dupes [--report]" >&2
  exit 2
}

[[ "${1:-}" == "dupes" ]] || usage
mode="label"
if [[ $# -eq 2 ]]; then
  [[ "$2" == "--report" ]] || usage
  mode="report"
elif [[ $# -ne 1 ]]; then
  usage
fi
if [[ ! -d "$root" ]]; then
  echo "No rounds folder at $root." >&2
  exit 1
fi

# The program comes from a variable, so stdin stays free for the y and n answers.
read -r -d '' program <<'PY' || true
import datetime
import json
import os
import sys
import tempfile
from pathlib import Path

JOB = "dupesConflicts"
FLAGGED = ["duplicate", "overlap", "conflict"]
CALL_TEXT = {
    "duplicate": "same ask",
    "overlap": "may overlap",
    "conflict": "opposite changes (conflict)",
}

root = Path(os.environ["REVIEW_ROOT"])
mode = os.environ["REVIEW_MODE"]
BAR_MIN = int(os.environ["REVIEW_BAR_MIN"])
BAR_MAX_WRONG = int(os.environ["REVIEW_BAR_MAX_WRONG"])


class Unreadable(Exception):
    """A file exists but is not a JSON object."""


def load(path):
    """The JSON object in `path`, or None when the file does not exist.
    Raises Unreadable for a file that exists but is not a JSON object."""
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as error:
        raise Unreadable(f"{path.name} in {path.parent.name}: {error}")
    if not isinstance(value, dict):
        raise Unreadable(f"{path.name} in {path.parent.name}: not a JSON object")
    return value


def entry_key(entry_id):
    """Sorts K.N and K.note ids by capture, then badge, with the note last."""
    capture, _, badge = entry_id.partition(".")
    try:
        return (int(capture), 10**6 if badge == "note" else int(badge))
    except ValueError:
        return (10**6, 10**6)


def notes_by_id(feedback):
    found = {}
    for capture in (feedback or {}).get("captures", []):
        index = capture.get("index")
        for mark in capture.get("marks", []):
            text = mark.get("instruction") or ""
            if mark.get("kind") == "counter" and mark.get("badge") is not None and text.strip():
                found[f"{index}.{mark['badge']}"] = text
        note = capture.get("note") or ""
        if note.strip():
            found[f"{index}.note"] = note
    return found


def split_question_id(question_id):
    """'4.2.vs.3.2.sameAsk' gives ('4.2', '3.2', 'sameAsk')."""
    new, separator, rest = question_id.partition(".vs.")
    earlier, _, kind = rest.rpartition(".")
    if not separator or not new or not earlier or kind not in ("sameAsk", "opposite"):
        return None
    return new, earlier, kind


def answer_value(answer):
    if answer.get("type") == "score":
        return answer.get("score")
    if answer.get("type") == "noul":
        return answer.get("noul", answer.get("probability"))
    return None


def job_records(jev):
    for capture in (jev or {}).get("captures", []):
        for job in capture.get("jobs", []):
            if isinstance(job, dict) and job.get("job") == JOB:
                yield job


def flagged_calls(jev):
    """Every flagged pair in the job's summary, in pair order. The answers
    give the numbers to show next to each call."""
    calls = []
    for job in job_records(jev):
        values = {}
        for answer in job.get("answers", []):
            parts = split_question_id(answer.get("id", ""))
            if parts is not None:
                new, earlier, kind = parts
                values.setdefault((new, earlier), {})[kind] = answer_value(answer)
        summary = job.get("summary")
        flagged = summary.get("flagged", []) if isinstance(summary, dict) else []
        for item in flagged:
            if not isinstance(item, dict) or item.get("outcome") not in FLAGGED:
                continue
            new, separator, earlier = str(item.get("pair", "")).partition(".vs.")
            if not separator or not new or not earlier:
                continue
            pair = values.get((new, earlier), {})
            calls.append({
                "pair": f"{new}.vs.{earlier}",
                "new": new,
                "earlier": earlier,
                "jobVersion": job.get("jobVersion"),
                "outcome": item["outcome"],
                "sameAsk": pair.get("sameAsk"),
                "opposite": pair.get("opposite"),
            })
    calls.sort(key=lambda call: (entry_key(call["new"]), entry_key(call["earlier"])))
    return calls


def not_checked(jev, version):
    """Entries whose request failed, for the given job version."""
    count = 0
    for job in job_records(jev):
        summary = job.get("summary")
        if job.get("jobVersion") == version and isinstance(summary, dict):
            count += len(summary.get("notChecked", []))
    return count


def label_key(item):
    return (item.get("job"), item.get("jobVersion"), item.get("pair"), item.get("outcome"))


def save_labels(folder, labels):
    """Writes jev-labels.json through a temporary file, so a reader never sees half a file."""
    path = folder / "jev-labels.json"
    body = json.dumps({"schemaVersion": 1, "labels": labels}, indent=2, ensure_ascii=False) + "\n"
    handle, temporary = tempfile.mkstemp(dir=folder, prefix=".jev-labels-", suffix=".json")
    with os.fdopen(handle, "w", encoding="utf-8") as file:
        file.write(body)
    os.replace(temporary, path)


def number(value):
    return "n/a" if value is None else f"{value:.2f}"


def ask(prompt):
    while True:
        try:
            answer = input(prompt).strip().lower()
        except EOFError:
            return "q"
        if answer in ("y", "n", "s", "q"):
            return answer
        print("Type y, n, s, or q.")


folders = sorted(path.parent for path in root.glob("*/jev.json"))

# First pass: read every round. A round with a file that cannot be read is
# skipped as a whole, so its labels are never overwritten.
rounds = []
records = []
for folder in folders:
    try:
        jev = load(folder / "jev.json")
        calls = flagged_calls(jev)
        stored = load(folder / "jev-labels.json") or {}
        notes = notes_by_id(load(folder / "feedback.json"))
    except Unreadable as error:
        print(f"Skipped round {folder.name}: {error}. Fix or move the file, then run again.", file=sys.stderr)
        continue
    stored_labels = stored.get("labels", [])
    if not isinstance(stored_labels, list) or not all(isinstance(item, dict) for item in stored_labels):
        print(f"Skipped round {folder.name}: jev-labels.json has no list of labels. Fix or move the file, then run again.", file=sys.stderr)
        continue
    records.append(jev)
    if calls:
        rounds.append((folder, calls, stored_labels, notes))

# The bar counts only the newest job version: a new version means new
# questions, and old answers must never mix with new ones.
versions = [call["jobVersion"] for _, calls, _, _ in rounds for call in calls if isinstance(call["jobVersion"], int)]
current = max(versions) if versions else None

counts = {call: {"labeled": 0, "right": 0} for call in FLAGGED}
unlabeled = 0
older = 0
stopped = False

for folder, calls, stored_labels, notes in rounds:
    labels = {label_key(item): item for item in stored_labels}
    changed = False

    for call in calls:
        key = (JOB, call["jobVersion"], call["pair"], call["outcome"])
        if call["jobVersion"] != current:
            older += 1 if key in labels else 0
            continue
        if key not in labels and mode == "label" and not stopped:
            print()
            print(f"Round {folder.name}, pair {call['new']} and {call['earlier']}")
            print(f"Jev's call: {CALL_TEXT[call['outcome']]} (sameAsk {number(call['sameAsk'])}, opposite {number(call['opposite'])})")
            print(f"  {call['new']}: {notes.get(call['new'], 'n/a')}")
            print(f"  {call['earlier']}: {notes.get(call['earlier'], 'n/a')}")
            answer = ask("Is the call right? y = right, n = wrong, s = skip, q = stop: ")
            if answer == "q":
                stopped = True
            elif answer in ("y", "n"):
                labels[key] = {
                    "job": JOB,
                    "jobVersion": call["jobVersion"],
                    "pair": call["pair"],
                    "outcome": call["outcome"],
                    "right": answer == "y",
                    "labeledAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                }
                changed = True
        if key in labels:
            counts[call["outcome"]]["labeled"] += 1
            counts[call["outcome"]]["right"] += 1 if labels[key].get("right") else 0
        else:
            unlabeled += 1

    if changed:
        save_labels(folder, list(labels.values()))

print()
print(f"Duplicates and conflicts, job version {current if current is not None else 'n/a'}: labels across {len(rounds)} {'round' if len(rounds) == 1 else 'rounds'} with flagged calls")
print(f"{'Call':<12}{'Labeled':>8}{'Right':>7}{'Wrong':>7}  Share right")
for call in FLAGGED:
    labeled = counts[call]["labeled"]
    right = counts[call]["right"]
    share = f"{100 * right / labeled:.0f}%" if labeled else "n/a"
    print(f"{call:<12}{labeled:>8}{right:>7}{labeled - right:>7}  {share}")
print(f"Flagged calls with no label: {unlabeled}")
if older:
    print(f"Labels for older job versions, not counted: {older}")
missed = sum(not_checked(jev, current) for jev in records)
if missed:
    print(f"Entries not checked, because a request failed: {missed}")
print()
print(f"Bar for on: at least {BAR_MIN} labeled calls with at most {BAR_MAX_WRONG} wrong, for duplicates and for conflicts.")
for call, name in (("duplicate", "Duplicates"), ("conflict", "Conflicts")):
    labeled = counts[call]["labeled"]
    wrong = labeled - counts[call]["right"]
    meets = labeled >= BAR_MIN and wrong <= BAR_MAX_WRONG
    print(f"- {name}: {'meets the bar' if meets else 'not yet'} ({labeled} labeled, {wrong} wrong).")
PY

REVIEW_ROOT="$root" REVIEW_MODE="$mode" \
  REVIEW_BAR_MIN="$BAR_MIN" REVIEW_BAR_MAX_WRONG="$BAR_MAX_WRONG" \
  exec /usr/bin/python3 -I -c "$program"
