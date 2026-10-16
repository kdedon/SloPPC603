#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Independent symbolic architectural oracle; encoding is not RTL decode.

Extends the existing full GPR/CR/XER/LR/CTR/byte-memory oracle. Its per-PC kinds
are program intent, never copied from DUT source-use or ready predicates.
"""
from pathlib import Path
import argparse,sys

def generate(output, tools):
    sys.path.insert(0,str(tools))
    from control_memory_program import make_program,Program
    p=make_program();assert p.ops.pop()==('illegal',())
    kinds={}
    def emit(op,*args):p.emit(op,*args)
    def mark(kind,op,*args):
        kinds[len(p.ops)]=kind;emit(op,*args)
    for phase in range(8):
        # Vary front-end alignment/background without changing test intent.
        for _ in range(phase):emit('ori',31,31,0)
        for kind in range(1,7):
            emit('addi',1,0,0x1000);emit('addi',2,0,0x1357)
            # Immediate-bit B alias: 0x2800 encodes raw rB5. Real dependencies
            # use deliberately nonzero loaded values from the memory oracle.
            dst=0 if kind in (1,3,5) else 5
            emit('lwz',dst,1,4*(kind-1))
            if kind==1:mark(kind,'addi',6,0,7)
            if kind==2:mark(kind,'addi',6,2,0x2800)
            if kind==3:
                name=f'false_branch_{phase}'
                # An ordinary B may already have its fallthrough prefetched
                # before decode folds it. Require no architectural effect;
                # the inherited waiting-branch poison guards stay unchanged.
                mark(kind,'b',name,0,0);emit('addi',8,0,-1);p.label(name)
            if kind==4:mark(kind,'rlwimi',5,2,5,8,15,0)
            if kind==5:mark(kind,'add',7,0,2)
            if kind==6:mark(kind,'add',7,2,5)
            # Drain through the following store before replacing this
            # destination, then verify architectural state at every retire.
            emit('stw',6 if kind in(1,2) else 5 if kind==4 else 7,1,224)
    emit('illegal')
    snapshots,counts=p.simulate(limit=20000)
    output.mkdir(parents=True,exist_ok=True)
    (output/'program.hex').write_text(''.join(f'{p.encode(i*4,*op):08x}\n' for i,op in enumerate(p.ops)))
    (output/'expected.txt').write_text(''.join(' '.join(f'{x:08x}' for x in row)+'\n' for row in snapshots))
    (output/'fold.hex').write_text(''.join(f'{pc:08x}\n' for pc in p.folds))
    (output/'manifest.txt').write_text(f'words={len(p.ops)} retirements={len(snapshots)}\n{counts}\n')
    (output/'cases.hex').write_text(''.join(f'{kinds.get(i,0):x}\n' for i in range(4096)))
    assert set(kinds.values())==set(range(1,7))
    print(f'Prepared independent native overlap program: {len(p.ops)} words; {len(snapshots)} retirements; 8 witnesses per kind')
if __name__=='__main__':
    a=argparse.ArgumentParser();a.add_argument('--output',type=Path,required=True)
    a.add_argument('--tools-dir',type=Path,required=True);args=a.parse_args();generate(args.output,args.tools_dir)
