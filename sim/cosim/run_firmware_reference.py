#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Run compiled firmware on DingusPPC and the RTL bench; compare retirements and RAM."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

from reference_checkout import add_arguments, verify
from run_reference import PROJECT, ROOT, command, digest

HERE = Path(__file__).resolve().parent
BASE = 0xfff00000
# Harness BATs the live-context bench installs before reset release.
LIVE_BATS = ('529=fff00002', '528=fff00002', '537=fff00002', '536=fff00002',
             '539=fff00002', '538=10000002')
# name: (run-rtl-smoke profile, ELF directory, reference SPR presets)
FIRMWARE = {
    'smoke': ('cached-bus', 'be', ()),
    'live-context': ('live-context', 'live-context', LIVE_BATS),
    'dsi': ('dsi', 'dsi', ()),
    'sdr1': ('sdr1', 'sdr1', ()),
    'lsu': ('lsu', 'lsu', ()),
    # The cached wrapper's reset-cache mode starts with HID0[ICE] set.
    'full-decode': ('full-decode', 'full-decode', ('1008=00008000',)),
}
SOURCES = ('cpu/ppc/ppcexec.cpp', 'cpu/ppc/ppcmmu.cpp', 'cpu/ppc/ppcexceptions.cpp',
           'cpu/ppc/ppcopcodes.cpp', 'cpu/ppc/poweropcodes.cpp', 'cpu/ppc/ppcfpopcodes.cpp',
           'devices/memctrl/memctrlbase.cpp', 'core/timermanager.cpp', 'utils/profiler.cpp',
           'thirdparty/loguru/loguru.cpp')


