# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Cross-check the exact-rational oracle against host IEEE arithmetic.

The host's binary64 operations, C library fma/fmaf, the C double-to-float
conversion and lrint run under each rounding mode set with fesetround; the
host exception flags are compared with the oracle's. Binary32 add, subtract,
multiply and divide take the binary64 result and convert it: double rounding
is exact for these operations in every IEEE mode. x86 detects tininess after
rounding, PowerPC before, so underflow is not compared when the rounded
result is the smallest normal magnitude. NaN results are compared as NaN
only, since payload choice is implementation-specific. IEEE 754 leaves the
invalid flag for infinity times zero plus a quiet NaN to the implementation;
PEM §3.3.6.1.1 lists every infinity-times-zero as VXIMZ, so that case skips
the invalid comparison.
"""
import argparse
import ctypes
import ctypes.util
import random
import struct
import sys

from ppc_reference import arithmetic
from cluster_vectors import CLUSTERS, Fmt, operands
from production_vectors import widen
from enabled_vectors import SPECIAL32, SPECIAL64

FE_INVALID, FE_DIVBYZERO, FE_OVERFLOW, FE_UNDERFLOW, FE_INEXACT = \
    0x01, 0x04, 0x08, 0x10, 0x20
FE_ALL = 0x3d
MODES = (0x000, 0xc00, 0x800, 0x400)  # PowerPC RN 0..3 on x86 glibc
OPS = ('add', 'sub', 'mul', 'div', 'madd', 'msub', 'nmadd', 'nmsub',
       'frsp', 'fctiw')

libm = ctypes.CDLL(ctypes.util.find_library('m'))
libm.fesetround.argtypes = [ctypes.c_int]
libm.feclearexcept.argtypes = [ctypes.c_int]
libm.fetestexcept.argtypes = [ctypes.c_int]
libm.fma.restype = ctypes.c_double
libm.fma.argtypes = [ctypes.c_double] * 3
libm.fmaf.restype = ctypes.c_float
libm.fmaf.argtypes = [ctypes.c_float] * 3
libm.lrint.restype = ctypes.c_long
libm.lrint.argtypes = [ctypes.c_double]


def to_float(bits):
    return struct.unpack('<d', struct.pack('<Q', bits))[0]


def to_bits(value):
    return struct.unpack('<Q', struct.pack('<d', value))[0]


def is_nan(bits):
    return (bits >> 52) & 0x7ff == 0x7ff and bool(bits & ((1 << 52) - 1))


def inf_times_zero(a, c):
    mag = [x & ~(1 << 63) for x in (a, c)]
    return 0x7ff0000000000000 in mag and 0 in mag


def narrow(value):
    """C double-to-float conversion under the current mode."""
    return ctypes.c_float(value).value


def host(op, a, b, c, single):
    """Return (raw binary64 result, flags) or None when not comparable."""
    x, y, z = to_float(a), to_float(b), to_float(c)
    if op == 'fctiw':
        if is_nan(b) or not -2.0**31 - 1 < y < 2.0**31:
            return None
        libm.feclearexcept(FE_ALL)
        value = libm.lrint(y)
        if not -2**31 <= value < 2**31:
            return None
        return value & 0xffffffff, libm.fetestexcept(FE_ALL)
    # Python raises on a zero divisor; an ordered compare also raises
    # invalid for NaN, so flags clear after it.
    if op == 'div' and not is_nan(b) and b & ~(1 << 63) == 0:
        return None
    libm.feclearexcept(FE_ALL)
    if single and op in ('madd', 'msub', 'nmadd', 'nmsub'):
        value = libm.fmaf(x, z, -y if op in ('msub', 'nmsub') else y)
    elif op in ('madd', 'msub', 'nmadd', 'nmsub'):
        value = libm.fma(x, z, -y if op in ('msub', 'nmsub') else y)
    elif op == 'frsp':
        value = narrow(y)
    else:
        value = {'add': lambda: x + y, 'sub': lambda: x - y,
                 'mul': lambda: x * z, 'div': lambda: x / y}[op]()
        if single:
            value = narrow(value)
    if op in ('nmadd', 'nmsub'):
        value = -value
    return to_bits(value), libm.fetestexcept(FE_ALL)


def cases(op, single, rng, count):
    f = Fmt(single)
    for index in range(count):
        if index % 3 == 0:
            raw = tuple(rng.getrandbits(f.width) for _ in range(3))
        elif index % 6 == 1:
            special = SPECIAL32 if single else SPECIAL64
            raw = tuple(rng.choice(special) if rng.getrandbits(1) else
                        rng.getrandbits(f.width) for _ in range(3))
        else:
            raw = operands(op, CLUSTERS[index % len(CLUSTERS)], rng, f)
        yield tuple(widen(v) for v in raw) if single else raw


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--count', type=int, default=3000)
    parser.add_argument('--seed', type=lambda v: int(v, 0), default=0x1eee754)
    args = parser.parse_args()
    rng = random.Random(args.seed)
    checked = skipped = 0
    failures = []
    for op in OPS:
        for single in (False, True):
            if single and op in ('frsp', 'fctiw'):
                continue
            for a, b, c in cases(op, single, rng, args.count):
                if op in ('frsp', 'fctiw'):
                    a, c = 0, 0
                for rn, mode in enumerate(MODES):
                    libm.fesetround(mode)
                    try:
                        got = host(op, a, b, c, single)
                    finally:
                        libm.fesetround(0)
                    if got is None:
                        skipped += 1
                        continue
                    bits, flags = got
                    exp = arithmetic(op, a, b, c, rn, single)
                    imz_qnan = op in ('madd', 'msub', 'nmadd', 'nmsub') and \
                        is_nan(b) and inf_times_zero(a, c)
                    tie_min = (bits & ~(1 << 63)) == (0x3810000000000000 if
                        single or op == 'frsp' else 0x0010000000000000)
                    problems = []
                    if is_nan(exp['result']) != is_nan(bits) or (
                            not is_nan(bits) and exp['result'] != bits):
                        problems.append(f"result {exp['result']:016x}")
                    for name, flag in (('invalid', FE_INVALID),
                                       ('zx', FE_DIVBYZERO),
                                       ('ox', FE_OVERFLOW),
                                       ('xx', FE_INEXACT),
                                       ('ux', FE_UNDERFLOW)):
                        if (name == 'ux' and tie_min) or (name == 'invalid' and imz_qnan):
                            continue
                        if bool(exp[name]) != bool(flags & flag):
                            problems.append(f'{name} oracle={int(bool(exp[name]))}')
                    checked += 1
                    if problems:
                        failures.append(f'{op} single={int(single)} rn={rn} '
                                        f'a={a:016x} b={b:016x} c={c:016x} '
                                        f'host={bits:016x} flags={flags:02x} ' +
                                        ' '.join(problems))
    for line in failures[:40]:
        print('MISMATCH', line)
    print(f'PPC_ORACLE_HOST checked={checked} skipped={skipped} '
          f'mismatches={len(failures)}')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
