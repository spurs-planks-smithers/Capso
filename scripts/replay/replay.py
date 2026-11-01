#!/usr/bin/env python3
"""Replay harness for the prompts that Nextshot copies.

It takes saved feedback rounds (scripts/replay/rounds.txt), renders the prompt
for each with `nextshot-prompt`, and runs Claude Code and Codex on it in plan
mode, on the repository as it was when the round started. It saves each
answer as JSON, so two prompt variants can be compared later.

    python3 -I scripts/replay/replay.py --variant today|linked [--runs N]
        [--agents claude,codex] [--only FOLDER[,FOLDER]] [--jobs N]
        [--date YYYY-MM-DD] [--force] [--yes] [--preflight-only]

Output: build/replay/<date>/<round>/<agent>-<variant>-<run>.json.
Without --yes it prints the run count and exits 3. A run whose file already
holds an answer is skipped, so a crash never repeats paid runs (--force redoes
them, and a failed run never replaces a good record). Each record holds the
version of its agent. --preflight-only prepares and checks the rounds, runs
the Codex preflight, and stops. It starts no agent and needs no --yes.
Exit status: 0 when every run is ok, 1 when a run, a round setup, or the
preflight failed, 2 for a bad command line or list, 3 when --yes is missing.

Privacy: the agents see a copy of each round (build/replay/rounds/<folder>),
never the Nextshot folder. The copy is checked before any run. If the check
fails, the copy is deleted and the round is not sent. Claude can read only the
replay worktree and the copy. Codex runs under a read profile that holds the
same two folders (and the system folders), so it cannot read other rounds.
Before the first Codex run, a preflight proves that profile still works in the
installed Codex build, with no vendor call. If it fails, nothing is started.
Ctrl-C or any exit kills the agent process groups, so a paid run stops.
The answers hold Drew's words, so build/ stays out of git.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime
import hashlib
import json
import os
import re
import secrets
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
CLAUDE_MAX_BUDGET_USD = 5  # safety cap per Claude run (claude --max-budget-usd)
TIMEOUT_SECONDS = 20 * 60
PREFLIGHT_TIMEOUT_SECONDS = 60
# What a sandboxed command prints when the sandbox refuses it (lower case).
DENIAL_WORDS = ("not permitted", "permission denied", "read-only file system")
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


def plain_name(name) -> bool:
    """True for a file name that stays inside its folder."""
    return isinstance(name, str) and bool(name) and "/" not in name and name not in (".", "..")


def read_source_round(folder: str) -> dict:
    """The round's feedback.json. It must be a non-empty object with a usable capture list."""
    path = SOURCE_ROOT / folder / "feedback.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise SetupError(f"cannot read the round {folder}: {error}") from error
    if not isinstance(data, dict) or not data:
        raise SetupError(f"{folder}: feedback.json is not a non-empty object")
    if not isinstance(data.get("startedAt"), str):
        raise SetupError(f"{folder}: feedback.json has no startedAt")
    captures = data.get("captures")
    if not isinstance(captures, list) or not captures:
        raise SetupError(f"{folder}: the round holds no captures")
    for capture in captures:
        if not (
            isinstance(capture, dict)
            and isinstance(capture.get("index"), int)
            and plain_name(capture.get("imageFile"))
            and plain_name(capture.get("cleanImageFile"))
        ):
            raise SetupError(f"{folder}: a capture has no usable index or image file name")
    if len({capture["index"] for capture in captures}) != len(captures):
        raise SetupError(f"{folder}: two captures share an index")
    return data


def chosen_indexes(spec: RoundSpec, source: dict) -> list[int]:
    """The capture indexes the copy must hold, in round order. Never empty."""
    have = [capture["index"] for capture in source["captures"]]
    if spec.captures == "all":
        chosen = have
    else:
        wanted = {int(part) for part in spec.captures.split(",")}
        missing = sorted(wanted - set(have))
        if missing:
            raise SetupError(f"{spec.folder}: no capture {missing} in the round")
        chosen = [index for index in have if index in wanted]
    if not chosen:
        raise SetupError(f"{spec.folder}: no capture is chosen")
    return chosen


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
            found.append((f"{label} of capture {index}", text.strip()))

    for field in ("windowTitle", "sourceApp", "note", "imageFile", "cleanImageFile", "ocrText"):
        add(field, capture.get(field))
    for line in (capture.get("ocrText") or "").splitlines():
        add("ocrText line", line, MIN_OCR_LINE)
    for mark in capture.get("marks") or []:
        for field in ("instruction", "ocrText", "textOnImage"):
            add(f"mark {field}", mark.get(field))
    return found


