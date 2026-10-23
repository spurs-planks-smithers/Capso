#!/usr/bin/env python3
"""Check that every voice clip starts and ends below -50 dB in its first and last 20 ms.

A clip that starts or ends on sound can click or sound cut off in the mix.
Exit code 1 when any clip fails. Run after make_audio.py.
"""
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def peak(path, head):
    # Trim inside the filter graph: "-t 0.02" would still measure the whole first decoded
    # frame (about 85 ms), which reaches past a 40 ms pad into the speech.
    graph = ("" if head else "areverse,") + "atrim=0:0.02,volumedetect"
    err = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(path), "-af", graph, "-f", "null", "-"],
                         capture_output=True, text=True).stderr
    m = re.search(r"max_volume: (-?[0-9.]+) dB", err)
    return float(m.group(1)) if m else -120.0


clips = sorted((ROOT / "audio" / "vo").glob("*.wav"))
assert clips, "no voice clips in audio/vo"
bad = 0
for clip in clips:
    a, b = peak(clip, True), peak(clip, False)
    ok = a < -50 and b < -50
    bad += not ok
    print(f"{'ok ' if ok else 'BAD'} {clip.stem:10} start {a:7.1f} dB  end {b:7.1f} dB")
print(f"{len(clips) - bad} of {len(clips)} clips start and end below -50 dB")
sys.exit(1 if bad else 0)