def load_smoke_module():
    spec = importlib.util.spec_from_file_location('run_rtl_smoke', PROJECT/'toolchain/run-rtl-smoke.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build_runner(build, ref):
    inputs = {str(p): digest(p) for p in (HERE/'firmware_runner.cpp', *(ref/s for s in SOURCES),
                                          *sorted(ref.rglob('*.h')))}
    runner, record = build/'firmware_runner', build/'firmware-runner.json'
    if runner.exists() and record.exists() and json.loads(record.read_text()) == inputs:
        return runner
    command(['g++', '-std=c++20', '-O2', '-fwrapv', '-DSUPPORTS_PPC_LITTLE_ENDIAN_MODE=0',
             '-DSUPPORTS_MEMORY_CTRL_ENDIAN_MODE=0', '-DCPU_PROFILING', f'-I{ref}',
             f'-I{ref}/thirdparty/loguru', HERE/'firmware_runner.cpp', *(ref/s for s in SOURCES),
             '-lpthread', '-ldl', '-o', runner], build/'firmware-runner-build.log')
    record.write_text(json.dumps(inputs, indent=1) + '\n')
    return runner


def rtl_records(path):
    """Merge micro-ops per instruction; report GPRs whose value changed."""
    gpr, rows, pending = [0]*32, [], None
    for line in path.read_text().split('\n'):
        if not line:
            continue
        pc, insn, more, fault, gw, g, gv, uw, ug, uv = line.split()
        if pending is None:
            pending = [int(pc, 16), int(insn, 16), int(fault), {}]
        for write, reg, value in ((gw, g, gv), (uw, ug, uv)):
            if write == '1' and gpr[int(reg)] != int(value, 16):
                gpr[int(reg)] = int(value, 16)
                pending[3][int(reg)] = int(value, 16)
        if more == '0':
            rows.append(tuple(pending))
            pending = None
    return rows


def reference_records(path):
    rows = []
    for line in path.read_text().split('\n'):
        if line:
            pc, exc, *changes = line.split()
            rows.append((int(pc, 16), int(exc),
                         {int(r): int(v, 16) for r, v in (c.split('=') for c in changes)}))
    return rows


def read_bytes(path):
    return [int(x, 16) for x in path.read_text().split() if not x.startswith('//')]


def compare(name, rtl, ref, rtl_bytes, ref_bytes):
    for index, (a, b) in enumerate(zip(rtl, ref)):
        if a[0] != b[0] or a[3] != b[2]:
            fmt = lambda d: ' '.join(f'r{r}={v:08x}' for r, v in sorted(d.items()))
            raise RuntimeError(f'{name}: retirement {index} differs\n  rtl pc={a[0]:08x} insn={a[1]:08x} '
                               f'fault={a[2]} {fmt(a[3])}\n  ref pc={b[0]:08x} exception={b[1]} {fmt(b[2])}')
    if len(rtl) != len(ref):
        raise RuntimeError(f'{name}: {len(rtl)} RTL retirements, {len(ref)} reference steps')
    for offset, (a, b) in enumerate(zip(rtl_bytes, ref_bytes)):
        if a != b:
            raise RuntimeError(f'{name}: RAM differs at {BASE+offset:08x}: rtl={a:02x} ref={b:02x}')
    return len(rtl_bytes)


def negative_controls(name, rtl, ref, rtl_bytes, ref_bytes):
    """A changed GPR value, PC, missing step or RAM byte must each fail."""
    written = max(i for i, row in enumerate(rtl) if row[3])
    reg = next(iter(rtl[written][3]))
    value = dict(rtl[written][3]); value[reg] ^= 1
    changed_value = rtl[:written] + [rtl[written][:3] + (value,)] + rtl[written+1:]
    changed_pc = [(rtl[0][0] ^ 4,) + rtl[0][1:]] + rtl[1:]
    changed_ram = list(rtl_bytes); changed_ram[len(changed_ram)//2] ^= 0x80
    for label, trace, ram in (('gpr value', changed_value, rtl_bytes), ('pc', changed_pc, rtl_bytes),
                              ('missing step', rtl[:-1], rtl_bytes), ('ram byte', rtl, changed_ram)):
        try:
            compare(name, trace, ref, ram, ref_bytes)
        except RuntimeError:
            continue
        raise RuntimeError(f'{name}: negative control ({label}) was not detected')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', type=Path, default=PROJECT/'sim/build/reference-firmware')
    parser.add_argument('--elf-dir', type=Path, default=PROJECT/'toolchain/build')
    parser.add_argument('--firmware', nargs='+', choices=tuple(FIRMWARE), default=tuple(FIRMWARE))
    parser.add_argument('--reference', type=Path, default=ROOT/'dingusppc')
    parser.add_argument('--steps', type=int, default=2_000_000)
    add_arguments(parser)
    args = parser.parse_args()
    build = args.build_dir.resolve()
    build.mkdir(parents=True, exist_ok=True)
    ref = args.reference.resolve()
    verify(ref)
    missing = [str(args.elf_dir/FIRMWARE[n][1]/'smoke.elf') for n in args.firmware
               if not (args.elf_dir/FIRMWARE[n][1]/'smoke.elf').exists()]
    if missing:
        raise RuntimeError('missing firmware ELFs (build with toolchain/build-in-container.sh firmware-all): '
                           + ' '.join(missing))
    runner = build_runner(build, ref)
    smoke = load_smoke_module()
    for name in args.firmware:
        profile, elf_dir, presets = FIRMWARE[name]
        out = build/name
        out.mkdir(exist_ok=True)
        elf = args.elf_dir/elf_dir/'smoke.elf'
        memory, mailbox = smoke.load_elf(elf, {}, {})
        image = out/'image.hex'
        image.write_text(''.join(f'{byte:02x}\n' for byte in memory))
        command([runner, image, f'{mailbox:08x}', out/'ref.trace', out/'ref.mem', args.steps, *presets],
                out/'reference.log')
        command([sys.executable, PROJECT/'toolchain/run-rtl-smoke.py', '--profile', profile, '--elf', elf,
                 '--build-dir', out/'rtl', '--verilator', args.verilator,
                 f'--plusarg=+TRACE={out}/rtl.trace', f'--plusarg=+MEMDUMP={out}/rtl.mem'], out/'rtl.log')
        rtl, reference = rtl_records(out/'rtl.trace'), reference_records(out/'ref.trace')
        rtl_bytes, ref_bytes = read_bytes(out/'rtl.mem'), read_bytes(out/'ref.mem')
        size = compare(name, rtl, reference, rtl_bytes, ref_bytes)
        negative_controls(name, rtl, reference, rtl_bytes, ref_bytes)
        exceptions = sum(row[1] for row in reference)
        print(f'PASS reference firmware {name}: retirements={len(rtl)} exceptions={exceptions} '
              f'ram_bytes={size}')
    print(f'PASS: reference firmware {len(args.firmware)} images')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
