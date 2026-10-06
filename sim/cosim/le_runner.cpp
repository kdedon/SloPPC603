// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Runs the little-endian core program on the unmodified DingusPPC CPU, MMU
// and exception code, built with SUPPORTS_PPC_LITTLE_ENDIAN_MODE=1.
// See LITTLE_ENDIAN_VERIFICATION.md.
#include <cpu/ppc/ppcemu.h>
#include <cpu/ppc/ppcmmu.h>
#include <devices/memctrl/memctrlbase.h>
#include <loguru.hpp>
#include <utils/profiler.h>
#include <array>
#include <cstring>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

struct Region { uint32_t base, bytes; uint8_t* host; };
static std::array<Region, 2> regions{{{0x00000000U, 0x00080000U, nullptr},
                                      {0xfff00000U, 0x00010000U, nullptr}}};
static uint32_t prot_lo = 0, prot_hi = 0, done_addr = 0;
static bool done = false;

static uint8_t* host(uint32_t address) {
    for (auto& r : regions)
        if (address - r.base < r.bytes) return r.host + (address - r.base);
    throw std::runtime_error("address outside RAM");
}

static std::map<PPCOpcode*, std::vector<PPCOpcode>> originals;
static void original(uint32_t opcode) {
    originals.at(ppc_opcode_grabber)[(opcode >> 15 & 0x1F800) | (opcode & 0x7FF)](opcode);
}

// Integer scalar load/store forms: bytes, load, sign-extend, byte-reverse, update.
struct Access { unsigned n; bool load, sign, rev, update; };
static bool decode_access(uint32_t opcode, Access& a, uint32_t& ea) {
    unsigned primary = opcode >> 26, ra = (opcode >> 16) & 31, rb = (opcode >> 11) & 31;
    uint32_t base = ra ? ppc_state.gpr[ra] : 0;
    if (primary == 31) {
        if (opcode & 1) return false;
        switch ((opcode >> 1) & 1023) {
        case 23:  a = {4, true, false, false, false}; break;   // lwzx
        case 55:  a = {4, true, false, false, true}; break;    // lwzux
        case 279: a = {2, true, false, false, false}; break;   // lhzx
        case 311: a = {2, true, false, false, true}; break;    // lhzux
        case 343: a = {2, true, true, false, false}; break;    // lhax
        case 375: a = {2, true, true, false, true}; break;     // lhaux
        case 534: a = {4, true, false, true, false}; break;    // lwbrx
        case 790: a = {2, true, false, true, false}; break;    // lhbrx
        case 151: a = {4, false, false, false, false}; break;  // stwx
        case 183: a = {4, false, false, false, true}; break;   // stwux
        case 407: a = {2, false, false, false, false}; break;  // sthx
        case 439: a = {2, false, false, false, true}; break;   // sthux
        case 662: a = {4, false, false, true, false}; break;   // stwbrx
        case 918: a = {2, false, false, true, false}; break;   // sthbrx
        default: return false;
        }
        ea = base + ppc_state.gpr[rb];
        return true;
    }
    switch (primary) {
    case 32: a = {4, true, false, false, false}; break;  // lwz
    case 33: a = {4, true, false, false, true}; break;   // lwzu
    case 40: a = {2, true, false, false, false}; break;  // lhz
    case 41: a = {2, true, false, false, true}; break;   // lhzu
    case 42: a = {2, true, true, false, false}; break;   // lha
    case 43: a = {2, true, true, false, true}; break;    // lhau
    case 36: a = {4, false, false, false, false}; break; // stw
    case 37: a = {4, false, false, false, true}; break;  // stwu
    case 44: a = {2, false, false, false, false}; break; // sth
    case 45: a = {2, false, false, false, true}; break;  // sthu
    default: return false;
    }
    ea = base + uint32_t(int32_t(int16_t(opcode)));
    return true;
}
static uint32_t byterev(uint32_t v, unsigned n) {
    uint32_t r = 0;
    for (unsigned i = 0; i < n; ++i) r = (r << 8) | ((v >> (8 * i)) & 0xff);
    return r;
}

