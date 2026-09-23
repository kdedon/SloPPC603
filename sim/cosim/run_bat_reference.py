#!/usr/bin/env python3
"""Compare original handlers with the CPU using startup-programmed BAT translation to physical memory."""
import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
from compare_memory import FIELDS, HEADER, read_trace
from compare_state import compare
from memory_program import corpus
from run_reference import HERE, PROJECT, ROOT, build_reference, command, digest
from run_reference_stress import memory_access


def run(build):
    build.mkdir(parents=True, exist_ok=True)
    (build/'manifest.json').unlink(missing_ok=True)
    ref = ROOT/'dingusppc'
    lists = [PROJECT/'rtl'/name for name in
             ['files.f', 'bat_service_files.f', 'core_bat_files.f']]
    sources = list(dict.fromkeys((PROJECT/'sim'/line).resolve()
                   for file in lists for line in file.read_text().splitlines() if line.strip()))
    bench = PROJECT/'tb/tb_core_bat_reference.sv'
    isa = PROJECT/'sim/spec/isa.json'
    adapters = [HERE/name for name in ['run_bat_reference.py', 'reference_runner.cpp',
                'run_reference.py', 'run_reference_stress.py', 'memory_program.py',
                'reference_program.py', 'compare_memory.py', 'compare_state.py']]
    inputs = list(dict.fromkeys([*sources, *lists, bench, isa, *adapters,
                  ref/'cpu/ppc/ppcopcodes.cpp', ref/'LICENSE', ref/'CREDITS.md', *sorted(ref.rglob('*.h'))]))
    frozen = {str(p): digest(p) for p in inputs}
    runner, cppargs = build_reference(build, ref, flat_ram=True)
    words, groups = corpus()
    program = build/'program.hex'
    program.write_text(''.join(f'{word:08x}\n' for word in words))
    expected, actual = build/'expected.txt', build/'actual.txt'
    command([runner, program, 'MPC603EV'], expected)
    rows = read_trace(expected)
    requests = sum(memory_access(row[1])[0] for row in rows)
    writes = sum(memory_access(row[1])[1] for row in rows)
    rtlargs = ['verilator', '--binary', '--timing', '--assert', '-Wall', '--top-module',
               'tb_core_bat_reference', '--Mdir', build/'rtl', *sources, bench]
    command(rtlargs, build/'rtl-build.log')
    executable = build/'rtl/Vtb_core_bat_reference'
    rtlrun = [executable, f'+PROGRAM={program}', f'+TRACE={actual}', f'+WORDS={len(words)}',
              f'+COMMITS={len(rows)}', f'+MEMORY_REQUESTS={requests}', f'+MEMORY_WRITES={writes}']
    command(rtlrun, build/'rtl-run.log')
    compare(rows, read_trace(actual), fields=FIELDS)
    command([sys.executable, HERE/'compare_memory.py', expected, actual], build/'compare.log')
    entries = json.loads(isa.read_text())['decode_entries']
    executed = {row[1] for row in rows}
    covered = sorted(e['id'] for e in entries if any(w & int(e['mask'], 16) == int(e['value'], 16) for w in executed))
    missing = [e['id'] for e in entries if e['implementation']['status'] == 'implemented' and e['id'] not in covered]
    if missing:
        raise RuntimeError(f'BAT corpus misses implemented forms: {missing}')
    negative = []
    for field in ['gpr5', 'ram[00001000]', 'ram[000010fc]']:
        altered = [list(row) for row in rows]
        altered[len(rows)//2][FIELDS.index(field)] ^= 1
        corrupt = build/'injected.txt'
        corrupt.write_text(HEADER+'\n'+''.join(' '.join(f'{value:08x}' for value in row)+'\n' for row in altered))
        result = subprocess.run([sys.executable, HERE/'compare_memory.py', corrupt, actual], capture_output=True, text=True)
        if result.returncode != 1 or f' {field}:' not in result.stderr:
            raise RuntimeError(f'BAT trace corruption not diagnosed: {field}')
        negative.append(result.stderr.strip())
        corrupt.unlink()
    if frozen != {str(p): digest(p) for p in inputs}:
        raise RuntimeError('sources changed during BAT reference build/run; rerun after freeze')
    match = re.search(r'PASS BAT reference RTL: (.*)', (build/'rtl-run.log').read_text())
    if not match:
        raise RuntimeError('missing BAT physical-transport coverage report')
    metrics = {name: int(value) for name, value in re.findall(r'(\w+)=(\d+)', match[1])}
    artifacts = [runner, executable, program, expected, actual]
    report = {'schema_version': 2, 'translation_profile': 'startup_IBAT0_to_40000000_DBAT0_to_80000000', 'comparison': 'PASS', 'header': HEADER,
              'snapshot_fields': FIELDS, 'snapshots': len(rows), 'covered_forms': covered,
              'uncovered_forms': missing, 'encoding_groups': groups, 'bus_metrics': metrics,
              'sha256': {**frozen, **{str(p): digest(p) for p in artifacts}},
              'compile_commands': [list(map(str, cppargs)), list(map(str, rtlargs))],
              'run_command': list(map(str, rtlrun)), 'negative_diagnostics': negative,
              'reference_commit': subprocess.check_output(['git', '-C', str(ref), 'rev-parse', 'HEAD'], text=True).strip(),
              'reference_dirty': subprocess.check_output(['git', '-C', str(ref), 'status', '--porcelain'], text=True).splitlines(),
              'compiler': subprocess.check_output(['g++', '--version'], text=True).splitlines()[0],
              'verilator': subprocess.check_output(['verilator', '--version'], text=True).strip(),
              'limits': ['separate immutable instruction image and 256-byte BE data RAM',
                         'local startup IR/DR/PR and BAT programming; no CPU CSR/MSR routing',
                         'abstract physical ports carry WIMG; no downstream cache/60x ordering',
                         'no segment/TLB, SMC, architectural exception or cycle-conformance oracle'],
              'license': 'GPL-3.0-or-later; original notices retained'}
    shutil.copyfile(ref/'LICENSE', build/'DINGUSPPC-LICENSE')
    shutil.copyfile(ref/'CREDITS.md', build/'DINGUSPPC-CREDITS.md')
    (build/'manifest.json').write_text(json.dumps(report, indent=2)+'\n')
    print(f'PASS BAT reference: {len(rows)} retirements, {len(covered)} forms, full RAM; {metrics}')
    print(f'Artifacts: {build}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', type=Path, default=Path('build/reference-bat'))
    args = parser.parse_args()
    build = args.build_dir.resolve()
    try:
        run(build)
    finally:
        for path in (build/'rtl').glob('*.gch'):
            if path.is_file() and not path.is_symlink():
                path.unlink()


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
