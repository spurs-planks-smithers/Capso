#!/usr/bin/env python3
"""Build the storyboard review page for the Nextshot onboarding video.

The page puts four standard review formats in one place: an AV script (what you hear beside what
you see), a storyboard (two frames per voice line), a timeline (scenes, voice, sounds, music), and
note boxes on every line. It reads the same files that drive the video, so it matches the newest
render after every change:

  script.json, timing.json     written by make_audio.py
  storyboard/shots.json        plain-English picture text, scene jobs, cue names (edit by hand)
  storyboard/template.html     the page design
  build/releases/Nextshot-onboarding-<date>.mp4   the newest render (render.sh)

It writes build/releases/storyboard/:
  page.html    the page that the claude.ai artifact publishes (no doctype: the publisher adds it)
  local.html   the same page as a full document, for a local browser and the PDF
  video.mp4 and frames/<line>-1.jpg, frames/<line>-2.jpg
With --pdf it also writes build/releases/Nextshot-onboarding-storyboard.pdf (Letter, headless Chrome).

Run: python3 scripts/video/nextshot-onboarding/storyboard/build_storyboard.py [--pdf]
"""
import argparse
import base64
import html
import json
import re
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
VIDEO = HERE.parent
REPO = VIDEO.parents[2]
RELEASES = REPO / "build" / "releases"
OUT = RELEASES / "storyboard"
PDF = RELEASES / "Nextshot-onboarding-storyboard.pdf"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
BRISK = 3.6  # words per second inside one line; above this a line sounds rushed (a working limit, not a published rule)


def need(ok, msg):
    if not ok:
        sys.exit(f"build_storyboard: {msg}")


def esc(s):
    return html.escape(str(s), quote=True)


def tc(t):
    """Timecode as minutes:seconds.tenths, for example 0:12.1."""
    tenths = round(t * 10)
    m, rem = divmod(tenths, 600)
    return f"{m}:{rem / 10:04.1f}"


def secs(t):
    return f"{t:.1f} s"


def newest_video():
    # Music option cuts (-musicB, -musicC) share the timing but are not the main cut.
    vids = sorted((v for v in RELEASES.glob("Nextshot-onboarding-20*.mp4") if "-music" not in v.name),
                  key=lambda p: p.stat().st_mtime)
    need(vids, f"no render in {RELEASES}. Run render.sh first.")
    vid = vids[-1]
    need((VIDEO / "timing.json").stat().st_mtime <= vid.stat().st_mtime + 2,
         f"timing.json is newer than {vid.name}. Run render.sh so the video matches the timing.")
    return vid


