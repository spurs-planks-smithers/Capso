#!/usr/bin/env python3
"""Replay harness for the prompts that Nextshot copies.

It takes saved feedback rounds (scripts/replay/rounds.txt), renders the prompt
for each with `nextshot-prompt`, and runs Claude Code and Codex on it in plan
mode, on the repository as it was when the round started. It saves each
answer as JSON, so two prompt variants can be compared later.

    python3 -I scripts/replay/replay.py --variant today|linked [--runs N]
        [--agents claude,codex] [--only FOLDER[,FOLDER]] [--jobs N]
        [--date YYYY-MM-DD] [--force] [--yes]

Output: build/replay/<date>/<round>/<agent>-<variant>-<run>.json.
Without --yes it prints the run count and exits 3. A run whose file already
holds an answer is skipped, so a crash never repeats paid runs (--force redoes).
Exit status: 0 when every run is ok, 1 when a run or a round setup failed,
2 for a bad command line or list, 3 when --yes is missing.

Privacy: the agents see a copy of each round (build/replay/rounds/<folder>),
never the Nextshot folder. The copy is checked before any run. If the check
fails, the copy is deleted and the round is not sent. Claude can read only the
replay worktree and the copy. Codex runs under a read profile that holds the
same two folders (and the system folders), so it cannot read other rounds.
The answers hold Drew's words, so build/ stays out of git.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import NamedTuple

try:
    import tomllib
except ImportError:  # Python older than 3.11
    tomllib = None

REPO = Path(__file__).resolve().parents[2]
REPLAY = REPO / "build" / "replay"
ROUNDS_DIR = REPLAY / "rounds"
WORKTREES = REPLAY / "worktrees"
ROUNDS_FILE = Path(__file__).resolve().parent / "rounds.txt"
SOURCE_ROOT = Path.home() / "Library" / "Application Support" / "Nextshot"
PACKAGE = REPO / "Packages" / "FeedbackKit"
CLI = PACKAGE / ".build" / "debug" / "nextshot-prompt"
CODEX_CONFIG = Path.home() / ".codex" / "config.toml"

CLAUDE_MODEL = "claude-opus-5-5"
TIMEOUT_SECONDS = 20 * 60
FOLDER_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}-\d{4}-[A-Za-z0-9._-]+$")
MIN_NEEDLE = 4  # shortest excluded string the privacy check searches for
MIN_OCR_LINE = 12  # shortest excluded OCR line the privacy check searches for

FINAL_LINE = {
    "today": "Replay run: write your plan table, any groups of related items, and your questions. Make no edit.",
    "linked": "Replay run: write the Links section, the plan table, and your questions. Make no edit.",
}

print_lock = threading.Lock()


class SetupError(Exception):
    """A round cannot be prepared. The message says why."""


class RoundSpec(NamedTuple):
    folder: str
    captures: str  # "all" or a comma list such as "3,4"


class Job(NamedTuple):
    spec: RoundSpec
    agent: str
    run: int
    path: Path


def say(message: str) -> None:
    with print_lock:
        print(message, flush=True)


# ---------------------------------------------------------------------------
# The list of rounds
# ---------------------------------------------------------------------------


def read_rounds(path: Path) -> list[RoundSpec]:
    """Reads rounds.txt: `<folder>` or `<folder> captures=3,4` per line."""
    specs: list[RoundSpec] = []
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        words = line.split()
        folder, options = words[0], words[1:]
        if not FOLDER_PATTERN.match(folder):
            raise SetupError(f"{path.name} line {number}: not a round folder name: {folder}")
        captures = "all"
        for option in options:
            if option.startswith("captures=") and re.fullmatch(r"captures=\d+(,\d+)*", option):
                captures = option.split("=", 1)[1]
            else:
                raise SetupError(f"{path.name} line {number}: cannot read: {option}")
        if any(spec.folder == folder for spec in specs):
            raise SetupError(f"{path.name} line {number}: {folder} is listed twice")
        specs.append(RoundSpec(folder, captures))
    if not specs:
        raise SetupError(f"{path.name} lists no rounds")
    return specs


def select_rounds(specs: list[RoundSpec], only: list[str]) -> list[RoundSpec]:
    """Keeps the rounds named by --only. A name outside rounds.txt is an error."""
    if not only:
        return specs
    known = {spec.folder for spec in specs}
    for name in only:
        if name not in known:
            raise SetupError(f"--only {name}: not in {ROUNDS_FILE.name}")
    return [spec for spec in specs if spec.folder in only]


# ---------------------------------------------------------------------------
# The round copy and its check
# ---------------------------------------------------------------------------


def read_source_round(folder: str) -> dict:
    path = SOURCE_ROOT / folder / "feedback.json"
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise SetupError(f"cannot read the round {folder}: {error}") from error


def chosen_indexes(spec: RoundSpec, source: dict) -> list[int]:
    """The capture indexes the copy must hold, in round order."""
    have = [capture["index"] for capture in source["captures"]]
    if spec.captures == "all":
        return have
    wanted = {int(part) for part in spec.captures.split(",")}
    missing = sorted(wanted - set(have))
    if missing:
        raise SetupError(f"{spec.folder}: no capture {missing} in the round")
    return [index for index in have if index in wanted]


def all_strings(value) -> list[str]:
    """Every string value inside a parsed JSON value."""
    if isinstance(value, str):
        return [value]
    if isinstance(value, dict):
        return [text for item in value.values() for text in all_strings(item)]
    if isinstance(value, list):
        return [text for item in value for text in all_strings(item)]
    return []


def excluded_strings(capture: dict) -> list[tuple[str, str]]:
    """(label, text) pairs from one excluded capture that must not reach the copy."""
    index = capture["index"]
    found: list[tuple[str, str]] = []

    def add(label: str, text, minimum: int = MIN_NEEDLE) -> None:
        if isinstance(text, str) and len(text.strip()) >= minimum:
            found.append((f"capture {index} {label}", text.strip()))

    for field in ("windowTitle", "note", "imageFile", "cleanImageFile", "ocrText"):
        add(field, capture.get(field))
    for line in (capture.get("ocrText") or "").splitlines():
        add("ocrText line", line, MIN_OCR_LINE)
    for mark in capture.get("marks") or []:
        for field in ("instruction", "ocrText", "textOnImage"):
            add(f"mark {field}", mark.get(field))
    return found


def verify_copy(copy_dir: Path, source: dict, chosen: list[int]) -> list[str]:
    """Checks a round copy and returns what was checked. Raises SetupError on any problem.

    Fails closed: the copy must hold exactly feedback.json, manifest.md, and the
    chosen PNGs. Its feedback.json must hold exactly the chosen captures, equal
    to the source. No string of an excluded capture may appear in any file.
    """
    included = [capture for capture in source["captures"] if capture["index"] in chosen]
    excluded = [capture for capture in source["captures"] if capture["index"] not in chosen]
    problems: list[str] = []
    report: list[str] = []

    expected = {"feedback.json", "manifest.md"}
    for capture in included:
        expected |= {capture["imageFile"], capture["cleanImageFile"]}
    found: set[str] = set()
    for entry in os.scandir(copy_dir):
        found.add(entry.name)
        if entry.is_symlink() or not entry.is_file(follow_symlinks=False):
            problems.append(f"not a plain file: {entry.name}")
    for name in sorted(found - expected):
        problems.append(f"extra file in the copy: {name}")
    for name in sorted(expected - found):
        problems.append(f"file missing from the copy: {name}")
    report.append(f"files: {len(found)} found, {len(expected)} expected (feedback.json, manifest.md, {len(expected) - 2} PNG)")

    texts: dict[str, str] = {}
    try:
        copy_round = json.loads((copy_dir / "feedback.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        copy_round = {}
        problems.append("feedback.json in the copy cannot be read")
    if copy_round:
        if [capture.get("index") for capture in copy_round.get("captures", [])] != chosen:
            problems.append("feedback.json holds other captures than the chosen ones")
        if copy_round.get("captures") != included:
            problems.append("a capture in the copy differs from the source capture")
        if {k: v for k, v in copy_round.items() if k != "captures"} != {k: v for k, v in source.items() if k != "captures"}:
            problems.append("a round field in the copy differs from the source")
        texts["feedback.json"] = "\n".join(all_strings(copy_round))
        report.append(f"feedback.json: captures {chosen} only, each equal to the source, round fields equal")
    try:
        manifest = (copy_dir / "manifest.md").read_text(encoding="utf-8")
    except OSError:
        manifest = ""
        problems.append("manifest.md in the copy cannot be read")
    if f"Captures: {len(chosen)}." not in manifest:
        problems.append(f"manifest.md does not say Captures: {len(chosen)}")
    texts["manifest.md"] = manifest
    report.append(f"manifest.md: rendered again, says Captures: {len(chosen)}")

    # A string that an included capture also holds proves nothing when found,
    # so it is skipped. The equality checks above cover those captures.
    allowed = "\n".join(all_strings(included))
    needles: list[tuple[str, str]] = []
    skipped = 0
    for capture in excluded:
        for label, text in excluded_strings(capture):
            if text in allowed:
                skipped += 1
            else:
                needles.append((label, text))
    hits = 0
    if needles:
        raw = {name: (copy_dir / name).read_bytes() for name in sorted(found) if (copy_dir / name).is_file()}
        for label, text in needles:
            encoded = text.encode("utf-8")
            for name, data in raw.items():
                if encoded in data or text in texts.get(name, ""):
                    hits += 1
                    problems.append(f"{label} ({len(text)} chars) found in {name}")
    if excluded:
        report.append(
            f"leak scan: {len(needles)} strings from {len(excluded)} excluded captures "
            f"(window title, note, file names, OCR, marks) searched in {len(found)} files, "
            f"{skipped} skipped (also in an included capture), {hits} found"
        )
    else:
        report.append("leak scan: no capture is excluded")

    if problems:
        raise SetupError("the round copy failed its check: " + "; ".join(problems[:6]))
    return report


def make_copy(spec: RoundSpec, source: dict, chosen: list[int]) -> tuple[Path, list[str]]:
    """Writes the copy with `nextshot-prompt subset` and checks it. Deletes it if the check fails."""
    target = ROUNDS_DIR / spec.folder
    if ROUNDS_DIR not in target.parents:
        raise SetupError(f"refusing to write outside {ROUNDS_DIR}")
    if target.exists():
        shutil.rmtree(target)
    ROUNDS_DIR.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        [str(CLI), "subset", str(SOURCE_ROOT), spec.folder, spec.captures, str(ROUNDS_DIR)],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    if proc.returncode != 0:
        shutil.rmtree(target, ignore_errors=True)
        raise SetupError(f"subset failed (exit {proc.returncode}): {proc.stderr.strip()[:300]}")
    try:
        report = verify_copy(target, source, chosen)
    except SetupError:
        shutil.rmtree(target, ignore_errors=True)
        raise
    return target, report


# ---------------------------------------------------------------------------
# The repository at the time of the round
# ---------------------------------------------------------------------------


def git(*args: str, cwd: Path = REPO) -> str:
    proc = subprocess.run(
        ["git", "-C", str(cwd), *args], capture_output=True, text=True, encoding="utf-8", errors="replace"
    )
    if proc.returncode != 0:
        raise SetupError(f"git {' '.join(args)} failed: {proc.stderr.strip()[:300]}")
    return proc.stdout.strip()


def commit_for(started_at: str) -> str:
    """The last commit of origin/main before the round started."""
    try:
        git("rev-parse", "--verify", "--quiet", "origin/main")
    except SetupError as error:
        raise SetupError("origin/main is missing; run git fetch origin") from error
    commit = git("rev-list", "-1", f"--before={started_at}", "origin/main")
    if not commit:
        raise SetupError(f"origin/main has no commit before {started_at}")
    return commit


def ensure_worktree(folder: str, commit: str) -> Path:
    """The worktree of `commit` for one round. A worktree that already exists at that commit is reused."""
    path = WORKTREES / folder
    if path.exists():
        if not (path / ".git").exists():
            raise SetupError(f"{path} exists but is not a worktree; remove it")
        head = git("rev-parse", "HEAD", cwd=path)
        if head != commit:
            raise SetupError(f"{path} is at {head[:7]}, not {commit[:7]}; remove it with git worktree remove")
        return path
    WORKTREES.mkdir(parents=True, exist_ok=True)
    git("worktree", "add", "--detach", str(path), commit)
    return path


# ---------------------------------------------------------------------------
# The prompt
# ---------------------------------------------------------------------------


def build_prompt(folder: str, variant: str) -> str:
    """The prompt Nextshot copies for the round copy, plus the replay line."""
    command = [str(CLI), "round", str(ROUNDS_DIR), folder]
    if variant == "linked":
        command.append("--linked")
    proc = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if proc.returncode != 0:
        raise SetupError(f"nextshot-prompt round failed (exit {proc.returncode}): {proc.stderr.strip()[:300]}")
    text = proc.stdout if proc.stdout.endswith("\n") else proc.stdout + "\n"
    return text + FINAL_LINE[variant] + "\n"


# ---------------------------------------------------------------------------
# Running an agent
# ---------------------------------------------------------------------------


def run_process(command: list[str], *, stdin_text: str, cwd: Path, env: dict, timeout: int) -> tuple[int, str, str]:
    """Runs a command and returns (status, stdout, stderr). Kills its process group on timeout."""
    proc = subprocess.Popen(
        command, cwd=cwd, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8", errors="replace", start_new_session=True,
    )
    try:
        out, err = proc.communicate(stdin_text, timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(proc.pid, signal.SIGKILL)
        proc.communicate()
        raise
    return proc.returncode, out, err


def claude_command(worktree: Path, copy_dir: Path) -> list[str]:
    """Claude Code in plan mode: three read tools, no hooks, MCP servers, skills, or user files.

    --restricted ignores user and project settings and confines the file tools
    to the working folders. The worktree is also an --add-dir so its CLAUDE.md
    loads (see claude_env). The prompt goes in on stdin.
    """
    return [
        "claude", "-p",
        "--model", CLAUDE_MODEL,
        "--allowedTools", "Read,Grep,Glob",
        "--tools", "Read,Grep,Glob",
        "--output-format", "json",
        "--restricted", "--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence",
        "--add-dir", str(worktree), str(copy_dir),
    ]


def claude_env() -> dict:
    env = dict(os.environ)
    env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"  # no user memory
    env["CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD"] = "1"  # load CLAUDE.md of the --add-dir worktree
    return env


def parse_claude(stdout: str) -> dict:
    """Reads the JSON that `claude -p --output-format json` prints (one object, or a list of events)."""
    data = json.loads(stdout)
    events = data if isinstance(data, list) else [data]
    init = next((e for e in events if e.get("type") == "system" and e.get("subtype") == "init"), {})
    result = next((e for e in reversed(events) if e.get("type") == "result"), None)
    if result is None:
        raise ValueError("no result event in the Claude output")
    usage = result.get("usage") or {}
    models = list((result.get("modelUsage") or {}).keys())
    text = result.get("result") if isinstance(result.get("result"), str) else ""
    failed = bool(result.get("is_error")) or result.get("subtype") != "success"
    return {
        "output": "" if failed else text,
        "error": (text[:300] or str(result.get("subtype"))) if failed else None,
        "model": init.get("model") or (models[0] if models else CLAUDE_MODEL),
        "tokens": {
            "input": int(usage.get("input_tokens") or 0)
            + int(usage.get("cache_creation_input_tokens") or 0)
            + int(usage.get("cache_read_input_tokens") or 0),
            "output": int(usage.get("output_tokens") or 0),
        },
        "cost_usd": result.get("total_cost_usd"),
        "turns": result.get("num_turns"),
        "denials": len(result.get("permission_denials") or []),
    }


def codex_settings() -> tuple[str | None, str | None]:
    """The model and reasoning effort in the user's Codex config, if any."""
    if tomllib is None or not CODEX_CONFIG.exists():
        return None, None
    try:
        with CODEX_CONFIG.open("rb") as handle:
            config = tomllib.load(handle)
    except (OSError, ValueError):
        return None, None
    model, effort = config.get("model"), config.get("model_reasoning_effort")
    return (model if isinstance(model, str) else None), (effort if isinstance(effort, str) else None)


