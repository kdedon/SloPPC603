#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Require each named instruction form in an ELF's executable sections."""

from __future__ import annotations

import struct
import sys
from pathlib import Path

# name: (mask, value) over the 32-bit big-endian instruction word.
FORMS = {
    'lmw': (0xFC000000, 46 << 26),
    'stmw': (0xFC000000, 47 << 26),
    'lwarx': (0xFC0007FF, (31 << 26) | (20 << 1)),
    'stwcx.': (0xFC0007FF, (31 << 26) | (150 << 1) | 1),
    'lswi': (0xFC0007FF, (31 << 26) | (597 << 1)),
    'stswi': (0xFC0007FF, (31 << 26) | (725 << 1)),
    'lswx': (0xFC0007FF, (31 << 26) | (533 << 1)),
    'stswx': (0xFC0007FF, (31 << 26) | (661 << 1)),
    'lwbrx': (0xFC0007FF, (31 << 26) | (534 << 1)),
    'stwbrx': (0xFC0007FF, (31 << 26) | (662 << 1)),
    'lhbrx': (0xFC0007FF, (31 << 26) | (790 << 1)),
    'sthbrx': (0xFC0007FF, (31 << 26) | (918 << 1)),
}


def text_words(path: Path) -> list[int]:
    data = path.read_bytes()
    if data[:4] != b'\x7fELF' or data[4] != 1 or data[5] != 2:
        raise ValueError(f'{path}: not a big-endian ELF32')
    shoff, = struct.unpack_from('>I', data, 32)
    shentsize, shnum = struct.unpack_from('>HH', data, 46)
    words = []
    for i in range(shnum):
        _, kind, flags, _, offset, size = struct.unpack_from('>IIIIII', data, shoff + i * shentsize)
        if kind == 1 and flags & 0x4:  # PROGBITS, EXECINSTR
            words += [w for (w,) in struct.iter_unpack('>I', data[offset:offset + size - size % 4])]
    return words


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print('usage: check_opcodes.py ELF FORM...', file=sys.stderr)
        return 2
    words = text_words(Path(argv[1]))
    counts = {}
    for name in argv[2:]:
        mask, value = FORMS[name]
        counts[name] = sum((w & mask) == value for w in words)
    missing = [name for name, count in counts.items() if count == 0]
    if missing:
        print(f'FAIL: {argv[1]} lacks {" ".join(missing)}', file=sys.stderr)
        return 1
    print('PASS opcodes: ' + ' '.join(f'{name}={count}' for name, count in counts.items()))
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
