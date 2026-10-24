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

# The decision rules of DupesConflictsJob. Keep this line in step with the
# constants in Packages/JevKit/Sources/JevKit/Jobs/DupesConflictsJob.swift.
# The test "scripts/nextshot-jev-review.sh uses the job's thresholds" in
# DupesConflictsJobTests fails when the two differ.
THRESHOLDS="conflictAt=0.7 duplicateAt=1.5 overlapAt=0.5"

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
limits = dict(part.split("=", 1) for part in os.environ["REVIEW_THRESHOLDS"].split())
CONFLICT_AT = float(limits["conflictAt"])
DUPLICATE_AT = float(limits["duplicateAt"])
OVERLAP_AT = float(limits["overlapAt"])
BAR_MIN = int(os.environ["REVIEW_BAR_MIN"])
BAR_MAX_WRONG = int(os.environ["REVIEW_BAR_MAX_WRONG"])


def outcome(same_ask, opposite):
    """The job's decision rules. A conflict wins over a duplicate."""
    if opposite is not None and opposite >= CONFLICT_AT:
        return "conflict"
    if same_ask is None:
        return "different"
    if same_ask >= DUPLICATE_AT:
        return "duplicate"
    if same_ask >= OVERLAP_AT:
        return "overlap"
    return "different"


def load(path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as error:
        print(f"Skipped {path.name} in {path.parent.name}: {error}", file=sys.stderr)
        return None


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


def flagged_calls(jev):
    """Every pair whose outcome is not 'different', in pair order."""
    values = {}
    for capture in (jev or {}).get("captures", []):
        for job in capture.get("jobs", []):
            if job.get("job") != JOB:
                continue
            version = job.get("jobVersion")
            for answer in job.get("answers", []):
                parts = split_question_id(answer.get("id", ""))
                if parts is None:
                    continue
                new, earlier, kind = parts
                values.setdefault((new, earlier, version), {})[kind] = answer_value(answer)
    calls = []
    for (new, earlier, version), pair in values.items():
        call = outcome(pair.get("sameAsk"), pair.get("opposite"))
        if call != "different":
            calls.append({
                "pair": f"{new}.vs.{earlier}",
                "new": new,
                "earlier": earlier,
                "jobVersion": version,
                "outcome": call,
                "sameAsk": pair.get("sameAsk"),
                "opposite": pair.get("opposite"),
            })
    calls.sort(key=lambda call: (entry_key(call["new"]), entry_key(call["earlier"])))
    return calls


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
counts = {call: {"labeled": 0, "right": 0} for call in FLAGGED}
unlabeled = 0
stopped = False

for folder in folders:
    calls = flagged_calls(load(folder / "jev.json"))
    if not calls:
        continue
    stored = (load(folder / "jev-labels.json") or {}).get("labels", [])
    labels = {label_key(item): item for item in stored}
    notes = notes_by_id(load(folder / "feedback.json"))
    changed = False

    for call in calls:
        key = (JOB, call["jobVersion"], call["pair"], call["outcome"])
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
print(f"Duplicates and conflicts: labels across {len(folders)} {'round' if len(folders) == 1 else 'rounds'} with jev.json")
print(f"{'Call':<12}{'Labeled':>8}{'Right':>7}{'Wrong':>7}  Share right")
for call in FLAGGED:
    labeled = counts[call]["labeled"]
    right = counts[call]["right"]
    share = f"{100 * right / labeled:.0f}%" if labeled else "n/a"
    print(f"{call:<12}{labeled:>8}{right:>7}{labeled - right:>7}  {share}")
print(f"Flagged calls with no label: {unlabeled}")
print()
print(f"Bar for on: at least {BAR_MIN} labeled calls with at most {BAR_MAX_WRONG} wrong, for duplicates and for conflicts.")
for call, name in (("duplicate", "Duplicates"), ("conflict", "Conflicts")):
    labeled = counts[call]["labeled"]
    wrong = labeled - counts[call]["right"]
    meets = labeled >= BAR_MIN and wrong <= BAR_MAX_WRONG
    print(f"- {name}: {'meets the bar' if meets else 'not yet'} ({labeled} labeled, {wrong} wrong).")
PY

REVIEW_ROOT="$root" REVIEW_MODE="$mode" REVIEW_THRESHOLDS="$THRESHOLDS" \
  REVIEW_BAR_MIN="$BAR_MIN" REVIEW_BAR_MAX_WRONG="$BAR_MAX_WRONG" \
  exec /usr/bin/python3 -I -c "$program"
