#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Kevin Dedon
"""Load BE firmware into cached-bus, exception, live-context, timer, BAT, or page-hit RTL."""
import argparse
from pathlib import Path
import struct
import subprocess

BASE = 0xFFF00000
SIZE = 65536


def load_elf(path, required_symbols=None, capture_symbols=None):
    data = path.read_bytes()
    if data[:7] != b'\x7fELF\x01\x02\x01':
        raise ValueError('expected big-endian ELF32 version 1')
    h = struct.unpack_from('>HHIIIIIHHHHHH', data, 16)
    if h[:4] != (2, 20, 1, BASE + 0x100):
        raise ValueError('expected executable PowerPC ELF at bootstrap reset address')
    memory = bytearray(SIZE)
    loaded = bytearray(SIZE)
    for i in range(h[9]):
        p = struct.unpack_from('>IIIIIIII', data, h[4] + i*h[8])
        kind, offset, va, pa, filesz, memsz, _, _ = p
        if kind != 1:
            continue
        if va != pa or not BASE <= pa <= BASE + SIZE or memsz > BASE + SIZE-pa:
            raise ValueError('load segment outside physical bootstrap window')
        if filesz > memsz or offset + filesz > len(data):
            raise ValueError('invalid load segment file size')
        start = pa-BASE
        if any(loaded[start:start+memsz]):
            raise ValueError('overlapping load segments')
        memory[start:start+filesz] = data[offset:offset+filesz]
        loaded[start:start+memsz] = b'\x01'*memsz
    sections = [struct.unpack_from('>IIIIIIIIII', data, h[5]+i*h[10]) for i in range(h[11])]
    mailbox = None
    found_symbols = {}
    for s in sections:
        if s[1] != 2:
            continue
        strings = sections[s[6]]
        names = data[strings[4]:strings[4]+strings[5]]
        if s[9] != 16:
            raise ValueError('invalid symbol table entry size')
        for offset in range(s[4], s[4]+s[5], s[9]):
            name, value, size, _, _, section = struct.unpack_from('>IIIBBH', data, offset)
            symbol_name = names[name:].split(b'\0', 1)[0]
            if section != 0:
                found_symbols[symbol_name] = (value, size)
            if symbol_name == b'tohost' and section != 0:
                if size != 4:
                    raise ValueError('tohost must be a 32-bit word')
                mailbox = value
    if mailbox is None or mailbox % 4 or not BASE <= mailbox <= BASE+SIZE-4:
        raise ValueError('missing or invalid tohost symbol')
    if not all(loaded[mailbox-BASE:mailbox-BASE+4]) or not all(loaded[0x100:0x104]):
        raise ValueError('entry/mailbox must be in load segments')
    for name, expected in (required_symbols or {}).items():
        value, size = found_symbols.get(name.encode(), (None, 0))
        if value != expected or size < 4 or not BASE <= value <= BASE+SIZE-size:
            raise ValueError(f'missing or invalid fixed-address function {name}')
        if not all(loaded[value-BASE:value-BASE+size]):
            raise ValueError(f'{name} is not in a load segment')
    if capture_symbols is not None:
        capture_symbols.update(found_symbols)
    return memory, mailbox


CACHED = ('files.f', 'bus_files.f', 'line_read_files.f', 'icache_files.f', 'cached_system_files.f')
BAT = ('files.f', 'bat_service_files.f', 'core_bat_files.f')
BAT_BUS = BAT + ('bus_files.f', 'system_files.f', 'core_bat_bus60x_files.f')
BAT_CACHED = BAT + ('bus_files.f', 'system_files.f', 'line_read_files.f', 'icache_files.f',
                    'cached_system_files.f', 'cache_control_files.f', 'core_bat_cached_bus60x_files.f')
CHIP = ('chip_files.f',)
TIMER = {'interrupt_handler': 0x500, 'decrementer_handler': 0x900}
PAGE = {**TIMER, 'page_probe': 0x6000}
TLBIE = {**PAGE, 'tlbie_data_probe': 0x7000}
MISS = {'imiss_handler': 0x1000, 'dlmiss_handler': 0x1100, 'dsmiss_handler': 0x1200, 'page_probe': 0x6000}
FAULT = {**MISS, 'table_search_dsi_vector': 0x300, 'table_search_isi_vector': 0x400}
STRESS = {**MISS, 'machine_check_handler': 0x200, 'dsi_handler': 0x300, 'isi_handler': 0x400, 'interrupt_handler': 0x500,
          'decrementer_handler': 0x900}
