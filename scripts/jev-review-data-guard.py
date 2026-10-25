#!/usr/bin/env python3
"""Build jev-review-data-guard.html for one feedback round (issue #79, dev tool).

Drew runs this to judge the Jev "data guard" job in shadow mode.

Usage:
  python3 scripts/jev-review-data-guard.py [--round PATH] [--no-open]

Input: a round folder with feedback.json and jev.json. The default is the
newest folder under ~/Library/Application Support/Nextshot that holds both,
and whose jev.json has a dataGuard record.
Output: jev-review-data-guard.html in the round folder, then `open` shows it.
The app never writes or reads this file. The page has no script, no form,
and no external asset. Python 3 standard library only.

The script never reads screen text. The dataGuard summary holds none, and the
script does not read ocrText, windowTitle, or mark text from feedback.json.
Every string from the two files goes through html.escape, rule names included.
Every box is untrusted: the script draws a box only when it is four finite
numbers.
"""

import argparse
import html
import json
import math
import os
import struct
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote

JOB_NAME = "dataGuard"
OUTPUT_NAME = "jev-review-data-guard.html"
STORE = Path.home() / "Library" / "Application Support" / "Nextshot"
MAX_IMAGE_WIDTH = 900

# Outline color by kind, in the summary's order. A tag letter repeats the kind
# on each box, so color is never the only cue. A kind that is not listed gets
# the fallback color and the letter "?".
KIND_COLORS = {
    "contact": "#0969da",
    "numbers": "#0f766e",
    "secrets": "#8250df",
    "faces": "#bf3989",
}
KIND_FALLBACK = "#1f2933"
# A Jev box with cover false, and an injection box.
LOW_COLOR = "#6e7781"
INJECTION_COLOR = "#c44f00"

NA = '<span class="na">n/a</span>'

CSS = """
body { font: 13.5px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
  color: #1f2933; background: #fff; margin: 24px auto 48px; max-width: 1280px; padding: 0 16px; }
h1, h2 { color: #14213d; font-weight: 600; }
h1 { font-size: 20px; margin: 0 0 6px; }
h2 { font-size: 16px; margin: 36px 0 4px; }
p { margin: 4px 0; }
table { border-collapse: collapse; width: 100%; margin-top: 10px; }
th, td { text-align: left; vertical-align: top; padding: 6px 8px; border-bottom: 1px solid #e3e6ea;
  overflow-wrap: break-word; }
th { color: #14213d; font-weight: 600; border-bottom: 1px solid #c3c9d0; white-space: nowrap; }
.na, .k { color: #7b8794; }
.shot { position: relative; margin: 10px 0 4px; border: 1px solid #d5d9de; line-height: 0; }
.shot img { display: block; width: 100%; height: auto; }
.box { position: absolute; box-sizing: border-box; border: 2px solid; }
.local { border-style: solid; }
.jev, .low { border-style: dashed; }
.injection { border: 3px solid; }
.tag { position: absolute; left: -2px; top: -2px; color: #fff; font: 600 11px/14px -apple-system, Helvetica, Arial, sans-serif;
  padding: 0 4px; }
.swatch { display: inline-block; width: 9px; height: 9px; margin-right: 5px; }
.legend { margin-top: 8px; color: #52606d; }
.legend span.item { display: inline-block; margin-right: 16px; white-space: nowrap; }
.legend .line { display: inline-block; width: 18px; height: 0; margin-right: 5px; vertical-align: middle; }
"""


def fail(message):
    print(f"jev-review-data-guard: {message}", file=sys.stderr)
    sys.exit(1)


def esc(value):
    return html.escape(str(value), quote=True)


def is_number(value):
    """A finite int or float. A huge int that overflows a float is not one."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return False
    try:
        return math.isfinite(float(value))
    except OverflowError:
        return False


def as_dict(value):
    return value if isinstance(value, dict) else {}


def as_list(value):
    return value if isinstance(value, list) else []


def read_json(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except OSError as error:
        fail(f"cannot read {path}: {error}")
    except (ValueError, RecursionError) as error:
        fail(f"{path} is not valid JSON: {error}")


def quiet_json(path):
    """The parsed file, or None when it cannot be read or parsed."""
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError, RecursionError):
        return None


def job_of(record):
    """The dataGuard job in one capture's jev.json record, or None."""
    for job in as_list(as_dict(record).get("jobs")):
        if isinstance(job, dict) and job.get("job") == JOB_NAME:
            return job
    return None


