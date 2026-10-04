# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Strict version-1 architectural trace comparator, shared by real/negative runs."""
import argparse
from pathlib import Path
import re

SCHEMA_VERSION = 1
FIELDS = ['pc', 'insn'] + [f'gpr{i}' for i in range(32)] + ['cr','xer','lr','ctr']


class Mismatch(ValueError):
    pass


def read_trace(path):
    rows = []
    for lineno, line in enumerate(Path(path).read_text().splitlines(), 1):
        tokens = line.split()
        if len(tokens) != len(FIELDS) or any(not re.fullmatch(r'[0-9a-fA-F]{8}', t) for t in tokens):
            raise Mismatch(f'{path}:{lineno}: malformed v{SCHEMA_VERSION} trace (expected 38 hex32 fields)')
        rows.append(tuple(int(t,16) for t in tokens))
    if not rows:
        raise Mismatch(f'{path}: empty trace')
    return rows


def removable_branch(insn):
    """b, bc, bclr or bcctr without LK or a CTR decrement (UM 6.3.1)."""
    op, xo = insn >> 26, (insn >> 1) & 1023
    branch = op in (16, 18) or (op == 19 and xo in (16, 528))
    return branch and not insn & 1 and (op == 18 or bool(insn >> 23 & 1))


def compare(expected, actual, *, fields=FIELDS):
    """Rows match in order. The RTL may remove a branch at dispatch, which
    then has no row: an expected removable branch the actual row does not
    match is skipped. Returns the number skipped."""
    removed, j = 0, 0
    kept = []
    for e in expected:
        if j < len(actual) and actual[j][0] != e[0] and removable_branch(e[1]):
            removed += 1
            continue
        kept.append(e)
        j += 1
    expected = kept
    for index,(e,a) in enumerate(zip(expected,actual)):
        if len(e) != len(fields) or len(a) != len(fields):
            raise Mismatch(f'row {index}: invalid field count')
        for field,ev,av in zip(fields,e,a):
            if ev != av:
                raise Mismatch(f'row {index} pc={e[0]:08x} {field}: expected={ev:08x} actual={av:08x}')
    if len(expected) != len(actual):
        index = min(len(expected),len(actual))
        row = expected[index] if len(expected) > len(actual) else actual[index]
        kind = 'missing' if len(expected) > len(actual) else 'extra'
        raise Mismatch(f'row {index} pc={row[0]:08x}: {kind} retirement; '
                       f'row count expected={len(expected)} actual={len(actual)}')
    return removed


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('expected',type=Path)
    parser.add_argument('actual',type=Path)
    args=parser.parse_args()
    try:
        expected=read_trace(args.expected)
        removed=compare(expected,read_trace(args.actual))
    except (OSError,ValueError) as error:
        parser.exit(1,f'MISMATCH: {error}\n')
    print(f'PASS: {len(expected)} architectural snapshots, {len(FIELDS)} fields each, '
          f'{removed} removed branches')


if __name__ == '__main__':
    main()
