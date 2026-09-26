#!/usr/bin/env python3
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
TIMER = {'interrupt_handler': 0x500, 'decrementer_handler': 0x900}
PAGE = {**TIMER, 'page_probe': 0x6000}
TLBIE = {**PAGE, 'tlbie_data_probe': 0x7000}
MISS = {'imiss_handler': 0x1000, 'dlmiss_handler': 0x1100, 'dsmiss_handler': 0x1200, 'page_probe': 0x6000}
FAULT = {**MISS, 'table_search_dsi_vector': 0x300, 'table_search_isi_vector': 0x400}

# profile: (bench, source lists, fixed-address symbols as offsets from BASE, +MODE runs)
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
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', choices=tuple(PROFILES), default='cached-bus')
    parser.add_argument('--elf', type=Path, default=Path(__file__).resolve().parent/'build/be/smoke.elf')
    parser.add_argument('--build-dir', type=Path, default=Path(__file__).resolve().parent/'build/rtl-smoke')
    parser.add_argument('--verilator', default=str(Path(__file__).resolve().parent.parent/'sim/tools/verilate'))
    parser.add_argument('--jobs', type=int, default=2)
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
    profile_params = [f'-GFAULT_PROFILE={int(table_fault_profile)}'] if manifests in (BAT_BUS, BAT_CACHED) else []
    subprocess.run([args.verilator, '--binary', '--timing', '--assert', '-Wall', '-j', str(args.jobs),
                    '--top-module', top, '--Mdir', str(build/'obj'),
                    *profile_params, *sources, f'../tb/{top}.sv'], cwd=root/'sim', check=True)
    for mode in (range(modes) if modes else (None,)):
        mode_args = [] if mode is None else [f'+MODE={mode}']
        subprocess.run([str(build/'obj'/f'V{top}'), f'+IMAGE={image}',
                        f'+TOHOST={mailbox:08x}', *fault_args, *mode_args], check=True)


if __name__ == '__main__':
    main()
