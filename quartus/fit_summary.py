#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Write one JSON summary of a Quartus build: resources and slack per clock and corner.

Reads <revision>.fit.summary or .fit.rpt, <revision>.sta.summary or .sta.rpt,
and, with --target-period, the re-timing written by report-target-paths.sh. The FPU
harness reports (setup.txt, hold.txt, clocks.txt) stand in for STA files.
"""
import argparse
import datetime
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

SCHEMA = 1
ANALYSES = ("setup", "hold", "recovery", "removal")


def read(path):
    return path.read_text(encoding="latin-1") if path and path.is_file() else ""


def number(text):
    match = re.match(r"\s*(-?[0-9][0-9,]*(?:\.[0-9]+)?)", text or "")
    if not match:
        return None
    value = float(match.group(1).replace(",", ""))
    return int(value) if value.is_integer() and "." not in match.group(1) else value


def corner(text):
    """'Slow 1100mV 100C Model' or '7_slow_1100mv_100c' -> 'slow_100c'."""
    match = re.search(r"(slow|fast|min_fast)\D*1100\s*mv[ _](-?\d+)c", text, re.IGNORECASE)
    if not match:
        return text.strip().lower().replace(" ", "_")
    speed = "fast" if "fast" in match.group(1).lower() else "slow"
    return f"{speed}_{match.group(2)}c"


def fitter(directory, revision):
    """Key/value pairs of the fitter summary, from .fit.summary or the .fit.rpt table."""
    values = {}
    summary = read(directory / f"{revision}.fit.summary")
    report = read(directory / f"{revision}.fit.rpt")
    if summary:
        for line in summary.splitlines():
            key, _, value = line.partition(" : ")
            values[key.strip()] = value.strip()
    elif report:
        section = report.split("; Fitter Summary", 1)[-1].split("\n\n", 1)[0]
        for line in section.splitlines():
            cells = [cell.strip() for cell in line.strip().strip(";").split(";")]
            if len(cells) == 2:
                values[cells[0]] = cells[1]
    # Resource usage summary rows ("; M10K blocks ; 36 / 553 ; 7 % ;").
    for line in report.splitlines():
        cells = [cell.strip() for cell in line.strip().strip(";").split(";")]
        if len(cells) >= 2 and cells[0] in ("M10K blocks", "Total MLAB memory bits",
                                            "-- Memory LABs (up to half of total LABs)"):
            values.setdefault(cells[0], cells[1])
    return values


def resources(values):
    return {
        "alms": number(values.get("Logic utilization (in ALMs)")),
        "registers": number(values.get("Total registers")),
        "m10k": number(values.get("M10K blocks") or values.get("Total RAM Blocks")),
        "mlab_labs": number(values.get("-- Memory LABs (up to half of total LABs)")),
        "mlab_bits": number(values.get("Total MLAB memory bits")),
        "block_memory_bits": number(values.get("Total block memory bits")),
        "dsp": number(values.get("Total DSP Blocks")),
        "pins": number(values.get("Total pins")),
    }


def sta_slack(directory, revision):
    """{clock: {analysis: {corner: slack}}} and {clock: period_ns}."""
    slack, periods = {}, {}
    summary = read(directory / f"{revision}.sta.summary")
    report = read(directory / f"{revision}.sta.rpt")
    if summary:
        kind = None
        for line in summary.splitlines():
            if line.startswith("Type"):
                match = re.match(r"Type\s*:\s*(.*) Model (.+?) '(.*)'", line)
                kind = match.groups() if match else None
            elif line.startswith("Slack") and kind and kind[1].lower() in ANALYSES:
                where, analysis, clock = kind
                slack.setdefault(clock, {}).setdefault(analysis.lower(), {})[corner(where)] = number(line.split(":", 1)[1])
    else:
        for match in re.finditer(r"^; (.*) Model (\w+) Summary\s*;\n(?:[+;].*\n)*?", report, re.MULTILINE):
            where, analysis = match.groups()
            if analysis.lower() not in ANALYSES:
                continue
            for line in report[match.end():].splitlines():
                if not line.startswith(("+", ";")):
                    break
                cells = [cell.strip() for cell in line.strip().strip(";").split(";")]
                if len(cells) >= 2 and cells[0] != "Clock" and number(cells[1]) is not None:
                    slack.setdefault(cells[0], {}).setdefault(analysis.lower(), {})[corner(where)] = number(cells[1])
    # Clocks table: "; core_clk ; Base ; 20.000 ; 50.0 MHz ; ...".
    for line in report.splitlines():
        cells = [cell.strip() for cell in line.strip().strip(";").split(";")]
        if len(cells) > 3 and cells[1] in ("Base", "Generated") and number(cells[2]) is not None:
            periods[cells[0]] = number(cells[2])
    return slack, periods


def harness_slack(directory):
    """FPU harness: one post-map or post-fit timing corner written by timing.tcl."""
    slack, periods = {}, {}
    for line in read(directory / "clocks.txt").splitlines():
        cells = [cell.strip() for cell in line.strip().strip(";").split(";")]
        if len(cells) > 3 and cells[1] in ("Base", "Generated") and number(cells[2]) is not None:
            periods[cells[0]] = number(cells[2])
    clock = next(iter(periods), "clock")
    for analysis in ("setup", "hold"):
        match = re.search(r"Worst case slack is\s+(-?[0-9.]+)", read(directory / f"{analysis}.txt"))
        if match:
            slack.setdefault(clock, {})[analysis] = {"default": float(match.group(1))}
    return slack, periods


def target(directory, revision, period):
    """Re-timing at another period by report-target-paths.sh: worst setup slack per corner."""
    tsv = directory / f"{revision}.target-paths.tsv"
    if not tsv.is_file():
        return None
    worst, failing = {}, 0
    for line in read(directory / f"{revision}.target-paths.tsv.worst.txt").splitlines():
        cells = line.split("\t")
        if len(cells) == 3 and number(cells[2]) is not None:
            key = corner(cells[0])
            worst[key] = min(worst.get(key, number(cells[2])), number(cells[2]))
    for line in read(tsv).splitlines():
        cells = line.split("\t")
        if len(cells) >= 2 and number(cells[1]) is not None:
            failing += 1
            key = corner(cells[0])
            worst[key] = min(worst.get(key, 0.0), number(cells[1]))
    return {
        "period_ns": period,
        "mhz": round(1000.0 / period, 1),
        # Without the worst-slack file, a corner with no failing endpoint is absent.
        "worst_setup_slack": worst,
        "failing_endpoints": failing,
        "met": failing == 0,
    }


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, check=False).stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--name", required=True, help="build label, e.g. chip or mister")
    parser.add_argument("--dir", required=True, type=Path, help="directory holding the reports")
    parser.add_argument("--revision", required=True)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--image", default="", help="Quartus container image")
    parser.add_argument("--rbf", type=Path, help="bitstream to name and hash")
    parser.add_argument("--note", default="", help="free text, e.g. firmware suite")
    parser.add_argument("--core-mhz", type=int, help="processor clock the build is made for")
    parser.add_argument("--target-period", type=float,
                        help="add the re-timing at this period; updates only that entry of an existing summary")
    args = parser.parse_args()

    if args.target_period and args.out.is_file():
        data = json.loads(args.out.read_text())
        data["target"] = target(args.dir, args.revision, args.target_period)
        args.out.write_text(json.dumps(data, indent=2) + "\n")
        return 0

    repo = Path(__file__).resolve().parent.parent
    values = fitter(args.dir, args.revision)
    if (args.dir / "setup.txt").is_file():
        slack, periods = harness_slack(args.dir)
    else:
        slack, periods = sta_slack(args.dir, args.revision)
    if not values or not slack:
        print(f"fit_summary: no fitter or timing report for {args.revision} in {args.dir}", file=sys.stderr)
        return 1
    worst = [value for clock in slack.values() for analysis in clock.values() for value in analysis.values()]
    met = all(value >= 0 for value in worst)
    data = {
        "schema": SCHEMA,
        "name": args.name,
        "commit": git(repo, "rev-parse", "HEAD"),
        "dirty": bool(git(repo, "status", "--porcelain", "--untracked-files=no")),
        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "revision": args.revision,
        "top": values.get("Top-level Entity Name"),
        "device": values.get("Device"),
        "quartus": values.get("Quartus Prime Version"),
        "image": args.image or None,
        "note": args.note or None,
        "resources": resources(values),
        "core_mhz": args.core_mhz,
        "clocks_ns": periods,
        "slack": slack,
        "timing_met": met,
        # The 50 MHz gate: every clock is constrained at 20 ns and meets it.
        "pass_50mhz": met if periods and all(abs(period - 20.0) < 1e-6 for period in periods.values()) else None,
        "target": target(args.dir, args.revision, args.target_period) if args.target_period else None,
        "rbf": None,
    }
    if args.rbf:
        data["rbf"] = {"name": args.rbf.name, "sha256": hashlib.sha256(args.rbf.read_bytes()).hexdigest()}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(data, indent=2) + "\n")
    print(f"summary: {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
