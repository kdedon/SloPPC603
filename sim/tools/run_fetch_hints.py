#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Run unchanged focused Make oracles serially with explicit hint profiles.

Optional acceptance only. The caller coordinates the repository simulator lock.
Each target has one compiler worker and its own process-group deadline/output ID.
"""
import argparse
import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import sys

SIM = Path(__file__).resolve().parents[1]
PROFILES = {
    "cached": ("test-core-bat-cached-bus60x", 0),
    "cacheops": ("test-core-bat-cached-bus60x-cacheops", 0),
    "coherence": ("test-core-bat-cached-bus60x-coherence", 1),
    "irq": ("test-core-bat-cached-bus60x-irq", 0),
    "drain": ("test-core-bat-cached-bus60x-drain", 1),
    "stress": ("test-core-bat-cached-bus60x-stress", 0),
    "timer": ("test-core-bat-cached-bus60x-timer", 0),
    "icache-real": ("test-chip-icache-real", 0),
    "pins": ("test-chip-pins", 1),
    "fpu": ("test-chip-fpu-lsu-pipe", 0),
}
GROUPS = {
    "focused": ("cached", "cacheops", "coherence", "irq", "drain", "icache-real", "pins", "fpu"),
    "cached-all": ("cached", "cacheops", "coherence", "irq", "drain", "stress", "timer"),
    "package": ("icache-real", "pins", "fpu"),
}


def run_bounded(command, environment, log, seconds):
    with log.open("w") as stream:
        child = subprocess.Popen(command, cwd=SIM, env=environment, stdout=stream,
                                 stderr=subprocess.STDOUT, start_new_session=True)
        try:
            return child.wait(timeout=seconds)
        except (subprocess.TimeoutExpired, KeyboardInterrupt) as failure:
            try:
                os.killpg(child.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                child.wait(timeout=10)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(child.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                child.wait()
            # Make may exit before a compiler child; always clear our group.
            try:
                os.killpg(child.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            return 130 if isinstance(failure, KeyboardInterrupt) else 124


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=sorted(set(PROFILES) | set(GROUPS)), default="focused")
    parser.add_argument("--hints", choices=("0", "1"), default="1")
    parser.add_argument("--build-dir", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=3600)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("timeout must be positive")
    directory = args.build_dir.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    compiler = "python3 " + shlex.quote(str(SIM / "tools/fetch_hints_compiler.py"))
    rows = []
    for profile in GROUPS.get(args.profile, (args.profile,)):
        target, fd = PROFILES[profile]
        output = directory / (profile + "-h" + args.hints + "-fd" + str(fd))
        output.mkdir(parents=True, exist_ok=True)
        command = ["make", "-j1", target, "VERILATOR=" + compiler,
                   "DISPATCH_WIDTH=2", "FETCH_DECODE_REG=" + str(fd),
                   "BUILD_DIR=" + os.path.relpath(output, SIM),
                   "SIM_ARGS=+verilator+seed+1 +verilator+rand+reset+2"]
        env = dict(os.environ, OBJCACHE="", PPC_FETCH_HINTS_VALUE=args.hints,
                   PPC_FETCH_HINTS_ARGV_LOG=str(output / "compiler-argv.jsonl"))
        row = {"profile": profile, "hints": int(args.hints), "fd": fd,
               "dispatch_width": 2, "lsu_pipeline": 1, "seed": 1,
               "target": target, "argv": command, "timeout_seconds": args.timeout}
        (output / "invocation.json").write_text(json.dumps(row, indent=2) + "\n")
        print("fetch-hints start: " + profile + " hints=" + args.hints + " fd=" + str(fd), flush=True)
        row["exit"] = run_bounded(command, env, output / "run.log", args.timeout)
        rows.append(row)
        (directory / ("summary-h" + args.hints + "-" + args.profile + ".json")).write_text(json.dumps(rows, indent=2) + "\n")
        print("fetch-hints finish: " + profile + " exit=" + str(row["exit"]), flush=True)
        if row["exit"] != 0:
            raise SystemExit(row["exit"] if row["exit"] > 0 else 1)
    print("PASS hint acceptance hints=" + args.hints + ": " + str(len(rows)) + " unchanged Make targets", flush=True)


if __name__ == "__main__":
    main()