del STRESS['page_probe']
# Bench plusarg: (symbol, minimum size) for the stress image's counters.
STRESS_SYMBOLS = {'EXT_COUNT': ('stress_ext_count', 4), 'DEC_COUNT': ('stress_dec_count', 4),
                  'IRQ_ACK': ('irq_ack', 4), 'MISS_TOTAL': ('miss_total', 4),
                  'MC_COUNT': ('stress_mc_count', 4)}
CACHEOPS = {'dsi_handler': 0x300, 'interrupt_handler': 0x500, 'alignment_handler': 0x600,
            'decrementer_handler': 0x900}
FULL_DECODE = {'dsi_handler': 0x300, 'program_handler': 0x700, 'fp_unavailable_handler': 0x800,
               'syscall_handler': 0xc00}
MACHINE_CHECK = {'machine_check_handler': 0x200, 'trace_handler': 0xd00, 'iabr_handler': 0x1300,
                 'bad_routine': 0xdfe0}
RESIDUALS = {'dsi_handler': 0x300, 'alignment_handler': 0x600, 'program_handler': 0x700,
             'decrementer_handler': 0x900, 'syscall_handler': 0xc00, 'trace_handler': 0xd00,
             'dtlb_load_handler': 0x1100, 'dtlb_store_handler': 0x1200, 'iabr_handler': 0x1300}

# profile: (bench, source lists, fixed-address symbols as offsets from BASE,
#           +MODE runs: a count or a tuple of modes)
PROFILES = {
    'cached-bus': ('tb_compiled_firmware', CACHED, {}, 0),
    'fetch-fault': ('tb_compiled_fetch_firmware', ('files.f',),
                    {'isi_handler': 0x400, 'fetch_protection_probe': 0x800, 'fetch_guarded_probe': 0x900}, 0),
    'live-context': ('tb_compiled_live_firmware', BAT, {'syscall_handler': 0xc00}, 0),
    'external-interrupt': ('tb_compiled_irq_firmware', BAT, {'interrupt_handler': 0x500}, 0),
    'timer': ('tb_compiled_timer_firmware', BAT, TIMER, 0),
    'runtime-bat': ('tb_compiled_runtime_bat_firmware', BAT, TIMER, 0),
    'dsi': ('tb_compiled_dsi_firmware', BAT, {'dsi_handler': 0x300}, 0),
    'segment': ('tb_compiled_segment_firmware', BAT, TIMER, 0),
    'page': ('tb_compiled_page_firmware', BAT, PAGE, 0),
    'tlbie': ('tb_compiled_tlbie_firmware', BAT, TLBIE, 3),
    'tlbload': ('tb_compiled_tlbload_firmware', BAT, TLBIE, 3),
    'page-dsi': ('tb_compiled_page_dsi_firmware', BAT, {'page_dsi_handler': 0x300}, 0),
    'page-isi': ('tb_compiled_page_isi_firmware', BAT, {'page_isi_handler': 0x400, 'page_probe': 0x6000}, 0),
    'page-miss': ('tb_compiled_page_miss_firmware', BAT, {**TLBIE, 'page_miss_store_probe': 0x7008}, 3),
    'sdr1': ('tb_compiled_sdr1_firmware', BAT, {}, 0),
    'tgpr': ('tb_compiled_tgpr_firmware', BAT, {}, 0),
    'miss-entry': ('tb_compiled_miss_entry_firmware', BAT, MISS, 2),
    'table-search': ('tb_compiled_table_search_firmware', BAT, MISS, 0),
    'table-fault': ('tb_compiled_table_fault_firmware', BAT, FAULT, 0),
    'table-search-bus': ('tb_compiled_table_bus60x_firmware', BAT_BUS, MISS, 0),
    'table-fault-bus': ('tb_compiled_table_bus60x_firmware', BAT_BUS, FAULT, 0),
    'table-search-cached': ('tb_compiled_table_cached_bus60x_firmware', BAT_CACHED, MISS, 0),
    'table-fault-cached': ('tb_compiled_table_cached_bus60x_firmware', BAT_CACHED, FAULT, 0),
    'mmu-stress-cached': ('tb_compiled_mmu_stress_firmware', BAT_CACHED, STRESS,
                          (0, 1, 2, 3, 4, 5, 6, 7, 8, 12, 13)),
    'mmu-stress-retry': ('tb_compiled_mmu_stress_firmware', BAT_CACHED, STRESS, 14),
    # Seeded TEA machine checks, without and with RETRY.
    'mmu-stress-tea': ('tb_compiled_mmu_stress_firmware', BAT_CACHED, STRESS, (14, 15)),
    'cacheops': ('tb_compiled_cacheops_firmware', BAT_CACHED, CACHEOPS, 0),
    'lsu': ('tb_compiled_lsu_firmware', BAT_CACHED, {'alignment_handler': 0x600}, 0),
    # The same image with the data cache on from reset, on the bench BIU.
    'lsu-dcache': ('tb_compiled_lsu_dcache_firmware', BAT_CACHED, {'alignment_handler': 0x600}, 0),
    'machine-check': ('tb_compiled_machine_check_firmware', BAT_CACHED, MACHINE_CHECK, 2),
    'full-decode': ('tb_compiled_full_decode_firmware', BAT_CACHED, FULL_DECODE, 0),
    # The package top, pins only.
    'chip-mmu-stress': ('tb_chip_firmware', CHIP, STRESS, 0),
    'chip-lsu': ('tb_chip_firmware', CHIP, {'alignment_handler': 0x600}, 0),
    'chip-machine-check': ('tb_chip_firmware', CHIP, MACHINE_CHECK, 0),
    'chip-full-decode': ('tb_chip_firmware', CHIP, FULL_DECODE, 0),
    'residuals': ('tb_compiled_residuals_firmware', BAT_CACHED, RESIDUALS, 0),
}
# Benches whose target is not the default for their source lists.
SCRIPTED_TARGET = {'cacheops', 'lsu', 'lsu-dcache', 'machine-check', 'full-decode', 'chip-mmu-stress',
                   'chip-lsu', 'chip-machine-check', 'chip-full-decode', 'residuals'}