def probe_duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def build_model(script, timing, shots):
    order = [ln["id"] for sc in script["scenes"] for ln in sc["lines"]]
    T = timing["lines"]
    scene_ids = [sc["id"] for sc in script["scenes"]]
    cue_ids = [c["id"] for c in script["cues"]]
    # Every set must be non-empty before a compare, or two empty parses would pass.
    need(order and scene_ids and cue_ids and T and timing["cues"], "a source file has no lines, scenes, or cues")
    need(set(order) == set(T), f"script.json and timing.json lines differ: {sorted(set(order) ^ set(T))}")
    need(set(order) == set(shots["lines"]), f"shots.json lines differ: {sorted(set(order) ^ set(shots['lines']))}")
    need(scene_ids == [s["id"] for s in timing["scenes"]], "script.json and timing.json scenes differ")
    need(set(scene_ids) == set(shots["scenes"]), f"shots.json scenes differ: {sorted(set(scene_ids) ^ set(shots['scenes']))}")
    need(set(cue_ids) == set(timing["cues"]) == set(shots["cues"]),
         f"cue ids differ: {sorted(set(cue_ids) ^ set(timing['cues']))} {sorted(set(cue_ids) ^ set(shots['cues']))}")
    sounds = {c["sfx"] for c in script["cues"] if c.get("sfx")}
    need(sounds <= set(shots["sounds"]), f"shots.json lacks sound names: {sorted(sounds - set(shots['sounds']))}")

    dur = timing["duration"]
    S = {s["id"]: s for s in timing["scenes"]}
    lines = []
    for i, lid in enumerate(order):
        t = T[lid]
        sc = S[t["scene"]]
        nxt = T[order[i + 1]] if i + 1 < len(order) else None
        last_in_scene = nxt is None or nxt["scene"] != t["scene"]
        win_end = dur if nxt is None else (sc["end"] if last_in_scene else nxt["start"])
        win = [t["start"], win_end]
        span = win[1] - win[0]
        f1, f2 = win[0] + 0.4 * span, win[1] - 0.12
        if shots["lines"][lid].get("frames"):  # optional override: two fractions of the line's window
            f1, f2 = (win[0] + f * span for f in shots["lines"][lid]["frames"])
        need(win[0] <= f1 < f2 <= win[1], f"line {lid}: frame times {f1:.2f}, {f2:.2f} fall outside {win}")
        prev_end = T[order[i - 1]]["end"] if i else 0.0
        words = len(re.findall(r"[A-Za-z0-9$']+", t["text"]))
        spoken = t["end"] - t["start"]
        caps = [c["text"] for c in timing["captions"] if t["start"] - 0.01 <= c["start"] < t["end"]]
        need(caps, f"line {lid} has no caption")
        cues = sorted((timing["cues"][c["id"]], c["id"], c.get("sfx")) for c in script["cues"] if c["line"] == lid)
        lines.append({
            "id": lid, "n": i + 1, "text": t["text"], "scene": t["scene"], "start": t["start"], "end": t["end"],
            "win": win, "frames": [round(f1, 3), round(f2, 3)], "before": t["start"] - prev_end,
            "after": (nxt["start"] if nxt else dur) - t["end"], "words": words, "spoken": spoken,
            "wps": words / spoken if spoken else 0.0, "captions": caps, "see": shots["lines"][lid]["see"],
            "cues": [{"t": ct, "id": cid, "label": shots["cues"][cid], "sound": shots["sounds"].get(sfx) if sfx else None}
                     for ct, cid, sfx in cues],
        })
    scenes = []
    for k, sid in enumerate(scene_ids):
        s = S[sid]
        scenes.append({"id": sid, "n": k + 1, "start": s["start"], "end": s["end"], **shots["scenes"][sid],
                       "lines": [ln for ln in lines if ln["scene"] == sid]})
    need(all(s["lines"] for s in scenes), "a scene has no voice line")
    return {"duration": dur, "lines": lines, "scenes": scenes, "cues": timing["cues"]}


def extract_frames(video, lines):
    frames = OUT / "frames"
    if frames.exists():
        shutil.rmtree(frames)
    frames.mkdir(parents=True)
    for ln in lines:
        for k, t in enumerate(ln["frames"], 1):
            out = frames / f"{ln['id']}-{k}.jpg"
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{t:.3f}", "-i", str(video), "-frames:v", "1",
                            "-vf", "scale=720:-2", "-q:v", "4", str(out)], check=True)
            need(out.exists() and out.stat().st_size > 2000, f"frame {out.name} is missing or empty")


def music_paths(model, turn_at):
    """The music band: full height in silence, lower while the voice talks (ducking)."""
    dur = model["duration"]
    speech = [(ln["start"], ln["end"]) for ln in model["lines"]]
    step, level, pts = 0.05, 1.0, []
    t = 0.0
    while t <= dur + 1e-9:
        want = 0.55 if any(a <= t < b for a, b in speech) else 1.0
        level += (want - level) * (0.6 if want < level else 0.15)
        pts.append((t, level))
        t += step

    def path(a, b):
        seg = [(x, lv) for x, lv in pts if a - 1e-9 <= x <= b + 1e-9]
        top = " ".join(f"L{1000 * x / dur:.1f},{100 - 88 * lv:.1f}" for x, lv in seg)
        return f"M{1000 * seg[0][0] / dur:.1f},100 {top} L{1000 * seg[-1][0] / dur:.1f},100 Z"

    return path(0, turn_at), path(turn_at, dur)


