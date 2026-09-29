# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Independent raw-bit corpus for the compile-time MPC602 arithmetic unit.

All architectural source operands are binary32 values widened exactly into
the arithmetic request transport. The 602 shell owns SP/LT eligibility and
the 32-bit physical FPR file; this corpus checks the eligible numerical path.
"""
import argparse
from pathlib import Path
import random

from ppc_reference import arithmetic
from production_vectors import OPS
from reference import B32, calculate

OPS_602 = ('add', 'sub', 'mul', 'div', 'madd', 'msub', 'nmadd', 'nmsub',
           'frsp', 'fctiwz', 'cmpu', 'cmpo', 'fres')
THREE = {'madd', 'msub', 'nmadd', 'nmsub'}
EDGES = (0, 1, 0x007fffff, 0x00800000, 0x3f000000, 0x3f7fffff,
         0x3f800000, 0x3f800001, 0x40000000, 0x7f7fffff, 0x7f800000,
         0x7f800001, 0x7fc00123)
ONE = 0x3ff0000000000000


def widen_raw(bits):
    """Preserve SNaN signaling while widening its binary32 payload."""
    if bits & 0x7f800000 == 0x7f800000 and bits & 0x007fffff:
        return ((bits >> 31) << 63) | (0x7ff << 52) | ((bits & 0x7fffff) << 29)
    return calculate('to64', bits, 0, fmt=B32)['bits']


def expected_602(op, a, b, c, rn, ni, ve, oe, ue, ze):
    if op == 'fres':
        value = arithmetic('div', ONE, b, 0, rn, True, ni, ve, oe, ue, ze)
    else:
        value = arithmetic(op, a, b, c, rn, op not in
                           ('fctiwz', 'cmpu', 'cmpo'), ni, ve, oe, ue, ze)
    # 602 UM Table 2-23 judges NI underflow before final rounding. The
    # exact rational reference supplies that bit; a tiny value which would
    # round up to minimum normal is still delivered as signed zero.
    if ni and value['tiny_before_round'] and value['write_result']:
        sign = value['result'] >> 63
        value = dict(value)
        value['result'] = sign << 63
        value['fprf'] = 0b10010 if sign else 0b00010
    return value


def cases_for(op, rng, random_count):
    edges = EDGES + tuple(x | 0x80000000 for x in EDGES)
    if op in ('add', 'sub', 'mul', 'div', 'cmpu', 'cmpo'):
        for x in edges:
            for y in edges:
                if op == 'mul':
                    yield (x, 0, y, 'cross')
                else:
                    yield (x, y, 0, 'cross')
    elif op in THREE:
        fused_edges = (0, 1, 0x00800000, 0x3f800000, 0x7f7fffff,
                       0x7f800000, 0x7fc00123)
        fused_edges += tuple(x | 0x80000000 for x in fused_edges)
        for x in fused_edges:
            for y in (0, 0x80000000, 0x3f800000, 0xbf800000):
                for z in fused_edges:
                    yield (x, y, z, 'fused-cross')
    else:
        for x in edges:
            yield (0, x, 0, 'edge')
    # Exact tiny, tiny-to-minnormal tie, and ordinary rounding cases.
    if op in ('mul', 'madd', 'msub', 'nmadd', 'nmsub'):
        yield (0x00800000, 0, 0x3f000000, 'exact-tiny')
        yield (0x007fffff, 0, 0x3f800001, 'tiny-rounds-normal')
    if op in THREE:
        # Exact product cancellation and both sides of a binary32 halfway
        # result; all sources are legal SP-tagged binary32 values.
        yield (0x3f800001, 0xbf800002, 0x3f800001, 'delta2')
        yield (0x3f800000, 0xbf7fffff, 0x3f800000, 'adjacent')
        yield (0x3f800001, 0x33800000, 0x3f7ffffe, 'halfway-below')
        yield (0x3f800001, 0x33800000, 0x3f800001, 'halfway-above')
        yield (0x3f800000, 0x0d800000, 0x3f800000, 'far-positive')
        yield (0x3f800000, 0x8d800000, 0x3f800000, 'far-negative')
    for _ in range(random_count):
        yield (rng.getrandbits(32), rng.getrandbits(32),
               rng.getrandbits(32), 'random')


def generate(path, random_count, seed):
    rng = random.Random(seed)
    fields = ('result', 'write_result', 'invalid', 'ox', 'ux', 'zx', 'xx',
              'fr', 'fi', 'frfi_valid', 'fprf', 'fprf_valid', 'fpcc',
              'compare_valid', 'tiny_before_round')
    counts = {op: 0 for op in OPS_602}
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w') as out:
        for op in OPS_602:
            for a32, b32, c32, kind in cases_for(op, rng, random_count):
                a, b, c = map(widen_raw, (a32, b32, c32))
                for rn in range(4):
                    modes = [(0, 0, 0, 0, 0)]
                    if kind != 'random':
                        modes += [(1, 0, 0, 0, 0), (0, 1, 0, 0, 0),
                                  (0, 0, 1, 0, 0), (0, 0, 0, 1, 0),
                                  (0, 0, 0, 0, 1)]
                    for ve, oe, ue, ze, ni in modes:
                        exp = expected_602(op, a, b, c, rn, ni, ve, oe, ue, ze)
                        mask = (0xffffffff if op == 'fctiwz' else
                                0xffffffffffffffff) if exp['write_result'] else 0
                        values = (OPS.get(op, 13), a, b, c, rn,
                                  int(op not in ('fctiwz', 'cmpu', 'cmpo')),
                                  ni, ve, oe, ue, ze)
                        values += tuple(exp[field] for field in fields) + (mask,)
                        out.write(' '.join(format(int(v), 'x') for v in values) + '\n')
                        counts[op] += 1
    print(f'PPC_602_CORPUS seed={seed:#x} random_per_op={random_count} '
          f'vectors={sum(counts.values())} ' +
          ' '.join(f'{op}={count}' for op, count in counts.items()))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--vectors', type=Path, required=True)
    parser.add_argument('--random', type=int, default=128)
    parser.add_argument('--seed', type=lambda value: int(value, 0), default=0x602f0002)
    args = parser.parse_args()
    generate(args.vectors, args.random, args.seed)
