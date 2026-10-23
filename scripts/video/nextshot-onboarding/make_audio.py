#!/usr/bin/env python3
"""Build the audio and the timing for the Nextshot onboarding video.

Reads script.json. Writes:
  audio/vo/<line>.wav  one Ava clip per line (48 kHz mono)
  audio/mix.wav        voice, effects, and music before loudness normalization
  audio/final.wav      the mix at -16 LUFS integrated, -1.5 dBTP true peak
  timing.json          scene, line, caption, and cue times in seconds
  timing.js            the same data as window.TIMING for index.html

Uses only the Python standard library, the macOS `say` command, and ffmpeg.
Every random choice uses a fixed seed, so each run writes the same audio.
"""

import json
import math
import random
import re
import subprocess
import wave
from array import array
from pathlib import Path

ROOT = Path(__file__).resolve().parent
AUDIO = ROOT / "audio"
VO_DIR = AUDIO / "vo"
SR = 48000


def run(cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True)


def read_wav(path):
    with wave.open(str(path), "rb") as w:
        assert w.getframerate() == SR and w.getnchannels() == 1 and w.getsampwidth() == 2
        raw = array("h")
        raw.frombytes(w.readframes(w.getnframes()))
    return array("f", (s / 32768.0 for s in raw))


def write_wav(path, samples):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = min(1.0, 0.89 / peak)
    data = array("h", (int(max(-1.0, min(1.0, s * scale)) * 32767) for s in samples))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def make_vo(text, voice, rate, tempo, out_wav):
    """Speak one line with `say`, trim the silence at both ends, and speed it up.

    Ava (Premium) barely changes pace with `say -r`, so the pitch-preserving
    atempo filter sets the final pace.
    """
    aiff = out_wav.with_suffix(".aiff")
    run(["say", "-v", voice, "-r", str(rate), "-o", str(aiff), text])
    # Peak detection never trims into a quiet word ending (the default RMS
    # window cut the tail of "all"). Short fades at both ends prevent clicks.
    trim = (
        "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.03:detection=peak,"
        "areverse,"
        "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.06:detection=peak,"
        "afade=t=in:d=0.025,areverse,afade=t=in:d=0.005,"
        f"atempo={tempo}"
    )
    run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(aiff), "-af", trim,
         "-ar", str(SR), "-ac", "1", "-c:a", "pcm_s16le", str(out_wav)])
    aiff.unlink()


# ---------- timing ----------

def build_timeline(script, vo_lengths):
    scenes, lines, captions = [], {}, []
    t = 0.0
    for scene in script["scenes"]:
        start = t
        t += scene["lead"]
        for line in scene["lines"]:
            dur = vo_lengths[line["id"]]
            lines[line["id"]] = {"text": line["text"], "start": round(t, 3),
                                 "end": round(t + dur, 3), "scene": scene["id"]}
            chunks = line.get("captions", [line["text"]])
            total = sum(len(c) for c in chunks)
            done = 0
            for chunk in chunks:
                captions.append({"text": chunk, "start": round(t + dur * done / total, 3)})
                done += len(chunk)
            t += dur + line["pause"]
        t += scene["tail"]
        scenes.append({"id": scene["id"], "start": round(start, 3), "end": round(t, 3)})

    # A caption stays up until the next one starts, or briefly past its line.
    ends = {}
    for line in lines.values():
        for c in captions:
            if line["start"] <= c["start"] <= line["end"]:
                ends[id(c)] = line["end"]
    for i, c in enumerate(captions):
        hold = ends[id(c)] + 0.35
        nxt = captions[i + 1]["start"] if i + 1 < len(captions) else hold
        c["end"] = round(min(hold, nxt), 3)
    return scenes, lines, captions, round(t, 3)


def cue_time(cue, lines):
    """A cue sits at a line start, or at the estimated time of a word in it.

    The word time is an estimate: speech time is taken as proportional to
    the characters before the word.
    """
    line = lines[cue["line"]]
    t = line["start"]
    if "word" in cue:
        hits = [m.start() for m in re.finditer(r"\b%s\b" % re.escape(cue["word"]), line["text"])]
        idx = hits[cue.get("nth", 1) - 1]
        t += (line["end"] - line["start"]) * idx / len(line["text"])
    return round(t + cue.get("offset", 0.0), 3)


# ---------- sound effects ----------

rng = random.Random(7)


def blank(seconds):
    return array("f", bytes(4 * int(seconds * SR)))


def add(dst, src, at, gain=1.0):
    i0 = int(at * SR)
    for i, s in enumerate(src):
        j = i0 + i
        if 0 <= j < len(dst):
            dst[j] += s * gain


def tone(freq, seconds, amp, tau, attack=0.002):
    out = blank(seconds)
    for i in range(len(out)):
        t = i / SR
        env = min(1.0, t / attack) * math.exp(-t / tau)
        out[i] = amp * env * math.sin(2 * math.pi * freq * t)
    return out