// Adapter correction. PEM 3.1.4.2: a little-endian access of n bytes moves
// byte i at physical (EA + i) XOR 7, as if the bytes were accessed one at a
// time; the PID7v-603e handles a misaligned one in hardware (UM 1.3).
// DingusPPC munges a misaligned access with the single size XOR and reads
// contiguous bytes there, which matches only for an aligned access. Byte
// accesses go through the reference MMU, which munges each with XOR 7.
static uint64_t le_misaligned_count = 0;
static void le_misaligned(uint32_t opcode, const Access& a, uint32_t ea) {
    unsigned rt = (opcode >> 21) & 31, ra = (opcode >> 16) & 31;
    ++le_misaligned_count;
    if (a.load) {
        uint32_t v = 0;
        for (unsigned i = 0; i < a.n; ++i)
            v |= uint32_t(mmu_read_vmem<uint8_t>(opcode, ea + i)) << (8 * i);
        if (a.rev) v = byterev(v, a.n);
        if (a.sign && a.n == 2) v = uint32_t(int32_t(int16_t(v)));
        ppc_state.gpr[rt] = v;
    } else {
        uint32_t v = ppc_state.gpr[rt];
        if (a.rev) v = byterev(v, a.n);
        for (unsigned i = 0; i < a.n; ++i) mmu_write_vmem<uint8_t>(opcode, ea + i, uint8_t(v >> (8 * i)));
    }
    if (a.update) ppc_state.gpr[ra] = ea;
}

