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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', choices=('cached-bus', 'fetch-fault', 'live-context', 'external-interrupt', 'timer', 'runtime-bat', 'dsi', 'segment', 'page', 'tlbie', 'tlbload', 'page-dsi', 'page-isi', 'page-miss', 'sdr1', 'tgpr', 'miss-entry', 'table-search', 'table-fault', 'table-search-bus', 'table-fault-bus', 'table-search-cached', 'table-fault-cached'), default='cached-bus')
    parser.add_argument('--elf', type=Path, default=Path(__file__).resolve().parent/'build/be/smoke.elf')
    parser.add_argument('--build-dir', type=Path, default=Path(__file__).resolve().parent/'build/rtl-smoke')
    parser.add_argument('--verilator', default='verilator')
    parser.add_argument('--jobs', type=int, default=2)
    args = parser.parse_args()
    table_cached_profile = args.profile in ('table-search-cached', 'table-fault-cached')
    table_bus_profile = args.profile in ('table-search-bus', 'table-fault-bus')
    table_fault_profile = args.profile in ('table-fault', 'table-fault-bus', 'table-fault-cached')
    table_search_profile = args.profile in ('table-search', 'table-search-bus', 'table-search-cached')
    miss_entry_profile = args.profile == 'miss-entry'
    tgpr_profile = args.profile == 'tgpr'
    sdr1_profile = args.profile == 'sdr1'
    fetch_profile = args.profile == 'fetch-fault'
    live_profile = args.profile == 'live-context'
    irq_profile = args.profile == 'external-interrupt'
    timer_profile = args.profile == 'timer'
    runtime_bat_profile = args.profile == 'runtime-bat'
    dsi_profile = args.profile == 'dsi'
    segment_profile = args.profile == 'segment'
    page_profile = args.profile in ('page', 'tlbie', 'tlbload', 'page-miss')
    tlbie_profile = args.profile in ('tlbie', 'tlbload', 'page-miss')
    tlbload_profile = args.profile in ('tlbload', 'page-miss')
    page_miss_profile = args.profile == 'page-miss'
    page_dsi_profile = args.profile == 'page-dsi'
    page_isi_profile = args.profile == 'page-isi'
    required = {'isi_handler': BASE+0x400, 'fetch_protection_probe': BASE+0x800,
                'fetch_guarded_probe': BASE+0x900} if fetch_profile else None
    if live_profile:
        required = {'syscall_handler': BASE+0xc00}
    if irq_profile:
        required = {'interrupt_handler': BASE+0x500}
    if timer_profile or runtime_bat_profile or segment_profile or page_profile:
        required = {'interrupt_handler': BASE+0x500, 'decrementer_handler': BASE+0x900}
    if dsi_profile:
        required = {'dsi_handler': BASE+0x300}
    if page_dsi_profile:
        required = {'page_dsi_handler': BASE+0x300}
    if page_isi_profile:
        required = {'page_isi_handler': BASE+0x400, 'page_probe': BASE+0x6000}
    if page_profile:
        required['page_probe'] = BASE+0x6000
    if tlbie_profile:
        required['tlbie_data_probe'] = BASE+0x7000
    if page_miss_profile:
        required['page_miss_store_probe'] = BASE+0x7008
    if miss_entry_profile or table_search_profile or table_fault_profile:
        required = {'imiss_handler': BASE+0x1000, 'dlmiss_handler': BASE+0x1100,
                    'dsmiss_handler': BASE+0x1200, 'page_probe': BASE+0x6000}
    if table_fault_profile:
        required.update({'table_search_dsi_vector': BASE+0x300,
                         'table_search_isi_vector': BASE+0x400})
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
    top = 'tb_compiled_fetch_firmware' if fetch_profile else 'tb_compiled_firmware'
    if live_profile:
        top = 'tb_compiled_live_firmware'
    if irq_profile:
        top = 'tb_compiled_irq_firmware'
    if timer_profile:
        top = 'tb_compiled_timer_firmware'
    if runtime_bat_profile:
        top = 'tb_compiled_runtime_bat_firmware'
    if dsi_profile:
        top = 'tb_compiled_dsi_firmware'
    if segment_profile:
        top = 'tb_compiled_segment_firmware'
    if page_profile:
        top = 'tb_compiled_page_firmware'
    if tlbie_profile:
        top = 'tb_compiled_tlbie_firmware'
    if tlbload_profile:
        top = 'tb_compiled_tlbload_firmware'
    if page_miss_profile:
        top = 'tb_compiled_page_miss_firmware'
    if page_dsi_profile:
        top = 'tb_compiled_page_dsi_firmware'
    if page_isi_profile:
        top = 'tb_compiled_page_isi_firmware'
    if sdr1_profile:
        top = 'tb_compiled_sdr1_firmware'
    if table_search_profile:
        top = 'tb_compiled_table_search_firmware'
    if table_fault_profile:
        top = 'tb_compiled_table_fault_firmware'
    if miss_entry_profile:
        top = 'tb_compiled_miss_entry_firmware'
    if tgpr_profile:
        top = 'tb_compiled_tgpr_firmware'
    if table_bus_profile:
        top = 'tb_compiled_table_bus60x_firmware'
    if table_cached_profile:
        top = 'tb_compiled_table_cached_bus60x_firmware'
    build = args.build_dir.resolve()
    build.mkdir(parents=True, exist_ok=True)
    image = build/'memory.hex'
    image.write_text(''.join(f'{byte:02x}\n' for byte in memory))
    root = Path(__file__).resolve().parent.parent
    sources = []
    manifests = ('files.f',) if fetch_profile else (
        'files.f', 'bus_files.f', 'line_read_files.f', 'icache_files.f', 'cached_system_files.f')
    if table_fault_profile or table_search_profile or miss_entry_profile or tgpr_profile or sdr1_profile or live_profile or irq_profile or timer_profile or runtime_bat_profile or dsi_profile or segment_profile or page_profile or page_dsi_profile or page_isi_profile:
        manifests = ('files.f', 'bat_service_files.f', 'core_bat_files.f')
    if table_bus_profile:
        manifests += ('bus_files.f', 'system_files.f', 'core_bat_bus60x_files.f')
    if table_cached_profile:
        manifests += ('bus_files.f', 'system_files.f', 'line_read_files.f',
                      'icache_files.f', 'cached_system_files.f', 'cache_control_files.f',
                      'core_bat_cached_bus60x_files.f')
    for manifest in manifests:
        for source in (root/'rtl'/manifest).read_text().split():
            if source not in sources:
                sources.append(source)
    profile_params = [f'-GFAULT_PROFILE={int(table_fault_profile)}'] if table_bus_profile or table_cached_profile else []
    subprocess.run([args.verilator, '--binary', '--timing', '--assert', '-Wall', '-j', str(args.jobs),
                    '--top-module', top, '--Mdir', str(build/'obj'),
                    *profile_params, *sources, f'../tb/{top}.sv'], cwd=root/'sim', check=True)
    for mode in (range(3) if tlbie_profile else (range(2) if miss_entry_profile else (None,))):
        mode_args = [] if mode is None else [f'+MODE={mode}']
        subprocess.run([str(build/'obj'/f'V{top}'), f'+IMAGE={image}',
                        f'+TOHOST={mailbox:08x}', *fault_args, *mode_args], check=True)


if __name__ == '__main__':
    main()
