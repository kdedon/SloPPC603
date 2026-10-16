#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Preserve the reproducing symbolic prefix without false-hazard extensions."""
import argparse
from pathlib import Path
from control_memory_program import make_program
p=argparse.ArgumentParser(); p.add_argument('--output',type=Path,required=True)
a=p.parse_args(); program=make_program()
assert program.encode(0x198,*program.ops[0x198//4])==0x418e0009
assert program.encode(0x19c,*program.ops[0x19c//4])==0
assert program.encode(0x1a0,*program.ops[0x1a0//4])==0x7ea802a6
rows,counts=program.simulate(limit=10000)
a.output.mkdir(parents=True,exist_ok=True)
(a.output/'program.hex').write_text(''.join(f'{program.encode(i*4,*op):08x}\n' for i,op in enumerate(program.ops)))
(a.output/'expected.txt').write_text(''.join(' '.join(f'{v:08x}' for v in row)+'\n' for row in rows))
(a.output/'fold.hex').write_text(''.join(f'{pc:08x}\n' for pc in program.folds))
(a.output/'manifest.txt').write_text(f'words={len(program.ops)} retirements={len(rows)}\n{counts}\n')
