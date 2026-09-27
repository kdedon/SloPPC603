#!/usr/bin/env python3
"""Group failing setup endpoints from target_paths.tcl by destination register."""
import re
import sys
from collections import Counter, defaultdict


def register(node: str) -> str:
    # Drop the measurement wrapper, entity names, bit and array indexes and
    # struct fields so one bus or record is one group.
    name = re.sub(r"~\S*$", "", node)
    name = re.sub(r"\[\d+\]", "", name)
    parts = [re.sub(r"^\w+:", "", part) for part in name.split("|")]
    parts = [part for part in parts if part not in ("dut", "auto_generated")]
    parts[-1] = parts[-1].split(".")[0]
    return "|".join(parts)


def main() -> int:
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 30
    groups = defaultdict(lambda: [0.0, 0, Counter()])
    worst = 0.0
    count = 0
    with open(sys.argv[1], encoding="utf-8") as tsv:
        for line in tsv:
            _, slack_text, src, dst = line.rstrip("\n").split("\t")
            slack = float(slack_text)
            group = groups[register(dst)]
            group[0] = min(group[0], slack)
            group[1] += 1
            group[2][register(src)] += 1
            worst = min(worst, slack)
            count += 1
    print(f"failing endpoints (all corners): {count}, worst slack {worst:.3f} ns")
    ranked = sorted(groups.items(), key=lambda item: item[1][0])
    for dst, (slack, n, sources) in ranked[:limit]:
        src = ", ".join(f"{s} ({k})" for s, k in sources.most_common(2))
        print(f"{slack:8.3f} {n:5d}  {dst}  <-  {src}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