def codex_command(worktree: Path, copy_dir: Path, images: list[Path]) -> list[str]:
    """Codex in plan mode, under a read profile that holds only the worktree, the copy, and system folders.

    The profile is used instead of --sandbox read-only, because that mode lets
    the agent read the whole disk, including every other Nextshot round. The
    profile also denies writes. The git folder is left out on purpose, so the
    agent sees the files of the commit only, as the Claude run does. User
    config, rules, hooks, memories, apps, and plugins are off, so a run does
    not depend on this Mac's setup.
    """
    roots = [":minimal", str(worktree), str(copy_dir)]
    if Path("/opt/homebrew").exists():
        roots.append("/opt/homebrew")  # rg and other tools
    profile = "{" + ", ".join(f"{json.dumps(root)}=\"read\"" for root in dict.fromkeys(roots)) + "}"

    model, effort = codex_settings()
    command = ["codex", "exec", "--json", "--ephemeral", "--ignore-user-config", "--ignore-rules"]
    if model:
        command += ["-m", model]
    if effort:
        command += ["-c", f"model_reasoning_effort={json.dumps(effort)}"]
    for feature in ("hooks", "memories", "apps", "plugins", "multi_agent", "computer_use", "browser_use"):
        command += ["--disable", feature]
    command += ["-c", 'web_search="disabled"', "-C", str(worktree)]
    command += ["-c", 'default_permissions="replay"', "-c", f"permissions.replay.filesystem={profile}"]
    for image in images:
        command += ["--image", str(image)]
    return command  # the prompt goes in on stdin