def noise(seconds, amp, tau, highpass=True):
    out = blank(seconds)
    prev = 0.0
    for i in range(len(out)):
        x = rng.uniform(-1, 1)
        y = x - prev if highpass else x
        prev = x
        out[i] = amp * y * math.exp(-(i / SR) / tau)
    return out


def sfx_pop():
    out = blank(0.12)
    phase = 0.0
    for i in range(len(out)):
        t = i / SR
        freq = 380 + 620 * math.exp(-t / 0.018)
        phase += 2 * math.pi * freq / SR
        out[i] = 0.8 * min(1.0, t / 0.002) * math.exp(-t / 0.03) * math.sin(phase)
    add(out, noise(0.006, 0.25, 0.002), 0)
    return out


def sfx_click():
    out = noise(0.02, 0.6, 0.003)
    add(out, tone(3000, 0.01, 0.25, 0.003), 0)
    return out


def sfx_key():
    out = noise(0.03, 0.45, 0.004)
    add(out, tone(180, 0.04, 0.3, 0.012), 0)
    add(out, tone(1800, 0.015, 0.15, 0.004), 0)
    return out


def sfx_shutter():
    out = blank(0.2)
    add(out, noise(0.06, 0.9, 0.012), 0.0)
    add(out, noise(0.06, 0.7, 0.012), 0.075)
    return out


def sfx_tick(pitch=2200):
    return tone(pitch, 0.04, 0.4, 0.008)


def sfx_whoosh(seconds=0.55, amp=0.55):
    out = blank(seconds)
    y = 0.0
    for i in range(len(out)):
        p = i / len(out)
        fc = 300 + 3200 * math.sin(math.pi * p) ** 2
        a = math.exp(-2 * math.pi * fc / SR)
        y = (1 - a) * rng.uniform(-1, 1) + a * y
        out[i] = amp * 3.0 * y * math.sin(math.pi * p) ** 2
    return out


def bell(freq, seconds, amp, tau):
    out = tone(freq, seconds, amp, tau)
    add(out, tone(freq * 2.0, seconds, amp * 0.3, tau * 0.5), 0)
    add(out, tone(freq * 3.01, seconds, amp * 0.12, tau * 0.3), 0)
    return out


def sfx_ding():
    out = blank(0.9)
    add(out, bell(880.0, 0.8, 0.35, 0.3), 0.0)
    add(out, bell(1318.5, 0.8, 0.35, 0.35), 0.09)
    return out


def sfx_sparkle():
    out = blank(0.8)
    for k, f in enumerate([1046.5, 1318.5, 1568.0, 2093.0]):
        add(out, bell(f, 0.6, 0.22, 0.2), k * 0.05)
    return out


def sfx_typing(span):
    out = blank(span + 0.1)
    t = 0.0
    while t < span:
        add(out, sfx_key(), t, rng.uniform(0.5, 0.9))
        t += rng.uniform(0.07, 0.13)
    return out


def sfx_ticks(span, count=10):
    out = blank(span + 0.1)
    for k in range(count):
        add(out, sfx_tick(1800 + 80 * k), span * k / count)
    return out


def make_sfx(name, span):
    if name == "typing":
        return sfx_typing(span)
    if name == "ticks":
        return sfx_ticks(span)
    if name == "whoosh_small":
        return sfx_whoosh(0.3, 0.4)
    return {"pop": sfx_pop, "click": sfx_click, "key": sfx_key, "shutter": sfx_shutter,
            "tick": sfx_tick, "whoosh": sfx_whoosh, "ding": sfx_ding,
            "sparkle": sfx_sparkle}[name]()


# ---------- music: plucked strings (Karplus-Strong) ----------

