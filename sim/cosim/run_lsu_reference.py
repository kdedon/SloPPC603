#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Original DingusPPC load/store-extension handlers + flat RAM vs actual core."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
from compare_state import compare
from compare_memory import FIELDS, HEADER, read_trace
from lsu_program import NEW_FORMS, accesses, corpus
from reference_checkout import add_arguments, verify, xrand_build_flags, xrand_run_args
from run_reference import HERE, PROJECT, ROOT, build_reference, command


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--build-dir', type=Path, default=PROJECT/'sim/build/reference-lsu')
    add_arguments(ap)
    args = ap.parse_args()
    build = args.build_dir.resolve(); build.mkdir(parents=True, exist_ok=True)
    ref = ROOT/'dingusppc'
    reference_commit, reference_dirty = verify(ref)
    (build/'runner').mkdir(exist_ok=True)
    runner, cppargs = build_reference(build/'runner', ref, flat_ram=True, lsu=True)
    words, groups = corpus(); program = build/'program.hex'
    program.write_text(''.join(f'{w:08x}\n' for w in words))
    expected = build/'expected.txt'; actual = build/'actual.txt'
    command([runner, program, 'MPC603EV'], expected)
    rows = read_trace(expected)
    requests, stores = accesses(rows)
    executed = {r[1] for r in rows}
    missing = [n for n, (mask, value) in NEW_FORMS.items() if not any(w & mask == value for w in executed)]
    if missing: raise RuntimeError(f'extension forms not executed: {missing}')
    sources = [(PROJECT/'sim'/line).resolve() for line in (PROJECT/'rtl/files.f').read_text().splitlines() if line.strip()]
    bench = PROJECT/'tb/tb_core_memory_reference.sv'
    rtlargs = [args.verilator, '--binary', '--timing', '--assert', '-Wall', '--top-module', 'tb_core_memory_reference',
               "-GEXTENSIONS=1'b1", '--Mdir', build/'rtl', *xrand_build_flags(args.xrand_seed), *sources, bench]
    command(rtlargs, build/'rtl-build.log')
    rtlrun = [build/'rtl/Vtb_core_memory_reference', f'+PROGRAM={program}', f'+TRACE={actual}',
              f'+WORDS={len(words)}', f'+COMMITS={len(rows)}', f'+MEMORY_REQUESTS={requests}',
              f'+MEMORY_WRITES={stores}', *xrand_run_args(args.xrand_seed)]
    command(rtlrun, build/'rtl-run.log')
    compare(rows, read_trace(actual), fields=FIELDS)
    # Negative controls: a flipped loaded register, CR0 and RAM byte must fail.
    negative = 0
    lmw = next(i for i, r in enumerate(rows) if r[1] >> 26 == 46)
    stwcx = next(i for i, r in enumerate(rows) if r[1] & 0xfc0007ff == 0x7c00012d)
    for field, bit, index in [('gpr31', 0, lmw), ('cr', 29, stwcx), ('ram[000010a0]', 24, len(rows) - 1)]:
        altered = [list(r) for r in rows]; altered[index][FIELDS.index(field)] ^= 1 << bit
        bad = build/'injected.txt'
        bad.write_text(HEADER + '\n' + ''.join(' '.join(f'{v:08x}' for v in r) + '\n' for r in altered))
        result = subprocess.run([sys.executable, HERE/'compare_memory.py', bad, actual], capture_output=True, text=True)
        if result.returncode != 1 or f' {field}:' not in result.stderr: raise RuntimeError(f'missed mutation {field}')
        negative += 1
    bad.unlink()
    # The runner rejects the lmw invalid form (rA in the loaded range).
    reject = build/'reject.hex'; reject.write_text(f'{(46 << 26) | (5 << 21) | (5 << 16):08x}\n')
    result = subprocess.run([str(runner), str(reject)], capture_output=True, text=True)
    if result.returncode != 2 or 'unsupported or reserved' not in result.stderr:
        raise RuntimeError('lmw invalid form not rejected')
    reject.unlink()
    (build/'manifest.json').write_text(json.dumps({
        'reference_commit': reference_commit, 'reference_dirty': reference_dirty,
        'compile_commands': [cppargs, [str(x) for x in rtlargs]], 'xrand_seed': args.xrand_seed,
        'program_words': len(words), 'snapshots': len(rows), 'encoding_groups': groups,
        'memory_requests': requests, 'memory_writes': stores, 'comparison': 'PASS'}, indent=2) + '\n')
    print(f'PASS LSU reference: {len(rows)} snapshots, {len(NEW_FORMS)} extension forms, '
          f'{requests} requests, {stores} stores; {negative} negative comparisons, 1 rejection gate')


if __name__ == '__main__':
    try: main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error: sys.exit(str(error))