def parse_codex(stdout: str, model: str | None) -> dict:
    """Reads the JSONL events of `codex exec --json`.

    Events seen: thread.started, turn.started, item.started and item.completed
    (item types agent_message with `text`, command_execution), turn.completed
    with `usage`, and error or turn.failed on failure. The answer is the last
    agent_message. The stream names no model, so the model comes from the config.
    """
    messages: list[str] = []
    errors: list[str] = []
    usage = {"input_tokens": 0, "cached_input_tokens": 0, "output_tokens": 0, "reasoning_output_tokens": 0}
    completed = False
    for line in stdout.splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        kind = event.get("type")
        item = event.get("item") or {}
        if kind == "item.completed" and item.get("type") == "agent_message" and isinstance(item.get("text"), str):
            messages.append(item["text"])
        elif kind == "turn.completed":
            completed = True
            for key in usage:
                usage[key] += int((event.get("usage") or {}).get(key) or 0)
        elif kind in ("error", "turn.failed"):
            errors.append(str(event.get("message") or (event.get("error") or {}).get("message") or kind)[:300])
    if errors or not completed or not messages:
        return {
            "output": "", "error": (errors[0] if errors else "no completed turn with an answer"),
            "model": model or "codex-default", "tokens": {"input": usage["input_tokens"], "output": usage["output_tokens"]},
        }
    return {
        "output": messages[-1], "error": None, "model": model or "codex-default",
        # input_tokens already counts the cached tokens.
        "tokens": {"input": usage["input_tokens"], "output": usage["output_tokens"]},
        "cached_input_tokens": usage["cached_input_tokens"],
        "reasoning_output_tokens": usage["reasoning_output_tokens"],
    }