def midi_hz(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def pluck(note, seconds, amp, decay):
    freq = midi_hz(note)
    period = max(2, int(round(SR / freq)))
    buf = [rng.uniform(-1, 1) for _ in range(period)]
    buf = [(buf[k] + buf[k - 1]) * 0.5 for k in range(period)]  # softer attack
    out = blank(seconds)
    idx = 0
    n = len(out)
    fade = int(0.05 * SR)
    for i in range(n):
        v = buf[idx]
        nxt = buf[idx + 1 if idx + 1 < period else 0]
        buf[idx] = decay * 0.5 * (v + nxt)
        idx = idx + 1 if idx + 1 < period else 0
        out[i] = amp * v * (1.0 if i < n - fade else (n - i) / fade)
    return out


def make_music(total, turn_at, chord_at):
    bpm = 104
    eighth = 60.0 / bpm / 2
    chords = [  # C, G, Am, F voicings and bass roots
        ([60, 64, 67, 72], 48),
        ([59, 62, 67, 71], 43),
        ([60, 64, 69, 72], 45),
        ([60, 65, 69, 72], 41),
    ]
    pattern = [0, 2, 3, 2, 1, 2, 3, 2]
    out = blank(total + 0.5)
    step = 0
    while True:
        t = step * eighth
        if t >= chord_at - 0.05:
            break
        tones, bass = chords[(step // 8) % 4]
        k = step % 8
        add(out, pluck(tones[pattern[k]], 0.6, 0.32, 0.994), t)
        if k in (0, 4):
            add(out, pluck(bass, 1.1, 0.5, 0.997), t)
        if t >= turn_at and k % 2 == 1:
            add(out, noise(0.03, 0.12, 0.008), t)  # shaker after the turn
        step += 1
    for k, note in enumerate([48, 60, 64, 67, 72, 76]):  # final strum, C major
        add(out, pluck(note, max(0.6, total - chord_at), 0.3, 0.9985), chord_at + k * 0.018)
    fade = int(0.6 * SR)
    end = int(total * SR)
    for i in range(max(0, end - fade), len(out)):
        out[i] *= max(0.0, (end - i) / fade)
    return out


# ---------- mix ----------

def rms(samples, mask=None):
    acc, n = 0.0, 0
    for i, s in enumerate(samples):
        if mask is None or mask[i]:
            acc += s * s
            n += 1
    return math.sqrt(acc / max(1, n))


def loudnorm(src, dst):
    """Two-pass EBU R128 normalization to -16 LUFS, -1.5 dBTP."""
    target = "I=-16:TP=-1.5:LRA=11"
    first = subprocess.run(
        ["ffmpeg", "-hide_banner", "-i", str(src), "-af", f"loudnorm={target}:print_format=json",
         "-f", "null", "-"], capture_output=True, text=True, check=True)
    block = first.stderr[first.stderr.rindex("{"):]
    m = json.loads(block[: block.index("}") + 1])
    second = (f"loudnorm={target}:measured_I={m['input_i']}:measured_TP={m['input_tp']}"
              f":measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}"
              f":offset={m['target_offset']}:linear=true")
    run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-af", second,
         "-ar", str(SR), "-ac", "2", "-c:a", "pcm_s16le", str(dst)])


def patch_durations(total):
    """HyperFrames reads data-duration from the HTML, so write the new length there."""
    page = ROOT / "index.html"
    if not page.exists():
        return
    text = page.read_text()
    new = re.sub(r'data-auto-duration data-duration="[0-9.]+"',
                 f'data-auto-duration data-duration="{total}"', text)
    if new != text:
        page.write_text(new)


def main():
    script = json.loads((ROOT / "script.json").read_text())
    VO_DIR.mkdir(parents=True, exist_ok=True)

    vo, lengths = {}, {}
    for scene in script["scenes"]:
        for line in scene["lines"]:
            path = VO_DIR / f"{line['id']}.wav"
            make_vo(line["text"], script["voice"], script["rate"], script["tempo"], path)
            vo[line["id"]] = read_wav(path)
            lengths[line["id"]] = len(vo[line["id"]]) / SR

    scenes, lines, captions, total = build_timeline(script, lengths)
    cues = {c["id"]: cue_time(c, lines) for c in script["cues"]}

    n = int((total + 0.5) * SR)
    voice, fx = blank(total + 0.5), blank(total + 0.5)
    active = bytearray(n)
    for lid, line in lines.items():
        add(voice, vo[lid], line["start"])
        for i in range(int((line["start"] - 0.05) * SR), min(n, int((line["end"] + 0.1) * SR))):
            active[i] = 1
    for c in script["cues"]:
        if c.get("sfx"):
            add(fx, make_sfx(c["sfx"], c.get("span", 0.0)), cues[c["id"]])

    turn = next(s for s in scenes if s["id"] == "turn")
    music = make_music(total, turn["start"], cues["final_chord"])

    # Levels relative to the voice: music about 20 dB under it, effects about 8 dB under.
    vo_rms = rms(voice, active)
    music_gain = vo_rms * 10 ** (-20 / 20) / max(1e-9, rms(music))
    fx_peak = max(abs(s) for s in fx) or 1.0
    vo_peak = max(abs(s) for s in voice)
    fx_gain = vo_peak * 10 ** (-8 / 20) / fx_peak

    mix = blank(total + 0.5)
    duck = 1.0
    for i in range(n):
        want = 0.55 if active[i] else 1.0  # duck the music under speech
        rate = 0.0006 if want < duck else 0.00008
        duck += (want - duck) * rate * 48
        mix[i] = voice[i] + fx[i] * fx_gain + music[i] * music_gain * duck
    mix = mix[: int(total * SR)]

    write_wav(AUDIO / "mix.wav", mix)
    loudnorm(AUDIO / "mix.wav", AUDIO / "final.wav")

    timing = {"duration": total, "fps": script["fps"], "scenes": scenes,
              "lines": lines, "captions": captions, "cues": cues}
    (ROOT / "timing.json").write_text(json.dumps(timing, indent=2) + "\n")
    (ROOT / "timing.js").write_text("window.TIMING = " + json.dumps(timing) + ";\n")
    patch_durations(total)

    words = sum(len(line["text"].split()) for line in lines.values())
    print(f"duration {total:.2f} s, {words} words, {len(captions)} captions")
    for s in scenes:
        print(f"  {s['id']:<8} {s['start']:6.2f} to {s['end']:6.2f}")


if __name__ == "__main__":
    main()
