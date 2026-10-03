#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Converts a PPC603e screen file (OSD "Save screen") to a PNG.

Usage: fb2png.py <screen.pfb> <out.png>
       fb2png.py --blank <screen.pfb>   writes an empty 2 MiB file to mount

Screen file, 512-byte sectors: sector 0 is the header ("PFB1"; width,
height, stride as little-endian 16-bit values; bits per pixel, 8), sectors
1-2 the palette (256 entries of R, G, B, 0), then one palette index per
pixel, rows top to bottom.
"""
import struct
import sys
import zlib


def png(width, height, rows):
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
    raw = b"".join(b"\x00" + row for row in rows)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def convert(src, dst):
    data = open(src, "rb").read()
    if data[:4] != b"PFB1":
        sys.exit(f"{src}: not a screen file (no PFB1 header; was the save finished?)")
    width, height, stride = struct.unpack_from("<HHH", data, 4)
    if data[10] != 8:
        sys.exit(f"{src}: {data[10]} bits per pixel, expected 8")
    pixels = 1536
    if len(data) < pixels + stride * height:
        sys.exit(f"{src}: {len(data)} bytes, too short for {width}x{height}")
    palette = [bytes(data[512 + 4 * i:515 + 4 * i]) for i in range(256)]
    rows = []
    for y in range(height):
        line = data[pixels + y * stride:pixels + y * stride + width]
        rows.append(b"".join(palette[i] for i in line))
    open(dst, "wb").write(png(width, height, rows))
    print(f"{dst}: {width}x{height}")


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--blank":
        with open(sys.argv[2], "wb") as f:
            f.truncate(2 * 1024 * 1024)
    elif len(sys.argv) == 3:
        convert(sys.argv[1], sys.argv[2])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
