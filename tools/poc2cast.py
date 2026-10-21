#!/usr/bin/env python3
"""
poc2cast.py — record a command's live stdout/stderr into an asciicast v2
file (.cast), for conversion to a demo gif with `agg` (asciinema/agg).

This is a faithful recorder, not a mock: the .cast events carry the real
wall-clock times of the lines the PoC actually printed.

Usage:
  python tools/poc2cast.py --out evidence/poc109619.cast \
      -- python poc/cve-2026-109619.py --url http://127.0.0.1:8088
Then:
  wsl agg evidence/poc109619.cast -o assets/poc109619.gif
"""
import argparse
import json
import subprocess
import sys
import time


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--width", type=int, default=110)
    ap.add_argument("--height", type=int, default=26)
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    args = ap.parse_args()

    cmd = args.cmd[1:] if args.cmd[:1] == ["--"] else args.cmd
    if not cmd:
        print("no command given (use -- <cmd>)")
        return 2

    t0 = time.time()
    events = []

    def emit(line):
        events.append([round(time.time() - t0, 3), "o", line + "\r\n"])

    emit(f"$ {' '.join(cmd)}")
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, bufsize=1)
    for line in proc.stdout:
        emit(line.rstrip("\r\n"))
    rc = proc.wait()
    emit(f"[process exited with code {rc}]")

    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps({"version": 2, "width": args.width, "height": args.height,
                            "timestamp": int(t0),
                            "env": {"SHELL": "/bin/bash", "TERM": "xterm-256color"}}) + "\n")
        for ev in events:
            f.write(json.dumps(ev) + "\n")
    print(f"cast written: {args.out} ({len(events)} events, rc={rc})")
    return 0 if rc == 0 else rc


if __name__ == "__main__":
    sys.exit(main())
