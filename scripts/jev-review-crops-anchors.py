#!/usr/bin/env python3
"""Build jev-review.html for one feedback round (issue #44, dev tool).

Drew runs this to judge the Jev "crops and anchors" job in shadow mode.

Usage:
  python3 scripts/jev-review-crops-anchors.py [--round PATH] [--no-open]

Input: a round folder with feedback.json and jev.json. The default is the
newest folder under ~/Library/Application Support/Nextshot that holds both.
Output: jev-review.html in the round folder, then `open` shows it.
The app never writes or reads this file. The page has no script, no form,
and no external asset. Python 3 standard library only.

Every string from the two files goes through html.escape. Screen text and
window titles are untrusted.
"""

import argparse
import html
import json
import math
import re
import struct
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote

JOB_NAME = "cropsAnchors"
OUTPUT_NAME = "jev-review.html"
STORE = Path.home() / "Library" / "Application Support" / "Nextshot"
MAX_IMAGE_WIDTH = 900
# The crop preview in each item row, in CSS pixels.
PREVIEW_WIDTH = 220
PREVIEW_HEIGHT = 160

# Final crop color by status. Statuses without a color use the fallback.
CROP_COLORS = {
    "checked": "#1a7f37",
    "edgesUnsure": "#bf8700",
    "marksOnly": "#6e7781",
    "notChecked": "#d1621c",
}
CROP_FALLBACK = "#a0a7b0"
WINDOW_COLOR = "#8c959f"
TARGET_COLOR = "#0969da"
ANCHOR_COLOR = "#8250df"

