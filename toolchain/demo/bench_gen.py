#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Generates build headers from fetched benchmark files.

bench_gen.py cstring <name> <input> <output>
    A C string constant holding the input file.
bench_gen.py embench <embench-dir> <output> <benchmark>...
    Embench's reference times (baseline-data/speed.json) and each
    benchmark's LOCAL_SCALE_FACTOR, as an X-macro list.
bench_gen.py whetstone <whetstone.c> <loop> <output> [<name>]
    Whetstone's opening comment block (its licence notice) as a C string, and
    the values the program prints per module at the given LOOP, from a model
    of the program in host double precision. With a name, only the values,
    as <name>_expected with the LOOP in <NAME>_LOOP.
"""
import math
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


def whetstone_model(loop):
    """(N, J, K, X1, X2, X3, X4) per printed module, as the program's POUT."""
    t, t1, t2 = 0.499975, 0.50025, 2.0
    n1, n2, n3, n4, n6, n7, n8, n9, n10, n11 = (
        0, 12 * loop, 14 * loop, 345 * loop, 210 * loop, 32 * loop, 899 * loop,
        616 * loop, 0, 93 * loop)
    out = []
    x1, x2, x3, x4 = 1.0, -1.0, -1.0, -1.0
    for _ in range(n1):
        x1 = (x1 + x2 + x3 - x4) * t
        x2 = (x1 + x2 - x3 + x4) * t
        x3 = (x1 - x2 + x3 + x4) * t
        x4 = (-x1 + x2 + x3 + x4) * t
    out.append((n1, n1, n1, x1, x2, x3, x4))
    e = [0.0, 1.0, -1.0, -1.0, -1.0]
    for _ in range(n2):
        e[1] = (e[1] + e[2] + e[3] - e[4]) * t
        e[2] = (e[1] + e[2] - e[3] + e[4]) * t
        e[3] = (e[1] - e[2] + e[3] + e[4]) * t
        e[4] = (-e[1] + e[2] + e[3] + e[4]) * t
    out.append((n2, n3, n2, *e[1:]))
    for _ in range(n3):
        for _ in range(6):
            e[1] = (e[1] + e[2] + e[3] - e[4]) * t
            e[2] = (e[1] + e[2] - e[3] + e[4]) * t
            e[3] = (e[1] - e[2] + e[3] + e[4]) * t
            e[4] = (-e[1] + e[2] + e[3] + e[4]) / t2
    out.append((n3, n2, n2, *e[1:]))
    j = 1
    for _ in range(n4):
        j = 2 if j == 1 else 3
        j = 0 if j > 2 else 1
        j = 1 if j < 1 else 0
    out.append((n4, j, j, x1, x2, x3, x4))
    j, k, l = 1, 2, 3
    for _ in range(n6):
        j = j * (k - j) * (l - k)
        k = l * k - (l - j) * k
        l = (l - k) * (k + j)
        e[l - 1] = float(j + k + l)
        e[k - 1] = float(j * k * l)
    out.append((n6, j, k, *e[1:]))
    x = y = 0.5
    for _ in range(n7):
        x = t * math.atan(t2 * math.sin(x) * math.cos(x) /
                          (math.cos(x + y) + math.cos(x - y) - 1.0))
        y = t * math.atan(t2 * math.sin(y) * math.cos(y) /
                          (math.cos(x + y) + math.cos(x - y) - 1.0))
    out.append((n7, j, k, x, x, y, y))
    x = y = z = 1.0
    for _ in range(n8):
        a = t * (x + y)
        b = t * (a + y)
        z = (a + b) / t2
    out.append((n8, j, k, x, y, z, z))
    j, k, l = 1, 2, 3
    e[1:4] = [1.0, 2.0, 3.0]
    for _ in range(n9):
        e[j] = e[k]
        e[k] = e[l]
        e[l] = e[j]
    out.append((n9, j, k, *e[1:]))
    j, k = 2, 3
    out.append((n10, j, k, x1, x2, x3, x4))
    x = 0.75
    for _ in range(n11):
        x = math.sqrt(math.exp(math.log(x) / t1))
    out.append((n11, j, k, x, x, x, x))
    return out


def whetstone(src, loop, out, name=None):
    rows = "".join(
        f"  {{{n}, {j}, {k}, {{{', '.join(float.hex(v) for v in xs)}}}}},\n"
        for n, j, k, *xs in whetstone_model(int(loop)))
    if name:
        pathlib.Path(out).write_text(
            f"#define {name.upper()}_LOOP {int(loop)}\n"
            f"static const struct whet_pout {name}_expected[] = {{\n{rows}}};\n")
        return
    text = pathlib.Path(src).read_text(encoding="ascii")
    notice = text[:text.index("*/") + 2]
    body = "".join(
        '  "' + line.replace("\\", "\\\\").replace('"', '\\"') + '\\n"\n'
        for line in notice.splitlines())
    pathlib.Path(out).write_text(
        f"#define WHET_LOOP {int(loop)}\n"
        f"static const char whet_notice[] =\n{body};\n"
        "/* N, J, K, X1-X4 printed per module */\n"
        f"static const struct whet_pout whet_expected[] = {{\n{rows}}};\n")


if __name__ == "__main__":
    if sys.argv[1] == "cstring":
        cstring(*sys.argv[2:5])
    elif sys.argv[1] == "embench":
        embench(sys.argv[2], sys.argv[3], sys.argv[4:])
    elif sys.argv[1] == "whetstone":
        whetstone(*sys.argv[2:6])
    else:
        sys.exit(__doc__)
