#!/usr/bin/env python3
"""Build real DingusPPC handlers and RTL, compare state, then inject mismatches."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

from compare_state import FIELDS, SCHEMA_VERSION, compare, read_trace
from reference_program import corpus

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
ROOT = PROJECT.parent


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(args, log):
    with log.open('w') as output:
        result = subprocess.run([str(x) for x in args], stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f'command failed ({result.returncode}); see {log}\n{log.read_text()[-5000:]}')


def build_reference(build, ref, *, flat_ram=False):
    runner=build/'reference_runner'
    cppargs=['g++','-std=c++20','-O2','-fwrapv','-flto','-ffunction-sections','-fdata-sections',
             '-DSUPPORTS_PPC_LITTLE_ENDIAN_MODE=0','-DSUPPORTS_MEMORY_CTRL_ENDIAN_MODE=0',
             *(['-DREFERENCE_FLAT_RAM=1'] if flat_ram else []),
             '-I'+str(ref),'-I'+str(ref/'thirdparty/loguru'),
             HERE/'reference_runner.cpp',ref/'cpu/ppc/ppcopcodes.cpp','-Wl,--gc-sections','-o',runner]
    command(cppargs,build/'reference-build.log')
    return runner,cppargs


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--build-dir',type=Path,default=Path('/tmp/ppc603e-reference-build'))
    ap.add_argument('--reference',type=Path,default=ROOT/'dingusppc')
    ap.add_argument('--model',choices=['MPC603EV','MPC603E'],default='MPC603EV')
    args=ap.parse_args()
    build=args.build_dir.resolve(); build.mkdir(parents=True,exist_ok=True)
    (build/'manifest.json').unlink(missing_ok=True)
    ref=args.reference.resolve()
    runner,cppargs=build_reference(build,ref)
    words, coverage=corpus()
    program=build/'program.hex'
    program.write_text(''.join(f'{w:08x}\n' for w in words))
    expected=build/'expected.txt'; actual=build/'actual.txt'
    command([runner,program,args.model],expected)
    rows=read_trace(expected)
    # Metadata only inventories exercised encodings; it supplies no expected
    # arithmetic, flags or state. Original handlers remain the state oracle.
    isa_path=PROJECT/'sim/spec/isa.json'
    entries=json.loads(isa_path.read_text())['decode_entries']
    executed={row[1] for row in rows}
    covered=sorted(e['id'] for e in entries if any(
        word & int(e['mask'],16) == int(e['value'],16) for word in executed))
    uncovered_nonmemory=sorted(e['id'] for e in entries if e['implementation']['status']=='implemented'
                              and e['unit']!='LSU' and e['id'] not in covered)
    if uncovered_nonmemory:
        raise RuntimeError(f'implemented non-memory forms not exercised: {uncovered_nonmemory}')
    sources=[(PROJECT/'sim'/line).resolve() for line in (PROJECT/'rtl/files.f').read_text().splitlines() if line.strip()]
    bench=PROJECT/'tb/tb_core_reference.sv'
    rtlargs=['verilator','--binary','--timing','--assert','-Wall','--top-module','tb_core_reference',
             '--Mdir',build/'rtl',*sources,bench]
    command(rtlargs,build/'rtl-build.log')
    command([build/'rtl/Vtb_core_reference',f'+PROGRAM={program}',f'+TRACE={actual}',
             f'+WORDS={len(words)}',f'+COMMITS={len(rows)}'],build/'rtl-run.log')
    compare(rows,read_trace(actual))
    # Invoke the SAME public comparator against the REAL actual RTL trace.
    command([sys.executable,HERE/'compare_state.py',expected,actual],build/'compare.log')
    negatives=[]
    for field in ['pc','insn','gpr0','gpr3','cr','xer','lr','ctr']:
        altered=[list(row) for row in rows]
        index=len(rows)//2
        altered[index][FIELDS.index(field)] ^= 1
        corrupt=build/f'injected-{field}.txt'
        corrupt.write_text(''.join(' '.join(f'{v:08x}' for v in row)+'\n' for row in altered))
        result=subprocess.run([sys.executable,HERE/'compare_state.py',corrupt,actual],capture_output=True,text=True)
        if result.returncode != 1 or f' {field}:' not in result.stderr:
            raise RuntimeError(f'injected {field} mismatch was not correctly diagnosed: {result}')
        negatives.append(result.stderr.strip())
        corrupt.unlink()
    for name,content,diagnostic in [
        ('truncated',actual.read_text().rsplit('\n',2)[0]+'\n','missing retirement'),
        ('extra',actual.read_text()+actual.read_text().splitlines()[-1]+'\n','extra retirement'),
        ('malformed','xxxxxxxx\n','malformed'),('empty','','empty trace')]:
        corrupt=build/f'injected-{name}.txt'; corrupt.write_text(content)
        result=subprocess.run([sys.executable,HERE/'compare_state.py',expected,corrupt],capture_output=True,text=True)
        if result.returncode != 1 or diagnostic not in result.stderr:
            raise RuntimeError(f'injected {name} trace was not correctly diagnosed: {result}')
        negatives.append(result.stderr.strip())
        corrupt.unlink()
    # Unsupported/reserved gates are exercised in the real execution binary.
    rejects={'undefined':0,'memory':32<<26,'divide-zero':(31<<26)|(491<<1),
             'neg-rb':(31<<26)|(1<<11)|(104<<1),'compare-L':(11<<26)|(1<<21),
             'reserved-BO':(16<<26)|(31<<21)|4,'bcctr-count':(19<<26)|(528<<1),
             'cntlzw-rb':(31<<26)|(1<<11)|(26<<1),
             'extsb-rb':(31<<26)|(1<<11)|(954<<1),
             'extsh-rb':(31<<26)|(1<<11)|(922<<1),
             'mfcr-reserved':(31<<26)|(1<<11)|(19<<1),
             'mtcrf-reserved':(31<<26)|(1<<20)|(144<<1),
             'mcrf-reserved':(19<<26)|(1<<16),
             'mcrxr-reserved':(31<<26)|(1<<21)|(512<<1),
             'mfspr-xer':(31<<26)|(1<<16)|(339<<1),
             'mtspr-xer':(31<<26)|(1<<16)|(467<<1),
             'spr-reserved-rc':(31<<26)|(8<<16)|(467<<1)|1}
    rejects.update({
        'mulhw-reserved-oe':(31<<26)|(1<<10)|(75<<1),
        'mulhwu-reserved-oe':(31<<26)|(1<<10)|(11<<1),
        'mfcr-rc':(31<<26)|(19<<1)|1,
        'mtcrf-rc':(31<<26)|(144<<1)|1,
        'mtcrf-reserved-bit11':(31<<26)|(1<<11)|(144<<1),
        'mcrf-rc':(19<<26)|1,
        'mcrf-reserved-bf':(19<<26)|(1<<21),
        'mcrf-reserved-rb':(19<<26)|(1<<11),
        'mcrxr-rc':(31<<26)|(512<<1)|1,
        'mcrxr-reserved-ra':(31<<26)|(1<<16)|(512<<1),
        'mfspr-reserved-rc':(31<<26)|(9<<16)|(339<<1)|1,
        'mfspr-other-spr':(31<<26)|(10<<16)|(339<<1),
        'mtspr-other-spr':(31<<26)|(10<<16)|(467<<1)})
    for name,word in rejects.items():
        bad=build/'reject.hex'; bad.write_text(f'{word:08x}\n')
        result=subprocess.run([str(runner),str(bad)],capture_output=True,text=True)
        if result.returncode != 2 or result.stdout:
            raise RuntimeError(f'unsupported gate failed: {name}')
    # Undefined-result divides are valid encodings, so gate them using LIVE
    # operands after real setup instructions. Never mask the output mismatch.
    undefined_divides=[]
    for unsigned,xo in [(False,491),(True,459)]:
        for oe in range(2):
            for rc in range(2):
                for kind,setup in [('zero',[0x38600007,0x38800000])] + (
                        [] if unsigned else [('overflow',[0x3c608000,0x3880ffff])]):
                    word=(31<<26)|(5<<21)|(3<<16)|(4<<11)|(oe<<10)|(xo<<1)|rc
                    bad=build/'reject.hex'; bad.write_text(''.join(f'{w:08x}\n' for w in setup+[word]))
                    result=subprocess.run([str(runner),str(bad)],capture_output=True,text=True)
                    if result.returncode != 2 or 'undefined divide result at PC 8' not in result.stderr or len(result.stdout.splitlines()) != 2:
                        raise RuntimeError(f'undefined divide gate failed: {kind}, OE={oe}, Rc={rc}')
                    undefined_divides.append(f'{"divwu" if unsigned else "divw"}/{kind}/oe{oe}/rc{rc}')
    result=subprocess.run([str(runner),str(program),'MPC602'],capture_output=True,text=True)
    if result.returncode != 2 or result.stdout:
        raise RuntimeError('unsupported model gate failed')
    (build/'reject.hex').unlink()
    original=[ref/'cpu/ppc/ppcopcodes.cpp',ref/'cpu/ppc/ppcemu.h',ref/'cpu/ppc/ppcmmu.h',
              ref/'LICENSE',ref/'CREDITS.md']
    adapter=[HERE/name for name in ['reference_runner.cpp','run_reference.py','reference_program.py','compare_state.py']]
    manifest={'schema_version':SCHEMA_VERSION,'reference':'DingusPPC original opcode handlers',
              'reference_commit':subprocess.check_output(['git','-C',str(ref),'rev-parse','HEAD'],text=True).strip(),
              'reference_dirty':subprocess.check_output(['git','-C',str(ref),'status','--porcelain'],text=True).splitlines(),
              'model':args.model,'pvr':'00070101' if args.model=='MPC603EV' else '00060101',
              'include_601':False,'ppc_le':False,'memory_controller_le':False,
              'initial_state':'zero GPR/CR/XER/LR/CTR, PC=0; PVR only model metadata',
              'snapshot_fields':FIELDS,'license':'GPL-3.0-or-later; see copied reference LICENSE',
              'compiler':subprocess.check_output(['g++','--version'],text=True).splitlines()[0],
              'verilator':subprocess.check_output(['verilator','--version'],text=True).strip(),
              'compile_commands':[[str(x) for x in cppargs],[str(x) for x in rtlargs]],
              'sha256':{str(p):digest(p) for p in original+adapter+sources+[bench,runner,program,expected,actual,isa_path]},
              'program_words':len(words),'snapshots':len(rows),'corpus_encoding_groups':coverage,
              'metadata_form_coverage':{'covered':covered,'uncovered_nonmemory':uncovered_nonmemory,
                'uncovered':sorted(e['id'] for e in entries if e['id'] not in covered)},
              'injected_mismatch_diagnostics':negatives,'rejected_cases':list(rejects)+undefined_divides+['MPC602'],
              'comparison':'PASS','limits':['handler-only dispatch','no full-machine initialization',
                'no memory/MMU/FP/exception/timing comparison','undefined-result divides rejected before original handler',
                'only LR/CTR SPR access; current RTL excludes XER moves',
                'zero initial CR1-7/XER reserved bits; CR fields later set by real instructions']}
    shutil.copyfile(ref/'LICENSE',build/'DINGUSPPC-LICENSE')
    shutil.copyfile(ref/'CREDITS.md',build/'DINGUSPPC-CREDITS.md')
    (build/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'PASS real DingusPPC vs RTL: {len(rows)} snapshots, {len(coverage)} encoding groups; '
          f'{len(negatives)} injected mismatches and {len(rejects)+len(undefined_divides)+1} unsupported gates detected')
    print(f'Metadata reconciliation: {len(covered)} forms covered; missing non-memory={uncovered_nonmemory}')
    print(f'Artifacts: {build}')


if __name__ == '__main__':
    try:
        main()
    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as error:
        sys.exit(str(error))