def file_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_copy(copy_dir: Path, source_dir: Path, source: dict, chosen: list[int]) -> list[str]:
    """Checks a round copy and returns what was checked. Raises SetupError on any problem.

    Fails closed: the copy must hold exactly feedback.json, manifest.md, and the
    chosen PNGs, and each PNG must equal its source by SHA-256. Its feedback.json
    must hold exactly the chosen captures, equal to the source. No string of an
    excluded capture may appear in any file. A gate never runs on an empty set:
    an empty capture list, folder, parse, or needle list aborts the round.
    """
    included = [capture for capture in source["captures"] if capture["index"] in chosen]
    excluded = [capture for capture in source["captures"] if capture["index"] not in chosen]
    if not chosen or not included or len(included) != len(chosen):
        raise SetupError("the chosen captures are empty or do not match the round")
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
    if not found:
        problems.append("the copy folder is empty")
    for name in sorted(found - expected):
        problems.append(f"extra file in the copy: {name}")
    for name in sorted(expected - found):
        problems.append(f"file missing from the copy: {name}")
    report.append(f"files: {len(found)} found, {len(expected)} expected (feedback.json, manifest.md, {len(expected) - 2} PNG)")

    # Each PNG must be the same bytes as its source.
    compared = 0
    for capture in included:
        for name in (capture["imageFile"], capture["cleanImageFile"]):
            copied, original = copy_dir / name, source_dir / name
            if not copied.is_file() or not original.is_file():
                problems.append(f"cannot compare the PNG with its source: {name}")
            elif file_digest(copied) != file_digest(original):
                problems.append(f"PNG differs from the source: {name}")
            compared += 1
    if compared == 0:
        problems.append("no PNG was compared with its source")
    report.append(f"PNG: {compared} files, SHA-256 equal to the source")

    texts: dict[str, str] = {}
    try:
        copy_round = json.loads((copy_dir / "feedback.json").read_text(encoding="utf-8"))
        parsed = True
    except (OSError, ValueError):
        copy_round, parsed = None, False
        problems.append("feedback.json in the copy cannot be read")
    if parsed:  # a JSON null parses too, and must fail the object check below
        copy_captures = copy_round.get("captures") if isinstance(copy_round, dict) else None
        if not isinstance(copy_round, dict) or not copy_round:
            problems.append("feedback.json in the copy is not a non-empty object")
        elif not isinstance(copy_captures, list) or not copy_captures:
            problems.append("feedback.json in the copy holds no captures")
        else:
            if [c.get("index") if isinstance(c, dict) else None for c in copy_captures] != chosen:
                problems.append("feedback.json holds other captures than the chosen ones")
            if copy_captures != included:
                problems.append("a capture in the copy differs from the source capture")
            if {k: v for k, v in copy_round.items() if k != "captures"} != {k: v for k, v in source.items() if k != "captures"}:
                problems.append("a round field in the copy differs from the source")
            texts["feedback.json"] = "\n".join(all_strings(copy_round))
            report.append(f"feedback.json: captures {chosen} only, each equal to the source, round fields equal")
    try:
        manifest = (copy_dir / "manifest.md").read_text(encoding="utf-8")
    except OSError:
        manifest = ""
    if not manifest.strip():
        problems.append("manifest.md in the copy is missing or empty")
    elif f"Captures: {len(chosen)}." not in manifest:
        problems.append(f"manifest.md does not say Captures: {len(chosen)}")
    texts["manifest.md"] = manifest
    report.append(f"manifest.md: rendered again, says Captures: {len(chosen)}")

    # A string that an included capture also holds proves nothing when found,
    # so it is skipped and named in the report. The equality checks above cover
    # those captures.
    allowed = "\n".join(all_strings(included))
    candidates = [pair for capture in excluded for pair in excluded_strings(capture)]
    needles: list[tuple[str, str]] = []
    skipped: dict[str, int] = {}
    for label, text in candidates:
        if text in allowed:
            skipped[label] = skipped.get(label, 0) + 1
        else:
            needles.append((label, text))
    if excluded and not candidates:
        problems.append("the excluded captures give no string to search for")
    elif excluded and not needles:
        problems.append("every excluded string is also in an included capture, so none can be searched")
    for label, count in skipped.items():
        report.append(f"needle skipped: {label}{f' ({count} lines)' if count > 1 else ''}, also in an included capture")
    hits = 0
    if needles:
        raw = {name: (copy_dir / name).read_bytes() for name in sorted(found) if (copy_dir / name).is_file()}
        if not raw:
            problems.append("the leak scan has no file to search")
        for label, text in needles:
            encoded = text.encode("utf-8")
            for name, data in raw.items():
                if encoded in data or text in texts.get(name, ""):
                    hits += 1
                    problems.append(f"{label} ({len(text)} chars) found in {name}")
    if excluded:
        report.append(
            f"leak scan: {len(needles)} strings from {len(excluded)} excluded captures "
            f"(window title, app, note, file names, OCR, marks) searched in {len(found)} files, "
            f"{sum(skipped.values())} skipped, {hits} found"
        )
    else:
        report.append("leak scan: no capture is excluded")

    if problems:
        raise SetupError("the round copy failed its check: " + "; ".join(problems[:6]))
    return report


