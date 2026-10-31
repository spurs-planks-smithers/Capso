#!/usr/bin/env python3
"""Create the one-page Letter shortcut sheet with ReportLab.

Run from any directory: python3 site/guides/scripts/make-shortcuts.py
Requires reportlab. Optional first argument selects another PDF output path.
Sources: src/content/docs/shortcuts.mdx and App/Feedback/FeedbackShortcuts.swift.
All text stays on one measured line. Width and overlap checks run before save.
"""
from pathlib import Path
import sys

from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import letter
from reportlab.pdfbase.pdfmetrics import getAscentDescent, stringWidth
from reportlab.pdfgen import canvas

OUTPUT = Path(__file__).resolve().parents[1] / "public/resources/nextshot-shortcuts.pdf"
INK = HexColor("#183235")
TEAL = HexColor("#126B64")
MUTED = HexColor("#526663")
PALE = HexColor("#EDF6F4")
RULE = HexColor("#CCDEDA")
LEFT, RIGHT = 48, 564


def build(output):
    output.parent.mkdir(parents=True, exist_ok=True)
    pdf = canvas.Canvas(str(output), pagesize=letter, invariant=1, pageCompression=1)
    pdf.setTitle("Nextshot keyboard shortcuts")
    pdf.setAuthor("Nextshot")
    pdf.setSubject("Default keys for capture, marks, notes, and feedback rounds")
    boxes = []

    def text(value, x, y, width, size=10.5, bold=False, color=INK):
        assert value.isascii(), f"Use readable ASCII text: {value!r}"
        font = "Helvetica-Bold" if bold else "Helvetica"
        measured = stringWidth(value, font, size)
        assert measured <= width, f"Text overflows: {value!r}, {measured:.1f} > {width}"
        ascent, descent = getAscentDescent(font, size)
        box = (x, y + descent, x + measured, y + ascent, value)
        assert LEFT <= box[0] < box[2] <= RIGHT
        assert 30 <= box[1] < box[3] <= 762
        for previous in boxes:
            overlap_x = min(box[2], previous[2]) - max(box[0], previous[0])
            overlap_y = min(box[3], previous[3]) - max(box[1], previous[1])
            assert not (overlap_x > 0 and overlap_y > -2), f"Text touches: {value!r} and {previous[4]!r}"
        boxes.append(box)
        pdf.setFont(font, size)
        pdf.setFillColor(color)
        pdf.drawString(x, y, value)

    def section(label, y, rows):
        text(label, LEFT, y, 516, size=12, bold=True, color=TEAL)
        y -= 26
        for index, (action, keys) in enumerate(rows):
            if index % 2 == 0:
                pdf.setFillColor(PALE)
                pdf.rect(LEFT, y - 7, RIGHT - LEFT, 22, fill=1, stroke=0)
            text(action, LEFT + 10, y, 305)
            text(keys, 382, y, 172, bold=True)
            y -= 22
        return y

    text("NEXTSHOT", LEFT, 750, 220, size=10, bold=True, color=TEAL)
    text("GUIDES", 522, 750, 42, size=9, color=MUTED)
    pdf.setStrokeColor(RULE)
    pdf.line(LEFT, 736, RIGHT, 736)
    text("Keyboard shortcuts", LEFT, 709, 516, size=22, bold=True)
    text("Default keys. Your settings may use different ones.", LEFT, 687, 516, size=10.5, color=MUTED)

    y = section("Capture", 655, [
        ("Start or add a capture", "Option + Shift + F"),
    ])
    text("Press the keys, then drag to select an area.", LEFT + 10, y + 1, 496, size=9.5, color=MUTED)

    y = section("Mark the capture", 582, [
        ("Add the next numbered dot (dot tool)", "Click"),
        ("Select the dot tool", "C or N"),
        ("Select the arrow tool", "A"),
        ("Select the box tool", "R"),
        ("Select the text tool", "T"),
        ("Save and open notes", "Command + S"),
        ("Undo / redo a mark (outside text)", "Left / Right arrow"),
    ])
    text("Escape with no marks copies the image and closes the editor.", LEFT + 10, y + 1, 496, size=9.5, color=MUTED)
    text("With marks, Escape copies the marked image, saves it to the round, and closes.", LEFT + 10, y - 13, 496, size=9.5, color=MUTED)

    y = section("Answer the note questions", 357, [
        ("Save the answer and continue", "Return"),
        ("Skip the current step", "Escape"),
        ("Earlier / later step", "Up / Down arrow"),
        ("Previous step, from start of answer", "Left arrow"),
        ("Next step, from end of answer", "Right arrow"),
    ])

    y = section("During a round", 202, [
        ("Copy last capture prompt", "Option + Shift + C"),
        ("Copy prompt and end round", "Option + Shift + R"),
        ("Open round folder", "Option + Shift + O"),
        ("End round and copy its prompt", "Option + Shift + E"),
    ])
    text("Round keys need an active round. Finish a capture before using R or E.", LEFT + 10, y + 1, 496, size=9.5, color=MUTED)
    text("Change keys in Settings > Shortcuts > Nextshot.", LEFT + 10, y - 14, 496, size=9.5, color=MUTED)

    pdf.setStrokeColor(RULE)
    pdf.line(LEFT, 51, RIGHT, 51)
    text("nextshot.dev/guides/shortcuts", LEFT, 35, 450, size=9, color=MUTED)
    text("1", 558, 35, 6, size=9, color=MUTED)
    pdf.linkURL("https://nextshot.dev/guides/shortcuts/", (LEFT, 32, 240, 45), relative=0)
    pdf.showPage()
    pdf.save()
    print(f"Created {output}")
    print(f"Measured {len(boxes)} text lines across 516 points: no wraps, overflows, or touching text.")


if __name__ == "__main__":
    build(Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else OUTPUT)
