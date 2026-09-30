# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Shell vectors for arithmetic instructions under FPSCR enables and MSR FE.

Each case loads fr1-fr3 as sources and a sentinel into fr4, writes the whole
FPSCR with mtfsfi (all sticky bits clear; random VE/OE/UE/ZE/XE, NI and RN),
then issues one arithmetic instruction into fr4 with random FE0/FE1 and Rc.
Expectations follow PEM §3.3.6 (Tables 3-12 to 3-16) and 603e UM Table 4-1
for the 603e, and 602 UM §4.5.7.1 for the 602 emulation trap.
"""
import argparse
from pathlib import Path
import random

from cluster_vectors import CLUSTERS, Fmt, operands
from ppc_reference import arithmetic
from production_vectors import widen
from production_vectors_602 import expected_602, widen_raw
from reference import B32, calculate

# name: (primary, xo, uses a, uses b, uses c, oracle op)
AFORM = {'fdiv': (18, 'div'), 'fsub': (20, 'sub'), 'fadd': (21, 'add'),
         'fmul': (25, 'mul'), 'fmsub': (28, 'msub'), 'fmadd': (29, 'madd'),
         'fnmsub': (30, 'nmsub'), 'fnmadd': (31, 'nmadd')}
XFORM = {'frsp': (12, 'frsp'), 'fctiw': (14, 'fctiw'), 'fctiwz': (15, 'fctiwz')}
NO_EXCEPTION, FP_ENABLED, EMULATION_TRAP = 0, 5, 6
# Invalid cause bit (ppc_reference order) to physical FPSCR bit.
INVALID_BITS = (24, 23, 22, 21, 20, 19, 10, 9, 8)


def encode(name, single, rc):
    if name in AFORM:
        xo = AFORM[name][0]
        b = 0 if name == 'fmul' else 2
        c = 3 if name in ('fmul', 'fmsub', 'fmadd', 'fnmsub', 'fnmadd') else 0
        return ((59 if single else 63) << 26) | (4 << 21) | (1 << 16) | \
            (b << 11) | (c << 6) | (xo << 1) | rc
    return (63 << 26) | (4 << 21) | (2 << 11) | (XFORM[name][0] << 1) | rc


def fpscr_after(old, exp):
    new = old
    for cause, bit in enumerate(INVALID_BITS):
        if exp['invalid'] >> cause & 1:
            new |= 1 << bit
    for name, bit in (('ox', 28), ('ux', 27), ('zx', 26), ('xx', 25)):
        if exp[name]:
            new |= 1 << bit
    if exp['frfi_valid']:
        new = (new & ~(3 << 17)) | (int(exp['fr']) << 18) | (int(exp['fi']) << 17)
    if exp['fprf_valid']:
        new = (new & ~(0x1f << 12)) | (exp['fprf'] << 12)
    exceptions = sum(1 << b for b in INVALID_BITS + (28, 27, 26, 25))
    if (new & ~old) & exceptions:
        new |= 1 << 31
    vx = any(new >> b & 1 for b in INVALID_BITS)
    new = (new & ~(1 << 29)) | (int(vx) << 29)
    fex = ((vx and new >> 7 & 1) or (new >> 28 & new >> 6 & 1) or
           (new >> 27 & new >> 5 & 1) or (new >> 26 & new >> 4 & 1) or
           (new >> 25 & new >> 3 & 1))
    return (new & ~(1 << 30)) | (int(bool(fex)) << 30)


def fpscr_mask(exp, oe):
    """FR is undefined after an overflow with OE clear (PEM Table 3-14)."""
    return 0xffffffff & ~(1 << 18) if exp['ox'] and not oe else 0xffffffff


SPECIAL64 = (0x7ff0000000000001, 0x7ff8000000000000, 0x7ff0000000000000,
             0xfff0000000000000, 0, 1 << 63, 0x3ff0000000000000,
             0x7fefffffffffffff, 0x0010000000000000, 0x0000000000000001,
             0x41e0000000000000, 0xc1e0000000200000)
SPECIAL32 = (0x7f800001, 0x7fc00000, 0x7f800000, 0xff800000, 0, 0x80000000,
             0x3f800000, 0x7f7fffff, 0x00800000, 0x00000001, 0x4f000000)


def sources(oracle_op, single, rng):
    f = Fmt(single)
    special = SPECIAL32 if single else SPECIAL64
    if rng.randrange(3) == 0:
        raw = [rng.choice(special) for _ in range(3)]
    else:
        raw = list(operands(oracle_op, CLUSTERS[rng.randrange(5)], rng, f))
        if oracle_op in ('frsp', 'fctiw', 'fctiwz'):
            raw = [raw[1], raw[1], raw[1]]
        if rng.randrange(4) == 0:
            raw[rng.randrange(3)] = rng.choice(special)
    if oracle_op in ('frsp', 'fctiw', 'fctiwz'):
        raw = [f.value(0, f.bias, 0), raw[1], f.value(0, f.bias, 0)]
    if oracle_op == 'div' and rng.randrange(3) == 0:
        raw[1] = f.value(rng.getrandbits(1), 0, 0)
    return raw


def case_603(rng):
    name = rng.choice(tuple(AFORM) + tuple(XFORM))
    oracle_op = (AFORM.get(name) or XFORM[name])[1]
    single = name in AFORM and rng.getrandbits(1)
    if name == 'frsp' and rng.getrandbits(1):
        # Double sources at single-precision range edges.
        b = rng.choice((0x47efffffe0000000, 0x47f0000000000000,
                        0x380fffffe0000000, 0x36a0000000000000,
                        0x3690000000000001)) | (rng.getrandbits(1) << 63)
        a, c = 0x3ff0000000000000, 0x3ff0000000000000
    else:
        raw = sources(oracle_op, single, rng)
        a, b, c = (widen(x) for x in raw) if single else raw
    enables = rng.getrandbits(5)
    ni, rn = rng.getrandbits(1), rng.randrange(4)
    ve, oe, ue, ze, xe = ((enables >> (4 - i)) & 1 for i in range(5))
    exp = arithmetic(oracle_op, a, b, c, rn, single, ni, ve, oe, ue, ze)
    old = (enables << 3) | (ni << 2) | rn
    fe = rng.randrange(4)
    rc = rng.getrandbits(1)
    new = fpscr_after(old, exp)
    exc = FP_ENABLED if fe and new >> 30 & 1 else NO_EXCEPTION
    mask = 0xffffffff if 'fctiw' in name else (1 << 64) - 1
    return (encode(name, single, rc), a, b, c, old, fe, exc,
            int(exp['write_result']), exp['result'] & mask, mask, new,
            fpscr_mask(exp, oe), rc, new >> 28)


def narrow(bits):
    return calculate('to32', bits, 0)['bits']


def case_602(rng):
    name = rng.choice(tuple(AFORM) + ('frsp', 'fctiwz'))
    oracle_op = (AFORM.get(name) or XFORM[name])[1]
    raw = sources(oracle_op, True, rng)
    a, b, c = (widen_raw(x) for x in raw)
    enables = rng.getrandbits(5)
    ni, rn = rng.getrandbits(1), rng.randrange(4)
    ve, oe, ue, ze, xe = ((enables >> (4 - i)) & 1 for i in range(5))
    exp = expected_602(oracle_op, a, b, c, rn, ni, ve, oe, ue, ze)
    old = (enables << 3) | (ni << 2) | rn
    fe = rng.randrange(4)
    rc = rng.getrandbits(1)
    enabled = ((exp['invalid'] and ve) or (exp['ox'] and oe) or
               (exp['ux'] and ue) or (exp['zx'] and ze) or (exp['xx'] and xe))
    if enabled or (not ni and exp['tiny_before_round']):
        return (encode(name, True, rc), *raw, old, fe, EMULATION_TRAP,
                0, 0, 0xffffffff, old, 0xffffffff, 0, 0)
    new = fpscr_after(old, exp)
    value = exp['result'] & 0xffffffff if name == 'fctiwz' else narrow(exp['result'])
    return (encode(name, True, rc), *raw, old, fe, NO_EXCEPTION,
            int(exp['write_result']), value, 0xffffffff, new,
            fpscr_mask(exp, oe), rc, new >> 28)


def generate(path, personality, count, seed):
    rng = random.Random(seed)
    make = case_602 if personality == '602' else case_603
    kinds = {}
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w') as out:
        for _ in range(count):
            row = make(rng)
            kinds[row[6]] = kinds.get(row[6], 0) + 1
            out.write(' '.join(format(int(v), 'x') for v in row) + '\n')
    print(f'PPC_ENABLED_CORPUS personality={personality} seed={seed:#x} '
          f'cases={count} ' + ' '.join(f'exception{k}={v}'
                                       for k, v in sorted(kinds.items())))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--vectors', type=Path, required=True)
    parser.add_argument('--personality', choices=('603e', '602'), default='603e')
    parser.add_argument('--count', type=int, default=3000)
    parser.add_argument('--seed', type=lambda v: int(v, 0), default=0xe7ab1ed)
    args = parser.parse_args()
    generate(args.vectors, args.personality, args.count, args.seed)
