#!/usr/bin/env python3
"""Compile ppc_decode and compare its legal/illegal result with ISA masks."""

from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = ROOT / "sim/spec/isa.json"


def _cpp(entries: list[dict[str, object]]) -> str:
    terms = []
    for entry in entries:
        term = f"((word & UINT32_C({entry['mask']})) == UINT32_C({entry['value']}))"
        if "allowed_bo" in entry:
            allowed = " || ".join(f"(((word >> 21) & 31) == {bo})" for bo in entry["allowed_bo"])
            term = f"({term} && ({allowed}))"
        if entry.get("semantic_class") == "lsu_update":
            term = f"({term} && (((word >> 16) & 31) != 0))"
            if "rD" in entry.get("writes", []):
                term = f"({term} && (((word >> 16) & 31) != ((word >> 21) & 31)))"
        terms.append(term)
    conditions = " ||\n        ".join(terms)
    return f'''#include "Visa_decode_probe.h"
#include "verilated.h"
#include <array>
#include <cstdint>
#include <cstdio>

static bool expected(uint32_t word) {{
    return {conditions};
}}

static bool check(Visa_decode_probe& top, uint32_t word, unsigned& accepted) {{
    top.insn_i = word;
    top.eval();
    const bool want = expected(word);
    const bool got = !top.illegal_o;
    accepted += got;
    if (want != got) {{
        std::fprintf(stderr, "decoder mismatch word=%08x expected=%u got=%u\\n", word, want, got);
        return false;
    }}
    return true;
}}

int main(int argc, char** argv) {{
    Verilated::commandArgs(argc, argv);
    Visa_decode_probe top;
    constexpr std::array<uint32_t, 5> payloads = {{
        UINT32_C(0x00000000), UINT32_C(0x03ffffff), UINT32_C(0x02aa5555),
        UINT32_C(0x0155aaaa), UINT32_C(0x0210f81f)
    }};
    constexpr std::array<uint32_t, 5> register_fields = {{
        UINT32_C(0x00000000), UINT32_C(0x03fff800), UINT32_C(0x02aaa800),
        UINT32_C(0x01555000), UINT32_C(0x0210f800)
    }};
    unsigned probes = 0, accepted = 0;
    for (uint32_t primary = 0; primary < 64; ++primary) {{
        for (uint32_t payload : payloads) {{
            ++probes;
            if (!check(top, (primary << 26) | payload, accepted)) return 1;
        }}
    }}
    // Exhaust every opcode-31 XO/OE/Rc combination with varied register fields.
    for (uint32_t xo = 0; xo < 512; ++xo) {{
        for (uint32_t oe = 0; oe < 2; ++oe) {{
            for (uint32_t rc = 0; rc < 2; ++rc) {{
                for (uint32_t regs : register_fields) {{
                    const uint32_t word = (UINT32_C(31) << 26) | regs | (oe << 10) | (xo << 1) | rc;
                    ++probes;
                    if (!check(top, word, accepted)) return 1;
                }}
            }}
        }}
    }}
    // Exhaust every opcode-19 XL XO/Rc combination with varied CR/branch
    // fields. This independently covers all CR logical encodings and their
    // fixed-zero Rc bit; branch legality remains constrained by its metadata.
    for (uint32_t xo = 0; xo < 1024; ++xo) {{
        for (uint32_t rc = 0; rc < 2; ++rc) {{
            for (uint32_t regs : register_fields) {{
                const uint32_t word = (UINT32_C(19) << 26) | regs | (xo << 1) | rc;
                ++probes;
                if (!check(top, word, accepted)) return 1;
            }}
        }}
    }}
    // Exhaust branch option values/BI extremes and the reserved XL field.
    for (uint32_t bo = 0; bo < 32; ++bo) {{
        for (uint32_t bi : {{0u, 7u, 31u}}) {{
            for (uint32_t lk = 0; lk < 2; ++lk) {{
                for (uint32_t aa = 0; aa < 2; ++aa) {{
                    ++probes;
                    if (!check(top, (16u << 26) | (bo << 21) | (bi << 16) | 0xfffcu | (aa << 1) | lk, accepted)) return 1;
                }}
                for (uint32_t xo : {{16u, 528u}}) {{
                    for (uint32_t reserved : {{0u, 31u}}) {{
                        ++probes;
                        if (!check(top, (19u << 26) | (bo << 21) | (bi << 16) | (reserved << 11) | (xo << 1) | lk, accepted)) return 1;
                    }}
                }}
            }}
        }}
    }}
    // Verify swapped SPR fields and reserved Rc across the complete SPR space.
    for (uint32_t spr = 0; spr < 1024; ++spr) {{
        for (uint32_t xo : {{339u, 467u}}) {{
            for (uint32_t rc = 0; rc < 2; ++rc) {{
                ++probes;
                const uint32_t word = (31u << 26) | (7u << 21) | ((spr & 31u) << 16) | ((spr >> 5) << 11) | (xo << 1) | rc;
                if (!check(top, word, accepted)) return 1;
            }}
        }}
    }}
    std::printf("PASS: %u compiled decoder probes, %u accepted by metadata and RTL\\n", probes, accepted);
    return probes == 26048 ? 0 : 2;
}}
'''


def run() -> subprocess.CompletedProcess[str]:
    spec = json.loads(SPEC.read_text())
    entries = [entry for entry in spec["decode_entries"] if entry["implementation"]["status"] == "implemented"]
    with tempfile.TemporaryDirectory(prefix="ppc603e-isa-decode-") as temp_name:
        temp = Path(temp_name)
        probe_sv = temp / "isa_decode_probe.sv"
        probe_cpp = temp / "isa_decode_probe.cpp"
        obj_dir = temp / "obj"
        probe_sv.write_text(
            "module isa_decode_probe(input logic [31:0] insn_i, output logic illegal_o);\n"
            "  ppc_pkg::uop_t uop;\n"
            "  ppc_decode decode(.insn_i(insn_i), .uop_o(uop));\n"
            "  assign illegal_o = uop.illegal;\n"
            "endmodule\n"
        )
        probe_cpp.write_text(_cpp(entries))
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
            return build
        return subprocess.run([str(obj_dir / "Visa_decode_probe")], cwd=ROOT, text=True, capture_output=True)


def main() -> int:
    result = run()
    print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=__import__("sys").stderr)
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
