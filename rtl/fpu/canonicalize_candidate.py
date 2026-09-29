#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Normalize translated VHDL and annotate known unused vector slices."""

import re
import sys
from pathlib import Path


COMMON = {
    "tem": "4:3,1:0", "c1": "19:10,5,0", "c2_asc_fhi_man": "2:0",
    "c2_fs2_exp": "10:8,0", "c2_fs2_man": "28:0", "n273_o": "18:9,4",
    "n5740_o": "6", "n5928_o": "18:15,13:3,1:0", "n6069_o": "12",
    "n6460_o": "0", "n6503_o": "0", "n6557_o": "22",
    "n6563_o": "12:11", "n752_o": "4:3,1:0", "n754_o": "4:3,1:0",
    "n7595_o": "2:0", "n955_o": "19:8,5,0",
    "mul_fs1_man": "53,0", "mul_fs2_man": "52",
}
VARIANT = {
    0: {"n7970_o": "31:6", "n8072_o": "57:56,1:0", "n7956_q": "33:0"},
    1: {"n7745_o": "31:6", "n7847_o": "57:56,1:0",
        "mul_sd": "all", "mul_flush": "all"},
}


def main() -> None:
    tech = int(sys.argv[1])
    path = Path(sys.argv[2])
    expected = COMMON | VARIANT[tech]
    seen = set()
    module_count = 0
    lines = []
    for line in path.read_text().splitlines(keepends=True):
        # Logical zero and reduction NOR are identical for one or many bits.
        line = re.sub(r"^(\s*assign\s+\S+\s*=\s*)!\s+(.+);$",
                      r"\1~| \2;", line)
        declaration = re.match(r"\s*(?:input|wire|reg)\s+(?:\[[^]]+\]\s+)?(\w+)\s*;", line)
        if declaration and declaration.group(1) in expected and declaration.group(1) not in seen:
            name = declaration.group(1)
            seen.add(name)
            lines.append(f"  // Translation preserves the vector layout; unused bits: {expected[name]}.\n")
            lines.append("  /* verilator lint_off UNUSEDSIGNAL */\n")
            lines.append(line)
            lines.append("  /* verilator lint_on UNUSEDSIGNAL */\n")
        elif re.match(r"module fpu_(?:div|mul)_", line):
            module_count += 1
            lines.append("/* verilator lint_off DECLFILENAME */\n")
            lines.append(line)
            lines.append("/* verilator lint_on DECLFILENAME */\n")
        else:
            lines.append(line)
    if seen != expected.keys() or module_count != 2:
        raise RuntimeError(f"generated declarations changed: missing={expected.keys()-seen}, extra={seen-expected.keys()}, child_modules={module_count}")
    path.write_text("".join(lines))


if __name__ == "__main__":
    main()