NA = '<span class="na">n/a</span>'
ANSWER_ID = re.compile(r"^(\d+(?:\.\d+)?)\.[^.]+$")

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
.screen { font-family: ui-monospace, Menlo, Consolas, monospace; font-size: 12.5px; overflow-wrap: anywhere; }
.shot { position: relative; margin: 10px 0 4px; border: 1px solid #d5d9de; line-height: 0; }
.shot img { display: block; width: 100%; height: auto; }
.preview { border: 1px solid #c3c9d0; background-repeat: no-repeat; margin-bottom: 6px; }
.box { position: absolute; box-sizing: border-box; }
.window { border: 1px dashed """ + WINDOW_COLOR + """; }
.target { border: 1px solid """ + TARGET_COLOR + """; }
.crop { border: 2px solid; }
.anchor { border: 2px dotted """ + ANCHOR_COLOR + """; }
.tag { position: absolute; left: -2px; top: -2px; color: #fff; font: 600 11px/14px -apple-system, Helvetica, Arial, sans-serif;
  padding: 0 4px; }
.swatch { display: inline-block; width: 9px; height: 9px; margin-right: 5px; }
.legend { margin-top: 8px; color: #52606d; }
.legend span.item { display: inline-block; margin-right: 16px; white-space: nowrap; }
.legend .line { display: inline-block; width: 18px; height: 0; margin-right: 5px; vertical-align: middle; }
b.yes { color: #14213d; }
"""


def fail(message):
    print(f"jev-review-crops-anchors: {message}", file=sys.stderr)
    sys.exit(1)


def esc(value):
    return html.escape(str(value), quote=True)


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def is_index(value):
    return isinstance(value, int) and not isinstance(value, bool)


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
    except ValueError as error:
        fail(f"{path} is not valid JSON: {error}")


def newest_round():
    if not STORE.is_dir():
        fail(f"{STORE} does not exist. Pass --round PATH.")
    folders = sorted((p for p in STORE.iterdir() if p.is_dir()), key=lambda p: p.name, reverse=True)
    for folder in folders:
        if (folder / "feedback.json").is_file() and (folder / "jev.json").is_file():
            return folder
    fail(f"no folder under {STORE} holds both feedback.json and jev.json. Pass --round PATH.")


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


def text_or_na(value):
    if isinstance(value, str) and value.strip():
        return esc(value.strip())
    if is_number(value):
        return esc(number_text(value))
    return NA


def box_of(value, width, height):
    """A [x1, y1, x2, y2] list clamped to the image, or None."""
    numbers = as_list(value)
    if len(numbers) != 4 or not all(is_number(n) for n in numbers) or not width or not height:
        return None
    x1, y1, x2, y2 = numbers
    x1, x2 = max(0, x1), min(width, x2)
    y1, y2 = max(0, y1), min(height, y2)
    if x2 <= x1 or y2 <= y1:
        return None
    return x1, y1, x2, y2


def px_text(value):
    numbers = as_list(value)
    if len(numbers) == 4 and all(is_number(n) for n in numbers):
        return "px " + " ".join(number_text(n) for n in numbers)
    return "px " + NA


def overlay(css_class, box, width, height, color=None, tag=None):
    x1, y1, x2, y2 = box
    style = (
        f"left:{x1 / width * 100:.3f}%;top:{y1 / height * 100:.3f}%;"
        f"width:{(x2 - x1) / width * 100:.3f}%;height:{(y2 - y1) / height * 100:.3f}%"
    )
    if color:
        style += f";border-color:{color}"
    inner = f'<span class="tag" style="background:{color}">{esc(tag)}</span>' if tag and color else ""
    return f'<div class="box {css_class}" style="{style}">{inner}</div>'


def crop_preview(value, image_name, width, height):
    """The final crop as the agent would see it, cut from the annotated image
    with CSS, at most PREVIEW_WIDTH by PREVIEW_HEIGHT pixels. Empty when the
    box or the image is missing."""
    box = box_of(value, width, height)
    if not box or not image_name:
        return ""
    x1, y1, x2, y2 = box
    scale = min(PREVIEW_WIDTH / (x2 - x1), PREVIEW_HEIGHT / (y2 - y1), 1)
    style = (
        f"width:{(x2 - x1) * scale:.0f}px;height:{(y2 - y1) * scale:.0f}px;"
        f"background-image:url('{esc(quote(image_name))}');"
        f"background-size:{width * scale:.0f}px {height * scale:.0f}px;"
        f"background-position:{-x1 * scale:.0f}px {-y1 * scale:.0f}px"
    )
    return f'<div class="preview" style="{style}"></div>'


def answers_by_id(job):
    """Map answer id to its fields. Handles flat records and an `answer` object."""
    result = {}
    for record in as_list(job.get("answers")):
        if not isinstance(record, dict) or not isinstance(record.get("id"), str):
            continue
        fields = dict(record)
        nested = record.get("answer")
        if isinstance(nested, dict):
            fields.update(nested)
        elif is_number(nested):
            fields.setdefault("noul", nested)
        result[record["id"]] = fields
    return result


def job_items(job, answers):
    """Items from the summary. Without a summary, item ids come from answer ids."""
    summary = as_dict(job.get("summary"))
    items = [i for i in as_list(summary.get("items")) if isinstance(i, dict) and isinstance(i.get("item"), str)]
    if items:
        return items, True
    found = []
    for answer_id in answers:
        match = ANSWER_ID.match(answer_id)
        if match and match.group(1) not in found:
            found.append(match.group(1))
    found.sort(key=lambda i: [int(part) for part in i.split(".")])
    return [{"item": i} for i in found], False


def note_for(item_id, capture):
    """Drew's note: the badge's instruction, or the capture note for a capture-level item."""
    parts = item_id.split(".")
    if len(parts) == 2 and parts[1].isdigit():
        badge = int(parts[1])
        for mark in as_list(capture.get("marks")):
            if isinstance(mark, dict) and mark.get("badge") == badge:
                text = mark.get("instruction")
                if isinstance(text, str) and text.strip():
                    return text.strip()
        return None
    note = capture.get("note")
    return note.strip() if isinstance(note, str) and note.strip() else None


def render_item_row(item, answers, capture, ocr_lines, image_name, width, height):
    item_id = item["item"]
    prefix = item_id + "."

    def answer(name):
        return answers.get(prefix + name)

    def noul(name):
        value = as_dict(answer(name)).get("noul")
        return value if is_number(value) else None

    def confidence(name):
        value = as_dict(answer(name)).get("confidence")
        return value if is_number(value) else None

    # Crop status and source.
    status = item.get("cropStatus")
    if isinstance(status, str) and status.strip():
        color = CROP_COLORS.get(status, CROP_FALLBACK)
        status_html = f'<span class="swatch" style="background:{color}"></span>{esc(status)}'
    else:
        status_html = NA
    crop_cell = (
        crop_preview(item.get("crop"), image_name, width, height)
        + f"{status_html}<br><span class=\"k\">source</span> {text_or_na(item.get('cropSource'))}"
        f"<br>{px_text(item.get('crop'))}"
    )

    # Step 2: target_shown and the Box confidence.
    target_cell = (
        f"<span class=\"k\">shown</span> {prob_text(noul('target_shown'))}"
        f"<br><span class=\"k\">box</span> {prob_text(confidence('target'))}"
    )

    # Step 3: edge answers, round 1 and round 2. A value of 0.5 or more is a yes.
    def edges(suffix):
        values = [(letter, noul(f"cut_{name}{suffix}")) for letter, name in
                  (("L", "left"), ("R", "right"), ("T", "top"), ("B", "bottom"))]
        if all(v is None for _, v in values):
            return NA
        parts = []
        for letter, value in values:
            if value is None:
                parts.append(f"{letter} {NA}")
            elif value >= 0.5:
                parts.append(f'<b class="yes">{letter} {value:.2f}</b>')
            else:
                parts.append(f"{letter} {value:.2f}")
        return ", ".join(parts)

    # Request C: the search line, anchor_fits, and the Choice confidence.
    source = item.get("anchorSource", item.get("anchorLine"))
    line_text = ocr_lines[source].strip() if is_index(source) and 0 <= source < len(ocr_lines) else ""
    if line_text:
        line_cell = f'<span class="screen">{esc(line_text)}</span><br><span class="k">line</span> {source}'
    elif is_index(source):
        line_cell = f"{NA}<br><span class=\"k\">line {source} is not in the OCR text</span>"
    else:
        line_cell = NA
    option = as_dict(answer("anchor")).get("choice")
    option_html = f' <span class="k">{esc(option)}</span>' if isinstance(option, str) and option else ""
    fits_cell = (
        f"<span class=\"k\">fits</span> {prob_text(noul('anchor_fits'))}"
        f"<br><span class=\"k\">choice</span> {prob_text(confidence('anchor'))}{option_html}"
    )

    note = note_for(item_id, capture)
    cells = [
        f"<b>{esc(item_id)}</b>",
        esc(note) if note else NA,
        crop_cell,
        target_cell,
        edges(""),
        edges("_2"),
        line_cell,
        fits_cell,
        text_or_na(item.get("anchorStatus")),
    ]
    return "<tr>" + "".join(f"<td>{cell}</td>" for cell in cells) + "</tr>"


def render_overlays(items, width, height):
    """Window, target, final crop, then anchor box, so crops sit above the others."""
    parts = []
    for key in ("window", "target"):
        for item in items:
            box = box_of(item.get(key), width, height)
            if box:
                parts.append(overlay(key, box, width, height))
    for item in items:
        box = box_of(item.get("crop"), width, height)
        if box:
            status = item.get("cropStatus")
            color = CROP_COLORS.get(status, CROP_FALLBACK) if isinstance(status, str) else CROP_FALLBACK
            parts.append(overlay("crop", box, width, height, color=color, tag=item["item"]))
    for item in items:
        box = box_of(item.get("anchorBox"), width, height)
        if box:
            parts.append(overlay("anchor", box, width, height))
    return "".join(parts)


def render_capture(capture, record, folder):
    index = capture.get("index")
    title = capture.get("windowTitle")
    heading = f"Capture {esc(index)}"
    if isinstance(title, str) and title.strip():
        heading += f": {esc(title.strip())}"
    out = [f"<section><h2>{heading}</h2>"]

    job = None
    if record:
        job = next((j for j in as_list(record.get("jobs")) if isinstance(j, dict) and j.get("job") == JOB_NAME), None)
    if job is None:
        out.append(f"<p>No {JOB_NAME} record for this capture.</p></section>")
        return "".join(out)

    reason = job.get("reason")
    out.append(
        f"<p class=\"k\">Job status {text_or_na(job.get('status'))}"
        + (f", reason {esc(reason)}" if isinstance(reason, str) and reason else "")
        + "</p>"
    )

    answers = answers_by_id(job)
    items, has_summary = job_items(job, answers)
    if not has_summary:
        out.append("<p>This record has no summary, so the final crops cannot be drawn.</p>")

    # The annotated image with the boxes over it.
    image_name = Path(str(capture.get("imageFile") or "")).name
    size = as_dict(capture.get("size"))
    width, height = size.get("width"), size.get("height")
    if not (is_number(width) and is_number(height) and width > 0 and height > 0):
        width, height = png_size(folder / image_name) or (None, None)
    if not image_name or not (folder / image_name).is_file():
        out.append(f"<p>The annotated image {text_or_na(image_name)} is not in the round folder.</p>")
    else:
        shown_width = min(width, MAX_IMAGE_WIDTH) if width else MAX_IMAGE_WIDTH
        overlays = render_overlays(items, width, height) if width and height else ""
        out.append(
            f'<div class="shot" style="max-width:{shown_width:.0f}px">'
            f'<img src="{esc(quote(image_name))}" alt="Annotated capture {esc(index)}">{overlays}</div>'
        )

    # One row per item.
    ocr = capture.get("ocrText")
    ocr_lines = ocr.split("\n") if isinstance(ocr, str) else []
    if items:
        head = ["Item", "Drew's note", "Final crop", "Target", "Edges, round 1", "Edges, round 2",
                "Search line", "Anchor answers", "Anchor status"]
        out.append("<table><thead><tr>" + "".join(f"<th>{esc(h)}</th>" for h in head) + "</tr></thead><tbody>")
        has_image = bool(image_name) and (folder / image_name).is_file()
        out.extend(
            render_item_row(item, answers, capture, ocr_lines, image_name if has_image else "", width, height)
            for item in items
        )
        out.append("</tbody></table>")
    else:
        out.append("<p>The record holds no items.</p>")
    out.append("</section>")
    return "".join(out)


def legend():
    def line(css, color):
        return f'<span class="line" style="border-top:2px {css} {color}"></span>'

    crops = "".join(
        f'<span class="item"><span class="swatch" style="background:{color}"></span>{esc(name)}</span>'
        for name, color in CROP_COLORS.items()
    )
    return (
        '<p class="legend">'
        f'<span class="item">{line("dashed", WINDOW_COLOR)}window</span>'
        f'<span class="item">{line("solid", TARGET_COLOR)}Jev target</span>'
        f'<span class="item">{line("dotted", ANCHOR_COLOR)}anchor box</span>'
        f"<br>Final crop by status: {crops}</p>"
        '<p class="legend">Edge answers: L left, R right, T top, B bottom. Bold means 0.5 or more (a yes). '
        "Values are probabilities from 0 to 1. The search line is row N of the capture's OCR text, counted from 0.</p>"
    )


def render_page(folder, feedback, jev):
    jev_by_capture = {}
    for record in as_list(jev.get("captures")):
        if isinstance(record, dict):
            jev_by_capture[str(record.get("capture"))] = record

    captures = [c for c in as_list(feedback.get("captures")) if isinstance(c, dict)]
    pairs = []
    for capture in captures:
        record = jev_by_capture.get(str(capture.get("index")))
        job = None
        if record:
            job = next((j for j in as_list(record.get("jobs")) if isinstance(j, dict) and j.get("job") == JOB_NAME), None)
        pairs.append((capture, record, job))

    modes = sorted({j["mode"] for _, _, j in pairs if j and isinstance(j.get("mode"), str) and j["mode"]})
    mode_html = esc(", ".join(modes)) if modes else NA

    rows = []
    for capture, _, job in pairs:
        title = capture.get("windowTitle")
        duration = job.get("durationMs") if job else None
        cells = [
            esc(capture.get("index")),
            esc(title.strip()) if isinstance(title, str) and title.strip() else NA,
            text_or_na(job.get("mode")) if job else NA,
            f"{duration / 1000:.1f} s" if is_number(duration) else NA,
            esc(f"{job['requests']:,}") if job and is_index(job.get("requests")) else NA,
            esc(f"{job['inputTokens']:,}") if job and is_index(job.get("inputTokens")) else NA,
        ]
        rows.append("<tr>" + "".join(f"<td>{c}</td>" for c in cells) + "</tr>")
    head = ["Capture", "Window", "Mode", "Duration", "Requests", "Input tokens"]

    body = [
        "<h1>Jev crops and anchors review</h1>",
        f"<p>Round folder: <b>{esc(folder.name)}</b></p>",
        f"<p>Job {esc(JOB_NAME)}, mode {mode_html}</p>",
        "<table><thead><tr>" + "".join(f"<th>{esc(h)}</th>" for h in head) + "</tr></thead><tbody>"
        + "".join(rows) + "</tbody></table>",
        legend(),
    ]
    if not captures:
        body.append("<p>feedback.json holds no captures.</p>")
    body.extend(render_capture(capture, record, folder) for capture, record, _ in pairs)

    return (
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        f"<title>Jev review {esc(folder.name)}</title><style>{CSS}</style></head><body>"
        + "".join(body)
        + "</body></html>\n"
    )


def main():
    parser = argparse.ArgumentParser(description="Build jev-review.html for one feedback round.")
    parser.add_argument("--round", dest="round_path", help="round folder (default: the newest with feedback.json and jev.json)")
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
    out_path.write_text(page, encoding="utf-8")
    print(out_path.resolve())

    if not args.no_open:
        try:
            subprocess.run(["open", str(out_path)], check=False)
        except OSError as error:
            print(f"could not run open: {error}", file=sys.stderr)


if __name__ == "__main__":
    main()
