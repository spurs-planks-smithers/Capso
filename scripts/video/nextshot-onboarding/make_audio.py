#!/usr/bin/env python3
"""Build the audio and the timing for the Nextshot onboarding video.

Reads script.json. Writes:
  audio/vo/<line>.wav  one voice clip per line (48 kHz mono)
  audio/mix.wav        voice, effects, and music before loudness normalization
  audio/final.wav      the mix at -16 LUFS integrated, -1.5 dBTP true peak
  timing.json          scene, line, caption, and cue times in seconds
  timing.js            the same data as window.TIMING for index.html

The voice comes from the OpenAI speech API (script.json "voice"). The key is read
from the macOS Keychain item named in "voice.keychain", in memory only. Each clip
is cached in audio/tts-cache/ by model, voice, direction, and text, so a re-run
buys no audio it already has. `--say` uses the macOS fallback voice instead.

Uses only the Python standard library, the macOS `say` command, and ffmpeg.
Every random choice uses a fixed seed, so each run writes the same audio.
"""

import hashlib
import http.client
import json
import math
import random
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
import wave
from array import array
from pathlib import Path

import check_voice  # Whisper transcription, shared with the voice check

ROOT = Path(__file__).resolve().parent
AUDIO = ROOT / "audio"
VO_DIR = AUDIO / "vo"
TTS_CACHE = AUDIO / "tts-cache"
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


def trim_to(src, out_wav, tempo=1.0, max_gap=None):
    """Trim the silence at both ends, cap the pauses inside, set the pace, write 48 kHz mono.

    max_gap caps every pause inside the line at about that many seconds. The OpenAI
    voice leaves pauses up to 0.8 s between sentences, which a 45-second cut cannot hold.
    """
    if max_gap:
        # The OpenAI clips carry soft breath noise in their pauses, so peak detection
        # calls them sound. Average level (RMS) finds them. Each pause keeps max_gap
        # seconds, and each end keeps 0.1 s, so a quiet word tail stays whole.
        trim = (
            f"silenceremove=stop_periods=-1:stop_duration={max_gap}:stop_threshold=-38dB:"
            f"stop_silence={max_gap}:detection=rms,"
            "silenceremove=start_periods=1:start_threshold=-48dB:start_silence=0.1:detection=rms,"
            "areverse,"
            "silenceremove=start_periods=1:start_threshold=-48dB:start_silence=0.15:detection=rms,"
            "afade=t=in:d=0.05,areverse,afade=t=in:d=0.01,"
            # 40 ms of true silence at each end, so every clip starts and ends clean.
            "adelay=delays=40:all=1,apad=pad_dur=0.04"
        )
    else:
        # Peak detection never trims into a quiet word ending (the default RMS
        # window cut the tail of "all"). Short fades at both ends prevent clicks.
        trim = (
            "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.03:detection=peak,"
            "areverse,"
            "silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.06:detection=peak,"
            "afade=t=in:d=0.025,areverse,afade=t=in:d=0.005"
        )
    if abs(tempo - 1.0) > 1e-6:
        trim += f",atempo={tempo}"
    run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-af", trim,
         "-ar", str(SR), "-ac", "1", "-c:a", "pcm_s16le", str(out_wav)])


def make_vo_say(text, voice, out_wav, tempo=1.08):
    """The macOS fallback. Ava (Premium) barely changes pace with `say -r`, so atempo sets it."""
    aiff = out_wav.with_suffix(".aiff")
    run(["say", "-v", voice, "-o", str(aiff), text])
    trim_to(aiff, out_wav, tempo)
    aiff.unlink()


_KEY = None


def openai_key(item):
    """Read the API key from the Keychain into memory. It is never printed or written."""
    global _KEY
    if _KEY is None:
        got = subprocess.run(["security", "find-generic-password", "-s", item, "-w"],
                             capture_output=True, text=True)
        if got.returncode != 0 or not got.stdout.strip():
            sys.exit(f"make_audio: no Keychain item {item}. Store it with keychain-store.sh {item}.")
        _KEY = got.stdout.strip()
    return _KEY


def make_vo_openai(text, cfg, direction, out_wav, take=1, max_gap=None):
    """Speak one line with the OpenAI speech API. Cached by model, voice, direction, text, and take.

    A new take number asks for a fresh reading of the same line.
    """
    instructions = cfg["style"] + (" " + direction if direction else "")
    parts = [cfg["model"], cfg["name"], instructions, text] + ([f"take {take}"] if take != 1 else [])
    key = hashlib.sha1("\n".join(parts).encode()).hexdigest()[:16]
    TTS_CACHE.mkdir(parents=True, exist_ok=True)
    raw = TTS_CACHE / f"{key}.wav"
    if not raw.exists():
        body = json.dumps({"model": cfg["model"], "voice": cfg["name"], "input": text,
                           "instructions": instructions, "response_format": "wav"}).encode()
        for attempt in range(4):
            req = urllib.request.Request("https://api.openai.com/v1/audio/speech", data=body, headers={
                "Authorization": "Bearer " + openai_key(cfg["keychain"]), "Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=120) as resp:
                    data = resp.read()
                break
            except (http.client.IncompleteRead, urllib.error.URLError, TimeoutError) as err:
                if attempt == 3:
                    raise
                print(f"  retry {attempt + 1} for {text[:30]!r}: {type(err).__name__}")
                time.sleep(1.5 * (attempt + 1))
        # A cut-off stream never reaches the cache: write to a temporary file, then rename.
        part = raw.with_suffix(".part")
        part.write_bytes(data)
        part.rename(raw)
    # sage breathes audibly between sentences, louder than a silence threshold.
    # A stretch that stays quiet for 0.3 s or more is a breath or a pause, never a word:
    # cut it to a short margin. (Whisper word times cut into words, so they are not used.)
    quiet = quiet_spans(raw, cfg.get("breath_db", -35), 0.35)
    segs = keep_segments(quiet, wav_seconds(raw))
    cut = out_wav.with_suffix(".cut.wav")
    cut_segments(raw, segs, cut)
    trim_to(cut, out_wav, cfg.get("tempo", 1.0), max_gap or cfg.get("max_gap"))
    cut.unlink()


def wav_seconds(path):
    with wave.open(str(path), "rb") as w:
        return w.getnframes() / w.getframerate()


def quiet_spans(path, db, min_len):
    """Stretches at least min_len seconds long whose level stays under db, from ffmpeg silencedetect."""
    out = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(path), "-af", f"silencedetect=noise={db}dB:d={min_len}",
                          "-f", "null", "-"], capture_output=True, text=True).stderr
    starts = [float(x) for x in re.findall(r"silence_start: ([0-9.]+)", out)]
    ends = [float(x) for x in re.findall(r"silence_end: ([0-9.]+)", out)]
    total = wav_seconds(path)
    ends += [total] * (len(starts) - len(ends))  # a quiet stretch that runs to the end
    return list(zip(starts, ends))


