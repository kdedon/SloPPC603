# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Exponent-clustered random arithmetic packets with random enables.

Operands cluster where rounding and exception logic is hardest: near
cancellation, fused alignment within two binades, tiny and overflowing
results, and denormal sources. Every packet draws RN and the VE/OE/UE/ZE/NI
bits independently, so combined enables are exercised. The output format
matches production_vectors.py for both personalities.
"""
import argparse
from pathlib import Path
import random

from ppc_reference import arithmetic
from production_vectors import OPS, widen
from production_vectors_602 import expected_602, widen_raw

THREE = ('madd', 'msub', 'nmadd', 'nmsub')
OPS_603 = ('add', 'sub', 'mul', 'div') + THREE + ('frsp', 'fctiw', 'fctiwz')
OPS_602 = ('add', 'sub', 'mul', 'div') + THREE + ('frsp', 'fctiwz', 'fres')
CLUSTERS = ('cancel', 'align', 'tiny', 'overflow', 'denormal')
FIELDS = ('result', 'write_result', 'invalid', 'ox', 'ux', 'zx', 'xx',
          'fr', 'fi', 'frfi_valid', 'fprf', 'fprf_valid', 'fpcc',
          'compare_valid', 'tiny_before_round')


class Fmt:
    def __init__(self, single):
        self.frac = 23 if single else 52
        self.bias = 127 if single else 1023
        self.emax = 254 if single else 2046
        self.width = 32 if single else 64

    def value(self, sign, exponent, fraction):
        exponent = min(max(exponent, 0), self.emax)
        return ((sign << (self.width - 1)) | (exponent << self.frac) |
                (fraction & ((1 << self.frac) - 1)))

    def exponent(self, bits):
        return (bits >> self.frac) & ((1 << (self.width - self.frac - 1)) - 1)


def fraction(rng, f):
    """Random fraction, sometimes with long runs of ones or zeros."""
    choice = rng.randrange(4)
    if choice == 0:
        return rng.getrandbits(f.frac)
    if choice == 1:
        return ((1 << f.frac) - 1) ^ rng.getrandbits(rng.randrange(1, 8))
    if choice == 2:
        return rng.getrandbits(rng.randrange(1, 8))
    return rng.getrandbits(f.frac) & ~((1 << rng.randrange(f.frac)) - 1)


def denormal(rng, f):
    return f.value(rng.getrandbits(1), 0,
                   max(1, rng.getrandbits(f.frac) >> rng.randrange(f.frac)))


def operands(op, cluster, rng, f):
    """Return raw (a, b, c) in the format's own width."""
    s = rng.getrandbits
    near = lambda e: e + rng.randrange(-2, 3)
    if op in ('frsp', 'fctiw', 'fctiwz', 'fres'):
        if cluster == 'tiny':
            e = rng.randrange(1, 40) if f.width == 32 else rng.choice(
                (rng.randrange(1023 - 160, 1023 - 120), rng.randrange(1, 40)))
        elif cluster == 'overflow':
            e = rng.randrange(f.emax - 8, f.emax + 1) if f.width == 32 or \
                op != 'frsp' else rng.randrange(1023 + 125, 1023 + 130)
        elif cluster == 'denormal':
            return 0, denormal(rng, f), 0
        else:
            e = f.bias + (rng.randrange(-2, 33) if 'fctiw' in op else
                          rng.randrange(-8, 8))
        return 0, f.value(s(1), e, fraction(rng, f)), 0
    if op in ('add', 'sub'):
        if cluster == 'tiny':
            ea = rng.randrange(0, 4)
        elif cluster == 'overflow':
            ea = rng.randrange(f.emax - 2, f.emax + 1)
        else:
            ea = rng.randrange(1, f.emax + 1)
        a = f.value(s(1), ea, fraction(rng, f))
        if cluster == 'denormal':
            a = denormal(rng, f)
        if cluster in ('cancel', 'tiny', 'denormal') or s(1):
            eb = near(f.exponent(a) or 1)
            fb = fraction(rng, f)
            if s(1):
                fb = (a ^ rng.getrandbits(rng.randrange(1, 6))) & ((1 << f.frac) - 1)
            b = f.value(s(1), eb, fb)
        else:
            b = f.value(s(1), near(ea), fraction(rng, f))
        if s(1):
            a, b = b, a
        return a, b, 0
    # Multiply, divide and fused: choose a, c, then the addend.
    if cluster == 'tiny':
        target = rng.randrange(-f.frac - 4, 3)
    elif cluster == 'overflow':
        target = rng.randrange(f.emax - 3, f.emax + 2)
    else:
        target = rng.randrange(f.bias - 40, f.bias + 40)
    ea = rng.randrange(max(1, target - f.bias + 1),
                       min(f.emax, target + f.bias - 1) + 1)
    if op == 'div':
        ec = ea - target + f.bias
    else:
        ec = target - ea + f.bias
    ec = min(max(ec, 1), f.emax)
    a = f.value(s(1), ea, fraction(rng, f))
    c = f.value(s(1), ec, fraction(rng, f))
    if cluster == 'denormal':
        if s(1):
            a = denormal(rng, f)
        else:
            c = denormal(rng, f)
    if op == 'mul':
        return a, 0, c
    if op == 'div':
        return a, c, 0
    # Addend within two binades of the product, often nearly cancelling.
    pe = f.exponent(a) + f.exponent(c) - f.bias
    if cluster == 'denormal' and s(1):
        return a, denormal(rng, f), c
    b = f.value(s(1), near(max(pe, 1)), fraction(rng, f))
    return a, b, c


