#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Run whole programs on a machine top and DingusPPC in lockstep (REFERENCE_MACHINE.md)."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from reference_checkout import verify
from run_firmware_reference import SOURCES
from run_reference import PROJECT, ROOT, command, digest

HERE = Path(__file__).resolve().parent
DEMO_ARGS = ('ram=fff00000:00040000', 'ram=f0000000:00100000', 'io=f0100000:00001000',
             'exit=f0100014')
DEMO_PROGRAMS = ('hello', 'dhrystone', 'coremark', 'whetstone', 'selftest')


def build_runner(build, ref, le=False):
    inputs = {str(p): digest(p) for p in (HERE/'machine_runner.cpp', HERE/'reference_adapter.h',
                                          *(ref/s for s in SOURCES), *sorted(ref.rglob('*.h')))}
    name = 'machine_runner_le' if le else 'machine_runner'
    runner, record = build/name, build/f'{name}.json'
    if runner.exists() and record.exists() and json.loads(record.read_text()) == inputs:
        return runner
    command(['g++', '-std=c++20', '-O2', '-fwrapv', f'-DSUPPORTS_PPC_LITTLE_ENDIAN_MODE={int(le)}',
             '-DSUPPORTS_MEMORY_CTRL_ENDIAN_MODE=0', '-DCPU_PROFILING', f'-I{ref}',
             f'-I{ref}/thirdparty/loguru', HERE/'machine_runner.cpp', *(ref/s for s in SOURCES),
             '-lpthread', '-ldl', '-o', runner], build/f'{name}-build.log')
    record.write_text(json.dumps(inputs, indent=1) + '\n')
    return runner


def lockstep(name, runner, image, runner_args, rtl_cmd, out, keep=None):
    """RTL writes its trace into a FIFO the runner reads, so no trace is stored."""
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=out) as scratch:
        fifo = Path(scratch)/'trace'
        os.mkfifo(fifo)
        with (out/'reference.log').open('w') as ref_log, (out/'rtl.log').open('w') as rtl_log:
            extra = [f'keep={keep}'] if keep else []
            ref = subprocess.Popen([str(runner), str(image), str(fifo), *runner_args, *extra],
                                   stdout=ref_log, stderr=subprocess.STDOUT)
            trace_arg = f'+RETIRE_TRACE={fifo}'
            if str(rtl_cmd[0]) == sys.executable:
                trace_arg = f'--plusarg={trace_arg}'
            rtl = subprocess.Popen([*map(str, rtl_cmd), trace_arg],
                                   stdout=rtl_log, stderr=subprocess.STDOUT)
            ref_code = ref.wait()
            if ref_code:
                rtl.kill()
            rtl_code = rtl.wait()
    ref_text, rtl_text = (out/'reference.log').read_text(), (out/'rtl.log').read_text()
    if ref_code:
        raise RuntimeError(f'{name}: reference comparison failed\n{ref_text[-4000:]}')
    if rtl_code or 'PASS' not in rtl_text:
        raise RuntimeError(f'{name}: RTL run failed\n{rtl_text[-3000:]}')
    summary = next(l for l in ref_text.splitlines() if l.startswith('PASS machine'))
    rtl_line = next(l for l in rtl_text.splitlines() if l.startswith('PASS'))
    cycles = rtl_line.split('cycles=')[1].split()[0]
    print(f'PASS reference machine {name}: {summary[len("PASS machine: "):]} cycles={cycles}', flush=True)


def negative_controls(runner, image, runner_args, prefix, le=False):
    """A flipped register, SPR, store byte or late store byte, or a dropped retirement must each fail.

    In little-endian runs a store moved to the other word of its doubleword,
    as an unmunged address would be, must fail too.
    """
    records = sum(1 for _ in prefix.open())
    clean = subprocess.run([str(runner), str(image), str(prefix), *runner_args, f'records={records}'],
                           capture_output=True, text=True)
    if clean.returncode:
        raise RuntimeError(f'negative control baseline failed\n{clean.stderr[-3000:]}')
    cases = {'gpr': ('mutate=1000:r1', 'state after'), 'msr': ('mutate=1500:msr', 'state after'),
             'cr': ('mutate=2000:cr', 'state after'), 'store': ('mutate=5000:st', 'store byte'),
             'late store': ('mutate=5000:stlate', 'store byte'),
             # A drop beside removed branches shows as a removed non-branch.
             'drop': ('drop=3000', ('pc:', 'removed instruction')),
             'lr after removed bl': ('mutate=1000:lrbl', 'state after')}
    if le:
        cases['store address'] = ('mutate=5000:staddr', 'store byte')
    # Without a store queue no write follows a younger store.
    if ' deferred_bytes=0 ' in clean.stdout:
        del cases['late store']
    # Without branch removal no bl retires through the shadow LR.
    if ' removed_bl=0 ' in clean.stdout:
        del cases['lr after removed bl']
    for label, (option, expect) in cases.items():
        run = subprocess.run([str(runner), str(image), str(prefix), *runner_args, f'records={records}',
                              option], capture_output=True, text=True)
        expect = (expect,) if isinstance(expect, str) else expect
        if run.returncode == 0 or not any(e in run.stderr for e in expect):
            raise RuntimeError(f'negative control ({label}) was not detected\n{run.stderr[-2000:]}')
    print(f'PASS reference machine negative controls: {len(cases)} mutations over {records} records',
          flush=True)


