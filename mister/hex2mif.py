#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Convert a $readmemh image of 64-bit words to a Quartus .mif.

usage: hex2mif.py in.hex depth out.mif
Words past the image are zero.
"""
import sys


def main():
    src, depth, dst = sys.argv[1], int(sys.argv[2], 0), sys.argv[3]
    words = []
    for line in open(src):
        line = line.split('//')[0].strip()
        if not line:
            continue
        if line.startswith('@') or len(line) != 16:
            sys.exit(f'{src}: unsupported line {line!r}')
        words.append(int(line, 16))
    if len(words) > depth:
        sys.exit(f'{src}: {len(words)} words exceed depth {depth}')
    with open(dst, 'w') as out:
        out.write(f'WIDTH=64;\nDEPTH={depth};\nADDRESS_RADIX=HEX;\nDATA_RADIX=HEX;\n'
                  'CONTENT BEGIN\n')
        for addr, word in enumerate(words):
            out.write(f'{addr:X} : {word:016X};\n')
        if len(words) < depth:
            out.write(f'[{len(words):X}..{depth - 1:X}] : 0;\n')
        out.write('END;\n')


if __name__ == '__main__':
    main()
