#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Extracts an LHA archive with level 0 or 1 headers and -lh0-, -lh5- or
-lhd- members, checking each file's CRC-16. Directories in the archive
are kept; with member names given, only those files are written.

Usage: lha.py archive.lha outdir [member ...]"""
import os
import sys

NT, NP, NC = 19, 14, 510


def crc16(data):
    crc = 0
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ (0xA001 if crc & 1 else 0)
    return crc


class Bits:
    def __init__(self, data):
        self.data, self.pos = data, 0

    def get(self, n):
        v = 0
        for _ in range(n):
            byte = self.pos >> 3
            bit = (self.data[byte] >> (7 - (self.pos & 7))) & 1 if byte < len(self.data) else 0
            v = v << 1 | bit
            self.pos += 1
        return v

    def peek(self, n):
        pos = self.pos
        v = self.get(n)
        self.pos = pos
        return v


class Huffman:
    """Canonical code: shorter codes first, then by symbol."""

    def __init__(self, lengths, single=None):
        self.single = single
        self.count = [0] * 17
        for n in lengths:
            self.count[n] += 1
        self.count[0] = 0
        self.symbols = [s for n in range(1, 17) for s, ln in enumerate(lengths) if ln == n]

    def decode(self, bits):
        if self.single is not None:
            return self.single
        code = first = index = 0
        for n in range(1, 17):
            code |= bits.get(1)
            count = self.count[n]
            if code - first < count:
                return self.symbols[index + code - first]
            index += count
            first = (first + count) << 1
            code <<= 1
        raise ValueError('bad Huffman code')


def read_pt(bits, nn, nbit, special):
    n = bits.get(nbit)
    if n == 0:
        return Huffman([], bits.get(nbit))
    lengths = []
    while len(lengths) < n:
        c = bits.peek(3)
        if c == 7:
            bits.get(3)
            while bits.get(1):
                c += 1
        else:
            bits.get(3)
        lengths.append(c)
        if len(lengths) == special:
            lengths += [0] * bits.get(2)
    return Huffman(lengths + [0] * (nn - len(lengths)))


def read_c(bits, pt):
    n = bits.get(9)
    if n == 0:
        return Huffman([], bits.get(9))
    lengths = []
    while len(lengths) < n:
        c = pt.decode(bits)
        if c == 0:
            lengths.append(0)
        elif c == 1:
            lengths += [0] * (bits.get(4) + 3)
        elif c == 2:
            lengths += [0] * (bits.get(9) + 20)
        else:
            lengths.append(c - 2)
    return Huffman(lengths + [0] * (NC - len(lengths)))


def lh5(data, size):
    bits, out, left = Bits(data), bytearray(), 0
    while len(out) < size:
        if left == 0:
            left = bits.get(16)
            pt = read_pt(bits, NT, 5, 3)
            c_code = read_c(bits, pt)
            p_code = read_pt(bits, NP, 4, -1)
        left -= 1
        c = c_code.decode(bits)
        if c < 256:
            out.append(c)
            continue
        j = p_code.decode(bits)
        if j:
            j = (1 << (j - 1)) + bits.get(j - 1)
        src = len(out) - j - 1
        for k in range(c - 253):
            out.append(out[src + k])
    return bytes(out[:size])


def members(arc):
    pos = 0
    while pos < len(arc) and arc[pos]:
        hsize, level = arc[pos], arc[pos + 20]
        method = arc[pos + 2:pos + 7].decode()
        packed = int.from_bytes(arc[pos + 7:pos + 11], 'little')
        size = int.from_bytes(arc[pos + 11:pos + 15], 'little')
        nlen = arc[pos + 21]
        name = arc[pos + 22:pos + 22 + nlen].decode('latin-1')
        crc = int.from_bytes(arc[pos + 22 + nlen:pos + 24 + nlen], 'little')
        data = pos + 2 + hsize
        if level == 1:
            ext = int.from_bytes(arc[data - 2:data], 'little')
            directory = ''
            while ext:
                kind, body = arc[data], arc[data + 1:data + ext - 2]
                if kind == 1:
                    name = body.decode('latin-1')
                elif kind == 2:
                    directory = body.replace(b'\xff', b'/').decode('latin-1')
                packed -= ext
                data += ext
                ext = int.from_bytes(arc[data - 2:data], 'little')
            name = directory + name
        elif level != 0:
            sys.exit(f'lha: header level {level} not supported')
        yield name.replace('\\', '/'), method, arc[data:data + packed], size, crc
        pos = data + packed


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    arc = open(argv[0], 'rb').read()
    wanted = set(argv[2:])
    for name, method, packed, size, crc in members(arc):
        if method == '-lhd-' or (argv[2:] and name not in wanted):
            continue
        if method == '-lh0-':
            data = packed
        elif method == '-lh5-':
            data = lh5(packed, size)
        else:
            sys.exit(f'lha: {name}: method {method} not supported')
        if len(data) != size or crc16(data) != crc:
            sys.exit(f'lha: {name}: CRC mismatch')
        out = os.path.join(argv[1], name)
        os.makedirs(os.path.dirname(out) or '.', exist_ok=True)
        open(out, 'wb').write(data)
        wanted.discard(name)
    if wanted:
        sys.exit(f'lha: not in archive: {" ".join(sorted(wanted))}')


if __name__ == '__main__':
    main(sys.argv[1:])
