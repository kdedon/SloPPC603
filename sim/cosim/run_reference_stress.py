#!/usr/bin/env python3
"""Reproducible multi-seed v2 stress, one reference/RTL build per invocation."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
from compare_memory import FIELDS, HEADER, read_trace
from compare_state import compare
from run_reference import HERE, PROJECT, ROOT, build_reference, command, digest
from stress_program import GENERATOR_VERSION, MIN_BLOCKS, MAX_BLOCKS, generate


def parse_seeds(value):
    try: seeds=[int(token,16) for token in value.split(',')]
    except ValueError as error: raise argparse.ArgumentTypeError('seeds must be comma-separated hexadecimal uint32 values') from error
    if not 1<=len(seeds)<=32 or len(set(seeds))!=len(seeds) or any(not 0<=s<=0xffffffff for s in seeds):
        raise argparse.ArgumentTypeError('supply1..32 distinct uint32 seeds')
    return seeds


def memory_access(word):
    primary=word>>26;xo=(word>>1)&1023
    memory=32<=primary<=45 or (primary==31 and xo in {23,55,87,119,151,183,215,247,279,311,343,375,407,439})
    write=primary in {36,37,38,39,44,45} or (primary==31 and xo in {151,183,215,247,407,439})
    return int(memory),int(write)


def source_inputs(ref,sources,bench):
    files=[ref/'cpu/ppc/ppcopcodes.cpp',ref/'LICENSE',ref/'CREDITS.md',*sources,bench,PROJECT/'rtl/files.f',PROJECT/'sim/spec/isa.json']
    # Pin all local reference headers, not only directly included headers.
    files.extend(sorted(ref.rglob('*.h')))
    files.extend(HERE/name for name in ['reference_runner.cpp','run_reference.py','compare_state.py',
                                      'compare_memory.py','stress_program.py','run_reference_stress.py'])
    return {str(path):digest(path) for path in files}


def run_suite(args):
    build=args.build_dir.resolve();build.mkdir(parents=True,exist_ok=True)
    (build/args.report_name).unlink(missing_ok=True)
    ref=ROOT/'dingusppc';bench=PROJECT/'tb/tb_core_memory_reference.sv'
    sources=[(PROJECT/'sim'/line).resolve() for line in (PROJECT/'rtl/files.f').read_text().splitlines() if line.strip()]
    inputs=source_inputs(ref,sources,bench)
    runner=build/'reference_runner';rtl=build/'rtl/Vtb_core_memory_reference'
    build_path=build/'build-manifest.json'
    if args.reuse_build:
        frozen=json.loads(build_path.read_text())
        if frozen['inputs']!=inputs or frozen['executables']!={str(p):digest(p) for p in [runner,rtl]}:
            raise RuntimeError('reuse-build inputs/binaries changed; rebuild to obtain trustworthy provenance')
    else:
        runner,cppargs=build_reference(build,ref,flat_ram=True)
        rtlargs=['verilator','--binary','--timing','--assert','-Wall','--top-module','tb_core_memory_reference',
                 '--Mdir',build/'rtl',*sources,bench]
        command(rtlargs,build/'rtl-build.log')
        if source_inputs(ref,sources,bench)!=inputs:
            raise RuntimeError('sources changed during compile; rerun after source freeze')
        frozen={'inputs':inputs,'executables':{str(p):digest(p) for p in [runner,rtl]},
                'commands':[[str(x) for x in cppargs],[str(x) for x in rtlargs]],
                'reference_commit':subprocess.check_output(['git','-C',str(ref),'rev-parse','HEAD'],text=True).strip(),
                'reference_dirty':subprocess.check_output(['git','-C',str(ref),'status','--porcelain'],text=True).splitlines(),
                'compiler':subprocess.check_output(['g++','--version'],text=True).splitlines()[0],
                'verilator':subprocess.check_output(['verilator','--version'],text=True).strip()}
        build_path.write_text(json.dumps(frozen,indent=2)+'\n')
    shutil.copyfile(ref/'LICENSE',build/'DINGUSPPC-LICENSE');shutil.copyfile(ref/'CREDITS.md',build/'DINGUSPPC-CREDITS.md')
    entries=json.loads((PROJECT/'sim/spec/isa.json').read_text())['decode_entries']
    results=[];aggregate=Counter();total=0
    try:
        for seed in args.seeds:
            directory=build/f'seed-{seed:08x}-blocks-{args.blocks}';directory.mkdir(exist_ok=True)
            manifest_path=directory/'manifest.json';manifest_path.unlink(missing_ok=True)
            words,description=generate(seed,args.blocks)
            program=directory/'program.hex';program.write_text(''.join(f'{word:08x}\n' for word in words))
            (directory/'program.json').write_text(json.dumps(description,indent=2)+'\n')
            expected=directory/'expected.txt';actual=directory/'actual.txt'
            repro=[sys.executable,HERE/'run_reference_stress.py','--build-dir',build,'--reuse-build',
                   '--seeds',f'{seed:08x}','--blocks',str(args.blocks),'--report-name',args.report_name]
            report={'seed':f'{seed:08x}','blocks':args.blocks,'generator_version':GENERATOR_VERSION,
                    'schema_version':2,'model':'MPC603EV','ram_base':'00001000','ram_bytes':256,
                    'program_words':len(words),'program_sha256':digest(program),
                    'build_manifest_sha256':digest(build_path),'reproduce':shlex.join(map(str,repro)),'status':'RUNNING'}
            report['commands']=[[str(runner),str(program),'MPC603EV']]
            rows=[]
            try:
                command([runner,program,'MPC603EV'],expected);rows=read_trace(expected)
                requests=sum(memory_access(r[1])[0] for r in rows)
                writes=sum(memory_access(r[1])[1] for r in rows)
                rtl_command=[rtl,f'+PROGRAM={program}',f'+TRACE={actual}',f'+WORDS={len(words)}',
                             f'+COMMITS={len(rows)}',f'+MEMORY_REQUESTS={requests}',f'+MEMORY_WRITES={writes}']
                report['commands'].append(list(map(str,rtl_command)))
                command(rtl_command,directory/'rtl-run.log')
                compare(rows,read_trace(actual),fields=FIELDS)
                command([sys.executable,HERE/'compare_memory.py',expected,actual],directory/'compare.log')
                forms=Counter();kinds=Counter();outcomes=Counter();nonsequential=0;backward=0
                for index,row in enumerate(rows):
                    matched=[e['id'] for e in entries if row[1]&int(e['mask'],16)==int(e['value'],16)]
                    if len(matched)!=1: raise RuntimeError(f'executed instruction {row[1]:08x} has {len(matched)} metadata matches')
                    forms[matched[0]]+=1;kinds[description['instructions'][row[0]//4]['kind']]+=1
                    if index+1<len(rows):
                        nonsequential+=rows[index+1][0]!=row[0]+4
                        backward+=rows[index+1][0]<row[0]
                        operation=description['instructions'][row[0]//4]['operation']
                        if operation in {'bc-forward','bdnz-loop','bcctr-forward','bclr-return'}:
                            outcome='taken' if rows[index+1][0]!=row[0]+4 else 'not-taken'
                            outcomes[f'{operation}/{outcome}']+=1
                if not requests or not writes or not backward: raise RuntimeError('required memory/backward-control coverage missing')
                # Same comparator, same actual RTL trace; independently corrupt
                # a middle architectural register and a memory byte per seed.
                injected=[]
                for column in [5,len(FIELDS)-1]:
                    altered=[list(row) for row in rows];altered[len(rows)//2][column]^=1
                    corrupt=directory/'injected.txt'
                    corrupt.write_text(HEADER+'\n'+''.join(' '.join(f'{v:08x}' for v in r)+'\n' for r in altered))
                    result=subprocess.run([sys.executable,HERE/'compare_memory.py',corrupt,actual],capture_output=True,text=True)
                    if result.returncode!=1 or f' {FIELDS[column]}:' not in result.stderr:
                        raise RuntimeError('stress mismatch injection was not diagnosed')
                    injected.append(result.stderr.strip());corrupt.unlink()
                report.update(status='PASS',snapshots=len(rows),memory_requests=requests,memory_writes=writes,
                              dynamic_forms=dict(sorted(forms.items())),dynamic_kinds=dict(sorted(kinds.items())),
                              nonsequential_edges=nonsequential,backward_edges=backward,control_outcomes=dict(sorted(outcomes.items())),
                              injected_diagnostics=injected,
                              expected_sha256=digest(expected),actual_sha256=digest(actual))
                aggregate.update(forms);total+=len(rows)
            except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as error:
                report.update(status='FAIL',error=str(error))
                match=re.search(r'row (\d+) pc=([0-9a-f]{8})',str(error))
                if match:
                    pc=int(match[2],16);index=pc//4
                    report['first_divergence']={'row':int(match[1]),'pc':match[2],
                        'instruction_context':description['instructions'][max(0,index-3):index+4]}
                manifest_path.write_text(json.dumps(report,indent=2)+'\n')
                raise RuntimeError(f'seed {seed:08x} failed: {error}\nReproduce: {report["reproduce"]}') from error
            manifest_path.write_text(json.dumps(report,indent=2)+'\n');results.append(report)
            print(f'PASS seed {seed:08x}: {len(rows)} snapshots, {len(report["dynamic_forms"])} dynamic forms, '
                  f'{report["memory_requests"]} memory accesses',flush=True)
        if source_inputs(ref,sources,bench)!=inputs: raise RuntimeError('sources changed during stress; final acceptance requires a frozen build')
        summary={'status':'PASS','schema_version':2,'generator_version':GENERATOR_VERSION,
                 'build_manifest_sha256':digest(build_path),'seeds':[r['seed'] for r in results],
                 'blocks_per_seed':args.blocks,'snapshots':total,'dynamic_forms':dict(sorted(aggregate.items())),
                 'uncovered_metadata_forms':sorted(e['id'] for e in entries if e['id'] not in aggregate),
                 'recompiled_per_seed':False,'limits':['stress coverage is not fixed168 coverage',
                  'normal flat BE RAM only','separate immutable instruction image','no MMU/SMC/fault/recovery',
                  'defined divides only','no 603e timing claim']}
        summary['seed_manifests']={str(build/f'seed-{r["seed"]}-blocks-{args.blocks}'/'manifest.json'):
                    digest(build/f'seed-{r["seed"]}-blocks-{args.blocks}'/'manifest.json') for r in results}
        (build/args.report_name).write_text(json.dumps(summary,indent=2)+'\n')
        print(f'PASS stress suite: {len(results)} seeds, {total} snapshots, {len(aggregate)} dynamic forms; artifacts {build}')
    finally:
        # Only regenerable precompiled headers under this owned build are removed.
        # Original sources, programs, traces, executable binaries and manifests remain.
        removed=[]
        for path in (build/'rtl').glob('*.gch'):
            removed.append(path.name);path.unlink()
        (build/'gch-cleanup.json').write_text(json.dumps({'removed':removed},indent=2)+'\n')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir',type=Path,default=Path('/tmp/ppc603e-reference-stress'))
    parser.add_argument('--seeds',type=parse_seeds,default=parse_seeds('603e,1,deadbeef'))
    parser.add_argument('--blocks',type=int,default=120)
    parser.add_argument('--report-name',default='suite.json',help='separate suite JSON name, e.g. maximum.json')
    parser.add_argument('--reuse-build',action='store_true',help='require exact recorded inputs/binaries; never rebuild')
    args=parser.parse_args()
    if Path(args.report_name).name!=args.report_name or not args.report_name.endswith('.json') or args.report_name in {'build-manifest.json','gch-cleanup.json'}:
        parser.error('--report-name must be a nonreserved JSON basename')
    if not MIN_BLOCKS<=args.blocks<=MAX_BLOCKS: parser.error(f'--blocks must be {MIN_BLOCKS}..{MAX_BLOCKS}')
    try:
        run_suite(args)
    finally:
        # Also clean a compilation aborted before the per-seed finally block.
        remaining=list((args.build_dir.resolve()/'rtl').glob('*.gch'))
        if remaining:
            removed=[p.name for p in remaining]
            for path in remaining: path.unlink()
            (args.build_dir.resolve()/'gch-cleanup.json').write_text(json.dumps({'removed':removed},indent=2)+'\n')


if __name__=='__main__':
    try: main()
    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as error: sys.exit(str(error))
