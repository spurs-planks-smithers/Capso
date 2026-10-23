#!/usr/bin/env python3
"""Check that every voice clip says exactly its script line, and report its pace.

Transcribes audio/vo/<line>.wav with OpenAI Whisper (word timestamps) and compares
the words with script.json. A speech model can add, drop, or repeat a word, as the
one-word "Nextshot." line once did, so run this after every make_audio.py.
Exit code 1 when any clip differs from its line.

The key comes from the Keychain item in script.json "voice.keychain", in memory only.
Run: python3 scripts/video/nextshot-onboarding/check_voice.py
"""
import json
import re
import subprocess
import sys
import uuid
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def words(text):
    return re.findall(r"[a-z0-9$']+", text.lower().replace("-", " "))


def transcribe(path, key):
    boundary = uuid.uuid4().hex
    parts = []
    for name, value in [("model", "whisper-1"), ("response_format", "verbose_json"),
                        ("timestamp_granularities[]", "word"), ("language", "en")]:
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
    parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{path.name}"\r\n'
                 f"Content-Type: audio/wav\r\n\r\n".encode() + path.read_bytes() + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    req = urllib.request.Request("https://api.openai.com/v1/audio/transcriptions", data=b"".join(parts), headers={
        "Authorization": "Bearer " + key, "Content-Type": f"multipart/form-data; boundary={boundary}"})
    return json.loads(urllib.request.urlopen(req, timeout=120).read())


def main():
    script = json.loads((ROOT / "script.json").read_text())
    item = script["voice"]["keychain"]
    key = subprocess.run(["security", "find-generic-password", "-s", item, "-w"],
                         capture_output=True, text=True, check=True).stdout.strip()
    lines = [ln for sc in script["scenes"] for ln in sc["lines"]]
    assert lines, "script.json has no lines"
    bad, report = 0, {}
    for ln in lines:
        clip = ROOT / "audio" / "vo" / f"{ln['id']}.wav"
        got = transcribe(clip, key)
        heard = words(got.get("text", ""))
        want = words(ln["text"])
        # Whisper may split a word ("Next shot", "Option-Shift-F"), so compare with spaces removed.
        ok = "".join(heard) == "".join(want)
        bad += not ok
        span = (got["words"][-1]["end"] - got["words"][0]["start"]) if got.get("words") else 0.0
        report[ln["id"]] = {"ok": ok, "heard": got.get("text", "").strip(), "words": got.get("words", [])}
        print(f"{'ok ' if ok else 'BAD'} {ln['id']:8} {len(want) / max(span, 0.01):4.2f} w/s  heard: {got.get('text', '').strip()}")
    (ROOT / "audio" / "transcripts.json").write_text(json.dumps(report, indent=1) + "\n")
    print(f"{len(lines) - bad} of {len(lines)} clips match their lines")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
