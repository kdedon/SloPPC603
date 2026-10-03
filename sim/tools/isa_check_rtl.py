#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Kevin Dedon
"""Compile ppc_decode per opt-in profile and compare legality with ISA masks."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "sim/spec/isa.json"
sys.path.insert(0, str(Path(__file__).resolve().parent))
from isa_generate import DECODE_PARAMETERS, feature_profile  # noqa: E402

SUP, LIVE = "ENABLE_SUPERVISOR_EXCEPTIONS", "ENABLE_LIVE_CONTEXT"
SPR_FIELD = 0x001FF800
OPT_IN_STATUSES = {
    "implemented_opt_in_supervisor", "implemented_opt_in_serialization", "implemented_opt_in_profile",
}

# Each profile satisfies the core's parameter prerequisites.
PROFILES: list[tuple[str, frozenset[str]]] = [
    ("default", frozenset()),
    ("supervisor", frozenset({SUP})),
    ("live", frozenset({SUP, LIVE})),
    ("timers", frozenset({SUP, LIVE, "ENABLE_TIMERS"})),
    ("runtime_bat", frozenset({SUP, LIVE, "ENABLE_RUNTIME_BAT"})),
    ("segments", frozenset({SUP, LIVE, "ENABLE_SEGMENT_REGISTERS"})),
    ("tlbie", frozenset({SUP, LIVE, "ENABLE_TLB_INVALIDATE"})),
    ("tlb_load", frozenset({SUP, LIVE, "ENABLE_TLB_LOAD"})),
    ("sdr1", frozenset({SUP, LIVE, "ENABLE_SDR1"})),
    ("tlb_miss", frozenset({SUP, LIVE, "ENABLE_SDR1", "ENABLE_TLB_LOAD", "ENABLE_TLB_MISS_EXCEPTIONS"})),
    ("cache", frozenset({SUP, "ENABLE_CACHE_INSTRUCTIONS"})),
    ("byte_reverse", frozenset({SUP, "ENABLE_BYTE_REVERSE"})),
    ("multiple_string", frozenset({SUP, "ENABLE_MULTIPLE_STRING"})),
    ("reservation", frozenset({SUP, "ENABLE_CACHE_INSTRUCTIONS", "ENABLE_RESERVATION"})),
    ("full_decode", frozenset({SUP, LIVE, "ENABLE_FULL_DECODE"})),
    ("all_base", frozenset(DECODE_PARAMETERS) - {"ENABLE_FULL_DECODE"}),
    # The translated MVP decode profile.
    ("all", frozenset(DECODE_PARAMETERS)),
]

# The decoder rejects XO 371 reads that the 603e bit-25 rule makes legal.
# Remove once ppc_decode aliases MFTB to MFSPR for every implemented selector.
PENDING_MFTB_ALIAS = False


def enabled_profiles(entry: dict[str, object]) -> int:
    status = entry["implementation"]["status"]  # type: ignore[index]
    if status == "implemented":
        return (1 << len(PROFILES)) - 1
    if status not in OPT_IN_STATUSES:
        return 0
    need = set(feature_profile(entry))  # type: ignore[arg-type]
    return sum(1 << index for index, (_, params) in enumerate(PROFILES) if need <= params)


def _term(entry: dict[str, object], ignored: int, read_xo: list[int]) -> str:
    mask, value = int(entry["mask"], 16), int(entry["value"], 16)  # type: ignore[arg-type]
    spr_read = entry["form"] == "XFX" and value >> 26 == 31 and (value >> 1) & 0x3FF in read_xo
    if spr_read and mask & SPR_FIELD == SPR_FIELD:
        mask &= ~ignored
        value &= ~ignored
    term = f"((word & UINT32_C({mask:#010x})) == UINT32_C({value:#010x}))"
    if "allowed_bo" in entry:
        allowed = " || ".join(f"(((word >> 21) & 31) == {bo})" for bo in entry["allowed_bo"])  # type: ignore[union-attr]
        term = f"({term} && ({allowed}))"
    if entry.get("semantic_class") == "load_multiple":
        # rA in the loaded range (rA >= rD, including rA = rD = 0) is invalid.
        term = f"({term} && (((word >> 16) & 31) < ((word >> 21) & 31)))"
    if entry.get("semantic_class") == "lsu_update":
        term = f"({term} && (((word >> 16) & 31) != 0))"
        if "rD" in entry.get("writes", []):  # type: ignore[operator]
            term = f"({term} && (((word >> 16) & 31) != ((word >> 21) & 31)))"
    return term


def _targeted_words(entries: list[dict[str, object]]) -> list[int]:
    """Each entry's value, all don't-care bits set, and every single-bit mutation of a fixed bit."""
    words = set()
    for entry in entries:
        mask, value = int(entry["mask"], 16), int(entry["value"], 16)  # type: ignore[arg-type]
        words.update({value, value | (~mask & 0xFFFFFFFF)})
        words.update(value ^ (1 << bit) for bit in range(32) if mask >> bit & 1)
    return sorted(words)


def _probe_sv() -> str:
    lines = [
        f"module isa_decode_probe(input logic [31:0] insn_i, output logic [{len(PROFILES) - 1}:0] reject_o);",
        "  import ppc_pkg::*;",
    ]
    for index, (name, params) in enumerate(PROFILES):
        overrides = ", ".join(f".{p}(1'b{int(p in params)})" for p in DECODE_PARAMETERS)
        lines += [
            f"  uop_t uop_{name};",
            f"  ppc_decode #({overrides}) decode_{name}(.insn_i(insn_i), .uop_o(uop_{name}));",
            # The all-zero word under supervisor exceptions raises a precise illegal-instruction program exception.
            f"  assign reject_o[{index}] = uop_{name}.illegal || (uop_{name}.special_op == SPECIAL_PROGRAM_ILLEGAL);",
        ]
    return "\n".join(lines + ["endmodule", ""])


def _cpp(entries: list[dict[str, object]], rule: dict[str, object]) -> str:
    ignored = int(rule["ignored_bit_mask"], 16)  # type: ignore[arg-type]
    read_xo = list(rule["extended_opcodes"])  # type: ignore[call-overload]
    terms = []
    for entry in entries:
        profiles = enabled_profiles(entry)
        if profiles:
            terms.append(f"(((UINT32_C({profiles}) >> profile) & 1) && {_term(entry, ignored, read_xo)})")
    conditions = " ||\n        ".join(terms)
    targeted = ", ".join(f"UINT32_C({word:#010x})" for word in _targeted_words(entries))
    names = ", ".join(f'"{name}"' for name, _ in PROFILES)
    return f'''#include "Visa_decode_probe.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>

static constexpr unsigned kProfiles = {len(PROFILES)};
static const char* const kNames[kProfiles] = {{{names}}};
static unsigned probes = 0, accepted[kProfiles] = {{}}, mismatches[kProfiles] = {{}};

static bool expected(unsigned profile, uint32_t word) {{
    return {conditions};
}}

static void check(Visa_decode_probe& top, uint32_t word) {{
    top.insn_i = word;
    top.eval();
    ++probes;
    for (unsigned p = 0; p < kProfiles; ++p) {{
        const bool want = expected(p, word);
        const bool got = !((top.reject_o >> p) & 1);
        accepted[p] += got;
        if (want != got) {{
            ++mismatches[p];
            std::printf("MISMATCH %s %08x expected=%u got=%u\\n", kNames[p], word, want, got);
        }}
    }}
}}

int main(int argc, char** argv) {{
    Verilated::commandArgs(argc, argv);
    Visa_decode_probe top;
    constexpr std::array<uint32_t, 5> payloads = {{
        UINT32_C(0x00000000), UINT32_C(0x03ffffff), UINT32_C(0x02aa5555),
        UINT32_C(0x0155aaaa), UINT32_C(0x0210f81f)
    }};
    constexpr std::array<uint32_t, 8> register_fields = {{
        UINT32_C(0x00000000), UINT32_C(0x03fff800), UINT32_C(0x02aaa800),
        UINT32_C(0x01555000), UINT32_C(0x0210f800), UINT32_C(0x0000f800),
        UINT32_C(0x000f0000), UINT32_C(0x03e00000)
    }};
    constexpr uint32_t targeted[] = {{{targeted}}};
    for (uint32_t primary = 0; primary < 64; ++primary)
        for (uint32_t payload : payloads) check(top, (primary << 26) | payload);
    // Every opcode-31 XO/OE/Rc combination with varied register fields.
    for (uint32_t xo = 0; xo < 512; ++xo)
        for (uint32_t oe = 0; oe < 2; ++oe)
            for (uint32_t rc = 0; rc < 2; ++rc)
                for (uint32_t regs : register_fields)
                    check(top, (UINT32_C(31) << 26) | regs | (oe << 10) | (xo << 1) | rc);
    // Every opcode-19 XL XO/Rc combination with varied CR/branch fields.
    for (uint32_t xo = 0; xo < 1024; ++xo)
        for (uint32_t rc = 0; rc < 2; ++rc)
            for (uint32_t regs : register_fields)
                check(top, (UINT32_C(19) << 26) | regs | (xo << 1) | rc);
    // Every opcode-59/63 XO/Rc combination: FP A-forms vary frC in word bits 10:6.
    for (uint32_t primary : {{59u, 63u}})
        for (uint32_t xo = 0; xo < 1024; ++xo)
            for (uint32_t rc = 0; rc < 2; ++rc)
                for (uint32_t regs : register_fields)
                    check(top, (primary << 26) | regs | (xo << 1) | rc);
    // Branch option values, BI extremes and the reserved XL field.
    for (uint32_t bo = 0; bo < 32; ++bo)
        for (uint32_t bi : {{0u, 7u, 31u}})
            for (uint32_t lk = 0; lk < 2; ++lk) {{
                for (uint32_t aa = 0; aa < 2; ++aa)
                    check(top, (16u << 26) | (bo << 21) | (bi << 16) | 0xfffcu | (aa << 1) | lk);
                for (uint32_t xo : {{16u, 528u}})
                    for (uint32_t reserved : {{0u, 31u}})
                        check(top, (19u << 26) | (bo << 21) | (bi << 16) | (reserved << 11) | (xo << 1) | lk);
            }}
    // Swapped SPR fields, MFSPR/MFTB/MTSPR and reserved Rc across the complete SPR space.
    for (uint32_t spr = 0; spr < 1024; ++spr)
        for (uint32_t xo : {{339u, 371u, 467u}})
            for (uint32_t rc = 0; rc < 2; ++rc)
                check(top, (31u << 26) | (7u << 21) | ((spr & 31u) << 16) | ((spr >> 5) << 11) | (xo << 1) | rc);
    for (uint32_t word : targeted) check(top, word);
    for (unsigned p = 0; p < kProfiles; ++p)
        std::printf("PROFILE %s probes=%u accepted=%u mismatches=%u\\n", kNames[p], probes, accepted[p], mismatches[p]);
    return 0;
}}
'''


@dataclass
class Result:
    returncode: int
    profiles: dict[str, tuple[int, int, int]] = field(default_factory=dict)
    mismatches: list[tuple[str, int, int, int]] = field(default_factory=list)
    log: str = ""

    def pending(self) -> list[tuple[str, int, int, int]]:
        return [m for m in self.mismatches if PENDING_MFTB_ALIAS and _mftb_alias_gap(m)]

    def unexpected(self) -> list[tuple[str, int, int, int]]:
        return [m for m in self.mismatches if not (PENDING_MFTB_ALIAS and _mftb_alias_gap(m))]


def _mftb_alias_gap(mismatch: tuple[str, int, int, int]) -> bool:
    _, word, want, got = mismatch
    return word >> 26 == 31 and (word >> 1) & 0x3FF == 371 and want == 1 and got == 0


def run() -> Result:
    spec = json.loads(SPEC.read_text())
    entries = spec["decode_entries"]
    with tempfile.TemporaryDirectory(prefix="ppc603e-isa-decode-") as temp_name:
        temp = Path(temp_name)
        probe_sv, probe_cpp, obj_dir = temp / "isa_decode_probe.sv", temp / "isa_decode_probe.cpp", temp / "obj"
        probe_sv.write_text(_probe_sv())
        probe_cpp.write_text(_cpp(entries, spec["spr_read_opcode_equivalence"]))
        build = subprocess.run(
            [
                "verilator", "--cc", "--exe", "--build", "-Wall", "-Wno-DECLFILENAME",
                "-Wno-UNUSEDSIGNAL", "-Wno-UNUSEDPARAM",
                "--top-module", "isa_decode_probe", "--Mdir", str(obj_dir),
                str(ROOT / "rtl/ppc_pkg.sv"), str(ROOT / "rtl/ppc_decode.sv"),
                str(probe_sv), str(probe_cpp),
            ],
            cwd=ROOT, text=True, capture_output=True,
        )
        if build.returncode:
            return Result(build.returncode, log=build.stdout + build.stderr)
        sim = subprocess.run([str(obj_dir / "Visa_decode_probe")], cwd=ROOT, text=True, capture_output=True)
    result = Result(sim.returncode, log=sim.stderr)
    for line in sim.stdout.splitlines():
        fields = line.split()
        if fields[0] == "MISMATCH":
            result.mismatches.append((fields[1], int(fields[2], 16),
                                      int(fields[3].split("=")[1]), int(fields[4].split("=")[1])))
        elif fields[0] == "PROFILE":
            values = [int(item.split("=")[1]) for item in fields[2:]]
            result.profiles[fields[1]] = (values[0], values[1], values[2])
    return result


def main() -> int:
    result = run()
    if result.returncode or not result.profiles:
        print(result.log, end="", file=sys.stderr)
        return result.returncode or 1
    for name, (probes, accepted, mismatches) in result.profiles.items():
        print(f"{name}: {probes} probes, {accepted} accepted, {mismatches} mismatches")
    for name, word, want, got in result.unexpected()[:40]:
        print(f"decoder mismatch profile={name} word={word:08x} expected={want} got={got}", file=sys.stderr)
    pending = result.pending()
    if pending:
        print(f"EXPECTED-FAIL: {len(pending)} XO 371 reads rejected despite the 603e MFTB/MFSPR equivalence")
    elif PENDING_MFTB_ALIAS:
        print("MFTB alias gap resolved: clear PENDING_MFTB_ALIAS", file=sys.stderr)
        return 3
    if result.unexpected():
        print(f"FAIL: {len(result.unexpected())} unexpected decoder mismatches", file=sys.stderr)
        return 2
    print("PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