def has_job(jev):
    return any(job_of(record) for record in as_list(as_dict(jev).get("captures")))


def newest_round():
    if not STORE.is_dir():
        fail(f"{STORE} does not exist. Pass --round PATH.")
    folders = sorted((p for p in STORE.iterdir() if p.is_dir()), key=lambda p: p.name, reverse=True)
    for folder in folders:
        if (folder / "feedback.json").is_file() and has_job(quiet_json(folder / "jev.json")):
            return folder
    fail(f"no folder under {STORE} holds feedback.json and a jev.json with a {JOB_NAME} record. Pass --round PATH.")


def png_size(path):
    """Width and height from the PNG header, or None."""
    try:
        with open(path, "rb") as handle:
            head = handle.read(24)
    except OSError:
        return None
    if len(head) == 24 and head[:8] == b"\x89PNG\r\n\x1a\n" and head[12:16] == b"IHDR":
        return struct.unpack(">II", head[16:24])
    return None


def number_text(value):
    return str(int(value)) if float(value).is_integer() else f"{value:g}"


def prob_text(value):
    return f"{value:.2f}" if is_number(value) else NA


def count_text(value):
    return esc(number_text(value)) if is_number(value) else NA


def text_or_na(value):
    if isinstance(value, str) and value.strip():
        return esc(value.strip())
    if is_number(value):
        return esc(number_text(value))
    return NA


def names_html(value):
    """A list of rule or place names as escaped text, or n/a when it holds none."""
    names = [n.strip() for n in as_list(value) if isinstance(n, str) and n.strip()]
    return esc(", ".join(names)) if names else NA


def valid_box(value):
    """[x1, y1, x2, y2] as four finite numbers with x2 > x1 and y2 > y1, or None."""
    numbers = as_list(value)
    if len(numbers) != 4 or not all(is_number(n) for n in numbers):
        return None
    x1, y1, x2, y2 = numbers
    if x2 <= x1 or y2 <= y1:
        return None
    return x1, y1, x2, y2


def box_of(value, width, height):
    """A valid box clamped to the image, or None."""
    box = valid_box(value)
    if box is None or not width or not height:
        return None
    x1, y1, x2, y2 = box
    x1, x2 = max(0, x1), min(width, x2)
    y1, y2 = max(0, y1), min(height, y2)
    if x2 <= x1 or y2 <= y1:
        return None
    return x1, y1, x2, y2


def kind_style(name):
    """(color, tag letter) for a kind name from the file."""
    if isinstance(name, str) and name in KIND_COLORS:
        return KIND_COLORS[name], name[0].upper()
    return KIND_FALLBACK, "?"


def overlay(css_class, box, width, height, color, tag, title):
    x1, y1, x2, y2 = box
    style = (
        f"left:{x1 / width * 100:.3f}%;top:{y1 / height * 100:.3f}%;"
        f"width:{(x2 - x1) / width * 100:.3f}%;height:{(y2 - y1) / height * 100:.3f}%;"
        f"border-color:{color}"
    )
    inner = f'<span class="tag" style="background:{color}">{esc(tag)}</span>'
    return f'<div class="box {css_class}" style="{style}" title="{esc(title)}">{inner}</div>'


def kind_entries(summary):
    return [k for k in as_list(summary.get("kinds")) if isinstance(k, dict)]


def render_overlays(summary, width, height):
    """Injection boxes first, then Jev boxes, then local hits on top."""
    parts = []
    for value in as_list(as_dict(summary.get("injection")).get("boxes")):
        box = box_of(value, width, height)
        if box:
            parts.append(overlay("injection", box, width, height, INJECTION_COLOR, "I", "injection line"))
    kinds = kind_entries(summary)
    for entry in kinds:
        color, letter = kind_style(entry.get("kind"))
        jev = as_dict(entry.get("jev"))
        box = box_of(jev.get("box"), width, height)
        if box:
            if jev.get("cover") is True:
                parts.append(overlay("jev", box, width, height, color, letter, "Jev box, cover true"))
            else:
                parts.append(overlay("low", box, width, height, LOW_COLOR, letter, "Jev box, cover false"))
    for entry in kinds:
        color, letter = kind_style(entry.get("kind"))
        for hit in as_list(entry.get("local")):
            box = box_of(as_dict(hit).get("box"), width, height)
            if box:
                rule = as_dict(hit).get("rule")
                title = f"local hit, {rule}" if isinstance(rule, str) and rule else "local hit"
                parts.append(overlay("local", box, width, height, color, letter, title))
    return "".join(parts)


