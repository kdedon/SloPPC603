#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Cover the generic cache INSTALL-abort arm with the existing public-pin oracle.

Two serial leaf models need no firmware. Temporary model/PCH files are owned by
this invocation; coverage data survives for the normal coverage-summary gate.
"""
import argparse
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile

from coverage_summary import parse, rtl_name

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--coverage-dir', type=Path, required=True)
    args = parser.parse_args()
    output = args.coverage_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    cache = (ROOT/'rtl/ppc_icache.sv').read_text().splitlines()
    arm = [n for n, line in enumerate(cache, 1)
           if line.strip() == "4'b1011: abort_install = 1'b1;"]
    if len(arm) != 1:
        raise ValueError('expected one actual known INSTALL-abort case arm')
    # Reuse the existing timed coverage main without invoking firmware loading.
    spec = importlib.util.spec_from_file_location('rtl_smoke', ROOT/'toolchain/run-rtl-smoke.py')
    smoke = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(smoke)
    top = 'tb_icache_abort_install'
    sources = (ROOT/'rtl/icache_files.f').read_text().split()
    env = dict(os.environ, OBJCACHE='')
    for sets, ways, checks in ((64, 2, 54), (128, 4, 96)):
        dat = output/f'cov-{sets}x{ways}.dat'
        dat.unlink(missing_ok=True)  # An old run cannot satisfy this run's gate.
        with tempfile.TemporaryDirectory(prefix=f'model-{sets}x{ways}-', dir=output) as directory:
            build = Path(directory)
            main_cpp = build/'coverage_main.cpp'
            main_cpp.write_text(smoke.COVERAGE_MAIN.replace('TOP', 'V'+top))
            command = [str(ROOT/'sim/tools/verilate'), '--cc', '--exe', '--build',
                       '--coverage-line', str(main_cpp), '--timing', '--assert',
                       '-Wall', '-j', '1', '--x-assign', 'unique', '--x-initial', 'unique',
                       '--top-module', top, f'-GSETS={sets}', f'-GWAYS={ways}',
                       '--Mdir', str(build/'obj'), '-MAKEFLAGS',
                       'OPT_FAST=-O0 OPT_SLOW=-O0 OPT_GLOBAL=-O0',
                       *sources, '../tb/tb_icache_abort_install.sv']
            subprocess.run(command, cwd=ROOT/'sim', env=env, check=True, timeout=300)
            result = subprocess.run([str(build/'obj'/('V'+top)), '+verilator+seed+1',
                                     '+verilator+rand+reset+2', f'+COVERAGE={dat}'],
                                    cwd=ROOT/'sim', check=True, timeout=30,
                                    text=True, stdout=subprocess.PIPE)
            print(result.stdout, end='', flush=True)
            certificate = (f'PASS abort-INSTALL address oracle sets={sets} '
                           f'ways={ways} checks={checks}')
            if result.stdout.splitlines().count(certificate) != 1:
                raise ValueError('missing unchanged public-oracle acceptance certificate')
            hits = sum(count for fields, count in parse(dat)
                       if rtl_name(fields.get('f', '')) == 'rtl/ppc_icache.sv'
                       and fields.get('o') == 'case' and int(fields['l']) == arm[0])
            if hits <= 0:
                raise ValueError(f'actual INSTALL-abort arm has no coverage: {dat}')
            print(f'PASS icache-abort coverage {sets}x{ways}: '
                  f'rtl/ppc_icache.sv:{arm[0]} hits={hits}', flush=True)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
