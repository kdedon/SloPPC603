#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Optional same-source hints0/1 benchmark using the existing integer/FPU pair.

No firmware compilation, new retirement normalization or scratch baseline.
The caller coordinates the simulator lock; four models execute serially.
"""
import argparse
import json
import os
from pathlib import Path
import re
import integer_branch_pair as pair
from run_fetch_hints import run_bounded

ROOT = Path(__file__).resolve().parents[2]
SIM = ROOT / "sim"


def sources():
    result = pair.sources(ROOT)
    for base in (ROOT / "rtl", ROOT / "tb", SIM / "tools"):
        for path in base.rglob("*"):
            if path.is_file() and path.suffix in (".sv", ".svh", ".f", ".py", ".mk", ".sh") and "__pycache__" not in path.parts:
                result[str(path.relative_to(ROOT))] = pair.digest(path)
    result["sim/tools/verilate"] = pair.digest(SIM / "tools/verilate")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--dump", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--quiet-observe", choices=("0", "1"), default="0")
    parser.add_argument("--timeout", type=int, default=7200)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("timeout must be positive")
    image, dump = args.image.resolve(), args.dump.resolve()
    pair.require(pair.digest(image) == pair.IMAGE_SHA, "image must be the existing pinned benchmark")
    pair.require(pair.digest(dump) == pair.DUMP_SHA, "dump must be the existing pinned benchmark")
    before = sources()
    output = args.output.resolve() / ("quiet" + args.quiet_observe)
    output.mkdir(parents=True, exist_ok=True)
    rows, inputs, digests, quiet, checks = {}, {}, {}, {}, {}
    for hints in (0, 1):
        mode = output / ("hints" + str(hints))
        mode.mkdir(parents=True, exist_ok=True)
        simargs = "+verilator+seed+1 +verilator+rand+reset+2"
        if args.quiet_observe == "1":
            simargs += " +INTEGER_QUIET_OBSERVE"
        command = ["make", "-j1", "benchmark-integer-fpu-pair",
                   "VERILATOR=" + str(SIM / "tools/verilate"),
                   "INTEGER_PAIR_HINTS=" + str(hints),
                   "INTEGER_PAIR_DIR=" + os.path.relpath(mode, SIM),
                   "INTEGER_PAIR_IMAGE=" + str(image), "INTEGER_PAIR_DUMP=" + str(dump),
                   "SIM_ARGS=" + simargs]
        (mode / "invocation.json").write_text(json.dumps({"argv": command, "sources": before}, indent=2) + "\n")
        print("benchmark-fetch-hints start hints=" + str(hints), flush=True)
        status = run_bounded(command, dict(os.environ, OBJCACHE=""), mode / "run.log", args.timeout)
        pair.require(status == 0, "existing integer/FPU pair failed hints=" + str(hints) + " status=" + str(status))
        pair.require(sources() == before, "source changed during hint pair")
        inputs[hints] = json.loads((mode / "input.json").read_text())
        rows[hints] = json.loads((mode / "comparison.json").read_text())
        digests[hints], quiet[hints], checks[hints] = {}, {}, {}
        for fpu in (0, 1):
            name = "fpu" + str(fpu)
            digests[hints][name] = json.loads((mode / (name + ".digest.json")).read_text())
            text = (mode / (name + ".log")).read_text()
            quiet[hints][name] = re.findall(r"^INTEGER_QUIET .*", text, re.M)
            pair.require(len(quiet[hints][name]) == (2 if args.quiet_observe == "1" else 0), "quiet observation missing/duplicated")
            counts = re.findall(r"checks:\s*(\d+), mismatches\s+0", text)
            pair.require(counts == ["23"], "fixed benchmark must retain its 23 original firmware checks")
            checks[hints][name] = counts
            # Compare every original report field, excluding only the requested mode.
            pair.require(rows[hints][name]["hints"] == hints, "effective hint mode mismatch")
            del rows[hints][name]["hints"]
        print("benchmark-fetch-hints existing pair PASS hints=" + str(hints), flush=True)
    pair.require(inputs[0] == inputs[1], "input image/dump/landmarks/source fingerprints differ")
    pair.require(pair.digest(output / "hints0/frozen.hex") == pair.digest(output / "hints1/frozen.hex") == pair.IMAGE_SHA, "frozen image drift")
    pair.require(rows[0] == rows[1], "hint mode changed existing metrics, counters, ratios or cycles")
    pair.require(digests[0] == digests[1], "full canonical retirement digests differ")
    pair.require(quiet[0] == quiet[1], "quiet observer lines/counters changed")
    pair.require(checks[0] == checks[1], "firmware check population differs")
    pair.require(sources() == before, "final source drift")
    result = {"scope": "same-source hint-mode identity; existing FPU0/1 pair checks retained",
              "quiet_observe": int(args.quiet_observe), "inputs_equal": True,
              "full_source_fingerprints_equal": True, "firmware_checks": checks[0],
              "digests": digests[0], "metrics_except_hints": rows[0], "quiet_lines": quiet[0],
              "sources": before}
    (output / "hint-comparison.json").write_text(json.dumps(result, indent=2) + "\n")
    print("PASS benchmark-fetch-hints: hints0/1 full digests/metrics/cycles/quiet lines identical", flush=True)


if __name__ == "__main__":
    main()