// The bench answers any access to words prot_lo..prot_hi with a protection
// DSI and ends the run on a store to done_addr. This models that bench, not
// CPU behaviour: it raises the reference's own DSI entry with the DAR and
// DSISR a protection fault produces (PEM 6.4.3).
static uint64_t bench_dsi_count = 0;
static void checked_access(uint32_t opcode) {
    Access a;
    uint32_t ea;
    if (!decode_access(opcode, a, ea)) { original(opcode); return; }
    uint32_t last = ea + a.n - 1;
    if ((last & ~3U) >= prot_lo && (ea & ~3U) <= prot_hi) {
        ++bench_dsi_count;
        ppc_state.spr[SPR::DAR] = ea;
        ppc_state.spr[SPR::DSISR] = 0x08000000U | (a.load ? 0U : 0x02000000U);
        ppc_exception_handler(Except_Type::EXC_DSI, 0);
    }
    if (ppc_state.is_LE && (ea % a.n) != 0) le_misaligned(opcode, a, ea);
    else original(opcode);
    if (!a.load && (ea & ~3U) <= done_addr && (last & ~3U) >= done_addr) done = true;
}
// Adapter corrections: alignment exceptions DingusPPC omits. UM 4.5.6:
// lwarx and FP accesses at an EA that is not word aligned take alignment
// (FP unavailable has priority); UM 2.3.4.3.6-7:
// multiples and strings in little-endian mode do. UM 4.5.6.2 (603e note):
// DAR = EA + 4 for lmw/stmw. DSISR follows Table 4-13, with bits 27-31 = rA
// (DingusPPC leaves them clear for lmw, lswi and lswx).
static uint64_t alignment_count = 0;
static void alignment(uint32_t opcode, uint32_t dar, bool x_form) {
    ++alignment_count;
    uint32_t dsisr = x_form ? (((opcode << 14) & 0x00018000U) | ((opcode << 8) & 0x00004000U) |
                               ((opcode << 3) & 0x00003c00U))
                            : (((opcode >> 12) & 0x00004000U) | ((opcode >> 17) & 0x00003c00U));
    dsisr |= ((opcode >> 16) & 0x000003e0U) | ((opcode >> 16) & 0x1fU);
    ppc_state.spr[SPR::DAR] = dar;
    ppc_state.spr[SPR::DSISR] = dsisr;
    ppc_exception_handler(Except_Type::EXC_ALIGNMENT, 0);
}
// lfsx lfsux lfdx lfdux stfsx stfsux stfdx stfdux stfiwx
static const uint32_t FP_X[] = {535, 567, 599, 631, 663, 695, 727, 759, 983};
static bool is_fp_x(uint32_t xo) {
    for (uint32_t x : FP_X) if (x == xo) return true;
    return false;
}
// Adapter correction, as for le_misaligned: a little-endian FP doubleword at
// EA = 4 mod 8 (split in hardware on the PID7v-603e, UM 1.3) moves byte i at
// (EA + i) XOR 7 (PEM 3.1.4.2). DingusPPC moves other bytes for both loads
// and stores.
static uint64_t le_fp_split_count = 0;
static bool le_fp_split(uint32_t opcode, uint32_t ea, bool store, bool update) {
    if (!ppc_state.is_LE || !(ea & 4)) return false;
    ++le_fp_split_count;
    uint64_t& fr = ppc_state.fpr[(opcode >> 21) & 31].int64_r;
    if (store) {
        for (unsigned i = 0; i < 8; ++i) mmu_write_vmem<uint8_t>(opcode, ea + i, uint8_t(fr >> (8 * i)));
    } else {
        uint64_t v = 0;
        for (unsigned i = 0; i < 8; ++i) v |= uint64_t(mmu_read_vmem<uint8_t>(opcode, ea + i)) << (8 * i);
        fr = v;
    }
    if (update) ppc_state.gpr[(opcode >> 16) & 31] = ea;
    return true;
}
static void alignment_rules(uint32_t opcode) {
    unsigned primary = opcode >> 26, xo = (opcode >> 1) & 1023;
    unsigned ra = (opcode >> 16) & 31, rb = (opcode >> 11) & 31;
    uint32_t base = ra ? ppc_state.gpr[ra] : 0;
    bool fp_enabled = ppc_state.msr & MSR::FP;
    if (primary >= 48 && primary <= 55) {
        uint32_t ea = base + uint32_t(int32_t(int16_t(opcode)));
        if (fp_enabled && (ea & 3)) alignment(opcode, ea, false);
        if (fp_enabled && (primary == 50 || primary == 51 || primary == 54 || primary == 55) &&
            le_fp_split(opcode, ea, primary >= 54, primary == 51 || primary == 55))
            return;
    } else if (primary == 46 || primary == 47) {
        if (ppc_state.is_LE) alignment(opcode, base + uint32_t(int32_t(int16_t(opcode))) + 4, false);
    } else if (xo == 20 || is_fp_x(xo)) {
        uint32_t ea = base + ppc_state.gpr[rb];
        if ((xo == 20 || fp_enabled) && (ea & 3)) alignment(opcode, ea, true);
        if (fp_enabled && (xo == 599 || xo == 631 || xo == 727 || xo == 759) &&
            le_fp_split(opcode, ea, xo >= 727, xo == 631 || xo == 759))
            return;
    } else if (ppc_state.is_LE) {
        alignment(opcode, (xo == 597 || xo == 725) ? base : base + ppc_state.gpr[rb], true);
    }
    original(opcode);
}

static void patch_table() {
    PPCOpcode* table = ppc_opcode_grabber;
    if (originals.count(table)) return;
    originals[table].assign(table, table + 0x20000);
    for (uint32_t index = 0; index < 0x20000; ++index) {
        uint32_t opcode = (index & 0x1F800) << 15 | (index & 0x7FF);
        Access a;
        uint32_t ea;
        if (decode_access(opcode, a, ea)) table[index] = checked_access;
    }
    for (uint32_t primary = 46; primary < 56; ++primary)
        for (uint32_t mod = 0; mod < 2048; ++mod) table[(primary << 11) | mod] = alignment_rules;
    for (uint32_t xo : {20U, 533U, 597U, 661U, 725U}) table[(31U << 11) | (xo << 1)] = alignment_rules;
    for (uint32_t xo : FP_X) table[(31U << 11) | (xo << 1)] = alignment_rules;
}

static uint32_t hex(const std::string& text) {
    size_t used = 0;
    unsigned long value = std::stoul(text, &used, 16);
    if (used != text.size() || value > 0xffffffffUL) throw std::runtime_error("bad hex " + text);
    return uint32_t(value);
}