def modes(rng):
    return (rng.randrange(4), rng.getrandbits(1), rng.getrandbits(1),
            rng.getrandbits(1), rng.getrandbits(1), rng.getrandbits(1))


def rows_603(rng, count):
    for op in OPS_603:
        for single in (False, True):
            if single and op in ('fctiw', 'fctiwz'):
                continue
            f = Fmt(single)
            for index in range(count):
                cluster = CLUSTERS[index % len(CLUSTERS)]
                raw = operands(op, cluster, rng, f)
                a, b, c = (widen(x) for x in raw) if single else raw
                rn, ni, ve, oe, ue, ze = modes(rng)
                exp = arithmetic(op, a, b, c, rn, single, ni, ve, oe, ue, ze)
                mask = 0 if not exp['write_result'] else (
                    0xffffffff if op in ('fctiw', 'fctiwz') else (1 << 64) - 1)
                yield op, (OPS[op], a, b, c, rn, int(single), ni, ve, oe, ue,
                           ze), exp, mask


def rows_602(rng, count):
    for op in OPS_602:
        f = Fmt(True)
        for index in range(count):
            cluster = CLUSTERS[index % len(CLUSTERS)]
            a, b, c = (widen_raw(x) for x in operands(op, cluster, rng, f))
            rn, ni, ve, oe, ue, ze = modes(rng)
            exp = expected_602(op, a, b, c, rn, ni, ve, oe, ue, ze)
            mask = (0xffffffff if op == 'fctiwz' else (1 << 64) - 1) \
                if exp['write_result'] else 0
            yield op, (OPS.get(op, 13), a, b, c, rn, int(op != 'fctiwz'), ni,
                       ve, oe, ue, ze), exp, mask


def generate(path, personality, count, seed):
    rng = random.Random(seed)
    rows = rows_602(rng, count) if personality == '602' else rows_603(rng, count)
    total = 0
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w') as out:
        for _, fields, exp, mask in rows:
            values = fields + tuple(exp[name] for name in FIELDS) + (mask,)
            out.write(' '.join(format(int(v), 'x') for v in values) + '\n')
            total += 1
    print(f'PPC_CLUSTER_CORPUS personality={personality} seed={seed:#x} '
          f'per_op_precision={count} vectors={total}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--vectors', type=Path, required=True)
    parser.add_argument('--personality', choices=('603e', '602'), default='603e')
    parser.add_argument('--count', type=int, default=2000)
    parser.add_argument('--seed', type=lambda value: int(value, 0), default=0xc105e603)
    args = parser.parse_args()
    generate(args.vectors, args.personality, args.count, args.seed)