RETRY_TARGET = {'mmu-stress-cached', 'mmu-stress-retry', 'mmu-stress-tea'}
# Plusargs added to every run of a profile.
# Bench parameters added to every build of a profile.
# These images expect the instruction cache on from reset.
PROFILE_GPARAMS = {profile: ["ICE_AT_RESET=1'b1"] for profile in
                   ('chip-full-decode', 'chip-machine-check')}
PROFILE_ARGS = {'mmu-stress-retry': ['+RETRY=1'],
                'chip-machine-check': ['+TEA_BASE=fff0dff0', '+TEA_END=fff0e100']}

COVERAGE_MAIN = '''#include <memory>
#include <string>
#include "verilated.h"
#include "verilated_cov.h"
#include "TOP.h"
int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> context{new VerilatedContext};
    context->commandArgs(argc, argv);
    const std::unique_ptr<TOP> top{new TOP{context.get()}};
    while (!context->gotFinish()) {
        top->eval();
        if (!top->eventsPending()) break;
        context->time(top->nextTimeSlot());
    }
    top->final();
    const std::string file = context->commandArgsPlusMatch("COVERAGE=");
    if (!file.empty()) context->coveragep()->write(file.substr(10).c_str());
    return context->gotFinish() ? 0 : 1;
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', choices=tuple(PROFILES), default='cached-bus')
    parser.add_argument('--elf', type=Path, default=Path(__file__).resolve().parent/'build/be/smoke.elf')
    parser.add_argument('--build-dir', type=Path, default=Path(__file__).resolve().parent/'build/rtl-smoke')
    parser.add_argument('--verilator', default=str(Path(__file__).resolve().parent.parent/'sim/tools/verilate'))
    parser.add_argument('--jobs', type=int, default=2)
    parser.add_argument('--coverage', action='store_true',
                        help='build with line coverage; each run writes cov-<mode>.dat in the build directory')
    parser.add_argument('--modes', type=int, nargs='+', help='run only these +MODE values')
    parser.add_argument('--gparam', action='append', default=[],
                        help='bench parameter override NAME=VALUE')
    parser.add_argument('--plusarg', action='append', default=[],
                        help='extra simulation plusarg, e.g. +TRACE=<file>')
    args = parser.parse_args()
    top, manifests, offsets, modes = PROFILES[args.profile]
    table_fault_profile = args.profile.startswith('table-fault')
    required = {name: BASE+offset for name, offset in offsets.items()}
    symbols = {}
    memory, mailbox = load_elf(args.elf, required, symbols)
    fault_args = []
    if table_fault_profile:
        for symbol, plusarg, needed in ((b'fault_count', 'FAULT_COUNT', 4),
                                       (b'fault_records', 'FAULT_RECORDS', 16*6*4)):
            value, size = symbols.get(symbol, (0, 0))
            if size < needed or value % 4 or not BASE <= value <= BASE+SIZE-size:
                raise ValueError(f'invalid fault verification symbol {symbol!r}')
            fault_args.append(f'+{plusarg}={value:08x}')
    if 'mmu-stress' in args.profile:
        for plusarg, (symbol, needed) in STRESS_SYMBOLS.items():
            value, size = symbols.get(symbol.encode(), (0, 0))
            if size < needed or value % 4 or not BASE <= value <= BASE+SIZE-size:
                raise ValueError(f'invalid stress symbol {symbol}')
            fault_args.append(f'+{plusarg}={value:08x}')
    build = args.build_dir.resolve()
    build.mkdir(parents=True, exist_ok=True)
    image = build/'memory.hex'
    image.write_text(''.join(f'{byte:02x}\n' for byte in memory))
    root = Path(__file__).resolve().parent.parent
    sources = []
    for manifest in manifests:
        for source in (root/'rtl'/manifest).read_text().split():
            if source not in sources:
                sources.append(source)
    scripted = args.profile in SCRIPTED_TARGET
    profile_params = ([f'-GFAULT_PROFILE={int(table_fault_profile)}']
                      if manifests in (BAT_BUS, BAT_CACHED) and args.profile.startswith('table-') else [])
    bfms = (['../tb/bfm/bus60x_scripted_target_bfm.sv', '../tb/bfm/dcache_biu_bfm.sv']
            if args.profile == 'lsu-dcache' else
            ['../tb/bfm/bus60x_scripted_target_bfm.sv'] if scripted else
            ['../tb/bfm/bus60x_retry_target_bfm.sv'] if args.profile in RETRY_TARGET else
            ['../tb/bfm/bus60x_delay_target_bfm.sv'] if manifests in (BAT_BUS, BAT_CACHED) else
            ['../tb/bfm/bus60x_negedge_target_bfm.sv'] if manifests == CACHED else [])
    # The --binary main does not save coverage; this one writes +COVERAGE=<file>.
    mode_flags = ['--binary']
    if args.coverage:
        main = build/'coverage_main.cpp'
        main.write_text(COVERAGE_MAIN.replace('TOP', f'V{top}'))
        mode_flags = ['--cc', '--exe', '--build', '--coverage-line', str(main)]
    subprocess.run([args.verilator, *mode_flags, '--timing', '--assert', '-Wall', '-j', str(args.jobs),
                    '--top-module', top, '--Mdir', str(build/'obj'), '-I../tb',
                    *profile_params, *(f'-G{g}' for g in [*PROFILE_GPARAMS.get(args.profile, []), *args.gparam]), *sources, *bfms, f'../tb/{top}.sv'], cwd=root/'sim', check=True)
    if isinstance(modes, int):
        modes = tuple(range(modes)) if modes else (None,)
    if args.modes:
        modes = tuple(args.modes)
    for mode in modes:
        mode_args = [] if mode is None else [f'+MODE={mode}']
        if args.coverage:
            mode_args.append(f'+COVERAGE={build}/cov-{mode}.dat')
        subprocess.run([str(build/'obj'/f'V{top}'), f'+IMAGE={image}',
                        f'+TOHOST={mailbox:08x}', *fault_args, *mode_args,
                        *PROFILE_ARGS.get(args.profile, []), *args.plusarg], check=True)


if __name__ == '__main__':
    main()
