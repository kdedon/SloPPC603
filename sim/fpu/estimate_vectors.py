# SPDX-License-Identifier: MIT
"""Independent estimate bounds and special-result checks using integer ratios."""
import argparse
from fractions import Fraction
from pathlib import Path
import random
from reference import B32, decode, calculate

DEFAULT_NAN = 0x7ff8000000000000


def exact_value(bits):
    kind, sign, significand, exponent = decode(bits)
    if kind != 'finite':
        raise ValueError(kind)
    value = Fraction(significand << max(exponent, 0), 1 << max(-exponent, 0))
    return -value if sign else value


def generate(path, seed, count):
    rng = random.Random(seed)
    edge = [0, 1 << 63, 0x7ff0000000000000, 0xfff0000000000000,
            0x7ff0000000000001, 0x7ff8000000000123,
            0x3ff0000000000000, 0xbff0000000000000,
            0x4008000000000000, 0xc008000000000000]
    rows = [(op, value) for op in (13, 14) for value in edge]
    for op in (13, 14):
        for _ in range(count):
            sign = rng.getrandbits(1) if op == 13 else 0
            exponent = rng.randrange(80, 170)
            fraction = rng.getrandbits(23)
            raw = (sign << 31) | (exponent << 23) | fraction
            rows.append((op, calculate('to64', raw, 0, fmt=B32)['bits']))
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w') as stream:
        for op, value in rows:
            stream.write(f'{op:x} {value:016x}\n')
    print(f'ESTIMATE_CORPUS seed={seed:#x} random_per_operation={count} vectors={len(rows)}')


def check_one(op, value, result, invalid, ox, ux, zx, xx, frfi_valid, fprf):
    kind, sign, _, _ = decode(value)
    if op == 13:
        if kind in ('snan', 'qnan'):
            expected = value | (1 << 51)
            return result == expected and invalid == int(kind == 'snan') and not frfi_valid
        if kind == 'inf':
            return result == sign << 63 and invalid == 0 and not zx
        if value & 0x7fffffffffffffff == 0:
            return result == ((sign << 63) | 0x7ff0000000000000) and zx == 1
        actual_kind, actual_sign, _, _ = decode(result)
        if actual_kind != 'finite' or actual_sign != sign:
            return False
        if calculate('to64', calculate('to32', result, 0)['bits'], 0, fmt=B32)['bits'] != result:
            return False
        product = abs(exact_value(value) * exact_value(result))
        return Fraction(255, 256) <= product <= Fraction(257, 256) and invalid == 0 and not (ox or ux or zx or xx)
    if kind in ('snan', 'qnan'):
        expected = value | (1 << 51)
        return result == expected and invalid == int(kind == 'snan') and not frfi_valid
    if value & 0x7fffffffffffffff == 0:
        return result == ((sign << 63) | 0x7ff0000000000000) and zx == 1
    if sign:
        return result == DEFAULT_NAN and bool(invalid & (1 << 7))
    if kind == 'inf':
        return result == 0 and invalid == 0
    actual_kind, actual_sign, _, _ = decode(result)
    if actual_kind != 'finite' or actual_sign:
        return False
    value_product = exact_value(value) * exact_value(result) ** 2
    return Fraction(31 * 31, 32 * 32) <= value_product <= Fraction(33 * 33, 32 * 32) and invalid == 0 and not (ox or ux or zx or xx)


def compare(vectors, results):
    source = vectors.read_text().splitlines()
    observed = results.read_text().splitlines()
    if len(source) != len(observed):
        raise SystemExit(f'FAIL estimate count expected={len(source)} observed={len(observed)}')
    mismatches = 0
    for index, (a, b) in enumerate(zip(source, observed)):
        op, value = (int(item, 16) for item in a.split())
        output = [int(item, 16) for item in b.split()]
        if len(output) != 9 or output[0] != op or output[1] != value:
            raise SystemExit(f'FAIL estimate trace format vector={index}')
        _, _, result, invalid, ox, ux, zx, xx, frfi_valid = output
        if not check_one(op, value, result, invalid, ox, ux, zx, xx, frfi_valid, 0):
            mismatches += 1
            if mismatches <= 12:
                print(f'ESTIMATE_MISMATCH index={index} op={op} input={value:016x} got={result:016x} invalid={invalid:03x} flags={ox}{ux}{zx}{xx} frfi_valid={frfi_valid}')
    print(f'ESTIMATE_RESULT vectors={len(source)} mismatches={mismatches}')
    if mismatches:
        raise SystemExit('FAIL estimate bound/special qualification')
    print('PASS estimate bounds and specials')


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
