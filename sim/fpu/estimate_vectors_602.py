# SPDX-License-Identifier: MIT
"""Independent 602 FRSQRTE bound, binary32-result and status oracle.

The 602 manual specifies one-part-in-32 accuracy but no exact table bits.
Exact 602 FRES is covered separately by production_vectors_602.py's rational
divide oracle, including the same binary32 source domain.
"""
import argparse
from fractions import Fraction
from pathlib import Path
import random

from estimate_vectors import (FRSQRTE, DEFAULT_NAN, POS_INF,
                              exact_value, result_class)
from production_vectors_602 import widen_raw
from reference import B32, B64, calculate

FINITE, SPECIAL = 4, 3  # Existing raw estimate bench format.


def special(bits):
    sign = bits >> 63
    magnitude = bits & ((1 << 63) - 1)
    exponent = (bits >> 52) & 0x7ff
    fraction = bits & ((1 << 52) - 1)
    if exponent == 0x7ff and fraction:
        signaling = not bool(fraction & (1 << 51))
        return bits | (1 << 51), int(signaling), 0
    if magnitude == 0:
        return (sign << 63) | POS_INF, 0, 1
    if sign:
        return DEFAULT_NAN, 1 << 7, 0
    if exponent == 0x7ff:
        return 0, 0, 0
    return None


def generate(path, seed, count):
    rng = random.Random(seed)
    rows = []
    edge = (0, 1, 2, 0x007fffff, 0x00800000, 0x3f000000,
            0x3f800000, 0x40000000, 0x7f7fffff, 0x7f800000,
            0x7f800001, 0x7fc00123)
    for raw in edge + tuple(x | 0x80000000 for x in edge):
        value = widen_raw(raw)
        mode = SPECIAL if special(value) is not None else FINITE
        for rn in range(4):
            for ni in (0, 1):
                for ve, ze in ((0, 0), (1, 0), (0, 1), (1, 1)):
                    rows.append((FRSQRTE, value, rn, ni, ve, 0, 0, ze, mode))
    # Every single-precision normal exponent and every table bin, at both
    # sides of the bin boundary. Every subnormal leading-bit position follows.
    for exponent in range(1, 255):
        for bin_index in range(16):
            for fraction in (bin_index << 19, ((bin_index + 1) << 19) - 1):
                raw = (exponent << 23) | fraction
                for ni in (0, 1):
                    rows.append((FRSQRTE, widen_raw(raw), exponent & 3,
                                 ni, 0, exponent & 1, (exponent >> 1) & 1,
                                 0, FINITE))
    for leading in range(23):
        for fraction in (1 << leading, (1 << (leading + 1)) - 1):
            for ni in (0, 1):
                rows.append((FRSQRTE, widen_raw(fraction), leading & 3,
                             ni, 0, 0, 0, 0, FINITE))
    for _ in range(count):
        exponent = rng.randrange(1, 255)
        fraction = rng.getrandbits(23)
        rows.append((FRSQRTE, widen_raw((exponent << 23) | fraction),
                     rng.randrange(4), rng.randrange(2),
                     rng.randrange(2), rng.randrange(2),
                     rng.randrange(2), rng.randrange(2), FINITE))
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w') as stream:
        for row in rows:
            stream.write(' '.join(format(int(item), 'x') for item in row) + '\n')
    print(f'PPC_602_RSQRT_CORPUS seed={seed:#x} random={count} '
          f'vectors={len(rows)}')


def check_one(row, observed):
    op, source, rn, ni, ve, oe, ue, ze, mode = row
    out_op, out_source, result, invalid, ox, ux, zx, xx, fr, fi, \
        frfi_valid, fprf_valid, fprf, write_result, compare_valid, fpcc = observed
    if (out_op, out_source) != (op, source):
        return 'input trace'
    expected = special(source)
    if expected is not None:
        bits, cause, zero_divide = expected
        write = not ((ve and cause) or (ze and zero_divide))
        if invalid != cause or zx != zero_divide or write_result != int(write):
            return 'special cause/write'
        if frfi_valid != int(bool(cause or zero_divide)):
            return 'special FR/FI validity'
        if frfi_valid and (fr or fi):
            return 'special FR/FI clear'
        if fprf_valid != int(write):
            return 'special FPRF validity'
        if write and (result != bits or fprf != result_class(bits)):
            return 'special result/class'
    else:
        if (invalid or ox or ux or zx or xx or frfi_valid or
                not fprf_valid or not write_result or compare_valid):
            return 'finite status'
        if result >> 63 or result == 0:
            return 'finite sign/zero'
        narrowed = calculate('to32', result, 0, fmt=B64)['bits']
        if widen_raw(narrowed) != result:
            return 'binary32 result representation'
        product = exact_value(result) ** 2 * exact_value(source)
        if not Fraction(31 * 31, 32 * 32) <= product <= Fraction(33 * 33, 32 * 32):
            return 'one-part-in-32 bound'
        if fprf != result_class(result, single=True):
            return 'finite FPRF'
    if ox or ux or xx or compare_valid or fpcc:
        return 'unaffected metadata'
    return None


def compare(vectors, results):
    rows = [tuple(int(item, 16) for item in line.split())
            for line in vectors.read_text().splitlines()]
    outputs = [tuple(int(item, 16) for item in line.split())
               for line in results.read_text().splitlines()]
    if len(rows) != len(outputs):
        raise SystemExit(f'602 estimate count mismatch {len(rows)} != {len(outputs)}')
    failures = []
    for index, (row, output) in enumerate(zip(rows, outputs)):
        reason = check_one(row, output)
        if reason:
            failures.append((index, reason, row, output))
    for index, reason, row, output in failures[:12]:
        print(f'602_RSQRT_MISMATCH index={index} reason={reason} '
              f'source={row[1]:016x} result={output[2]:016x}')
    print(f'PPC_602_RSQRT_RESULT vectors={len(rows)} mismatches={len(failures)}')
    if failures:
        raise SystemExit(1)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('generate', 'compare'))
    parser.add_argument('--vectors', type=Path, required=True)
    parser.add_argument('--results', type=Path)
    parser.add_argument('--seed', type=lambda x: int(x, 0), default=0x602f0003)
    parser.add_argument('--random', type=int, default=512)
    args = parser.parse_args()
    if args.action == 'generate':
        generate(args.vectors, args.seed, args.random)
    elif args.results is None:
        parser.error('--results is required for compare')
    else:
        compare(args.vectors, args.results)
