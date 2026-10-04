#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Run the little-endian core program on DingusPPC (LE build) and tb_core_le.

DingusPPC is exported at LAST_VERIFIED into the build directory and compiled
there with SUPPORTS_PPC_LITTLE_ENDIAN_MODE=1; the sibling checkout is only
read. Retirements are compared instruction by instruction (PC and GPR
changes), then every memory word.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys

from reference_checkout import LAST_VERIFIED, verify
from run_reference import PROJECT, ROOT, command, digest
from run_firmware_reference import SOURCES, reference_records, rtl_records

HERE = Path(__file__).resolve().parent
RESET_PC = 0x4000


def export_reference(ref, dest):
    """Unpack DingusPPC at LAST_VERIFIED into dest unless already there."""
    stamp = dest/'.commit'
    if stamp.exists() and stamp.read_text().strip() == LAST_VERIFIED:
        return
    subprocess.run(['rm', '-rf', str(dest)], check=True)
    dest.mkdir(parents=True)
    archive = subprocess.run(['git', '-C', str(ref), 'archive', '--format=tar', LAST_VERIFIED],
                             check=True, capture_output=True).stdout
    subprocess.run(['tar', '-x', '-C', str(dest)], input=archive, check=True)
    stamp.write_text(LAST_VERIFIED + '\n')


def build_runner(build, src):
    inputs = {str(p): digest(p) for p in (HERE/'le_runner.cpp', *(src/s for s in SOURCES))}
    inputs['commit'] = LAST_VERIFIED
    runner, record = build/'le_runner', build/'le-runner.json'
    if runner.exists() and record.exists() and json.loads(record.read_text()) == inputs:
        return runner
    command(['g++', '-std=c++20', '-O2', '-fwrapv', '-DSUPPORTS_PPC_LITTLE_ENDIAN_MODE=1',
             '-DSUPPORTS_MEMORY_CTRL_ENDIAN_MODE=0', '-DCPU_PROFILING', f'-I{src}',
             f'-I{src}/thirdparty/loguru', HERE/'le_runner.cpp', *(src/s for s in SOURCES),
             '-lpthread', '-ldl', '-o', runner], build/'le-runner-build.log')
    record.write_text(json.dumps(inputs, indent=1) + '\n')
    return runner


def read_words(path):
    words = {}
    for line in path.read_text().splitlines():
        addr, value = line.split()
        words[int(addr, 16)] = int(value, 16)
    return words


def compare(rtl, ref, rtl_mem, ref_mem):
    fmt = lambda d: ' '.join(f'r{r}={v:08x}' for r, v in sorted(d.items()))
    for index, (a, b) in enumerate(zip(rtl, ref)):
        if a[0] != b[0] or a[3] != b[2]:
            raise RuntimeError(f'retirement {index} differs\n  rtl pc={a[0]:08x} insn={a[1]:08x} '
                               f'fault={a[2]} {fmt(a[3])}\n  ref pc={b[0]:08x} exception={b[1]} {fmt(b[2])}')
    if len(rtl) != len(ref):
        raise RuntimeError(f'{len(rtl)} RTL retirements, {len(ref)} reference steps')
    for addr in sorted(set(rtl_mem) | set(ref_mem)):
        if rtl_mem.get(addr, 0) != ref_mem.get(addr, 0):
            raise RuntimeError(f'memory differs at {addr:08x}: rtl={rtl_mem.get(addr, 0):08x} '
                               f'ref={ref_mem.get(addr, 0):08x}')
    return len(set(rtl_mem) | set(ref_mem))


def negative_controls(rtl, ref, rtl_mem, ref_mem):
    """A changed GPR value, PC, missing step or memory word must each fail."""
    written = max(i for i, row in enumerate(rtl) if row[3])
    reg = next(iter(rtl[written][3]))
    value = dict(rtl[written][3]); value[reg] ^= 1
    changed_mem = dict(rtl_mem); addr = sorted(changed_mem)[len(changed_mem)//2]; changed_mem[addr] ^= 0x80
    for label, trace, mem in (('gpr value', rtl[:written] + [rtl[written][:3] + (value,)] + rtl[written+1:], rtl_mem),
                              ('pc', [(rtl[0][0] ^ 4,) + rtl[0][1:]] + rtl[1:], rtl_mem),
                              ('missing step', rtl[:-1], rtl_mem), ('memory word', rtl, changed_mem)):
        try:
            compare(trace, ref, mem, ref_mem)
        except RuntimeError:
            continue
        raise RuntimeError(f'negative control ({label}) was not detected')


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--build-dir', type=Path, required=True)
    parser.add_argument('--rtl', type=Path, required=True, help='built Vtb_core_le')
    parser.add_argument('--reference', type=Path, default=ROOT/'dingusppc')
    parser.add_argument('--steps', type=int, default=200_000)
    args = parser.parse_args()
    build = args.build_dir.resolve()
    build.mkdir(parents=True, exist_ok=True)
    ref = args.reference.resolve()
    verify(ref)
    src = build/'dingusppc'
    export_reference(ref, src)
    runner = build_runner(build, src)
    image = build/'program.txt'
    command([sys.executable, PROJECT/'sim/tools/le_core_program.py', '--image', image, '--variant', 'pid7v'],
            build/'program.log')
    command([runner, image, f'{RESET_PC:08x}', build/'ref.trace', build/'ref.mem', args.steps],
            build/'reference.log')
    command([args.rtl.resolve(), f'+IMAGE={image}', '+STALL=1', '+SEED=1', f'+RTRACE={build}/rtl.trace',
             f'+MEMDUMP={build}/rtl.mem'], build/'rtl.log')
    rtl, reference = rtl_records(build/'rtl.trace'), reference_records(build/'ref.trace')
    rtl_mem, ref_mem = read_words(build/'rtl.mem'), read_words(build/'ref.mem')
    words = compare(rtl, reference, rtl_mem, ref_mem)
    negative_controls(rtl, reference, rtl_mem, ref_mem)
    exceptions = sum(row[1] for row in reference)
    # The reference prints steps and exceptions, then bench-DSI and correction counts.
    counts = ' '.join((build/'reference.log').read_text().split()[2:])
    print(f'PASS reference little-endian: DingusPPC {LAST_VERIFIED[:12]} LE build, '
          f'retirements={len(rtl)} exceptions={exceptions} memory_words={words}; {counts}')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(str(error))
