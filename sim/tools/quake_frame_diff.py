#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Compares Quake smoke frames: each input is a smoke run's log, whose
'quake: frame' lines hold the 320 x 200 picture and the palette in hex, or
the host build's quake-frame.bin. Prints, against the first input, the
number of differing pixels, how many palette indices they differ by at most
and on average, and the RGB difference; with --ppm, writes each frame.

Usage: quake_frame_diff.py [--ppm prefix] reference other..."""
import re
import sys

W, H = 320, 200


def load(path):
    if path.endswith('.bin'):
        data = open(path, 'rb').read()
    else:
        chunks = {}
        for line in open(path, encoding='latin-1'):
            m = re.match(r'^quake: frame ([0-9a-f]{5}) ([0-9a-f]+)\s*$', line)
            if m:
                chunks[int(m.group(1), 16)] = bytes.fromhex(m.group(2))
        data = b''.join(chunks[k] for k in sorted(chunks))
    if len(data) < W * H + 768:
        sys.exit(f'{path}: {len(data)} bytes of frame, {W * H + 768} expected')
    return data[:W * H], data[W * H:W * H + 768]


def main(argv):
    ppm = None
    if argv[:1] == ['--ppm']:
        ppm, argv = argv[1], argv[2:]
    if len(argv) < 2:
        sys.exit(__doc__)
    frames = [load(p) for p in argv]
    ref_pix, ref_pal = frames[0]
    for path, (pix, pal) in zip(argv, frames):
        diff = [(a, b) for a, b in zip(ref_pix, pix) if a != b]
        rgb = [abs(ref_pal[3 * a + c] - pal[3 * b + c]) for a, b in diff for c in range(3)]
        idx = [abs(a - b) for a, b in diff]
        print(f'{path}: {len(diff)} of {W * H} pixels differ ({100 * len(diff) / (W * H):.2f}%)'
              + (f', index difference max {max(idx)} mean {sum(idx) / len(idx):.1f}, '
                 f'RGB difference max {max(rgb)} mean {sum(rgb) / len(rgb):.1f}' if diff else '')
              + ('' if pal == ref_pal else ', palette differs'))
        if ppm:
            name = f'{ppm}-{len([p for p in argv[:argv.index(path)]])}.ppm'
            out = bytearray(f'P6\n{W} {H}\n255\n'.encode())
            for p in pix:
                out += pal[3 * p:3 * p + 3]
            open(name, 'wb').write(out)


if __name__ == '__main__':
    main(sys.argv[1:])