def make_copy(spec: RoundSpec, source: dict, chosen: list[int]) -> tuple[Path, list[str]]:
    """Writes the copy with `nextshot-prompt subset` and checks it.

    The copy is deleted on any failure, whatever its type, so an unchecked
    copy never stays on disk. Ctrl-C counts as a failure too.
    """
    target = ROUNDS_DIR / spec.folder
    if ROUNDS_DIR not in target.parents:
        raise SetupError(f"refusing to write outside {ROUNDS_DIR}")
    verified = False
    try:
        if target.exists():
            shutil.rmtree(target)
        ROUNDS_DIR.mkdir(parents=True, exist_ok=True)
        proc = subprocess.run(
            [str(CLI), "subset", str(SOURCE_ROOT), spec.folder, spec.captures, str(ROUNDS_DIR)],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
        if proc.returncode != 0:
            raise SetupError(f"subset failed (exit {proc.returncode}): {proc.stderr.strip()[:300]}")
        report = verify_copy(target, SOURCE_ROOT / spec.folder, source, chosen)
        verified = True
        return target, report
    finally:
        if not verified:
            shutil.rmtree(target, ignore_errors=True)


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


class AgentRegistry:
    """The agent processes that are running, so one call can stop them all."""

    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.live: set[subprocess.Popen] = set()
        self.stopping = False

    def start(self, command: list[str], *, cwd: Path, env: dict) -> subprocess.Popen:
        """Starts a process in its own process group. Refuses once the harness is stopping."""
        with self.lock:
            if self.stopping:
                raise RuntimeError("the harness is stopping")
            proc = subprocess.Popen(
                command, cwd=cwd, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, encoding="utf-8", errors="replace", start_new_session=True,
            )
            self.live.add(proc)
            return proc

    def done(self, proc: subprocess.Popen) -> None:
        with self.lock:
            self.live.discard(proc)

    def kill_group(self, proc: subprocess.Popen) -> None:
        try:
            os.killpg(proc.pid, signal.SIGKILL)  # start_new_session makes the group id the pid
        except OSError:
            pass  # the group is already gone

    def stop_all(self) -> int:
        """Kills every live process group and refuses new ones. Returns how many it killed."""
        with self.lock:
            self.stopping = True
            procs = list(self.live)
        for proc in procs:
            self.kill_group(proc)
        return len(procs)

    def reopen(self) -> None:
        with self.lock:
            self.stopping = False


AGENTS = AgentRegistry()


def run_process(command: list[str], *, stdin_text: str, cwd: Path, env: dict, timeout: int) -> tuple[int, str, str]:
    """Runs a command and returns (status, stdout, stderr). Kills its process group on timeout."""
    proc = AGENTS.start(command, cwd=cwd, env=env)
    try:
        out, err = proc.communicate(stdin_text, timeout=timeout)
    except subprocess.TimeoutExpired:
        AGENTS.kill_group(proc)
        proc.communicate()
        raise
    finally:
        AGENTS.done(proc)
    return proc.returncode, out, err


def run_jobs(jobs: list[Job], work, max_workers: int) -> list[dict]:
    """Runs the jobs in a pool and returns their records.

    On any exit, Ctrl-C included, the live agent process groups are killed
    first and queued jobs are dropped, so a paid run does not go on.
    """
    AGENTS.reopen()
    pool = concurrent.futures.ThreadPoolExecutor(max_workers=max_workers)
    try:
        futures = [pool.submit(work, job) for job in jobs]
        return [future.result() for future in futures]
    finally:
        AGENTS.stop_all()
        pool.shutdown(wait=True, cancel_futures=True)


def claude_command(worktree: Path, copy_dir: Path) -> list[str]:
    """Claude Code in plan mode: three read tools, no hooks, MCP servers, skills, or user files.

    --restricted ignores user and project settings and confines the file tools
    to the working folders. The worktree is also an --add-dir so its CLAUDE.md
    loads (see claude_env). --max-budget-usd caps the spend of one run. The
    prompt goes in on stdin. There is no no-vendor preflight for these flags,
    so each record names the Claude version, and a changed version shows up.
    """
    return [
        "claude", "-p",
        "--model", CLAUDE_MODEL,
        "--allowedTools", "Read,Grep,Glob",
        "--tools", "Read,Grep,Glob",
        "--output-format", "json",
        "--max-budget-usd", str(CLAUDE_MAX_BUDGET_USD),
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


def codex_overrides(worktree: Path, copy_dir: Path) -> list[str]:
    """The -c overrides that confine Codex to one round.

    codex_command (the real run) and codex_preflight (the check) both take the
    overrides from here, so they cannot drift apart. The read profile replaces
    --sandbox read-only, because that mode lets the agent read the whole disk,
    including every other Nextshot round. The profile also denies writes. The
    git folder is left out on purpose, so the agent sees the files of the
    commit only, as the Claude run does. Approvals are off.
    """
    roots = [":minimal", str(worktree), str(copy_dir)]
    if Path("/opt/homebrew").exists():
        roots.append("/opt/homebrew")  # rg and other tools
    profile = "{" + ", ".join(f"{json.dumps(root)}=\"read\"" for root in dict.fromkeys(roots)) + "}"
    return [
        "-c", 'default_permissions="replay"',
        "-c", f"permissions.replay.filesystem={profile}",
        "-c", 'approval_policy="never"',
    ]


def codex_command(worktree: Path, copy_dir: Path, images: list[Path]) -> list[str]:
    """Codex in plan mode, under the read profile of codex_overrides.

    User config, rules, hooks, memories, apps, and plugins are off, so a run
    does not depend on this Mac's setup. --strict-config makes Codex stop on a
    config field it does not know. The prompt goes in on stdin.
    """
    model, effort = codex_settings()
    command = ["codex", "exec", "--json", "--ephemeral", "--ignore-user-config", "--ignore-rules", "--strict-config"]
    if model:
        command += ["-m", model]
    if effort:
        command += ["-c", f"model_reasoning_effort={json.dumps(effort)}"]
    for feature in ("hooks", "memories", "apps", "plugins", "multi_agent", "computer_use", "browser_use"):
        command += ["--disable", feature]
    command += ["-c", 'web_search="disabled"', "-C", str(worktree)]
    command += codex_overrides(worktree, copy_dir)
    for image in images:
        command += ["--image", str(image)]
    return command


def sandbox_run(overrides: list[str], cwd: Path, argv: list[str]) -> tuple[int, str]:
    """Runs argv under `codex sandbox` with the overrides. Returns (status, lower-case stderr).

    No vendor call happens. The command's output is thrown away: only the
    status and the refusal message matter, so no file content is ever read.
    The process folder is the worktree, as `-C` is for codex exec. (`codex
    sandbox -C` would need a named profile, which is a different path from
    default_permissions.)
    """
    proc = subprocess.run(
        ["codex", "sandbox", *overrides, "--", *argv],
        cwd=cwd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        text=True, encoding="utf-8", errors="replace", timeout=PREFLIGHT_TIMEOUT_SECONDS,
    )
    return proc.returncode, proc.stderr.lower()


def codex_preflight(contexts: dict[str, RoundContext]) -> list[str]:
    """Proves, before the first Codex run, that the read profile works in the installed Codex build.

    It makes no vendor call. It runs small commands under `codex sandbox` with
    the same overrides as the real run, and under `codex debug prompt-input`
    (which only renders the prompt). It fails closed: any check that does not
    behave as expected raises SetupError, and the harness starts nothing.
    Every denied check also needs a refusal message, so a command that failed
    for another reason (a missing file, a broken codex) cannot pass.
    """
    if not contexts:
        raise SetupError("codex preflight: no round to check")
    token = secrets.token_hex(8)
    canary = REPLAY / f"preflight-canary-{token}.txt"
    cleanup: list[Path] = [canary]
    passed: list[str] = []
    failed: list[str] = []

    def check(name: str, ok: bool) -> None:
        (passed if ok else failed).append(name)

    def readable(overrides: list[str], cwd: Path, path: Path) -> bool:
        return sandbox_run(overrides, cwd, ["/usr/bin/head", "-c", "1", str(path)])[0] == 0

    def refused(status_and_error: tuple[int, str]) -> bool:
        status, error = status_and_error
        return status != 0 and any(word in error for word in DENIAL_WORDS)

    try:
        REPLAY.mkdir(parents=True, exist_ok=True)
        canary.write_text(token, encoding="utf-8")  # outside every allowed folder
        folders = list(contexts)
        for folder, context in contexts.items():
            overrides = codex_overrides(context.worktree, context.copy_dir)
            cwd = context.worktree
            head = ["/usr/bin/head", "-c", "1"]
            tree_files = [p for p in sorted(context.worktree.iterdir()) if p.is_file() and p.name != ".git"]
            check(f"{folder}: a file in the copy is readable", readable(overrides, cwd, context.copy_dir / "manifest.md"))
            check(
                f"{folder}: a file in the worktree is readable",
                bool(tree_files) and readable(overrides, cwd, tree_files[0]),
            )
            check(f"{folder}: a canary file outside the allowed folders is refused", refused(sandbox_run(overrides, cwd, [*head, str(canary)])))
            check(f"{folder}: the Nextshot rounds folder cannot be listed", refused(sandbox_run(overrides, cwd, ["/bin/ls", str(SOURCE_ROOT)])))
            check(
                f"{folder}: a real round file in the Nextshot folder is refused",
                refused(sandbox_run(overrides, cwd, [*head, str(SOURCE_ROOT / folder / "feedback.json")])),
            )
            if CODEX_CONFIG.exists():
                check(f"{folder}: ~/.codex/config.toml is refused", refused(sandbox_run(overrides, cwd, [*head, str(CODEX_CONFIG)])))
            for label, directory in (("worktree", context.worktree), ("copy", context.copy_dir)):
                probe = directory / f".preflight-write-{token}"
                cleanup.append(probe)
                result = sandbox_run(overrides, cwd, ["/usr/bin/touch", str(probe)])
                check(f"{folder}: a write into the {label} is refused", refused(result) and not probe.exists())
            for other in folders:
                if other != folder:
                    check(
                        f"{folder}: the copy of round {other} is refused",
                        refused(sandbox_run(overrides, cwd, [*head, str(contexts[other].copy_dir / "manifest.md")])),
                    )

        # The prompt Codex would see must say read-only and never ask for approval.
        first = next(iter(contexts.values()))
        proc = subprocess.run(
            ["codex", "debug", "prompt-input", *codex_overrides(first.worktree, first.copy_dir), "x"],
            cwd=first.worktree, capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=PREFLIGHT_TIMEOUT_SECONDS,
        )
        try:
            permissions = [t for t in all_strings(json.loads(proc.stdout)) if "<permissions instructions>" in t]
        except ValueError:
            permissions = []
        check(
            "the prompt Codex would see says sandbox_mode read-only and approval never",
            bool(permissions) and all(
                "`sandbox_mode` is `read-only`" in t and "Approval policy is currently never" in t for t in permissions
            ),
        )
    finally:
        for path in cleanup:
            path.unlink(missing_ok=True)

    if failed:
        raise SetupError("codex preflight failed: " + "; ".join(failed))
    return passed


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


def tool_version(command: str) -> str:
    """The first line of `<command> --version`. It makes no vendor call."""
    try:
        proc = subprocess.run(
            [command, "--version"], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SetupError(f"cannot run {command} --version: {error}") from error
    lines = proc.stdout.strip().splitlines()
    if proc.returncode != 0 or not lines:
        raise SetupError(f"{command} --version printed no version")
    return lines[0].strip()


def run_job(job: Job, context: RoundContext, variant: str, agent_version: str) -> dict:
    """Runs one agent once and returns the record to save."""
    record = {
        "round": job.spec.folder, "agent": job.agent, "variant": variant, "run": job.run,
        "commit": context.commit, "captures": context.captures, "model": None, "agent_version": agent_version,
        "output": "", "tokens": {"input": 0, "output": 0}, "status": "error", "error": None, "seconds": 0.0,
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


def is_done(path: Path) -> bool:
    """True when the file holds an answer. A failed run has an empty output."""
    try:
        return bool(json.loads(path.read_text(encoding="utf-8")).get("output"))
    except (OSError, ValueError, AttributeError):
        return False


def save_unless_good(path: Path, record: dict) -> bool:
    """Saves the record, except that a failure never replaces a good record (--force). Returns True if saved."""
    if record["status"] != "ok" and is_done(path):
        return False
    save_record(path, record)
    return True


def status_line(record: dict) -> str:
    tokens = record["tokens"]
    detail = f"in {tokens['input']} out {tokens['output']}"
    cost = f" ${record['cost_usd']:.2f}" if isinstance(record.get("cost_usd"), (int, float)) else ""
    error = f" ({record['error'][:80]})" if record["status"] != "ok" and record["error"] else ""
    return (
        f"{record['round']} {record['agent']} run {record['run']}: {record['status']} "
        f"{record['seconds']}s {detail}{cost}{error}"
    )


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
    parser.add_argument("--preflight-only", action="store_true", help="prepare the rounds, run the Codex preflight, and stop")
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


def setup_round(spec: RoundSpec, variant: str, output_dir: Path, with_prompt: bool) -> tuple[RoundContext, list[str]]:
    """Copies and checks one round, finds its commit and worktree, and renders its prompt.

    Returns the context and the lines to print. Any failure raises, and
    nothing is sent for that round.
    """
    source = read_source_round(spec.folder)
    chosen = chosen_indexes(spec, source)
    copy_dir, lines = make_copy(spec, source, chosen)
    commit = commit_for(source["startedAt"])
    worktree = ensure_worktree(spec.folder, commit)
    images = [copy_dir / capture["imageFile"] for capture in source["captures"] if capture["index"] in chosen]
    if not images or not all(image.is_file() for image in images):
        raise SetupError("the copy has no image to attach")
    prompt = ""
    if with_prompt:
        prompt = build_prompt(spec.folder, variant)
        prompt_file = output_dir / spec.folder / f"prompt-{variant}.txt"
        prompt_file.parent.mkdir(parents=True, exist_ok=True)
        prompt_file.write_text(prompt, encoding="utf-8")
    lines.append(f"commit {commit[:7]}, worktree {worktree.relative_to(REPO)}, {len(images)} images")
    return RoundContext(commit, worktree, copy_dir, prompt, images, spec.captures), lines


def run(args: argparse.Namespace) -> int:
    try:
        specs = select_rounds(read_rounds(ROUNDS_FILE), args.only)
    except SetupError as error:
        say(f"error: {error}")
        return 2

    output_dir = REPLAY / args.date
    planned: list[Job] = []
    skipped = 0
    for spec in specs:
        for run_number in range(1, args.runs + 1):
            for agent in args.agents:
                path = output_dir / spec.folder / f"{agent}-{args.variant}-{run_number}.json"
                if is_done(path) and not args.force:
                    skipped += 1
                else:
                    planned.append(Job(spec, agent, run_number, path))

    total = len(specs) * len(args.agents) * args.runs
    say(
        f"Variant {args.variant}: {len(specs)} rounds x {len(args.agents)} agents x {args.runs} runs = {total}, "
        f"{skipped} already done, {len(planned)} to run."
    )
    for spec in specs:
        say(f"  {spec.folder}" + ("" if spec.captures == "all" else f" (captures {spec.captures} only)"))
    if args.preflight_only:
        targets = specs
    else:
        if not planned:
            say("Nothing to run.")
            return 0
        if not args.yes:
            say("Nothing was started. Add --yes to run.")
            return 3
        targets = [spec for spec in specs if any(job.spec == spec for job in planned)]

    try:
        versions = {agent: tool_version(agent) for agent in args.agents}
        build_cli()
    except SetupError as error:
        say(f"error: {error}")
        return 1
    say("Agents: " + "; ".join(f"{agent} {version}" for agent, version in versions.items()))

    failures = 0
    contexts: dict[str, RoundContext] = {}
    for spec in targets:
        jobs = [] if args.preflight_only else [job for job in planned if job.spec == spec]
        try:
            context, lines = setup_round(spec, args.variant, output_dir, with_prompt=not args.preflight_only)
        except Exception as error:  # whatever the cause, nothing is sent for this round
            failures += 1
            say(f"{spec.folder}: NOT SENT. {type(error).__name__}: {str(error)[:600]}")
            for job in jobs:
                saved = save_unless_good(job.path, {
                    "round": spec.folder, "agent": job.agent, "variant": args.variant, "run": job.run,
                    "commit": None, "model": None, "agent_version": versions[job.agent], "output": "",
                    "tokens": {"input": 0, "output": 0}, "status": "error",
                    "error": f"setup failed: {str(error)[:250]}", "seconds": 0.0,
                })
                if not saved:
                    say(f"    kept the earlier good record: {job.path.name}")
            planned = [job for job in planned if job.spec != spec]
            continue
        contexts[spec.folder] = context
        say(f"{spec.folder}: copy checked")
        for line in lines:
            say(f"    {line}")

    codex_contexts = {
        folder: context for folder, context in contexts.items()
        if "codex" in args.agents and (args.preflight_only or any(
            job.agent == "codex" and job.spec.folder == folder for job in planned))
    }
    if codex_contexts:
        try:
            checks = codex_preflight(codex_contexts)
        except Exception as error:  # a failed or broken preflight stops everything
            say(f"PREFLIGHT FAILED. No agent was started. {type(error).__name__}: {str(error)[:900]}")
            return 1
        say(f"codex preflight ok, {len(checks)} checks, no vendor call:")
        for name in checks:
            say(f"    ok: {name}")
    elif args.preflight_only:
        say("Nothing to preflight: no Codex round was prepared.")

    if args.preflight_only:
        return 1 if failures else 0

    def execute(job: Job) -> dict:
        record = run_job(job, contexts[job.spec.folder], args.variant, versions[job.agent])
        saved = save_unless_good(job.path, record)
        say(status_line(record) + ("" if saved else " [kept the earlier good record]"))
        return record

    records = run_jobs(planned, execute, args.jobs)
    failures += sum(1 for record in records if record["status"] != "ok")

    for folder, context in contexts.items():
        dirty = git("status", "--porcelain", cwd=context.worktree)
        if dirty:
            say(f"WARNING: {folder} worktree changed during the runs:\n{dirty[:300]}")
            failures += 1

    ok = sum(1 for record in records if record["status"] == "ok")
    say(f"Done: {ok} of {len(records)} runs ok, {failures} failures. Output: {output_dir.relative_to(REPO)}")
    return 1 if failures else 0


def main(argv: list[str]) -> int:
    args = parse_arguments(argv)

    def on_signal(signum, frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGHUP, on_signal)
    try:
        return run(args)
    except KeyboardInterrupt:
        say("Interrupted. The agent processes were stopped.")
        return 130
    finally:
        AGENTS.stop_all()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