def timeline_html(model):
    dur = model["duration"]
    pct = lambda t: f"{100 * t / dur:.3f}%"
    ruler = []
    for s in range(0, int(dur) + 1):
        big = s % 5 == 0
        lab = f"<span>{tc(s)[:-2]}</span>" if big else ""
        ruler.append(f'<span class="tick{" big" if big else ""}" style="left:{pct(s)}">{lab}</span>')
    scenes = "".join(
        f'<div class="blk {s["look"]}" style="left:{pct(s["start"])};width:{pct(s["end"] - s["start"])}" '
        f'title="Scene {s["n"]}, {esc(s["name"])}: {tc(s["start"])} to {tc(s["end"])}"><span>{esc(s["name"])}</span></div>'
        for s in model["scenes"])
    voice = "".join(
        f'<div class="blk voice" data-line="{ln["id"]}" tabindex="0" role="button" style="left:{pct(ln["start"])};'
        f'width:{pct(ln["end"] - ln["start"])}" title="Line {ln["n"]}, {tc(ln["start"])}: {esc(ln["text"])}">'
        f'<span>{ln["n"]}</span></div>'
        for ln in model["lines"])
    ticks = []
    for ln in model["lines"]:
        for c in ln["cues"]:
            kind = "sfx" if c["sound"] else "sfx silent"
            what = c["sound"] or "picture only"
            ticks.append(f'<span class="{kind}" style="left:{pct(c["t"])}" title="{tc(c["t"])} {esc(what)}: {esc(c["label"])}"></span>')
    turn_at = next(s["start"] for s in model["scenes"] if s["id"] == "turn")
    before, after = music_paths(model, turn_at)
    chord = model["cues"]["final_chord"]
    music = (f'<svg viewBox="0 0 1000 100" preserveAspectRatio="none" aria-hidden="true">'
             f'<path class="band" d="{before}"/><path class="band after" d="{after}"/></svg>'
             f'<span class="mlab" style="left:{pct(turn_at)}">busier</span>'
             f'<span class="mlab{" end" if chord > 0.8 * dur else ""}" style="left:{pct(chord)}">final chord</span>')
    return (
        '<div class="tl" id="tl">'
        f'<span class="tl-lab"></span><div class="tl-track ruler">{"".join(ruler)}</div>'
        f'<span class="tl-lab">Scenes</span><div class="tl-track">{scenes}</div>'
        f'<span class="tl-lab">Voice</span><div class="tl-track">{voice}</div>'
        f'<span class="tl-lab">Sounds</span><div class="tl-track sounds">{"".join(ticks)}</div>'
        f'<span class="tl-lab">Music</span><div class="tl-track music">{music}</div>'
        '<div class="tl-ph" aria-hidden="true"></div></div>')


