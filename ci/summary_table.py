#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Print build summaries (quartus/fit_summary.py JSON) as a markdown table."""
import argparse
import json
import sys
from pathlib import Path


def worst(summary, analysis):
    values = [slack for clock in summary["slack"].values() for slack in clock.get(analysis, {}).values()]
    return min(values) if values else None


def cell(value, fmt="{}"):
    return "–" if value is None else fmt.format(value)


def verdict(value):
    return {True: "pass", False: "**FAIL**", None: "–"}[value]


def target(summary):
    entry = summary.get("target")
    if not entry:
        return "–"
    slack = min(entry["worst_setup_slack"].values()) if entry["worst_setup_slack"] else None
    text = f"{entry['mhz']:g} MHz: "
    if slack is not None:
        text += f"{slack:+.3f} ns"
    else:
        text += "met" if entry["met"] else "failed"
    if entry["failing_endpoints"]:
        text += f" ({entry['failing_endpoints']} endpoints)"
    return text


def table(summaries):
    rows = [
        "| Build | Commit | ALMs | Registers | M10K | MLAB bits | DSP | Worst setup | Worst hold | Timing met | 50 MHz | Re-timed | Bitstream |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- | --- |",
    ]
    for s in summaries:
        r = s["resources"]
        commit = s["commit"][:10] + ("+dirty" if s["dirty"] else "")
        rbf = f"`{s['rbf']['name']}` `{s['rbf']['sha256'][:16]}`" if s.get("rbf") else "–"
        rows.append(" | ".join([
            f"| {s['name']}", f"`{commit}`", cell(r["alms"], "{:,}"), cell(r["registers"], "{:,}"),
            cell(r["m10k"]), cell(r["mlab_bits"], "{:,}"), cell(r["dsp"]),
            cell(worst(s, "setup"), "{:+.3f}"), cell(worst(s, "hold"), "{:+.3f}"),
            verdict(s["timing_met"]), verdict(s["pass_50mhz"]), target(s), rbf + " |",
        ]))
    return "\n".join(rows)


def detail(summaries):
    corners = []
    for s in summaries:
        for analyses in s["slack"].values():
            for by_corner in analyses.values():
                corners += [c for c in by_corner if c not in corners]
    rows = ["| Build | Clock | Analysis | " + " | ".join(c.replace("_", " ") for c in corners) + " |",
            "| --- | --- | --- |" + " ---: |" * len(corners)]
    for s in summaries:
        for clock, analyses in s["slack"].items():
            for analysis, by_corner in analyses.items():
                name = clock.replace("|", "\\|")
                rows.append(f"| {s['name']} | `{name}` | {analysis} | "
                            + " | ".join(cell(by_corner.get(c), "{:+.3f}") for c in corners) + " |")
    return "\n".join(rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("summaries", nargs="+", type=Path)
    parser.add_argument("--detail", action="store_true", help="add worst slack per clock, analysis and corner")
    args = parser.parse_args()
    summaries = [json.loads(path.read_text()) for path in args.summaries]
    print(table(summaries))
    if args.detail:
        print()
        print(detail(summaries))
    return 0


if __name__ == "__main__":
    sys.exit(main())
