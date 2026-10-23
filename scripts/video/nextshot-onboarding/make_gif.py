#!/usr/bin/env python3
"""Build the email GIF for the Nextshot onboarding video.

  python3 make_gif.py              render in GIF mode, then build the GIF
  python3 make_gif.py --no-render  reuse the last GIF-mode render

Steps:
  1. Render the composition in GIF mode (large captions, none over the end
     card) to renders/gif-source.mp4.
  2. Cut eight short segments at the cue times in timing.json, speed some up,
     hold the first and last frames, scale to 640 pixels, and encode a
     12 frames per second GIF with one 255-color palette.

Output: build/releases/Nextshot-onboarding-hero.gif

The first frame stands alone, because classic Outlook on Windows shows only
that frame of an animated GIF. Every other common client plays the loop.
"""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
SRC = ROOT / "renders" / "gif-source.mp4"
OUT = REPO / "build" / "releases" / "Nextshot-onboarding-hero.gif"
WIDTH, FPS, COLORS = 640, 12, 255


def segments(c):
    """(start, end, speed, hold at start, hold at end), in source seconds."""
    return [
        (c["squint"] - 0.95, c["squint"] + 0.95, 1.0, 1.0, 0.0),    # the stand, then "Almost."
        (c["tally"] - 0.1, c["tally"] + 1.35, 1.0, 0.0, 0.0),       # the pile of screenshots
        (c["mark"] - 0.05, c["wipe"] + 1.05, 1.0, 0.0, 0.0),        # "Meet Nextshot."
        (c["key_opt"] - 0.15, c["answer1"] + 0.75, 1.1, 0.0, 0.0),  # keys, grab, circles, answer
        (c["cap2"] - 0.2, c["tray"] + 1.5, 1.3, 0.0, 0.0),          # more screens, one session
        (c["menu"] - 0.45, c["paste"] - 0.05, 1.5, 0.0, 0.0),       # copy the session once
        (c["paste"] - 0.05, c["chip_any"] + 1.0, 1.0, 0.0, 0.0),    # paste into the agent
        (c["fix"] + 0.75, c["final_chord"] + 1.0, 1.0, 0.0, 1.4),   # the fixed stand and the end card
    ]


def main():
    if "--no-render" not in sys.argv:
        SRC.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([str(ROOT / "node_modules" / ".bin" / "hyperframes"), "render", str(ROOT),
                        "-o", str(SRC), "--variables", json.dumps({"gif": "on"}),
                        "--quality", "delivery", "--quiet"], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    cues = json.loads((ROOT / "timing.json").read_text())["cues"]
    segs = segments(cues)

    parts, labels, total = [], [], 0.0
    for i, (start, end, speed, head, tail) in enumerate(segs):
        chain = f"[0:v]trim=start={start:.3f}:end={end:.3f},setpts=(PTS-STARTPTS)/{speed}"
        if head:
            chain += f",tpad=start_duration={head}:start_mode=clone"
        if tail:
            chain += f",tpad=stop_duration={tail}:stop_mode=clone"
        parts.append(f"{chain}[s{i}]")
        labels.append(f"[s{i}]")
        total += head + (end - start) / speed + tail
    graph = (";".join(parts) + ";" + "".join(labels)
             + f"concat=n={len(segs)}:v=1:a=0,fps={FPS},scale={WIDTH}:-2:flags=lanczos,split[a][b];"
             f"[a]palettegen=max_colors={COLORS}:stats_mode=full[p];"
             "[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(SRC),
                    "-filter_complex", graph, "-loop", "0", str(OUT)], check=True)
    print(f"{OUT}\n{OUT.stat().st_size / 1e6:.2f} MB, about {total:.1f} s at {FPS} fps, {WIDTH} px wide")


if __name__ == "__main__":
    main()