def keep_segments(quiet, total, margin=0.15, lead=0.08, tail=0.3):
    """The parts of a clip to keep: everything except the quiet stretches, which shrink to
    a margin on each side. A leading or trailing stretch keeps only lead or tail seconds."""
    start, segs = 0.0, []
    for a, b in quiet:
        if a <= 0.01:
            start = max(0.0, b - lead)
        elif b >= total - 0.01:
            segs.append((start, min(total, a + tail)))
            return segs
        elif b - a > 2 * margin + 0.05:
            segs.append((start, a + margin))
            start = b - margin
    segs.append((start, total))
    return segs


def cut_segments(src, segs, out):
    """Join the kept parts with 5 ms fades at each joint, so no cut clicks."""
    chains, labels = [], []
    for k, (a, b) in enumerate(segs):
        d = b - a
        chains.append(f"[0:a]atrim={a:.3f}:{b:.3f},asetpts=PTS-STARTPTS,"
                      f"afade=t=in:d=0.005,afade=t=out:st={max(0.0, d - 0.005):.3f}:d=0.005[s{k}]")
        labels.append(f"[s{k}]")
    graph = ";".join(chains) + ";" + "".join(labels) + f"concat=n={len(segs)}:v=0:a=1[out]"
    run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(src), "-filter_complex", graph, "-map", "[out]", str(out)])


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


def sfx_pops(span, count):
    """A run of pops, evenly spaced, rising slightly. The picture places a dot on each."""
    out = blank(span + 0.2)
    for k in range(count):
        add(out, sfx_pop(), span * k / max(1, count), 0.75 + 0.25 * k / max(1, count))
    return out


def sfx_snip():
    """Scissors: two short bright clicks."""
    out = blank(0.12)
    add(out, noise(0.015, 0.7, 0.004), 0.0)
    add(out, tone(4200, 0.02, 0.2, 0.004), 0.0)
    add(out, noise(0.015, 0.8, 0.004), 0.055)
    add(out, tone(3600, 0.02, 0.22, 0.004), 0.055)
    return out


def make_sfx(name, span, count=None):
    if name == "typing":
        return sfx_typing(span)
    if name == "ticks":
        return sfx_ticks(span, count or 10)
    if name == "pops":
        return sfx_pops(span, count or 3)
    if name == "snip":
        return sfx_snip()
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
        # Sparse in the rough sketch part (quarter notes), full eighths after the turn.
        if t >= turn_at or k % 2 == 0:
            add(out, pluck(tones[pattern[k]], 0.6, 0.32, 0.994), t)
        if k in (0, 4):
            add(out, pluck(bass, 1.1, 0.5, 0.997), t)
        if t >= turn_at and k % 2 == 1:
            add(out, noise(0.03, 0.12, 0.008), t)  # shaker after the turn
        step += 1
    for k, note in enumerate([48, 60, 64, 67, 72, 76]):  # final strum, C major
        add(out, pluck(note, max(0.6, total - chord_at), 0.3, 0.9985), chord_at + k * 0.018)
    fade_in = int(1.0 * SR)  # a soft start: the opening is pictures and music only
    for i in range(min(fade_in, len(out))):
        out[i] *= i / fade_in
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
    cfg = script["voice"]
    use_say = "--say" in sys.argv or cfg.get("engine") != "openai"
    VO_DIR.mkdir(parents=True, exist_ok=True)
    for old in VO_DIR.glob("*.wav"):  # line ids change between cuts
        old.unlink()

    vo, lengths = {}, {}
    for scene in script["scenes"]:
        for line in scene["lines"]:
            path = VO_DIR / f"{line['id']}.wav"
            if use_say:
                make_vo_say(line["text"], cfg.get("fallback", "Ava (Premium)"), path)
            else:
                make_vo_openai(line["text"], cfg, line.get("direction", ""), path, line.get("take", 1), line.get("max_gap"))
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
            add(fx, make_sfx(c["sfx"], c.get("span", 0.0), c.get("count")), cues[c["id"]])

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
    who = cfg.get("fallback") if use_say else f"OpenAI {cfg['model']}, voice {cfg['name']}"
    print(f"duration {total:.2f} s, {words} words, {len(captions)} captions, voice: {who}")
    for s in scenes:
        print(f"  {s['id']:<8} {s['start']:6.2f} to {s['end']:6.2f}")


if __name__ == "__main__":
    main()
