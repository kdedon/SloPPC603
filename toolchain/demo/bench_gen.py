#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Generates build headers from fetched benchmark files.

bench_gen.py cstring <name> <input> <output>
    A C string constant holding the input file.
bench_gen.py embench <embench-dir> <output> <benchmark>...
    Embench's reference times (baseline-data/speed.json) and each
    benchmark's LOCAL_SCALE_FACTOR, as an X-macro list.
"""
import pathlib
import re
import sys


def cstring(name, src, out):
    data = pathlib.Path(src).read_bytes().decode("ascii")
    body = "".join(
        '  "' + line.replace("\\", "\\\\").replace('"', '\\"') + '\\n"\n'
        for line in data.splitlines())
    pathlib.Path(out).write_text(f"static const char {name}[] =\n{body};\n")


def embench(root, out, names):
    root = pathlib.Path(root)
    # speed.json is a flat object of names and numbers.
    speed = {k: int(v) for k, v in re.findall(
        r'"([^"]+)"\s*:\s*(\d+)', (root / "baseline-data" / "speed.json").read_text())}
    rows = []
    for name in names:
        scale = None
        for src in sorted((root / "src" / name).glob("*.c")):
            m = re.search(r"^#define\s+LOCAL_SCALE_FACTOR\s+(\d+)", src.read_text(), re.M)
            if m:
                scale = int(m.group(1))
        if scale is None:
            sys.exit(f"bench_gen: no LOCAL_SCALE_FACTOR for {name}")
        ident = name.replace("-", "_")
        rows.append(f'  X({ident}, "{name}", {speed[name]}, {scale})')
    pathlib.Path(out).write_text(
        "/* id, name, reference time in ms, LOCAL_SCALE_FACTOR */\n"
        "#define EMBENCH_LIST(X) \\\n" + " \\\n".join(rows) + "\n")


if __name__ == "__main__":
    if sys.argv[1] == "cstring":
        cstring(*sys.argv[2:5])
    elif sys.argv[1] == "embench":
        embench(sys.argv[2], sys.argv[3], sys.argv[4:])
    else:
        sys.exit(__doc__)
