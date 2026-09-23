"""Explicit v2 full-RAM trace: v1 register fields plus 64 big-endian words."""
import argparse
from pathlib import Path
import re
from compare_state import FIELDS as REGISTER_FIELDS, Mismatch, compare

SCHEMA_VERSION=2
RAM_BASE=0x1000
RAM_BYTES=256
HEADER='#ppc-reference-v2 ram_base=00001000 ram_bytes=00000100'
FIELDS=REGISTER_FIELDS+[f'ram[{address:08x}]' for address in range(RAM_BASE,RAM_BASE+RAM_BYTES,4)]


def read_trace(path):
    lines=Path(path).read_text().splitlines()
    if not lines or lines[0] != HEADER:
        raise Mismatch(f'{path}: missing/mismatched v2 RAM schema header')
    rows=[]
    for line_number,line in enumerate(lines[1:],2):
        tokens=line.split()
        if len(tokens)!=len(FIELDS) or any(not re.fullmatch(r'[0-9a-fA-F]{8}',x) for x in tokens):
            raise Mismatch(f'{path}:{line_number}: malformed v2 trace (expected 102 hex32 fields)')
        rows.append(tuple(int(x,16) for x in tokens))
    if not rows:
        raise Mismatch(f'{path}: empty v2 trace')
    return rows


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('expected',type=Path)
    parser.add_argument('actual',type=Path)
    args=parser.parse_args()
    try:
        expected=read_trace(args.expected)
        compare(expected,read_trace(args.actual),fields=FIELDS)
    except (OSError,ValueError) as error:
        parser.exit(1,f'MISMATCH: {error}\n')
    print(f'PASS v2: {len(expected)} snapshots, all38 register fields and all256 RAM bytes')


if __name__=='__main__':
    main()
