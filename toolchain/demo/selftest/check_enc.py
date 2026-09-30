#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Checks gen.py's instruction words against the assembler.

check_enc.py <check.bin> <cases.S>

check.bin is check.S assembled: one word per case instruction, in order.
Each ".long" word in cases.S must equal the assembler's word; the other
instruction lines (relocated branches) have a nop in check.S.
"""
import pathlib
import re
import sys


def main():
    data = pathlib.Path(sys.argv[1]).read_bytes()
    words = [int.from_bytes(data[i:i + 4], "big") for i in range(0, len(data), 4)]
    ours = []
    for line in pathlib.Path(sys.argv[2]).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith(("/*", ".", "b st_done")) and not line.startswith(".long"):
            continue
        if line.endswith(":"):
            continue
        m = re.match(r"\.long 0x([0-9a-f]{8})\s+/\* (.*) \*/", line)
        ours.append((int(m.group(1), 16), m.group(2)) if m else (None, line))
    if len(ours) != len(words):
        sys.exit(f"check_enc: {len(ours)} case instructions, {len(words)} assembled words")
    bad = [(w, a, t) for (w, t), a in zip(ours, words) if w is not None and w != a]
    for w, a, t in bad[:20]:
        print(f"check_enc: {t}: gen.py {w:08x}, assembler {a:08x}")
    if bad:
        sys.exit(f"check_enc: {len(bad)} encodings differ")
    print(f"check_enc: {sum(1 for w, _ in ours if w is not None)} encodings match")


if __name__ == "__main__":
    main()
