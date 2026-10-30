#!/usr/bin/env python3
"""N1 spike 3 harness: plays Chrome against the spike app and host.

Chrome is a fixture here (a Python process that owns the host's stdio, which is all
Chrome does for connectNative). The real Chrome engine lifecycle is covered by the
chromium folder. Usage: harness.py <bin folder> <idle seconds>
"""
import json
import os
import signal
import struct
import subprocess
import sys
import threading
import time

BIN = sys.argv[1]
IDLE = float(sys.argv[2]) if len(sys.argv) > 2 else 20
APP_ID = "com.drewschulz.nextshot.dev.spike-app"
HOST_ID = "com.drewschulz.nextshot.dev.spike-host"
ORIGIN = "chrome-extension://spike/"


def cpu_seconds(pid):
    out = subprocess.run(["ps", "-o", "cputime=,rss=", "-p", str(pid)], capture_output=True, text=True).stdout.split()
    if not out:
        return None, None
    minutes, seconds = out[0].split(":")
    return round(int(minutes) * 60 + float(seconds), 2), int(out[1])


class App:
    def __init__(self):
        self.t0 = time.monotonic()
        self.process = subprocess.Popen([f"{BIN}/spike-app", HOST_ID, f"{BIN}/spike-host", "120"],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        self.events = []
        threading.Thread(target=self._read, daemon=True).start()
        self.wait_for("ready", 5)

    def _read(self):
        for line in self.process.stdout:
            event = json.loads(line)
            event["at"] = time.monotonic()
            self.events.append(event)

    def wait_for(self, name, seconds, after=0):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            for event in self.events:
                if event["ev"] == name and event["at"] >= after:
                    return event
            time.sleep(0.005)
        return None

    def say(self, line):
        self.process.stdin.write(line + "\n")
        self.process.stdin.flush()

    def stop(self):
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait()


class Host:
    def __init__(self, app_pid, binary="spike-host"):
        self.process = subprocess.Popen([f"{BIN}/{binary}", ORIGIN, str(app_pid), APP_ID, f"{BIN}/spike-app"],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.started = time.monotonic()
        self.frames = []
        self.stderr_text = ""
        threading.Thread(target=self._read, daemon=True).start()
        threading.Thread(target=self._read_err, daemon=True).start()

    def _read(self):
        while True:
            header = self.process.stdout.read(4)
            if len(header) < 4:
                return
            body = self.process.stdout.read(struct.unpack("<I", header)[0])
            frame = json.loads(body)
            frame["at"] = time.monotonic()
            self.frames.append(frame)

    def _read_err(self):
        self.stderr_text = self.process.stderr.read().decode()

    def send(self, body):
        data = json.dumps(body).encode()
        self.process.stdin.write(struct.pack("<I", len(data)) + data)
        self.process.stdin.flush()

    def wait_frame(self, kind, seconds, after=0):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            for frame in self.frames:
                if frame.get("type") == kind and frame["at"] >= after:
                    return frame
            time.sleep(0.005)
        return None

    def wait_exit(self, seconds):
        try:
            self.process.wait(timeout=seconds)
            return time.monotonic()
        except subprocess.TimeoutExpired:
            return None

    def kill(self):
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait()


def ms(a, b):
    return None if a is None or b is None else round((b - a) * 1000)


def scenario_happy():
    app = App()
    host = Host(app.process.pid)
    t = time.monotonic()
    host.send({"op": "open"})
    ready = host.wait_frame("ready", 5)
    open_ms = ms(t, ready["at"]) if ready else None
    held = app.wait_for("wait-held", 5)
    time.sleep(1.0)
    t = time.monotonic()
    app.say("cmd frames")
    command = host.wait_frame("command", 5)
    command_ms = ms(t, command["at"]) if command else None
    t = time.monotonic()
    host.send({"op": "result", "value": "frames:3"})
    result = app.wait_for("result", 5, after=t)
    result_ms = ms(t, result["at"]) if result else None
    app.wait_for("wait-held", 5, after=t)
    cpu_before = (cpu_seconds(host.process.pid), cpu_seconds(app.process.pid))
    time.sleep(IDLE)
    cpu_after = (cpu_seconds(host.process.pid), cpu_seconds(app.process.pid))
    t = time.monotonic()
    host.process.stdin.close()  # what Chrome does when the port closes or the worker ends
    exited = host.wait_exit(5)
    ended = app.wait_for("session-ended", 5, after=t)
    host.kill(); app.stop()
    return {"scenario": "happy-then-chrome-disconnect", "open_ms": open_ms, "command_ms": command_ms, "result_ms": result_ms,
            "idle_seconds": IDLE, "host_cpu_s_and_rss_kb": [cpu_before[0], cpu_after[0]], "app_cpu_s_and_rss_kb": [cpu_before[1], cpu_after[1]],
            "host_exit_after_disconnect_ms": ms(t, exited), "app_session_end_after_disconnect_ms": ms(t, ended["at"]) if ended else None,
            "app_end_reason": ended.get("reason") if ended else None, "host_stderr": host.stderr_text.strip()}


def scenario_close_op():
    app = App(); host = Host(app.process.pid)
    host.send({"op": "open"}); host.wait_frame("ready", 5); app.wait_for("wait-held", 5)
    t = time.monotonic()
    host.send({"op": "close"})
    closed = host.wait_frame("closed", 5, after=t); exited = host.wait_exit(5)
    ended = app.wait_for("session-ended", 5, after=t)
    host.kill(); app.stop()
    return {"scenario": "chrome-close-op", "closed_frame_ms": ms(t, closed["at"]) if closed else None, "host_exit_ms": ms(t, exited),
            "app_session_end_ms": ms(t, ended["at"]) if ended else None, "app_end_reason": ended.get("reason") if ended else None}


def scenario_app_crash():
    app = App(); host = Host(app.process.pid)
    host.send({"op": "open"}); host.wait_frame("ready", 5); app.wait_for("wait-held", 5)
    t = time.monotonic()
    os.kill(app.process.pid, signal.SIGKILL)
    closed = host.wait_frame("closed", 10, after=t); exited = host.wait_exit(10)
    host.kill(); app.stop()
    return {"scenario": "app-crash-sigkill", "closed_frame_ms": ms(t, closed["at"]) if closed else None,
            "closed_reason": closed.get("reason") if closed else None, "ae_error_code": closed.get("code") if closed else None,
            "host_exit_ms": ms(t, exited), "host_stderr": host.stderr_text.strip()}


def scenario_cancel():
    app = App(); host = Host(app.process.pid)
    host.send({"op": "open"}); host.wait_frame("ready", 5); app.wait_for("wait-held", 5)
    t = time.monotonic()
    app.say("cancel")
    closed = host.wait_frame("closed", 5, after=t); exited = host.wait_exit(5)
    host.kill(); app.stop()
    return {"scenario": "app-cancel", "closed_frame_ms": ms(t, closed["at"]) if closed else None,
            "closed_reason": closed.get("reason") if closed else None, "host_exit_ms": ms(t, exited)}


def scenario_host_killed():
    app = App(); host = Host(app.process.pid)
    host.send({"op": "open"}); host.wait_frame("ready", 5); app.wait_for("wait-held", 5)
    t = time.monotonic()
    os.kill(host.process.pid, signal.SIGKILL)
    ended = app.wait_for("session-ended", 5, after=t)
    host.kill(); app.stop()
    return {"scenario": "host-crash-sigkill", "app_session_end_ms": ms(t, ended["at"]) if ended else None,
            "app_end_reason": ended.get("reason") if ended else None}


def scenario_chrome_killed():
    app = App()
    code = ("import subprocess,sys,time,struct,json;"
            f"p=subprocess.Popen(['{BIN}/spike-host','{ORIGIN}','{app.process.pid}','{APP_ID}','{BIN}/spike-app'],stdin=subprocess.PIPE,stdout=subprocess.PIPE);"
            "d=json.dumps({'op':'open'}).encode();p.stdin.write(struct.pack('<I',len(d))+d);p.stdin.flush();"
            "print(p.pid,flush=True);time.sleep(120)")
    fake = subprocess.Popen([sys.executable, "-I", "-c", code], stdout=subprocess.PIPE, text=True)
    host_pid = int(fake.stdout.readline())
    app.wait_for("wait-held", 5)
    t = time.monotonic()
    os.kill(fake.pid, signal.SIGKILL)  # the browser process dies without closing anything
    ended = app.wait_for("session-ended", 5, after=t)
    time.sleep(0.2)
    alive = subprocess.run(["ps", "-p", str(host_pid)], capture_output=True).returncode == 0
    if alive:
        os.kill(host_pid, signal.SIGKILL)
    app.stop()
    return {"scenario": "chrome-process-killed", "host_still_alive_after": alive,
            "app_session_end_ms": ms(t, ended["at"]) if ended else None, "app_end_reason": ended.get("reason") if ended else None}


def scenario_impostor():
    app = App(); host = Host(app.process.pid, "spike-impostor")
    t = time.monotonic()
    host.send({"op": "open"})
    closed = host.wait_frame("closed", 5, after=t); exited = host.wait_exit(5)
    rejected = app.wait_for("rejected", 2)
    host.kill(); app.stop()
    return {"scenario": "adhoc-signed-impostor", "closed_reason": closed.get("reason") if closed else None, "host_exit_ms": ms(t, exited),
            "app_rejected": rejected, "host_stderr": host.stderr_text.strip()}


def scenario_no_app():
    host = Host(999999)
    t = time.monotonic()
    host.send({"op": "open"})
    closed = host.wait_frame("closed", 5, after=t); exited = host.wait_exit(5)
    host.kill()
    return {"scenario": "app-not-running", "closed_reason": closed.get("reason") if closed else None, "ae_error_code": closed.get("code") if closed else None,
            "closed_frame_ms": ms(t, closed["at"]) if closed else None, "host_exit_ms": ms(t, exited)}


if __name__ == "__main__":
    only = sys.argv[3:] or None
    for fn in [scenario_happy, scenario_close_op, scenario_cancel, scenario_app_crash, scenario_host_killed,
               scenario_chrome_killed, scenario_impostor, scenario_no_app]:
        if only and fn.__name__.replace("scenario_", "") not in only:
            continue
        try:
            print(json.dumps(fn()), flush=True)
        except Exception as error:  # a failed scenario is a result
            print(json.dumps({"scenario": fn.__name__, "harness_error": repr(error)}), flush=True)
