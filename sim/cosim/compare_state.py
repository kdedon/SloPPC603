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


def compare(expected, actual, *, fields=FIELDS):
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


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('expected',type=Path)
    parser.add_argument('actual',type=Path)
    args=parser.parse_args()
    try:
        expected=read_trace(args.expected)
        compare(expected,read_trace(args.actual))
    except (OSError,ValueError) as error:
        parser.exit(1,f'MISMATCH: {error}\n')
    print(f'PASS: {len(expected)} architectural snapshots, {len(FIELDS)} fields each')


if __name__ == '__main__':
    main()