class RoundContext(NamedTuple):
    commit: str
    worktree: Path
    copy_dir: Path
    prompt: str
    images: list[Path]
    captures: str


def run_job(job: Job, context: RoundContext, variant: str) -> dict:
    """Runs one agent once and returns the record to save."""
    record = {
        "round": job.spec.folder, "agent": job.agent, "variant": variant, "run": job.run,
        "commit": context.commit, "captures": context.captures, "model": None, "output": "",
        "tokens": {"input": 0, "output": 0}, "status": "error", "error": None, "seconds": 0.0,
    }
    record["model"] = CLAUDE_MODEL if job.agent == "claude" else (codex_settings()[0] or "codex-default")
    started = time.monotonic()
    try:
        if job.agent == "claude":
            command, env = claude_command(context.worktree, context.copy_dir), claude_env()
        else:
            command, env = codex_command(context.worktree, context.copy_dir, context.images), dict(os.environ)
        status, out, err = run_process(
            command, stdin_text=context.prompt, cwd=context.worktree, env=env, timeout=TIMEOUT_SECONDS
        )
        try:
            parsed = parse_claude(out) if job.agent == "claude" else parse_codex(out, codex_settings()[0])
        except ValueError:
            parsed = {"error": f"{job.agent} exited with status {status} and printed no readable result: {err.strip()[:200]}"}
        record.update(parsed)
        if status != 0 and record["error"] is None:
            record["error"] = f"{job.agent} exited with status {status}: {err.strip()[:200]}"
        if record["error"] is None and not record["output"]:
            record["error"] = "empty answer"
        if record["error"] is not None:
            record["output"] = ""
        record["status"] = "error" if record["error"] is not None else "ok"
    except subprocess.TimeoutExpired:
        record["error"] = "timeout"
    except Exception as error:  # one failed run must not stop the others
        record["error"] = f"{type(error).__name__}: {str(error)[:250]}"
    record["seconds"] = round(time.monotonic() - started, 1)
    return record