def card_html(ln):
    lid, n = ln["id"], ln["n"]
    figs = "".join(
        f'<figure><button type="button" data-seek="{t:.3f}" aria-label="Show the video at {tc(t)}">'
        f'<img src="frames/{lid}-{k}.jpg" alt="Video frame at {tc(t)}" width="720" height="405"></button>'
        f'<figcaption class="tc">{tc(t)}</figcaption></figure>'
        for k, t in enumerate(ln["frames"], 1))
    caps = "".join(f'<span class="cap">{esc(c)}</span>' for c in ln["captions"])
    cues = "".join(
        f'<li><span class="tc">{tc(c["t"])}</span> '
        + (f'<span class="snd">{esc(c["sound"])}</span>, ' if c["sound"] else '<span class="none">no sound</span>, ')
        + f'{esc(c["label"])}</li>'
        for c in ln["cues"]) or '<li class="none">No cue on this line.</li>'
    if ln["words"] >= 3:
        pace = f'<span><b>{ln["wps"]:.1f}</b> words per second</span>'
        if ln["wps"] > BRISK:
            pace += ' <span class="pace fast">brisk</span>'
    else:
        pace = '<span>Short line</span>'
    timing = (f'<span>Spoken <b>{secs(ln["spoken"])}</b></span>'
              f'<span>Silence before <b>{secs(ln["before"])}</b></span>'
              f'<span>Silence after <b>{secs(ln["after"])}</b></span>{pace}')
    note = lambda f, lab, ph: (f'<label class="field"><span class="k">{lab}</span>'
                               f'<textarea id="n-{lid}-{f}" data-f="{f}" placeholder="{ph}"></textarea></label>')
    return f'''
      <article class="card" id="line-{lid}" data-line="{lid}">
        <div class="card-head"><span class="badge" aria-label="Line {n}">{n}</span>
          <span class="tc">{tc(ln["start"])} to {tc(ln["end"])}</span><span class="lid">id {lid}</span>
          <span class="spacer"></span><button class="btn play" type="button" data-play="{lid}">Play this line</button></div>
        <div class="frames">{figs}</div>
        <dl class="av">
          <dt>You hear</dt><dd class="spoken">“{esc(ln["text"])}”</dd>
          <dt>Caption</dt><dd><div class="caps">{caps}</div></dd>
          <dt>You see</dt><dd>{esc(ln["see"])}</dd>
          <dt>Sounds</dt><dd><ul class="cues">{cues}</ul></dd>
          <dt>Timing</dt><dd><div class="timing">{timing}</div></dd>
        </dl>
        <section class="notes" data-note="{lid}" aria-label="Your notes on line {n}">
          <div class="row"><span class="k">Your call</span>
            <div class="verdict" role="group" aria-label="Keep, change, or cut line {n}">
              <button type="button" data-v="keep" aria-pressed="false">Keep</button><button type="button" data-v="change" aria-pressed="false">Change</button><button type="button" data-v="cut" aria-pressed="false">Cut</button>
            </div></div>
          <label class="field"><span class="k">Rewrite the line</span><input id="n-{lid}-rewrite" data-f="rewrite" type="text" value="{esc(ln["text"])}"></label>
          <div class="note-grid">{note("words", "Words", "What the voice says")}{note("picture", "Picture", "What you see")}{note("timing", "Timing", "Faster, slower, longer hold")}</div>
          <p class="reply" hidden></p>
        </section>
      </article>'''


def scene_html(s):
    look = "Sketch look" if s["look"] == "sketch" else "Nextshot look"
    cards = "".join(card_html(ln) for ln in s["lines"])
    return f'''
    <section class="scene" id="scene-{s["id"]}" aria-labelledby="h-{s["id"]}">
      <div class="scene-head"><span class="num">Scene {s["n"]}</span><h2 id="h-{s["id"]}">{esc(s["name"])}</h2>
        <span class="look {s["look"]}">{look}</span>
        <span class="tc">{tc(s["start"])} to {tc(s["end"])}, {secs(s["end"] - s["start"])}</span>
        <button class="btn play" type="button" data-play-scene="{s["id"]}">Play scene</button>
        <div class="job">Job: {esc(s["job"])}</div></div>{cards}
    </section>'''


def font_faces():
    fonts = VIDEO / "assets" / "fonts"
    out = []
    for fam, f, wt in [("Inter", "Inter-latin.woff2", "100 900"), ("Caveat", "Caveat-latin.woff2", "400 700")]:
        b64 = base64.b64encode((fonts / f).read_bytes()).decode()
        out.append(f"@font-face {{ font-family: '{fam}'; src: url(data:font/woff2;base64,{b64}) format('woff2'); "
                   f"font-weight: {wt}; font-display: swap; }}")
    return "\n".join(out)


