#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Retained-stop coverage uses a real load consumer, not false branch GPR use.

All original taken/not-taken, absolute/relative and physical-lane obligations
remain mandatory in the existing control-memory observer. No DUT target helper
or source-use helper predicts the target or architectural state here.
"""
from pathlib import Path
import argparse,sys

def generate(output,tools):
    sys.path.insert(0,str(tools))
    from control_memory_program import make_branch_fold,Program
    p=make_branch_fold();insert_at=p.labels['body']//4-1
    assert p.ops[insert_at]==('illegal',())
    q=Program();e=q.emit;meta={};targets={}
    for phase in range(8):
        for _ in range(phase):e('ori',0,0,0)
        for aa in (0,1):
            for taken in (0,1):
                for lane in (0,1):
                    name=f'retained_{phase}_{aa}_{taken}_{lane}'
                    if (insert_at+len(q.ops)+7)%2!=lane:e('ori',0,0,0)
                    e('addi',6,0,100);e('addi',7,0,7)
                    e('divw',8,6,7,0,0)
                    e('addi',5,8,(2 if taken else 1)-14);e('mtctr',5)
                    e('lwz',0,1,32)
                    # This architecturally consumes r0 and blocks at the
                    # native lane's destination; BC itself consumes no GPR.
                    e('add',22,0,0)
                    branch_index=insert_at+len(q.ops)
                    meta[branch_index]=8|(taken<<2)|(aa<<1)|lane
                    targets[branch_index]=name+'_target'
                    e('bc',16,0,name+'_target',aa,0)
                    e('addi',21,21,1);e('b',name+'_join',0,0)
                    q.label(name+'_target');e('addi',21,21,2)
                    q.label(name+'_join')
                    e('mfctr',24);e('stw',24,1,32)
                    e('lwz',25,1,32);e('stw',21,1,36)
    delta=4*len(q.ops);p.ops[insert_at:insert_at]=q.ops
    p.labels={name:addr+(delta if addr>=insert_at*4 else 0) for name,addr in p.labels.items()}
    p.labels.update({name:insert_at*4+addr for name,addr in q.labels.items()})
    p.folds=[pc+(delta if pc>=insert_at*4 else 0) for pc in p.folds]
    assert len(p.ops)<=4096 and max(p.labels.values())<0x8000
    snapshots,counts=p.simulate(limit=20000);output.mkdir(parents=True,exist_ok=True)
    (output/'program.hex').write_text(''.join(f'{p.encode(i*4,*op):08x}\n' for i,op in enumerate(p.ops)))
    (output/'expected.txt').write_text(''.join(' '.join(f'{x:08x}' for x in row)+'\n' for row in snapshots))
    (output/'fold.hex').write_text(''.join(f'{pc:08x}\n' for pc in p.folds))
    (output/'manifest.txt').write_text(f'words={len(p.ops)} retirements={len(snapshots)}\n{counts}\n')
    (output/'retained_cases.hex').write_text(''.join(f'{meta.get(i,0):x}\n' for i in range(4096)))
    (output/'retained_targets.hex').write_text(''.join(f'{p.labels[targets[i]] if i in targets else 0:08x}\n' for i in range(4096)))
    print(f'Prepared retained-stop true-dependency matrix: {len(p.ops)} words, {len(snapshots)} retirements; actual coverage pending')
if __name__=='__main__':
    a=argparse.ArgumentParser();a.add_argument('--output',type=Path,required=True)
    a.add_argument('--tools-dir',type=Path,required=True);args=a.parse_args();generate(args.output,args.tools_dir)