def save_record(path: Path, record: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def status_line(record: dict) -> str:
    tokens = record["tokens"]
    detail = f"in {tokens['input']} out {tokens['output']}"
    cost = f" ${record['cost_usd']:.2f}" if isinstance(record.get("cost_usd"), (int, float)) else ""
    error = f" ({record['error'][:80]})" if record["status"] != "ok" and record["error"] else ""
    return (
        f"{record['round']} {record['agent']} run {record['run']}: {record['status']} "
        f"{record['seconds']}s {detail}{cost}{error}"
    )


def is_done(path: Path) -> bool:
    """True when the file holds an answer. A failed run has an empty output."""
    try:
        return bool(json.loads(path.read_text(encoding="utf-8")).get("output"))
    except (OSError, ValueError):
        return False


# ---------------------------------------------------------------------------
# The command line
# ---------------------------------------------------------------------------


def build_cli() -> None:
    """Builds nextshot-prompt, so the harness uses the current source."""
    proc = subprocess.run(
        ["swift", "build", "--package-path", str(PACKAGE), "--product", "nextshot-prompt"],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    if proc.returncode != 0 or not CLI.exists():
        raise SetupError("swift build of nextshot-prompt failed:\n" + proc.stdout[-600:] + proc.stderr[-600:])


def parse_arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Replay saved Nextshot rounds through Claude Code and Codex.")
    parser.add_argument("--variant", required=True, choices=sorted(FINAL_LINE))
    parser.add_argument("--runs", type=int, default=1, help="runs per round and agent (default 1)")
    parser.add_argument("--agents", default="claude,codex", help="comma list of claude, codex")
    parser.add_argument("--only", action="append", default=[], help="folder name(s) from rounds.txt, comma list or repeated")
    parser.add_argument("--jobs", type=int, default=2, help="runs at the same time (default 2)")
    parser.add_argument("--date", default=datetime.date.today().isoformat(), help="output folder date (default today)")
    parser.add_argument("--force", action="store_true", help="run again even when a file holds an answer")
    parser.add_argument("--yes", action="store_true", help="start the runs")
    args = parser.parse_args(argv)
    args.only = [name for item in args.only for name in item.split(",") if name]
    args.agents = [name for name in args.agents.split(",") if name]
    if args.runs < 1 or args.jobs < 1:
        parser.error("--runs and --jobs must be 1 or more")
    if not args.agents or any(name not in ("claude", "codex") for name in args.agents):
        parser.error("--agents takes claude, codex, or both")
    try:
        datetime.date.fromisoformat(args.date)
    except ValueError:
        parser.error("--date must be YYYY-MM-DD")
    return args


def main(argv: list[str]) -> int:
    args = parse_arguments(argv)
    try:
        specs = select_rounds(read_rounds(ROUNDS_FILE), args.only)
    except SetupError as error:
        say(f"error: {error}")
        return 2

    output_dir = REPLAY / args.date
    planned: list[Job] = []
    skipped = 0
    for spec in specs:
        for run in range(1, args.runs + 1):
            for agent in args.agents:
                path = output_dir / spec.folder / f"{agent}-{args.variant}-{run}.json"
                if is_done(path) and not args.force:
                    skipped += 1
                else:
                    planned.append(Job(spec, agent, run, path))

    total = len(specs) * len(args.agents) * args.runs
    say(
        f"Variant {args.variant}: {len(specs)} rounds x {len(args.agents)} agents x {args.runs} runs = {total}, "
        f"{skipped} already done, {len(planned)} to run."
    )
    for spec in specs:
        say(f"  {spec.folder}" + ("" if spec.captures == "all" else f" (captures {spec.captures} only)"))
    if not planned:
        say("Nothing to run.")
        return 0
    if not args.yes:
        say("Nothing was started. Add --yes to run.")
        return 3

    try:
        build_cli()
    except SetupError as error:
        say(f"error: {error}")
        return 1

    failures = 0
    contexts: dict[str, RoundContext] = {}
    for spec in specs:
        jobs = [job for job in planned if job.spec == spec]
        if not jobs:
            continue
        try:
            source = read_source_round(spec.folder)
            chosen = chosen_indexes(spec, source)
            copy_dir, report = make_copy(spec, source, chosen)
            say(f"{spec.folder}: copy checked")
            for line in report:
                say(f"    {line}")
            commit = commit_for(source["startedAt"])
            worktree = ensure_worktree(spec.folder, commit)
            prompt = build_prompt(spec.folder, args.variant)
            copy_round = json.loads((copy_dir / "feedback.json").read_text(encoding="utf-8"))
            images = [copy_dir / capture["imageFile"] for capture in copy_round["captures"]]
            save_prompt = output_dir / spec.folder / f"prompt-{args.variant}.txt"
            save_prompt.parent.mkdir(parents=True, exist_ok=True)
            save_prompt.write_text(prompt, encoding="utf-8")
            contexts[spec.folder] = RoundContext(commit, worktree, copy_dir, prompt, images, spec.captures)
            say(f"    commit {commit[:7]}, worktree {worktree.relative_to(REPO)}, {len(images)} images")
        except (SetupError, KeyError, ValueError, OSError) as error:
            failures += 1
            say(f"{spec.folder}: NOT SENT. {error}")
            for job in jobs:
                save_record(job.path, {
                    "round": spec.folder, "agent": job.agent, "variant": args.variant, "run": job.run,
                    "commit": None, "model": None, "output": "", "tokens": {"input": 0, "output": 0},
                    "status": "error", "error": f"setup failed: {str(error)[:250]}", "seconds": 0.0,
                })
            planned = [job for job in planned if job.spec != spec]

    def execute(job: Job) -> dict:
        record = run_job(job, contexts[job.spec.folder], args.variant)
        save_record(job.path, record)
        say(status_line(record))
        return record

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        records = list(pool.map(execute, planned))
    failures += sum(1 for record in records if record["status"] != "ok")

    for folder, context in contexts.items():
        dirty = git("status", "--porcelain", cwd=context.worktree)
        if dirty:
            say(f"WARNING: {folder} worktree changed during the runs:\n{dirty[:300]}")
            failures += 1

    ok = len(records) - sum(1 for record in records if record["status"] != "ok")
    say(f"Done: {ok} of {len(records)} runs ok, {failures} failures. Output: {output_dir.relative_to(REPO)}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
