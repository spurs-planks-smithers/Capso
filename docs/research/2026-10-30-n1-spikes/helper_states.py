#!/usr/bin/env python3
"""N1 spike 2: drive the real NextshotBrowserHost the way Chrome does.

Chrome starts the helper with argv[1] = the extension origin, writes one
framed JSON message (4-byte little-endian length), and reads one framed reply.
This script does the same (fixture tier for Chrome, installed tier for helper
and app) and records what the receipt says and how long the helper lives.

Usage: helper_states.py <label> <helper path> [--origin ORIGIN] [--version N] [--op OP]
"""
import json
import struct
import subprocess
import sys
import time

DEV_ORIGIN = "chrome-extension://ghmidcmcjigfckaiopacgpfaffofgjel/"


def main() -> None:
    args = sys.argv[1:]
    label, helper = args[0], args[1]
    origin, version, op = DEV_ORIGIN, 1, "handshake"
    rest = args[2:]
    while rest:
        flag, value = rest[0], rest[1]
        rest = rest[2:]
        if flag == "--origin":
            origin = value
        elif flag == "--version":
            version = int(value)
        elif flag == "--op":
            op = value
    message = json.dumps({"version": version, "channel": "dev", "operation": op}).encode()
    started = time.monotonic()
    process = subprocess.Popen([helper, origin], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert process.stdin and process.stdout
    process.stdin.write(struct.pack("<I", len(message)) + message)
    process.stdin.flush()
    header = process.stdout.read(4)
    reply = None
    if len(header) == 4:
        (length,) = struct.unpack("<I", header)
        reply = process.stdout.read(length).decode()
    replied = time.monotonic()
    code = process.wait(timeout=15)
    exited = time.monotonic()
    print(json.dumps({
        "label": label,
        "operation": op,
        "version": version,
        "origin_ok": origin == DEV_ORIGIN,
        "reply": json.loads(reply) if reply else None,
        "reply_ms": round((replied - started) * 1000),
        "lifetime_ms": round((exited - started) * 1000),
        "exit_code": code,
    }))


if __name__ == "__main__":
    main()