def rule_counts(hits):
    """Distinct rule names in order, with a count after any that repeat."""
    counts = {}
    for hit in hits:
        rule = hit.get("rule")
        if isinstance(rule, str) and rule.strip():
            counts[rule.strip()] = counts.get(rule.strip(), 0) + 1
    if not counts:
        return NA
    return ", ".join(esc(rule) + (f" ({n})" if n > 1 else "") for rule, n in counts.items())


def table(head, rows):
    return (
        "<table><thead><tr>" + "".join(f"<th>{esc(h)}</th>" for h in head) + "</tr></thead><tbody>"
        + "".join("<tr>" + "".join(f"<td>{cell}</td>" for cell in row) + "</tr>" for row in rows)
        + "</tbody></table>"
    )


def kind_row(entry):
    """One row of the kinds table. A hit with no usable box is found, not placed."""
    hits = [h for h in as_list(entry.get("local")) if isinstance(h, dict)]
    unplaced = sum(1 for hit in hits if valid_box(hit.get("box")) is None)
    jev = entry.get("jev")
    if isinstance(jev, dict):
        cover = jev.get("cover")
        cover_text = "yes" if cover is True else "no" if cover is False else NA
        jev_cells = [prob_text(jev.get("shown")), prob_text(jev.get("confidence")), cover_text]
    else:
        jev_cells = [NA, NA, NA]
    return [
        text_or_na(entry.get("kind")),
        text_or_na(entry.get("mode")),
        str(len(hits)),
        rule_counts(hits),
        str(unplaced),
    ] + jev_cells


def injection_row(summary):
    injection = as_dict(summary.get("injection"))
    return [
        text_or_na(injection.get("result")),
        names_html(injection.get("strong")),
        names_html(injection.get("weak")),
        names_html(injection.get("where")),
        prob_text(injection.get("aimed")),
        prob_text(injection.get("chat")),
        count_text(summary.get("covers")),
        text_or_na(summary.get("notAsked")),
    ]


def render_capture(capture, job, folder):
    index = capture.get("index")
    out = [f"<section><h2>Capture {esc(index)}</h2>"]

    if job is None:
        out.append(f"<p>No {JOB_NAME} record for this capture.</p></section>")
        return "".join(out)

    out.append(
        f"<p class=\"k\">Mode {text_or_na(job.get('mode'))}, status {text_or_na(job.get('status'))}, "
        f"reason {text_or_na(job.get('reason'))}</p>"
    )

    summary = job.get("summary")
    if not isinstance(summary, dict):
        out.append("<p>This record has no summary, so there is nothing to draw.</p></section>")
        return "".join(out)

    # The annotated image with the boxes over it.
    image_name = Path(str(capture.get("imageFile") or "")).name
    size = as_dict(capture.get("size"))
    width, height = size.get("width"), size.get("height")
    if not (is_number(width) and is_number(height) and width > 0 and height > 0):
        width, height = (png_size(folder / image_name) if image_name else None) or (None, None)
    if not image_name or not (folder / image_name).is_file():
        out.append(f"<p>The annotated image {text_or_na(image_name)} is not in the round folder.</p>")
    else:
        shown_width = min(width, MAX_IMAGE_WIDTH) if width else MAX_IMAGE_WIDTH
        overlays = render_overlays(summary, width, height) if width and height else ""
        out.append(
            f'<div class="shot" style="max-width:{shown_width:.0f}px">'
            f'<img src="{esc(quote(image_name))}" alt="Annotated capture {esc(index)}">{overlays}</div>'
        )
        if not (width and height):
            out.append("<p>The image size is unknown, so no box is drawn.</p>")

    # One row per kind, then the injection row.
    kinds = kind_entries(summary)
    if kinds:
        head = ["Kind", "Mode", "Local hits", "Rules", "Local hits with no box", "Jev shown", "Jev confidence", "Jev cover"]
        out.append(table(head, [kind_row(entry) for entry in kinds]))
    else:
        out.append("<p>The summary holds no kinds.</p>")
    head = ["Injection", "Strong rules", "Weak rules", "Where", "Aimed", "Chat", "Covers", "Not asked"]
    out.append(table(head, [injection_row(summary)]))
    out.append("</section>")
    return "".join(out)


