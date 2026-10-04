#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Per-instruction cycles of the core against the 603e model, with stall causes.

Inputs, from one tb_demo_soc run over the same window:
  retire log      stdout with +TRACE=<n> +TRACE_TO=<m>
  dispatch trace  +DISPATCH_TRACE=<path> (core dispatch/retire events)
  stall trace     +STALL_TRACE=<path> (DQ0 stall slot or DQ1 refusal per cycle)

The retired stream runs through perf_model_603e.schedule. Each instruction is
charged the cycles from the previous instruction's front-end event to its own:
dispatch on the core, dispatch (or BPU execute, for a folded branch) in the
model, both as running maxima so the charges add up to the window. The core's
cycles carry a cause: the stall slot of each cycle DQ0 waited, and, for the
instruction's own dispatch cycle, why it did not dispatch in DQ1 the cycle
before. The model's cycles are taken off the end of the core's (the dispatch
cycle first), so what remains is the excess and its causes.

Per static PC, basic block and function: count, core and model cycles, the
difference, the same for retirement spacing, and the excess by cause.
"""

import argparse
import csv
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import perf_model_603e as pm  # noqa: E402

EVENT_RE = re.compile(r"(\d+) D(\d) R(\d)([^|]*)\|([^!]*)(?:!(\d+))?")


def read_events(path):
    """Program-order dispatch cycles (squashed work removed) and retire cycles."""
    disp, ret = [], []
    with open(path) as fh:
        for line in fh:
            m = EVENT_RE.match(line)
            if not m:
                continue
            cyc = int(m.group(1))
            for pc in m.group(4).split():
                disp.append((cyc, int(pc, 16)))
            for pc in m.group(5).split():
                ret.append((cyc, int(pc, 16)))
            if m.group(6) and int(m.group(6)):
                del disp[-int(m.group(6)):]
    return disp, ret


def read_stalls(path):
    stall, alone = {}, {}
    with open(path) as fh:
        for line in fh:
            parts = line.split()
            if len(parts) < 2:
                continue
            cyc, what, rest = int(parts[0]), parts[1], " ".join(parts[2:])
            rest = rest.replace("PERF_", "").replace("SPECIAL_", "").replace("UNIT_", "")
            (stall if what == "stall" else alone)[cyc] = rest
    return stall, alone


def align(events, pcs, start_hint=0):
    """Index into events where the PC sequence pcs begins."""
    n = min(4096, len(pcs))     # short windows repeat inside byte loops
    epcs = [p for _, p in events]
    for j in range(start_hint, len(epcs) - n + 1):
        if epcs[j] == pcs[0] and epcs[j:j + n] == pcs[:n]:
            return j
    sys.exit("cannot align the event trace with the retire log")


def read_symbols(path):
    syms = []
    with open(path) as fh:
        for line in fh:
            m = re.match(r"([0-9a-f]{8}) <([^>]+)>:", line)
            if m:
                syms.append((int(m.group(1), 16), m.group(2)))
    return sorted(syms)


def func_of(syms, pc):
    name = "?"
    for a, n in syms:
        if a > pc:
            break
        name = n
    return name


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("retire_log")
    ap.add_argument("dispatch_trace")
    ap.add_argument("stall_trace")
    ap.add_argument("--mark", type=lambda v: int(v, 16), required=True,
                    help="PC (hex) that starts each iteration of the timed loop")
    ap.add_argument("--dump", required=True, help="objdump -d output (symbols, text)")
    ap.add_argument("--div", type=int, default=20)
    ap.add_argument("--mul", type=int, default=3)
    ap.add_argument("--fetch", choices=("aligned", "any"), default="aligned")
    ap.add_argument("--no-sru-add", dest="sru_add", action="store_false")
    ap.add_argument("--core", action="append", default=[], choices=sorted(pm.CORE_RULES),
                    help="apply a restriction of this core to the model (repeatable)")
    ap.add_argument("--top", type=int, default=40, help="rows of the per-PC table")
    ap.add_argument("--csv", help="write per-PC rows here")
    args = ap.parse_args()
    pm.ARGS = args
    pm.Insn.div_cycles = args.div

    recs = pm.read_trace(args.retire_log)
    stream = [(pc, w, recs[i + 1][1]) for i, (_, pc, w) in enumerate(recs[:-1])]
    sched = pm.schedule(stream, args.fetch == "any", frozenset(args.core))
    disp, ret = read_events(args.dispatch_trace)
    stall, alone = read_stalls(args.stall_trace)
    pcs = [pc for pc, _, _ in stream]
    with open(args.retire_log) as fh:
        first = next(int(m.group(1)) for m in map(pm.TRACE_RE.match, fh) if m)
    jr = align(ret, pcs, max(0, first - 64))
    jd = align(disp, pcs, max(0, first - 64))
    bad = sum(1 for k, pc in enumerate(pcs)
              if jd + k >= len(disp) or disp[jd + k][1] != pc or ret[jr + k][1] != pc)
    if bad:
        sys.exit(f"{bad} retired instructions do not match the event trace")
    marks = [i for i, pc in enumerate(pcs) if pc == args.mark]
    if len(marks) < 4:
        sys.exit("fewer than four iterations in the window")
    lo, hi = marks[1], marks[-1]
    iters = len(marks) - 2
    text = pm.read_dump(args.dump)
    syms = read_symbols(args.dump)

    def model_front(i):
        s = sched[i]
        return s["X"] if "X" in s else s["D"]

    # Running maxima of front-end and retirement times, core and model.
    rd = rm = cd = cm = None
    rows = defaultdict(lambda: {"n": 0, "core_d": 0, "model_d": 0, "core_r": 0,
                                "model_r": 0, "cause": Counter(), "excess": Counter()})
    leaders = set()
    total_excess, total_deficit = Counter(), 0
    for i in range(lo - 8, hi + 1):
        cdi = disp[jd + i][0]
        cri = ret[jr + i][0]
        mdi = model_front(i)
        mri = sched[i]["C"]
        if rd is None:
            rd, rm, cd, cm = cdi, mdi, cri, mri
            continue
        nd, nm = max(rd, cdi), max(rm, mdi)
        if i > lo:
            pc = pcs[i]
            prev = stream[i - 1]
            if prev[2] != prev[0] + 4 or pm.Insn(prev[0], prev[1], args.mul).unit == "BPU":
                leaders.add(pc)
            r = rows[pc]
            r["n"] += 1
            r["core_d"] += nd - rd
            r["model_d"] += nm - rm
            r["core_r"] += max(cd, cri) - cd
            r["model_r"] += max(cm, mri) - cm
            causes = []
            for c in range(rd + 1, nd + 1):
                if c == nd:
                    causes.append("own slot: " + ("DQ1 " + alone[rd] if rd in alone
                                                  else "not in DQ1"))
                elif c in stall:
                    causes.append(stall[c])
                else:
                    causes.append("wrong-path dispatch")
            r["cause"].update(causes)
            k = nm - rm
            excess = causes[:max(0, len(causes) - k)]
            r["excess"].update(excess)
            total_excess.update(excess)
            total_deficit += max(0, k - len(causes))
        rd, rm = nd, nm
        cd, cm = max(cd, cri), max(cm, mri)

    core_cyc = (ret[jr + hi][0] - ret[jr + lo][0]) / iters
    model_cyc = (sched[hi]["C"] - sched[lo]["C"]) / iters
    print(f"iterations {iters}, instructions per iteration {(hi - lo) / iters:.1f}")
    print(f"core {core_cyc:.1f} cycles, 603e model {model_cyc:.1f}, "
          f"difference {core_cyc - model_cyc:.1f}")
    ex = sum(total_excess.values()) / iters
    print(f"front end: core cycles beyond the model {ex:.1f}, "
          f"model cycles beyond the core {total_deficit / iters:.1f}")

    print("\nexcess core cycles by cause (per iteration):")
    for cause, n in total_excess.most_common():
        if n / iters >= 0.5:
            print(f"  {n / iters:6.1f}  {cause}")

    def table(title, keyf, top):
        agg = defaultdict(lambda: {"n": 0, "core_d": 0, "model_d": 0, "core_r": 0,
                                   "model_r": 0, "excess": Counter()})
        for pc, r in rows.items():
            a = agg[keyf(pc)]
            for f in ("n", "core_d", "model_d", "core_r", "model_r"):
                a[f] += r[f]
            a["excess"].update(r["excess"])
        print(f"\n{title} (per iteration; d = front end, r = retirement spacing)")
        print(f"{'':34} {'n':>5} {'core d':>7} {'603e d':>7} {'gap d':>6} {'gap r':>6}  top excess causes")
        for key, a in sorted(agg.items(), key=lambda kv: -(kv[1]["core_d"] - kv[1]["model_d"]))[:top]:
            causes = ", ".join(f"{c} {n / iters:.1f}" for c, n in a["excess"].most_common(3))
            print(f"{key:34.34} {a['n'] / iters:5.1f} {a['core_d'] / iters:7.1f} "
                  f"{a['model_d'] / iters:7.1f} {(a['core_d'] - a['model_d']) / iters:6.1f} "
                  f"{(a['core_r'] - a['model_r']) / iters:6.1f}  {causes}")

    # Dispatch to retirement by class, and taken-branch redirects: branch
    # dispatch (model: BPU execute) to the next instruction's dispatch.
    lat_c, lat_m = defaultdict(Counter), defaultdict(Counter)
    red_c, red_m = defaultdict(Counter), defaultdict(Counter)
    for i in range(lo, hi):
        s = sched[i]
        ins = s["ins"]
        if ins.unit != "BPU":
            k = ins.kind
            lat_c[k][ret[jr + i][0] - disp[jd + i][0]] += 1
            lat_m[k][s["C"] - s["D"]] += 1
        elif stream[i][2] != stream[i][0] + 4:
            k = ins.kind + (" mispredicted" if s.get("mispredict") else "")
            red_c[k][disp[jd + i + 1][0] - disp[jd + i][0]] += 1
            red_m[k][model_front(i + 1) - s["X"]] += 1

    def dist(c):
        n = sum(c.values())
        return f"min {min(c)} mean {sum(k * v for k, v in c.items()) / n:5.2f}"
    print("\ndispatch to retirement (core) and completion (model), cycles")
    for k in sorted(lat_c):
        print(f"  {k:8} n/iter {sum(lat_c[k].values()) / iters:6.1f}  core {dist(lat_c[k])}"
              f"  603e {dist(lat_m[k])}")
    print("\ntaken branch to next dispatch, cycles (excess = per iteration)")
    for k in sorted(red_c):
        n = sum(red_c[k].values())
        exc = (sum(a * b for a, b in red_c[k].items()) - sum(a * b for a, b in red_m[k].items()))
        print(f"  {k:18} n/iter {n / iters:5.1f}  core {dist(red_c[k])}  603e {dist(red_m[k])}"
              f"  excess {exc / iters:5.1f}")

    table("by function", lambda pc: func_of(syms, pc), 30)
    lead = sorted(leaders)

    def block_of(pc):
        f = func_of(syms, pc)
        b = max((a for a in lead if a <= pc and func_of(syms, a) == f), default=pc)
        return f"{b:08x} {f}"
    table("by basic block", block_of, 30)
    table("by PC", lambda pc: f"{pc:08x} {text.get(pc, '')}", args.top)
    if args.csv:
        with open(args.csv, "w", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["pc", "function", "insn", "count", "core_d", "model_d",
                        "core_r", "model_r", "excess_causes"])
            for pc, r in sorted(rows.items()):
                w.writerow([f"{pc:08x}", func_of(syms, pc), text.get(pc, ""),
                            *(f"{r[f] / iters:.2f}" for f in ("n", "core_d", "model_d",
                                                            "core_r", "model_r")),
                            ";".join(f"{c}={n / iters:.2f}" for c, n in r["excess"].most_common())])

if __name__ == "__main__":
    main()