def check_text(page):
    """House text rules: no Capso, no em dash, no middot, no italics, no unfilled slot."""
    bad = {"Capso": "Capso", "—": "em dash", "·": "middot", "font-style: italic": "italic style",
           "<em>": "em tag", "<i>": "i tag", "<i ": "i tag", "{{": "unfilled template slot"}
    found = [name for s, name in bad.items() if s in page]
    need(not found, f"page breaks text rules: {found}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--pdf", action="store_true", help="also write the Letter PDF through headless Chrome")
    args = ap.parse_args()

    script = json.loads((VIDEO / "script.json").read_text())
    timing = json.loads((VIDEO / "timing.json").read_text())
    shots = json.loads((HERE / "shots.json").read_text())
    # The version names the page database path that holds this cut's notes.
    need(re.fullmatch(r"v[0-9][0-9.]*", shots["version"]) is not None, f"shots.json version {shots['version']!r} is not like v3.2")
    video = newest_video()
    vdur = probe_duration(video)
    need(abs(vdur - timing["duration"]) < 0.3, f"{video.name} runs {vdur:.2f} s but timing.json says {timing['duration']:.2f} s")

    model = build_model(script, timing, shots)
    OUT.mkdir(parents=True, exist_ok=True)
    extract_frames(video, model["lines"])
    dst = OUT / "video.mp4"
    if not dst.exists() or dst.stat().st_size != video.stat().st_size or dst.stat().st_mtime < video.stat().st_mtime:
        shutil.copy2(video, dst)

    lines, dur = model["lines"], model["duration"]
    words = sum(ln["words"] for ln in lines)
    v = script["voice"]
    voice = f"{v['name']}, an OpenAI voice" if isinstance(v, dict) and v.get("engine") == "openai" else str(v)
    meta = [f"Cut {shots['version']}", f"{dur:.1f} seconds", f"{words} words", f"{words / dur * 60:.0f} words per minute",
            f"{len(lines)} lines", f"{len(model['scenes'])} scenes", f"Voice: {voice}"]
    data = {"version": shots["version"], "duration": dur,
            "lines": [{k: ln[k] for k in ("id", "n", "text", "start", "win")} for ln in lines],
            "scenes": [{k: s[k] for k in ("id", "n", "name", "start", "end")} for s in model["scenes"]]}
    built = datetime.now().astimezone().strftime("%Y-%m-%d %H:%M %Z")
    footer = (f"Built {built} from script.json, timing.json, and {esc(video.name)}. "
              "Source: scripts/video/nextshot-onboarding/storyboard/. Rebuild after each render with build_storyboard.py.")
    page = (HERE / "template.html").read_text()
    for key, val in {
        "{{FONTS}}": font_faces(), "{{VERSION}}": esc(shots["version"]),
        "{{META}}": "".join(f'<span class="chip">{esc(m)}</span>' for m in meta),
        "{{TIMELINE}}": timeline_html(model), "{{CARDS}}": "".join(scene_html(s) for s in model["scenes"]),
        "{{WATCH}}": esc(shots["watch"]), "{{WATCH_SHORT}}": esc(shots["watch"].split("//", 1)[-1]),
        "{{SCENE_COUNT}}": str(len(model["scenes"])), "{{FOOTER}}": footer, "{{VOICE}}": esc(voice), "{{POSTER}}": f"frames/{lines[0]['id']}-2.jpg",
        "{{DATA}}": json.dumps(data).replace("</", "<\\/"),
    }.items():
        need(key in page, f"template.html has no {key} slot")
        page = page.replace(key, val)
    check_text(page)
    (OUT / "page.html").write_text(page)
    (OUT / "local.html").write_text(
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"></head><body>'
        + page + "</body></html>")

    n_frames = len(list((OUT / "frames").glob("*.jpg")))
    need(n_frames == 2 * len(lines), f"expected {2 * len(lines)} frames, found {n_frames}")
    n_cues = sum(len(ln["cues"]) for ln in lines)
    need(n_cues == len(timing["cues"]), f"{n_cues} cues on cards but timing.json has {len(timing['cues'])}")
    print(f"storyboard: {len(model['scenes'])} scenes, {len(lines)} lines, {n_cues} cues, {n_frames} frames, "
          f"{words} words, {dur:.2f} s, from {video.name}")
    print(f"wrote {OUT / 'page.html'} and {OUT / 'local.html'}")

    if args.pdf:
        need(Path(CHROME).exists(), f"no Chrome at {CHROME}")
        subprocess.run([CHROME, "--headless", "--disable-gpu", "--no-pdf-header-footer", "--virtual-time-budget=8000",
                        f"--print-to-pdf={PDF}", (OUT / "local.html").as_uri()],
                       check=True, capture_output=True)
        need(PDF.exists() and PDF.stat().st_size > 50_000, "the PDF is missing or too small")
        print(f"wrote {PDF}")


if __name__ == "__main__":
    main()
