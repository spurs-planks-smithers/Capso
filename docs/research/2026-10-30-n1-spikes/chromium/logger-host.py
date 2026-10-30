#!/usr/bin/python3 -I
"""One-shot native host: append the extension's message to a log file with a host-side clock.

The no-debugger probe uses it so that no DevTools session touches the worker.
Chrome starts one process per sendNativeMessage call.
"""
import json
import struct
import sys
import time

log_path = sys.argv[1]
header = sys.stdin.buffer.read(4)
if len(header) == 4:
    (length,) = struct.unpack("<I", header)
    message = json.loads(sys.stdin.buffer.read(length))
    with open(log_path, "a") as handle:
        handle.write(json.dumps({"host_ms": round(time.time() * 1000), **message}) + "\n")
    reply = b"{}"
    sys.stdout.buffer.write(struct.pack("<I", len(reply)) + reply)
    sys.stdout.buffer.flush()
