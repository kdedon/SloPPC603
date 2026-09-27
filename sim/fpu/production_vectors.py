# SPDX-License-Identifier: MIT
"""Raw architectural arithmetic packets from the independent PPC model."""
import argparse
from pathlib import Path
import random
from ppc_reference import arithmetic
from reference import B32, calculate

OPS = {'add': 0, 'sub': 1, 'mul': 2, 'div': 3, 'madd': 4, 'msub': 5,
       'nmadd': 6, 'nmsub': 7, 'frsp': 8, 'fctiw': 9, 'fctiwz': 10,
       'cmpu': 11, 'cmpo': 12}
THREE = {'madd', 'msub', 'nmadd', 'nmsub'}
UNARY = {'frsp', 'fctiw', 'fctiwz'}


def widen(bits):
    return calculate('to64', bits, 0, fmt=B32)['bits']


def edge_values(single):
    if single:
        base = [0, 1, 0x007fffff, 0x00800000, 0x3f000000, 0x3f800000,
                0x3f800001, 0x40000000, 0x7f7fffff, 0x7f800000,
                0x7f800001, 0x7fc00123]
        return [widen(x) for x in base + [x | 0x80000000 for x in base]]
    base = [0, 1, 0x000fffffffffffff, 0x0010000000000000,
            0x3fe0000000000000, 0x3ff0000000000000, 0x3ff0000000000001,
            0x4000000000000000, 0x7fefffffffffffff, 0x7ff0000000000000,
            0x7ff0000000000001, 0x7ff8000000000123]
    return base + [x | (1 << 63) for x in base]


def packets(ops, random_count, seed):
    rng = random.Random(seed)
    for op in ops:
        for single in (False, True):
            if single and op in ('fctiw', 'fctiwz', 'cmpu', 'cmpo'):
                continue
            edge = edge_values(single)
            cases = []
            for x in edge:
                if op in UNARY:
                    cases.append((0, x, 0, 'edge'))
                elif op == 'mul':
                    cases.extend(((x, 0, 0, 'edge'), (x, 0, edge[5], 'edge')))
                elif op in THREE:
                    cases.extend(((x, edge[5], edge[5], 'edge'),
                                  (edge[5], x, edge[5], 'edge'),
                                  (edge[5], edge[5], x, 'edge')))
                else:
                    cases.extend(((x, edge[5], 0, 'edge'), (edge[5], x, 0, 'edge')))
            if op in THREE:
                cases.append((0x3ff8000000000000, 0xbaf0000000000000,
                              0x3ff0000020000000, 'single-round'))
            if op == 'frsp':
                cases.extend((0, x, 0, 'round-boundary') for x in
                             (0x380fffffe0000000, 0x36a0000000000000,
                              0x47f0000000000000, 0x3800000000000000))
            for _ in range(random_count):
                width = 32 if single else 64
                raw = [rng.getrandbits(width) for _ in range(3)]
                if single:
                    raw = [widen(value) for value in raw]
                cases.append((*raw, 'random'))
            for rn in range(4):
                for a, b, c, kind in cases:
                    modes = [(False, False, False, False, False)]
                    if kind != 'random':
                        modes.extend(((True, False, False, False, False),
                                      (False, True, False, False, False),
                                      (False, False, True, False, False),
                                      (False, False, False, True, False)))
                    for ve, oe, ue, ze, ni in modes:
                        expected = arithmetic(op, a, b, c, rn, single, ni, ve, oe, ue, ze)
                        mask = 0 if not expected['write_result'] else 0xffffffff if op in ('fctiw', 'fctiwz') else (1 << 64) - 1
                        yield dict(op=op, code=OPS[op], a=a, b=b, c=c, rn=rn,
                                   single=int(single), ni=int(ni), ve=int(ve),
                                   oe=int(oe), ue=int(ue), ze=int(ze), kind=kind,
                                   expected=expected, result_mask=mask)


def generate(path, ops, random_count, seed):
    rows = list(packets(ops, random_count, seed))
    fields = ('code', 'a', 'b', 'c', 'rn', 'single', 'ni', 've', 'oe', 'ue', 'ze')
    results = ('result', 'write_result', 'invalid', 'ox', 'ux', 'zx', 'xx',
               'fr', 'fi', 'frfi_valid', 'fprf', 'fprf_valid', 'fpcc', 'compare_valid')
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('w') as out:
        for row in rows:
            values = [row[name] for name in fields] + [row['expected'][name] for name in results] + [row['result_mask']]
            out.write(' '.join(format(int(value), 'x') for value in values) + '\n')
    print(f'PPC_CORPUS seed={seed:#x} random_per_operation_precision={random_count} vectors={len(rows)} ops={",".join(ops)}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--vectors', type=Path, required=True)
    parser.add_argument('--seed', type=lambda value: int(value, 0), default=0x603ef002)
    parser.add_argument('--random', type=int, default=128)
    parser.add_argument('--ops', nargs='+', choices=OPS, default=list(OPS))
    args = parser.parse_args()
    generate(args.vectors, args.ops, args.random, args.seed)
