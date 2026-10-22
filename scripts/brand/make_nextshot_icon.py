"""Build the Nextshot mark: the Icon Composer app icon and the menu bar image.

The mark is a teal rounded square with a mint chevron on its right edge. A
gap (a real cut, not paint) separates the chevron from the square. All
geometry is in design units: a 1024 canvas with the icon body at 100..924.

Writes:
  Branding/Nextshot.icon/                       app icon (Icon Composer)
  App/Feedback/FeedbackAssets.xcassets/         menu bar template image

Needs shapely (pip install shapely). Spec: docs/brand/nextshot-mark.md.
"""
import json
from pathlib import Path

from shapely.geometry import LineString, MultiPolygon, box

ROOT = Path(__file__).resolve().parents[2]

# Master geometry, approved 2026-10-22 (round 9, "chevron right 56").
SQUARE_SIZE, SQUARE_RADIUS = 380, 104
CHEVRON_START_X, CHEVRON_TIP_X, CHEVRON_HALF_HEIGHT = 660, 790, 132
CHEVRON_WIDTH = 84
GAP = 48
CORNER_ROUNDING = 10

TEAL, TEAL_OPACITY = "#3CCDBE", 0.6
MINT = "#8FF3E4"
GRAPHITE = (0.137, 0.157, 0.173)  # #23282C, base of the body gradient


def square():
    lo = 512 - SQUARE_SIZE / 2 + SQUARE_RADIUS
    hi = 512 + SQUARE_SIZE / 2 - SQUARE_RADIUS
    return box(lo, lo, hi, hi).buffer(SQUARE_RADIUS, quad_segs=48)


def chevron(extra=0.0):
    line = LineString([
        (CHEVRON_START_X, 512 - CHEVRON_HALF_HEIGHT),
        (CHEVRON_TIP_X, 512),
        (CHEVRON_START_X, 512 + CHEVRON_HALF_HEIGHT),
    ])
    return line.buffer(CHEVRON_WIDTH / 2 + extra, quad_segs=48, cap_style="round", join_style="round")


def cut_square():
    cut = square().difference(chevron(GAP))
    # Shrink, then grow: rounds the points where the gap meets the edge.
    cut = cut.buffer(-CORNER_ROUNDING, quad_segs=24).buffer(CORNER_ROUNDING, quad_segs=24)
    if isinstance(cut, MultiPolygon):
        cut = max(cut.geoms, key=lambda g: g.area)
    return cut


def path_d(poly, scale=1.0, dx=0.0, dy=0.0):
    rings = [poly.exterior, *poly.interiors]
    return " ".join(
        "M" + " L".join(f"{(x + dx) * scale:.2f} {(y + dy) * scale:.2f}" for x, y in ring.coords) + " Z"
        for ring in rings
    )


def svg(width, height, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width:.0f}" height="{height:.0f}" '
            f'viewBox="0 0 {width:.2f} {height:.2f}">{body}</svg>\n')


def write_app_icon():
    # Icon Composer's canvas is the icon body, so map 100..924 onto 0..1024.
    scale, shift = 1024 / 824, -100
    icon = ROOT / "Branding" / "Nextshot.icon"
    (icon / "Assets").mkdir(parents=True, exist_ok=True)
    (icon / "Assets" / "square.svg").write_text(svg(1024, 1024, (
        f'<path d="{path_d(cut_square(), scale, shift, shift)}" fill="{TEAL}" fill-opacity="{TEAL_OPACITY}"/>')))
    (icon / "Assets" / "chevron.svg").write_text(svg(1024, 1024, (
        f'<path d="{path_d(chevron(), scale, shift, shift)}" fill="{MINT}"/>')))
    r, g, b = GRAPHITE
    doc = {
        "fill": {"automatic-gradient": f"extended-srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"},
        "groups": [
            {"layers": [{"image-name": "chevron.svg", "name": "chevron"}],
             "shadow": {"kind": "neutral", "opacity": 0.5},
             "translucency": {"enabled": True, "value": 0.5}},
            {"layers": [{"image-name": "square.svg", "name": "square"}],
             "shadow": {"kind": "neutral", "opacity": 0.5},
             "translucency": {"enabled": True, "value": 0.5}},
        ],
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }
    (icon / "icon.json").write_text(json.dumps(doc, indent=2) + "\n")


def write_menu_bar_mark():
    # A template image: macOS uses only its alpha, so the square is 50% alpha.
    sq, ch = cut_square(), chevron()
    minx, miny, maxx, maxy = sq.union(ch).bounds
    catalog = ROOT / "App" / "Feedback" / "FeedbackAssets.xcassets"
    imageset = catalog / "NextshotMark.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    (catalog / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    (imageset / "nextshot-mark.svg").write_text(svg(maxx - minx, maxy - miny, (
        f'<path d="{path_d(sq, 1, -minx, -miny)}" fill="#000" fill-opacity="0.5"/>'
        f'<path d="{path_d(ch, 1, -minx, -miny)}" fill="#000"/>')))
    contents = {
        "images": [{"filename": "nextshot-mark.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
    }
    (imageset / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


if __name__ == "__main__":
    write_app_icon()
    write_menu_bar_mark()
    print("wrote Branding/Nextshot.icon and App/Feedback/FeedbackAssets.xcassets")
