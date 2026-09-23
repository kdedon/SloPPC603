#!/usr/bin/env python3
"""Original load/store handlers + bounded flat RAM vs actual core, v2 trace."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
from compare_state import compare
from compare_memory import FIELDS, HEADER, RAM_BASE, RAM_BYTES, read_trace
from memory_program import corpus, FORMS
from run_reference import HERE, PROJECT, ROOT, build_reference, command, digest


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--build-dir',type=Path,default=Path('/tmp/ppc603e-memory-reference-build'))
    args=ap.parse_args();build=args.build_dir.resolve();build.mkdir(parents=True,exist_ok=True)
    (build/'manifest.json').unlink(missing_ok=True)
    ref=ROOT/'dingusppc'
    runner,cppargs=build_reference(build,ref,flat_ram=True)
    words,groups=corpus();program=build/'program.hex'
    program.write_text(''.join(f'{w:08x}\n' for w in words))
    expected=build/'expected.txt';actual=build/'actual.txt'
    command([runner,program,'MPC603EV'],expected)
    rows=read_trace(expected)
    def memory_access(word):
        primary=word>>26;xo=(word>>1)&1023
        memory=(32<=primary<=45) or (primary==31 and xo in {23,55,87,119,151,183,215,247,279,311,343,375,407,439})
        write=primary in {36,37,38,39,44,45} or (primary==31 and xo in {151,183,215,247,407,439})
        return int(memory),int(write)
    memory_requests=sum(memory_access(r[1])[0] for r in rows)
    memory_writes=sum(memory_access(r[1])[1] for r in rows)
    sources=[(PROJECT/'sim'/line).resolve() for line in (PROJECT/'rtl/files.f').read_text().splitlines() if line.strip()]
    bench=PROJECT/'tb/tb_core_memory_reference.sv'
    rtlargs=['verilator','--binary','--timing','--assert','-Wall','--top-module','tb_core_memory_reference',
             '--Mdir',build/'rtl',*sources,bench]
    command(rtlargs,build/'rtl-build.log')
    command([build/'rtl/Vtb_core_memory_reference',f'+PROGRAM={program}',f'+TRACE={actual}',
             f'+WORDS={len(words)}',f'+COMMITS={len(rows)}',
             f'+MEMORY_REQUESTS={memory_requests}',f'+MEMORY_WRITES={memory_writes}'],build/'rtl-run.log')
    compare(rows,read_trace(actual),fields=FIELDS)
    command([sys.executable,HERE/'compare_memory.py',expected,actual],build/'compare.log')
    isa_path=PROJECT/'sim/spec/isa.json';entries=json.loads(isa_path.read_text())['decode_entries']
    executed={r[1] for r in rows}
    covered=sorted(e['id'] for e in entries if any(w&int(e['mask'],16)==int(e['value'],16) for w in executed))
    uncovered=[e['id'] for e in entries if e['implementation']['status']=='implemented' and e['id'] not in covered]
    if uncovered: raise RuntimeError(f'implemented forms not executed: {uncovered}')
    negative=[]
    # Corrupt actual new memory and update-register data through public v2 CLI.
    update_index=next(i for i,r in enumerate(rows) if r[1]>>26==33)
    for field,bit,index in [('gpr4',0,update_index),('gpr3',0,update_index),
                            ('cr',0,update_index),('xer',29,update_index)]+[
                            (f'ram[{RAM_BASE:08x}]',bit,len(rows)-1) for bit in [0,8,16,24]]+[
                            (f'ram[{RAM_BASE+RAM_BYTES-4:08x}]',0,len(rows)-1)]:
        altered=[list(r) for r in rows];altered[index][FIELDS.index(field)]^=1<<bit
        bad=build/'injected.txt';bad.write_text(HEADER+'\n'+''.join(' '.join(f'{v:08x}' for v in r)+'\n' for r in altered))
        result=subprocess.run([sys.executable,HERE/'compare_memory.py',bad,actual],capture_output=True,text=True)
        if result.returncode!=1 or f' {field}:' not in result.stderr: raise RuntimeError(f'missed v2 mutation {field}/{bit}')
        negative.append(result.stderr.strip())
    for name,contents,diagnostic in [('v1',' '.join(['00000000']*38)+'\n','schema header'),
                                    ('empty',HEADER+'\n','empty v2'),
                                    ('truncated',actual.read_text().rsplit('\n',2)[0]+'\n','missing retirement'),
                                    ('short-row',HEADER+'\n'+' '.join(['00000000']*101)+'\n','malformed v2')]:
        bad.write_text(contents)
        result=subprocess.run([sys.executable,HERE/'compare_memory.py',expected,bad],capture_output=True,text=True)
        if result.returncode!=1 or diagnostic not in result.stderr: raise RuntimeError(f'missed v2 structural mutation {name}')
        negative.append(result.stderr.strip())
    bad.unlink()
    # Static legality gates: all14 update forms forbid RA0; all8 update loads
    # also forbid RA=RT; every indexed form forbids Rc1.
    rejected=[]
    def reject(name,program_words,diagnostic,successful_prefix=0):
        bad=build/'reject.hex';bad.write_text(''.join(f'{w:08x}\n' for w in program_words))
        result=subprocess.run([str(runner),str(bad)],capture_output=True,text=True)
        if result.returncode!=2 or diagnostic not in result.stderr: raise RuntimeError(f'missed reject {name}: {result.stderr}')
        lines=result.stdout.splitlines()
        if successful_prefix and (len(lines)!=successful_prefix+1 or lines[0]!=HEADER):
            raise RuntimeError(f'partial/failed operation emitted state for {name}')
        if not successful_prefix and lines: raise RuntimeError(f'static rejection emitted trace for {name}')
        rejected.append(name)
    for name,op,xo,size,load in FORMS:
        for indexed in range(2):
            label=name+'u'+('x' if indexed else '')
            def encode(rt,ra):
                return ((31<<26)|(rt<<21)|(ra<<16)|(5<<11)|((xo+32)<<1)) if indexed else (((op+1)<<26)|(rt<<21)|(ra<<16))
            reject(label+'/ra0',[encode(3,0)],'unsupported or reserved')
            if load: reject(label+'/ra=rt',[encode(3,3)],'unsupported or reserved')
            if indexed:
                for update in range(2):
                    reject(name+('u' if update else '')+'x/rc1',[(31<<26)|(3<<21)|(4<<16)|(5<<11)|((xo+32*update)<<1)|1],'unsupported or reserved')
        # Source computes address from real setup, service rejects before any
        # load/update register write or partial store mutation can complete.
        for address in [0x0fff,0x1100]:
            for update in range(2):
                word=((op+update)<<26)|(3<<21)|(4<<16)
                setup=[0x38800000|address]
                diagnostic='misaligned' if address%size else 'outside range'
                reject(name+('u' if update else '')+f'/outside-{address:x}',setup+[word],diagnostic,1)
        if size>1:
            reject(name+'/misaligned',[0x38801001,(op<<26)|(3<<21)|(4<<16)],'misaligned',1)
    (build/'reject.hex').unlink()
    original=[ref/'cpu/ppc/ppcopcodes.cpp',ref/'cpu/ppc/ppcemu.h',ref/'cpu/ppc/ppcmmu.h',ref/'LICENSE',ref/'CREDITS.md']
    adapter=[HERE/name for name in ['reference_runner.cpp','run_reference.py','run_memory_reference.py','memory_program.py',
                                   'reference_program.py','compare_memory.py','compare_state.py']]
    manifest={'schema_version':2,'header':HEADER,'snapshot_fields':FIELDS,'model':'MPC603EV','pvr':'00070101',
              'ppc_le':False,'memory_controller_le':False,'backend':'flat big-endian service; no original MMU',
              'ram_base':RAM_BASE,'ram_bytes':RAM_BYTES,'instruction_image':'separate immutable Harvard image',
              'initial_state':'zero GPR/CR/XER/LR/CTR and RAM; PC0; real instruction initialization',
              'reference_commit':subprocess.check_output(['git','-C',str(ref),'rev-parse','HEAD'],text=True).strip(),
              'reference_dirty':subprocess.check_output(['git','-C',str(ref),'status','--porcelain'],text=True).splitlines(),
              'compiler':subprocess.check_output(['g++','--version'],text=True).splitlines()[0],
              'verilator':subprocess.check_output(['verilator','--version'],text=True).strip(),
              'compile_commands':[[str(x) for x in cppargs],[str(x) for x in rtlargs]],
              'sha256':{str(p):digest(p) for p in original+adapter+sources+[bench,runner,program,expected,actual,isa_path]},
              'program_words':len(words),'snapshots':len(rows),'encoding_groups':groups,'covered_forms':covered,
              'memory_requests':memory_requests,'memory_writes':memory_writes,
              'uncovered_forms':uncovered,'negative_diagnostics':negative,'rejected_cases':rejected,'comparison':'PASS',
              'limits':['no MMU/cache/60x bus','no faults/recovery/SMC','reserved-XER bits unseeded','undefined divides rejected'],
              'license':'GPL-3.0-or-later; original notices/license retained'}
    shutil.copyfile(ref/'LICENSE',build/'DINGUSPPC-LICENSE');shutil.copyfile(ref/'CREDITS.md',build/'DINGUSPPC-CREDITS.md')
    (build/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print(f'PASS memory reference: {len(rows)} snapshots, {len(covered)} forms, full256-byte RAM; '
          f'{len(negative)} negative comparisons, {len(rejected)} rejection gates')
    print(f'Artifacts: {build}')


if __name__=='__main__':
    try: main()
    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as error: sys.exit(str(error))
