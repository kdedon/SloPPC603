#!/usr/bin/env python3
"""Check the bootstrap ELF identity, byte order, and required symbols."""

from __future__ import annotations

import struct
import sys
import re
from pathlib import Path


def elf32_sections(path: Path, expected_data: int) -> tuple[int, bytes]:
    data = path.read_bytes()
    if data[:4] != b"\x7fELF" or data[4] != 1:
        raise ValueError(f"{path}: not ELF32")
    if data[5] != expected_data:
        raise ValueError(f"{path}: EI_DATA={data[5]}, expected {expected_data}")
    order = ">" if expected_data == 2 else "<"
    header = struct.unpack_from(order + "HHIIIIIHHHHHH", data, 16)
    e_machine, e_entry = header[1], header[3]
    e_shoff, e_shentsize, e_shnum, e_shstrndx = header[5], header[10], header[11], header[12]
    if e_machine != 20:
        raise ValueError(f"{path}: e_machine={e_machine}, expected EM_PPC (20)")
    sections = [
        struct.unpack_from(order + "IIIIIIIIII", data, e_shoff + i * e_shentsize)
        for i in range(e_shnum)
    ]
    shstr = sections[e_shstrndx]
    names = data[shstr[4] : shstr[4] + shstr[5]]

    def name_at(offset: int) -> str:
        end = names.find(b"\0", offset)
        return names[offset:end].decode("ascii")

    for section in sections:
        if name_at(section[0]) == ".text.boot":
            return e_entry, data[section[4] : section[4] + section[5]]
    raise ValueError(f"{path}: no .text.boot section")


def require_dump(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    for symbol in ("<_start>:", "<main>:"):
        if symbol not in text:
            raise ValueError(f"{path}: disassembly is missing {symbol}")
    if re.search(r"(?m)^\S+\s+g\s+O\s+\.tohost\s+\S+\s+tohost$", text) is None:
        raise ValueError(f"{path}: symbol table is missing global .tohost object")


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        print("usage: check_artifacts.py BE_ELF BE_DUMP LE_ELF LE_DUMP", file=sys.stderr)
        return 2
    be_elf, be_dump, le_elf, le_dump = map(Path, argv[1:])
    be_entry, be_boot = elf32_sections(be_elf, 2)
    le_entry, le_boot = elf32_sections(le_elf, 1)
    if be_entry != 0xFFF00100 or le_entry != be_entry:
        raise ValueError(f"entry mismatch: BE={be_entry:#x}, LE={le_entry:#x}")
    if be_boot[:4] != bytes.fromhex("60 00 00 00"):
        raise ValueError(f"BE first word is {be_boot[:4].hex(' ')}")
    if le_boot[:4] != bytes.fromhex("00 00 00 60"):
        raise ValueError(f"LE first word is {le_boot[:4].hex(' ')}")
    require_dump(be_dump)
    require_dump(le_dump)
    print("PASS: ELF32 PowerPC BE/LE identity, entry point, byte order, and symbols")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
