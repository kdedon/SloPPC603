#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Builds a loadable Doom image: the program's memory image from 0xfff00000
with the big-endian reset stub at byte 0x100. With --le the program part is
laid out for little-endian mode: file byte n holds program byte n ^ 7 (each
doubleword reversed), as the processor's munged accesses expect.

Usage: mkimage.py [--le] stub.bin program.bin base out.bin
program.bin is objcopy -O binary output starting at address base."""
import sys

IMAGE_BASE = 0xFFF00000
STUB_OFF, STUB_MAX = 0x100, 0x100
IMAGE_MAX = 1 << 20


def main(argv):
    le = '--le' in argv
    args = [a for a in argv if a != '--le']
    if len(args) != 4:
        sys.exit(__doc__)
    stub = open(args[0], 'rb').read()
    prog = open(args[1], 'rb').read()
    base = int(args[2], 0)
    if len(stub) > STUB_MAX:
        sys.exit(f'stub is {len(stub)} bytes, over {STUB_MAX}')
    off = base - IMAGE_BASE
    if off < STUB_OFF + STUB_MAX:
        sys.exit(f'program starts at {base:#x}, inside the stub')
    image = bytearray(off) + prog
    image += bytes(-len(image) % 8)
    if len(image) > IMAGE_MAX:
        sys.exit(f'image is {len(image)} bytes, over {IMAGE_MAX}')
    if le:
        for i in range(0, len(image), 8):
            image[i:i + 8] = image[i:i + 8][::-1]
    image[STUB_OFF:STUB_OFF + len(stub)] = stub
    open(args[3], 'wb').write(image)


if __name__ == '__main__':
    main(sys.argv[1:])
