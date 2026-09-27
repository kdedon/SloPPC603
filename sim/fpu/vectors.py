# SPDX-License-Identifier: MIT
"""Deterministic raw-bit corpus and independent result comparison."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import random
from reference import B32, B64, calculate, decode

OPS = {'add': 0, 'sub': 4, 'mul': 8, 'cmp': 6, 'ftoi32': 2, 'i32tof': 3, 'convert': 11}


def causes(op, a, b, fmt, expected):
    ka, sa, ma, _ = decode(a, fmt)
    kb, sb, mb, _ = decode(b, fmt)
    snan = ka == 'snan' or (op in ('add', 'sub', 'mul', 'cmp') and kb == 'snan')
    opposite_infinities = op in ('add', 'sub') and ka == kb == 'inf' and (sa != sb if op == 'add' else sa == sb)
    zero_times_infinity = op == 'mul' and ((ka == 'inf' and kb == 'finite' and not mb) or (kb == 'inf' and ka == 'finite' and not ma))
    return int(snan) | (int(opposite_infinities) << 1) | (int(zero_times_infinity) << 2) | (int(op == 'ftoi32' and expected['invalid']) << 3)


def corners(fmt):
    unit = 1 << fmt.fraction
    values = [0, 1, 2, unit - 1, unit, unit + 1,
              (fmt.bias << fmt.fraction) - 1, fmt.bias << fmt.fraction,
              (fmt.bias << fmt.fraction) + 1, (fmt.bias + 1) << fmt.fraction,
              ((fmt.bias - fmt.fraction - 1) << fmt.fraction),
              fmt.infinity - 1, fmt.infinity, fmt.infinity | 1,
              fmt.infinity | (unit >> 1), fmt.infinity | (unit >> 1) | 0x123]
    return values + [value | (1 << fmt.signbit) for value in values]


def directed_pairs(op, fmt):
    edge = corners(fmt)
    pairs = [(a, b, 'directed') for a in edge for b in edge] if op in ('add', 'sub', 'mul', 'cmp') else [(a, 0, 'directed') for a in edge]
    if op == 'i32tof':
        pairs = [(a, 0, 'directed') for a in (0, 1, 0xffffffff, 0x7fffffff, 0x80000000, 0x01000001, 0xfeffffff)]
    if fmt == B64 and op == 'convert':
        pairs += [(a, 0, 'underflow-boundary') for a in (0x380fffffe0000000, 0x380fffffa0000000, 0x3810000010000000, 0x3690000000000000)]
    if op in ('add', 'sub', 'mul'):
        pairs += [(fmt.infinity | 0x123, fmt.infinity | (1 << (fmt.fraction - 1)) | 0x456, 'snan-payload'),
                  ((1 << fmt.signbit) | fmt.infinity | 0x123, 0, 'snan-sign')]
    return pairs


def generate(path, seed, count):
    rng = random.Random(seed)
    rows = []
    for sd, fmt in enumerate((B32, B64)):
        for op in OPS:
            for rn in range(4):
                pairs = directed_pairs(op, fmt)
                pairs += [(rng.getrandbits(32 if op == 'i32tof' else fmt.signbit + 1), rng.getrandbits(fmt.signbit + 1), 'random') for _ in range(count)]
                for a, b, kind in pairs:
                    oracle_op = ('to32' if sd else 'to64') if op == 'convert' else op
                    expected = calculate(oracle_op, a, b, rn, fmt)
                    rows.append(dict(op=op, code=OPS[op], sd=sd, sdo=1-sd if op == 'convert' else sd, rn=rn, a=a, b=b, kind=kind, expected=expected, causes=causes(op, a, b, fmt, expected)))
    with path.open('w') as out:
        for row in rows:
            out.write(json.dumps(row, separators=(',', ':')) + '\n')
    with path.with_suffix('.txt').open('w') as out:
        for row in rows:
            out.write(f"{row['code']} {row['sd']} {row['sdo']} {row['rn']} {row['a']:016x} {row['b']:016x}\n")
    print(f"CORPUS seed={seed:#x} random_per_op_mode_format={count} vectors={len(rows)}")


def compare(vectors, results, strict):
    expected = [json.loads(line) for line in vectors.read_text().splitlines()]
    actual = results.read_text().splitlines()
    if len(actual) != len(expected):
        raise SystemExit(f'FAIL count expected={len(expected)} actual={len(actual)}')
    counts, mismatches, first, first_normal = Counter(), Counter(), {}, {}
    kinds, domains, normal = Counter(), Counter(), Counter()
    fingerprint = hashlib.sha256()
    for row, line in zip(expected, actual):
        bits, flags, unf, cycles, increment, invalid_causes = [int(token, 16) for token in line.split()]
        ref = row['expected']
        ref_flags = (int(ref['invalid']) << 4) | (int(ref['of']) << 3) | (int(ref['uf']) << 2) | int(ref['nx'])
        key = f"{row['op']}.{'d' if row['sd'] else 's'}.rn{row['rn']}"
        counts[key] += 1
        if not 1 <= cycles <= 1024:
            raise SystemExit(f'FAIL latency {cycles}')
        ka = decode(row['a'], B64 if row['sd'] else B32)[0]
        kb = decode(row['b'], B64 if row['sd'] else B32)[0]
        check_increment = row['op'] in ('add', 'sub', 'mul', 'convert') and ka == 'finite' and (kb == 'finite' or row['op'] == 'convert') and not ref['of']
        bad_bits = bits != ref['bits']
        bad_flags = flags != ref_flags
        bad_unfinished = bool(unf)
        bad_causes = invalid_causes != row['causes']
        bad_increment = check_increment and increment != int(ref['increment'])
        mismatch = bad_bits or bad_flags or bad_unfinished or bad_causes or bad_increment
        normal_inputs = row['op'] == 'i32tof' or (ka == 'finite' and
                         ((row['a'] >> (B64.fraction if row['sd'] else B32.fraction)) &
                          ((1 << (B64.exponent if row['sd'] else B32.exponent)) - 1)) != 0 and
                         (row['op'] not in ('add', 'sub', 'mul', 'cmp') or
                          (kb == 'finite' and
                           ((row['b'] >> (B64.fraction if row['sd'] else B32.fraction)) &
                            ((1 << (B64.exponent if row['sd'] else B32.exponent)) - 1)) != 0)))
        if normal_inputs:
            nk = f"{row['op']}.{'d' if row['sd'] else 's'}"
            normal[nk + '.vectors'] += 1
            normal[nk + '.mismatch'] += bool(mismatch)
            normal[nk + '.bits'] += bad_bits
            normal[nk + '.flags'] += bad_flags
            if mismatch:
                first_normal.setdefault(nk, f"a={row['a']:016x} b={row['b']:016x} got={bits:016x}/{flags:02x}/inc{increment} expected={ref['bits']:016x}/{ref_flags:02x}/inc{int(ref['increment'])}")
        if mismatch:
            mismatches[key] += 1
            kinds[row['kind']] += 1
            for name, bad in (('bits', bad_bits), ('flags', bad_flags), ('unfinished', bad_unfinished),
                              ('invalid_causes', bad_causes), ('round_increment', bad_increment)):
                domains[name] += bool(bad)
            fingerprint.update(f"{key}:{row['a']:x}:{row['b']:x}:{bits:x}:{flags:x}:{unf}:{invalid_causes}:{increment}\n".encode())
            first.setdefault(key, f"a={row['a']:016x} b={row['b']:016x} got={bits:016x}/{flags:02x}/unf{unf}/cause{invalid_causes:x}/inc{increment} expected={ref['bits']:016x}/{ref_flags:02x}/cause{row['causes']:x}/inc{int(ref['increment'])}")
    for key in sorted(counts):
        print(f"QUALIFY {key} vectors={counts[key]} match={counts[key]-mismatches[key]} mismatch={mismatches[key]}")
        if key in first:
            print(f'FIRST {key} {first[key]}')
    total = sum(mismatches.values())
    print(f"RESULT vectors={len(expected)} match={len(expected)-total} mismatch={total} groups={len(counts)} mismatch_sha256={fingerprint.hexdigest()}")
    print('MISMATCH_KINDS ' + ' '.join(f'{kind}={n}' for kind, n in sorted(kinds.items())))
    print('MISMATCH_DOMAINS ' + ' '.join(f'{kind}={n}' for kind, n in sorted(domains.items())))
    for group in sorted({key.rsplit('.', 1)[0] for key in normal}):
        print('NORMAL_FINITE ' + group + ' ' + ' '.join(f'{field}={normal[group + "." + field]}'
              for field in ('vectors', 'mismatch', 'bits', 'flags')))
        if group in first_normal:
            print('NORMAL_FIRST ' + group + ' ' + first_normal[group])
    if strict and total:
        raise SystemExit('FAIL IEEE qualification: donor has semantic gaps')
    print('PASS characterization transport and corpus accounting' if total else 'PASS IEEE corpus')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('generate', 'compare'))
    parser.add_argument('--vectors', type=Path, required=True)
    parser.add_argument('--results', type=Path)
    parser.add_argument('--seed', type=lambda x: int(x, 0), default=0x603ef001)
    parser.add_argument('--random', type=int, default=256)
    parser.add_argument('--strict', action='store_true')
    args = parser.parse_args()
    if args.action == 'generate':
        generate(args.vectors, args.seed, args.random)
    else:
        compare(args.vectors, args.results, args.strict)