def legend():
    def line(css, color, thick=2):
        return f'<span class="line" style="border-top:{thick}px {css} {color}"></span>'

    kinds = "".join(
        f'<span class="item"><span class="swatch" style="background:{color}"></span>{esc(name[0].upper())} {esc(name)}</span>'
        for name, color in KIND_COLORS.items()
    )
    return (
        '<p class="legend">'
        f'<span class="item">{line("solid", "#1f2933")}local hit</span>'
        f'<span class="item">{line("dashed", "#1f2933")}Jev box, cover true</span>'
        f'<span class="item">{line("dashed", LOW_COLOR)}gray: Jev box, cover false</span>'
        f'<span class="item">{line("solid", INJECTION_COLOR, 3)}injection line</span>'
        f"<br>Kind color and tag letter: {kinds}</p>"
        '<p class="legend">Boxes are in pixels of the annotated PNG, as the file gives them, before any padding. '
        "Cover true means the Jev box passed both thresholds. "
        "A local hit with no box is found but not placed, so the page cannot draw it. "
        "Jev values are probabilities from 0 to 1. "
        "Covers counts the covers drawn in the covered copy, so kinds in on only. "
        "Not asked is time when the job skipped its request for lack of time.</p>"
    )


def render_page(folder, feedback, jev):
    jev_by_capture = {}
    for record in as_list(jev.get("captures")):
        if isinstance(record, dict):
            jev_by_capture[str(record.get("capture"))] = record

    captures = [c for c in as_list(feedback.get("captures")) if isinstance(c, dict)]
    pairs = [(capture, job_of(jev_by_capture.get(str(capture.get("index"))))) for capture in captures]

    modes = sorted({j["mode"] for _, j in pairs if j and isinstance(j.get("mode"), str) and j["mode"]})
    mode_html = esc(", ".join(modes)) if modes else NA

    body = [
        "<h1>Jev data guard review</h1>",
        f"<p>Round folder: <b>{esc(folder.name)}</b></p>",
        f"<p>Job {esc(JOB_NAME)}, mode {mode_html}</p>",
        legend(),
    ]
    if not captures:
        body.append("<p>feedback.json holds no captures.</p>")
    body.extend(render_capture(capture, job, folder) for capture, job in pairs)

    return (
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        f"<title>Jev data guard review {esc(folder.name)}</title><style>{CSS}</style></head><body>"
        + "".join(body)
        + "</body></html>\n"
    )


def main():
    parser = argparse.ArgumentParser(description="Build jev-review-data-guard.html for one feedback round.")
    parser.add_argument(
        "--round", dest="round_path",
        help="round folder (default: the newest with feedback.json and a jev.json with a dataGuard record)",
    )
    parser.add_argument("--no-open", action="store_true", help="write the page but do not open it")
    args = parser.parse_args()

    folder = Path(args.round_path).expanduser() if args.round_path else newest_round()
    if not folder.is_dir():
        fail(f"{folder} is not a folder")
    for name in ("feedback.json", "jev.json"):
        if not (folder / name).is_file():
            fail(f"{folder} has no {name}")

    feedback = as_dict(read_json(folder / "feedback.json"))
    jev = as_dict(read_json(folder / "jev.json"))
    page = render_page(folder.resolve(), feedback, jev)

    out_path = folder / OUTPUT_NAME
    # An imported bundle could hold a symlink with the page's name. O_NOFOLLOW
    # refuses it, so the script never writes over the link's target.
    try:
        fd = os.open(out_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o644)
    except OSError as error:
        fail(f"cannot write {out_path.name}: {error.strerror}")
    with os.fdopen(fd, "w", encoding="utf-8") as out:
        out.write(page)
    print(out_path.resolve())

    if not args.no_open:
        try:
            subprocess.run(["open", str(out_path)], check=False)
        except OSError as error:
            print(f"could not run open: {error}", file=sys.stderr)


if __name__ == "__main__":
    main()
