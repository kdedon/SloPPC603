#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Convert a binary PPM (P6, maxval 255) to an RGB PNG."""
import struct
import sys
import zlib


def read_ppm(path):
    data = open(path, 'rb').read()
    fields, pos = [], 0
    while len(fields) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        end = pos
        while not data[end:end + 1].isspace():
            end += 1
        fields.append(data[pos:end])
        pos = end
    if fields[0] != b'P6' or int(fields[3]) != 255:
        sys.exit(f'{path}: not a P6 PPM with maxval 255')
    width, height = int(fields[1]), int(fields[2])
    pixels = data[pos + 1:]
    if len(pixels) != width * height * 3:
        sys.exit(f'{path}: {len(pixels)} pixel bytes, expected {width * height * 3}')
    return width, height, pixels


def chunk(kind, body):
    return (struct.pack('>I', len(body)) + kind + body +
            struct.pack('>I', zlib.crc32(kind + body) & 0xffffffff))


def main():
    if len(sys.argv) != 3:
        sys.exit('usage: ppm_to_png.py in.ppm out.png')
    width, height, pixels = read_ppm(sys.argv[1])
    stride = width * 3
    raw = b''.join(b'\0' + pixels[y * stride:(y + 1) * stride] for y in range(height))
    png = (b'\x89PNG\r\n\x1a\n' +
           chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) +
           chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))
    open(sys.argv[2], 'wb').write(png)
    print(f'wrote {sys.argv[2]} ({width}x{height})')


if __name__ == '__main__':
    main()