def chip_stress(runner, args, out):
    spec = importlib.util.spec_from_file_location('run_rtl_smoke', PROJECT/'toolchain/run-rtl-smoke.py')
    smoke = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(smoke)
    memory, mailbox = smoke.load_elf(args.chip_elf, {}, {})
    out.mkdir(parents=True, exist_ok=True)
    image = out/'image.hex'
    image.write_text(''.join(bytes(memory[i:i+8]).hex() + '\n' for i in range(0, len(memory), 8)))
    rtl = [sys.executable, PROJECT/'toolchain/run-rtl-smoke.py', '--profile', 'chip-mmu-stress',
           '--elf', args.chip_elf.resolve(), '--build-dir', out/'rtl', '--verilator', args.verilator]
    lockstep('chip-mmu-stress', runner, image, ('ram=fff00000:00040000', f'exit={mailbox:08x}'), rtl, out)


def chip_le(runner, model, out):
    """The little-endian core program on the package top, with the FPU."""
    out.mkdir(parents=True, exist_ok=True)
    image = out/'program.hex'
    command([sys.executable, PROJECT/'sim/tools/le_core_program.py', '--chip-image', image], out/'program.log')
    data = bytes(int(line, 16) for line in image.read_text().split())
    words = out/'image.hex'
    words.write_text(''.join(data[i:i+8].hex() + '\n' for i in range(0, len(data), 8)))
    rtl = [model.resolve(), f'+IMAGE={image}', '+TOHOST=fff3ff00']
    lockstep('chip-le', runner, words, ('ram=fff00000:00040000', 'exit=fff3ff00', 'fpu'), rtl, out)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', type=Path, default=PROJECT/'sim/build/reference-machine')
    parser.add_argument('--reference', type=Path, default=ROOT/'dingusppc')
    parser.add_argument('--model', type=Path, help='demo SoC Verilator binary')
    parser.add_argument('--image-dir', type=Path, help='demo firmware .hex directory')
    parser.add_argument('--chip-elf', type=Path, help='chip-mmu-stress ELF: run it on the package top')
    parser.add_argument('--verilator', default='verilator')
    parser.add_argument('--programs', nargs='*', default=DEMO_PROGRAMS)
    parser.add_argument('--little-endian', action='store_true',
                        help='reference built with little-endian mode, for images that switch to it')
    parser.add_argument('--chip-le', type=Path,
                        help='tb_chip_firmware binary with the FPU: also run the little-endian core program')
    parser.add_argument('--max-cycles', type=int, default=400_000_000)
    args = parser.parse_args()
    build = args.build_dir.resolve()
    build.mkdir(parents=True, exist_ok=True)
    ref = args.reference.resolve()
    verify(ref)
    if args.chip_elf:
        runner = build_runner(build, ref)
        chip_stress(runner, args, build/'chip-mmu-stress')
        return
    images = {n: args.image_dir.resolve()/f'{n}.hex' for n in args.programs}
    missing = [str(p) for p in images.values() if not p.exists()]
    if missing:
        raise RuntimeError('missing demo images (build with make -C sim demo-firmware demo-bench-firmware): '
                           + ' '.join(missing))
    runner = build_runner(build, ref, args.little_endian)
    if args.chip_le:
        chip_le(runner, args.chip_le, build/'chip-le')
    for index, (name, image) in enumerate(images.items()):
        rtl = [args.model.resolve(), f'+IMAGE={image}', f'+NAME={name}', f'+MAX_CYCLES={args.max_cycles}']
        prefix = build/name/'prefix.trace' if index == 0 else None
        lockstep(name, runner, image, DEMO_ARGS, rtl, build/name, prefix)
        if prefix:
            negative_controls(runner, image, DEMO_ARGS, prefix, args.little_endian)
            prefix.unlink()
    print(f'PASS: reference machine {len(images)} programs')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, StopIteration, subprocess.SubprocessError) as error:
        sys.exit(str(error))
