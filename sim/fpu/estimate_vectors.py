# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""603e estimate qualification from PEM pp. 509-513 and exact rational bounds.

The manuals permit implementation-dependent estimate bits. This oracle therefore
checks the specified relative error, special values, and defined FPSCR metadata,
without sharing a lookup table or algorithm with the arithmetic RTL. NI flush is
an explicit project policy from docs/FPU_CONTRACT.md, not a PEM estimate guarantee.
"""
import argparse
from fractions import Fraction
from pathlib import Path
import random
from reference import B32, B64, calculate, decode

FRES, FRSQRTE = 13, 14
NORMAL, OVERFLOW, UNDERFLOW, SPECIAL, RSQRT, SUBNORMAL = range(6)
DEFAULT_NAN = 0x7ff8000000000000
POS_INF = 0x7ff0000000000000
SP_MAX = calculate('to64', 0x7f7fffff, 0, fmt=B32)['bits']
SP_MIN = calculate('to64', 1, 0, fmt=B32)['bits']


def exact_value(bits):
    kind, sign, significand, exponent = decode(bits)
    if kind != 'finite':
        raise ValueError(kind)
    value = Fraction(significand << max(exponent, 0), 1 << max(-exponent, 0))
    return -value if sign else value


def power_two(exponent, sign=0):
    """Build a binary64 power of two, including the smallest subnormal."""
    if exponent < -1022:
        bits = 1 << (exponent + 1074)
    else:
        bits = (exponent + 1023) << 52
    return bits | (sign << 63)


def widen_sp(bits):
    return calculate('to64', bits, 0, fmt=B32)['bits']


def add(rows, op, value, mode, rn=0, ni=0, ve=0, oe=0, ue=0, ze=0):
    rows.append((op, value, rn, ni, ve, oe, ue, ze, mode))


def generate(path, seed, count):
    rng = random.Random(seed)
    rows = []
    specials = [0, 1 << 63, POS_INF, POS_INF | (1 << 63),
                0x7ff0000000000001, 0xfff0000000000045,
                0x7ff8000000000123, 0xfff8000000000045,
                power_two(0), power_two(0, 1), power_two(1), power_two(1, 1)]
    for op in (FRES, FRSQRTE):
        for value in specials:
            mode = (NORMAL if op == FRES else RSQRT) if \
                expected_special(op, value) is None else SPECIAL
            for rn in range(4):
                for ni in (0, 1):
                    for ve, ze in ((0, 0), (1, 0), (0, 1), (1, 1)):
                        add(rows, op, value, mode, rn, ni, ve, ze=ze)

    # Reciprocal bound is meaningful when the estimate is a normal binary32.
    for value in (0x3f800000, 0x40400000, 0x3f000000, 0xbf800000,
                  0xc0400000, 0x02000000, 0x7d000000):
        for rn in range(4):
            for ni in (0, 1):
                add(rows, FRES, widen_sp(value), NORMAL, rn, ni)
    for _ in range(count):
        sign = rng.getrandbits(1)
        exponent = rng.randrange(5, 251)
        fraction = rng.getrandbits(23)
        value = widen_sp((sign << 31) | (exponent << 23) | fraction)
        add(rows, FRES, value, NORMAL, rng.randrange(4), rng.randrange(2))
    # The source FPR is binary64. Its low 29 fraction bits need not be zero.
    for _ in range(count):
        sign = rng.getrandbits(1)
        exponent = rng.randrange(903, 1144)  # true exponents -120..120
        fraction = rng.getrandbits(52)
        value = (sign << 63) | (exponent << 52) | fraction
        add(rows, FRES, value, NORMAL, rng.randrange(4), rng.randrange(2),
            oe=rng.randrange(2), ue=rng.randrange(2))

    # These binary32 subnormal reciprocals have no alternative estimate
    # within the manual's 1/256 relative bound. OE is irrelevant here.
    for exponent in (148, 149):
        for sign in (0, 1):
            for rn in range(4):
                for ni in (0, 1):
                    for oe in (0, 1):
                        add(rows, FRES, power_two(exponent, sign), SUBNORMAL,
                            rn, ni, oe=oe)

    # Choose magnitudes far from the SP boundaries: overflow and underflow
    # classifications do not depend on the implementation's estimate bits.
    for exponent, mode in ((-1074, OVERFLOW), (-500, OVERFLOW),
                           (-200, OVERFLOW), (200, UNDERFLOW),
                           (500, UNDERFLOW), (1023, UNDERFLOW)):
        for sign in (0, 1):
            value = power_two(exponent, sign)
            for rn in range(4):
                for ni in (0, 1):
                    for enabled in (0, 1):
                        add(rows, FRES, value, mode, rn, ni,
                            oe=enabled if mode == OVERFLOW else 0,
                            ue=enabled if mode == UNDERFLOW else 0)
                        if mode == UNDERFLOW:
                            add(rows, FRES, value, mode, rn, ni,
                                oe=1, ue=enabled)
                        else:
                            add(rows, FRES, value, mode, rn, ni,
                                oe=enabled, ue=1)

    # All 32 leading-significand bins and both exponent parities. A point at
    # each bin's first, middle and last binary64 encoding catches endpoint
    # indexing errors. Include both extreme normal exponents and subnormals.
    for exponent in (1, 2, 1023, 1024, 2045, 2046):
        for bin_index in range(16):
            base = bin_index << 48
            for fraction in (base, base + (1 << 47), base + (1 << 48) - 1):
                value = (exponent << 52) | fraction
                for rn in range(4):
                    for ni in (0, 1):
                        add(rows, FRSQRTE, value, RSQRT, rn, ni,
                            oe=(exponent & 1), ue=((exponent >> 1) & 1))
    for value in (1, 2, 3, (1 << 48) - 1, 1 << 48,
                  (1 << 52) - 2, (1 << 52) - 1):
        for rn in range(4):
            for ni in (0, 1):
                add(rows, FRSQRTE, value, RSQRT, rn, ni, oe=1, ue=1)
    # Architecturally conforming FRSQRTE operands must be binary32 values.
    for raw in (1, 2, 0x007fffff, 0x00800000, 0x3f000000,
                0x3f800000, 0x40000000, 0x40400000, 0x7f7fffff):
        for rn in range(4):
            add(rows, FRSQRTE, widen_sp(raw), RSQRT, rn)
    for _ in range(count):
        exponent = rng.randrange(1, 255)
        fraction = rng.getrandbits(23)
        add(rows, FRSQRTE, widen_sp((exponent << 23) | fraction),
            RSQRT, rng.randrange(4), rng.randrange(2))
    # Exercise every binary64 exponent, plus each subnormal leading-bit
    # position. This complements the cross-product of all lookup bins above.
    for exponent in range(1, 2047):
        for fraction in (0, 1 << 51, (1 << 52) - 1):
            add(rows, FRSQRTE, (exponent << 52) | fraction, RSQRT,
                rn=exponent & 3, ni=(exponent >> 2) & 1,
                oe=(exponent >> 3) & 1, ue=(exponent >> 4) & 1)
    for position in range(52):
        for fraction in (1 << position, min((1 << (position + 1)) - 1,
                                           (1 << 52) - 1)):
            add(rows, FRSQRTE, fraction, RSQRT, rn=position & 3,
                ni=(position >> 2) & 1)
    for _ in range(count):
        exponent = rng.randrange(0, 2047)
        fraction = rng.getrandbits(52)
        if exponent == 0 and fraction == 0:
            fraction = 1
        add(rows, FRSQRTE, (exponent << 52) | fraction, RSQRT,
            rng.randrange(4), rng.randrange(2), oe=rng.randrange(2),
            ue=rng.randrange(2))

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w') as stream:
        for row in rows:
            stream.write(' '.join(f'{item:x}' for item in row) + '\n')
    counts = {name: sum(row[-1] == mode for row in rows)
              for name, mode in (('normal', NORMAL), ('overflow', OVERFLOW),
                                 ('underflow', UNDERFLOW), ('special', SPECIAL),
                                 ('rsqrt', RSQRT), ('subnormal', SUBNORMAL))}
    print(f'ESTIMATE_CORPUS seed={seed:#x} random_per_operation={count} '
          f'vectors={len(rows)} coverage={counts}')


def result_class(bits, single=False):
    kind, sign, _, _ = decode(bits)
    if kind in ('snan', 'qnan'):
        return 0b10001
    if kind == 'inf':
        return 0b01001 if sign else 0b00101
    magnitude = bits & ((1 << 63) - 1)
    if magnitude == 0:
        return 0b10010 if sign else 0b00010
    denormal = exact_value(magnitude) < Fraction(1, 1 << (126 if single else 1022))
    if denormal:
        return 0b11000 if sign else 0b10100
    return 0b01000 if sign else 0b00100


def scale_fraction(value, exponent):
    if exponent >= 0:
        return value * (1 << exponent)
    return value / (1 << -exponent)


def expected_special(op, value):
    kind, sign, _, _ = decode(value)
    negative_nonzero = bool(sign and (value & ((1 << 63) - 1)))
    if kind in ('snan', 'qnan'):
        return value | (1 << 51), int(kind == 'snan'), 0
    if not (value & ((1 << 63) - 1)):
        return (sign << 63) | POS_INF, 0, 1
    if op == FRSQRTE and negative_nonzero:
        return DEFAULT_NAN, 1 << 7, 0
    if kind == 'inf':
        return sign << 63, 0, 0
    return None


def check_one(row, output):
    op, value, rn, ni, ve, oe, ue, ze, mode = row
    out_op, out_input, result, invalid, ox, ux, zx, xx, fr, fi, frfi_valid, \
        fprf_valid, fprf, write_result, compare_valid, fpcc = output
    if (out_op, out_input) != (op, value):
        return 'trace op/input'
    if compare_valid or fpcc or xx:
        return 'unexpected compare/XX update'
    special = expected_special(op, value)
    if special is not None:
        expected_result, expected_invalid, expected_zx = special
        exceptional = bool(expected_invalid or expected_zx)
        if frfi_valid != exceptional or (exceptional and (fr or fi)):
            return 'exceptional FR/FI clear or ordinary FR/FI validity'
        suppress = bool((expected_invalid and ve) or (expected_zx and ze))
        if (invalid, ox, ux, zx, write_result, fprf_valid) != \
                (expected_invalid, 0, 0, expected_zx, int(not suppress), int(not suppress)):
            return 'special status/suppression'
        if not suppress and result != expected_result:
            return 'special result'
    else:
        if frfi_valid:
            return 'finite estimate FR/FI validity'
        if invalid or zx or not write_result or not fprf_valid:
            return 'finite invalid/ZX/write'
        if op == FRSQRTE:
            if ox or ux:
                return 'rsqrt affected bits'
            kind, sign, _, _ = decode(result)
            if kind != 'finite' or sign or not (result & ((1 << 63) - 1)):
                return 'rsqrt positive finite result'
            squared_product = exact_value(value) * exact_value(result) ** 2
            if not Fraction(31 * 31, 32 * 32) <= squared_product <= \
                    Fraction(33 * 33, 32 * 32):
                return 'rsqrt 1/32 relative bound'
            source_sp = widen_sp(calculate('to32', value, 0)['bits']) == value
            if source_sp and widen_sp(calculate('to32', result, 0)['bits']) != result:
                return 'rsqrt SP-representable destination'
        else:
            sign = value >> 63
            if result >> 63 != sign:
                return 'reciprocal finite sign'
            if mode == NORMAL:
                if ox or ux:
                    return 'normal reciprocal range flags'
                product = abs(exact_value(value) * exact_value(result))
                if not Fraction(255, 256) <= product <= Fraction(257, 256):
                    return 'reciprocal 1/256 relative bound'
                sp = calculate('to32', result, 0)['bits']
                if widen_sp(sp) != result:
                    return 'reciprocal is not binary32 representable'
            elif mode == OVERFLOW:
                if (ox, ux) != (1, 0):
                    return 'overflow flags'
                if oe:
                    scaled_product = abs(scale_fraction(
                        exact_value(value) * exact_value(result), 192))
                    if not Fraction(255, 256) <= scaled_product <= Fraction(257, 256):
                        return 'overflow scaled reciprocal bound'
                else:
                    toward_infinity = rn == 0 or (rn == 2 and not sign) or (rn == 3 and sign)
                    expected = (sign << 63) | (POS_INF if toward_infinity else SP_MAX)
                    if result != expected:
                        return 'overflow RN result'
            elif mode == UNDERFLOW:
                if ox or ux != 1:
                    return 'underflow flags'
                if ue:
                    scaled_product = abs(scale_fraction(
                        exact_value(value) * exact_value(result), -192))
                    if not Fraction(255, 256) <= scaled_product <= Fraction(257, 256):
                        return 'underflow scaled reciprocal bound'
                else:
                    toward_nonzero = (rn == 2 and not sign) or (rn == 3 and sign)
                    expected = (sign << 63) | (SP_MIN if toward_nonzero and not ni else 0)
                    if result != expected:
                        return 'underflow RN/NI result'
            elif mode == SUBNORMAL:
                if ox or ux:
                    return 'exact subnormal flags'
                exponent = 149 if (value & ((1 << 63) - 1)) == power_two(149) else 148
                expected = (sign << 63) | (0 if ni else widen_sp(1 if exponent == 149 else 2))
                if result != expected:
                    return 'exact subnormal result/NI'
            else:
                return 'unexpected finite mode'
            if ((mode == OVERFLOW and oe) or (mode == UNDERFLOW and ue)) and \
                    result & ((1 << 29) - 1):
                return 'scaled result exceeds binary32 precision'
    if write_result:
        # PEM D.4.1 classifies an unscaled SP denormal before FPR widening.
        # Exponent-adjusted enabled results are classified after adjustment.
        adjusted = (mode == OVERFLOW and oe) or (mode == UNDERFLOW and ue)
        single = op == FRES and not adjusted
        if fprf != result_class(result, single=single):
            return 'FPRF class'
    return None


def compare(vectors, results):
    source = vectors.read_text().splitlines()
    observed = results.read_text().splitlines()
    if len(source) != len(observed):
        raise SystemExit(f'FAIL estimate count expected={len(source)} observed={len(observed)}')
    mismatches = 0
    categories = {}
    for index, (a, b) in enumerate(zip(source, observed)):
        row = tuple(int(item, 16) for item in a.split())
        output = tuple(int(item, 16) for item in b.split())
        if len(row) != 9 or len(output) != 16:
            raise SystemExit(f'FAIL estimate trace format vector={index}')
        mismatch = check_one(row, output)
        if mismatch:
            mismatches += 1
            categories[mismatch] = categories.get(mismatch, 0) + 1
            if mismatches <= 12:
                print(f'ESTIMATE_MISMATCH index={index} why={mismatch} '
                      f'vector={a} observed={b}')
    print(f'ESTIMATE_RESULT vectors={len(source)} mismatches={mismatches} categories={categories}')
    if mismatches:
        raise SystemExit('FAIL estimate qualification')
    print('PASS estimate bounds, specials, statuses, and suppression')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('generate', 'compare'))
    parser.add_argument('--vectors', type=Path, required=True)
    parser.add_argument('--results', type=Path)
    parser.add_argument('--seed', type=lambda value: int(value, 0), default=0x603ef003)
    parser.add_argument('--random', type=int, default=512)
    args = parser.parse_args()
    if args.action == 'generate':
        generate(args.vectors, args.seed, args.random)
    else:
        compare(args.vectors, args.results)
