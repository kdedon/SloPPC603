#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Write a flat binary as $readmemh input for a 64-bit big-endian RAM.

usage: bin2hex64.py image.bin offset out.hex
offset is where the binary starts in RAM (bytes, multiple of 8).
"""
import sys


def main():
    data = open(sys.argv[1], 'rb').read()
    offset = int(sys.argv[2], 0)
    if offset % 8:
        sys.exit('offset must be doubleword aligned')
    data = bytes(offset) + data
    data += bytes(-len(data) % 8)
    with open(sys.argv[3], 'w') as out:
        for i in range(0, len(data), 8):
            out.write(data[i:i + 8].hex() + '\n')


if __name__ == '__main__':
    main()