int main(int argc, char** argv) {
    try {
        if (argc != 6)
            throw std::runtime_error("usage: le_runner image.txt reset_pc trace memdump max_steps");
        loguru::g_stderr_verbosity = loguru::Verbosity_WARNING;
        uint32_t reset_pc = hex(argv[2]);
        uint64_t max_steps = std::stoull(argv[5]);
        MemCtrlBase memory;
        for (auto& r : regions) {
            if (!memory.add_ram_region(r.base, r.bytes)) throw std::runtime_error("RAM region");
            r.host = memory.get_region_hostmem_ptr(r.base);
            std::memset(r.host, 0, r.bytes);
        }
        // Image lines: M addr word, E addr value mask, P lo hi, D addr.
        std::ifstream image(argv[1]);
        if (!image) throw std::runtime_error("cannot open image");
        std::string line;
        while (std::getline(image, line)) {
            std::istringstream fields(line);
            std::string tag, a, b, c;
            fields >> tag >> a >> b >> c;
            if (tag == "M") {
                uint32_t addr = hex(a), word = hex(b);
                for (unsigned i = 0; i < 4; ++i) *host(addr + i) = uint8_t(word >> (24 - 8 * i));
            } else if (tag == "P") { prot_lo = hex(a); prot_hi = hex(b); }
            else if (tag == "D") done_addr = hex(a);
            else if (tag != "E" && !tag.empty()) throw std::runtime_error("bad image tag " + tag);
        }
        is_deterministic = true;
        gProfilerObj.reset(new Profiler());
        ppc_cpu_init(&memory, PPC_VER::MPC603EV, false, 25000000ULL);
        ppc_state.spr[SPR::PVR] = 0x00070200U;  // UM 1.3.1.2 PID7v level
        ppc_state.pc = reset_pc;
        std::ofstream trace(argv[3]);
        if (!trace) throw std::runtime_error("cannot open trace");
        trace << std::hex << std::setfill('0');
        uint64_t step = 0, srr1_count = 0;
        for (; !done; ++step) {
            if (step >= max_steps) throw std::runtime_error("step limit before the final store");
            uint32_t pc = ppc_state.pc;
            std::array<uint32_t, 32> before;
            std::memcpy(before.data(), ppc_state.gpr, sizeof(before));
            uint64_t exceptions = exceptions_processed;
            patch_table();
            ppc_exec_single();
            // Adapter correction. UM 4.5.8 and 4.5.10: FP unavailable and
            // system call clear SRR1 bits 0-15; the reference sets bit 11 and
            // bit 14 respectively.
            if (exceptions_processed != exceptions) {
                uint32_t vector = ppc_state.pc & 0x000fffffU, srr1 = ppc_state.spr[SPR::SRR1];
                if (vector == 0x00000800U) ppc_state.spr[SPR::SRR1] &= ~0x00100000U;
                if (vector == 0x00000c00U) ppc_state.spr[SPR::SRR1] &= ~0x00020000U;
                srr1_count += srr1 != ppc_state.spr[SPR::SRR1];
            }
            trace << std::setw(8) << pc << ' ' << (exceptions_processed != exceptions ? 1 : 0);
            for (unsigned r = 0; r < 32; ++r)
                if (ppc_state.gpr[r] != before[r])
                    trace << ' ' << std::dec << r << std::hex << '=' << std::setw(8) << ppc_state.gpr[r];
            trace << '\n';
        }
        std::ofstream dump(argv[4]);
        dump << std::hex << std::setfill('0');
        for (auto& r : regions)
            for (uint32_t o = 0; o < r.bytes; o += 4) {
                uint32_t w = uint32_t(r.host[o]) << 24 | uint32_t(r.host[o + 1]) << 16 |
                             uint32_t(r.host[o + 2]) << 8 | r.host[o + 3];
                if (w) dump << std::setw(8) << r.base + o << ' ' << std::setw(8) << w << '\n';
            }
        std::cout << "steps=" << std::dec << step << " exceptions=" << exceptions_processed
                  << " bench_dsi=" << bench_dsi_count << " le_misaligned=" << le_misaligned_count
                  << " alignment=" << alignment_count << " le_fp_split=" << le_fp_split_count
                  << " srr1=" << srr1_count << '\n';
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "LE reference error: " << e.what() << '\n';
        return 2;
    }
}
