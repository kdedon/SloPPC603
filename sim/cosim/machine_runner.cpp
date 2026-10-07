// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Whole-machine lockstep: steps the unmodified DingusPPC CPU, MMU and
// exception code against an RTL retirement trace (tb/machine_trace.svh) and
// compares architectural state and stores after every retirement. See
// REFERENCE_MACHINE.md.
#include <cpu/ppc/ppcemu.h>
#include <cpu/ppc/ppcmmu.h>
#include <devices/common/mmiodevice.h>
#include <devices/memctrl/memctrlbase.h>
#include <loguru.hpp>
#include <utils/profiler.h>
#include "reference_adapter.h"
#include <array>
#include <csetjmp>
#include <csignal>
#include <cstring>
#include <deque>
#include <fstream>
#include <iostream>
#include <map>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

static uint32_t hex(const std::string& text) {
    size_t used = 0;
    unsigned long value = std::stoul(text, &used, 16);
    if (used != text.size() || value > 0xffffffffUL) throw std::runtime_error("bad hex " + text);
    return uint32_t(value);
}

static std::string h8(uint32_t v) {
    char text[9];
    std::snprintf(text, sizeof(text), "%08x", v);
    return text;
}

// Machine registers: reads return the value the RTL load retired with, since
// counters and timers are implementation timing. Writes are logged per step.
struct InjectedIo : MMIODevice {
    uint32_t base = 0, pending = 0;
    bool have_pending = false;
    uint64_t reads = 0;
    std::vector<std::pair<uint32_t, uint8_t>> writes;
    uint32_t read(uint32_t, uint32_t offset, int size) override {
        if (!have_pending)
            throw std::runtime_error("I/O read at " + h8(base + offset) + " by a non-load");
        ++reads;
        return size == 4 ? pending : size == 2 ? (pending & 0xffffU) : (pending & 0xffU);
    }
    void write(uint32_t, uint32_t offset, uint32_t value, int size) override {
        for (int i = 0; i < size; ++i)
            writes.push_back({base + offset + i, uint8_t(value >> (8 * (size - 1 - i)))});
    }
};

// State fields in trace order: r0-r31 then these.
static const char* const NAMES[] = {"cr", "xer", "lr", "ctr", "msr", "srr0", "srr1",
                                    "dar", "dsisr", "sprg0", "sprg1", "sprg2", "sprg3",
                                    "t0", "t1", "t2", "t3"};
static constexpr int FIELDS = 49;

// The reference has no TGPRs: while MSR[TGPR] is set its r0-r3 stand for
// them and the architectural r0-r3 wait in saved; otherwise tgpr holds them.
static uint32_t saved[4], tgpr[4];
static bool tgpr_on() { return ppc_state.msr & MSR::TGPR; }

static std::array<uint32_t, FIELDS> reference_state() {
    std::array<uint32_t, FIELDS> s{};
    std::memcpy(s.data(), ppc_state.gpr, 32 * 4);
    for (int i = 0; i < 4; ++i) {
        s[45 + i] = tgpr_on() ? ppc_state.gpr[i] : tgpr[i];
        if (tgpr_on()) s[i] = saved[i];
    }
    s[32] = ppc_state.cr;
    s[33] = ppc_state.spr[SPR::XER];
    s[34] = ppc_state.spr[SPR::LR];
    s[35] = ppc_state.spr[SPR::CTR];
    s[36] = ppc_state.msr;
    s[37] = ppc_state.spr[SPR::SRR0];
    s[38] = ppc_state.spr[SPR::SRR1];
    s[39] = ppc_state.spr[SPR::DAR];
    s[40] = ppc_state.spr[SPR::DSISR];
    for (int i = 0; i < 4; ++i) s[41 + i] = ppc_state.spr[SPR::SPRG0 + i];
    return s;
}

static std::string field_name(int i) { return i < 32 ? "r" + std::to_string(i) : NAMES[i - 32]; }

static int field_index(const std::string& name) {
    if (name.size() > 1 && name[0] == 'r' && std::isdigit(name[1])) return std::stoi(name.substr(1));
    for (int i = 0; i < FIELDS - 32; ++i)
        if (name == NAMES[i]) return 32 + i;
    throw std::runtime_error("unknown field " + name);
}

// Destination of an integer load whose value may come from an I/O read, and
// whether the register holds it byte-reversed (0, 2 or 4 bytes).
static bool load_target(uint32_t insn, unsigned& rd, int& reverse) {
    unsigned op = insn >> 26, xo = (insn >> 1) & 1023;
    rd = (insn >> 21) & 31;
    reverse = 0;
    if ((op >= 32 && op <= 35) || (op >= 40 && op <= 43)) return true;
    if (op != 31) return false;
    switch (xo) {
    case 23: case 55: case 87: case 119: case 279: case 311: case 343: case 375: case 20:
        return true;
    case 534: reverse = 4; return true;
    case 790: reverse = 2; return true;
    default: return false;
    }
}

// mftb and mfspr of DEC/TBL/TBU read timing state; the RTL value is taken.
static bool timing_read(uint32_t insn) {
    unsigned op = insn >> 26, xo = (insn >> 1) & 1023;
    unsigned spr = ((insn >> 16) & 31) | (((insn >> 11) & 31) << 5);
    if (op != 31) return false;
    if (xo == 371) return true;
    return xo == 339 && (spr == 22 || spr == 268 || spr == 269 || spr == 284 || spr == 285);
}

static bool store_class(uint32_t insn) {
    unsigned op = insn >> 26, xo = (insn >> 1) & 1023;
    if ((op >= 36 && op <= 39) || op == 44 || op == 45 || op == 47) return true;
    if (op != 31) return false;
    switch (xo) {
    case 151: case 183: case 215: case 247: case 407: case 439: case 662: case 918:
    case 150: case 725: case 661: case 1014:
        return true;
    default: return false;
    }
}

// Bytes a completed store writes to memory; dcbz is a cache operation and a
// failed stwcx. writes nothing.
static unsigned store_size(uint32_t insn) {
    unsigned op = insn >> 26, xo = (insn >> 1) & 1023, nb = (insn >> 11) & 31;
    switch (op) {
    case 36: case 37: case 52: case 53: return 4;
    case 38: case 39: return 1;
    case 44: case 45: return 2;
    case 47: return 4 * (32 - ((insn >> 21) & 31));
    case 54: case 55: return 8;
    case 31: break;
    default: return 0;
    }
    switch (xo) {
    case 151: case 183: case 662: case 663: case 695: case 983: return 4;
    case 150: return (ppc_state.cr & 0x20000000U) ? 4 : 0;
    case 215: case 247: return 1;
    case 407: case 439: case 918: return 2;
    case 727: case 759: return 8;
    case 725: return nb ? nb : 32;
    case 661: return ppc_state.spr[SPR::XER] & 127;
    default: return 0;
    }
}

// UM 7.6.3: IMISS, ICMP, DMISS, DCMP, HASH1, HASH2 and RPA hold miss state the
// reference never forms; their reads take the RTL value.
static bool miss_spr_read(uint32_t insn) {
    unsigned spr = ((insn >> 16) & 31) | (((insn >> 11) & 31) << 5);
    return (insn >> 26) == 31 && ((insn >> 1) & 1023) == 339 && spr >= 976 && spr <= 982;
}

static bool cache_op(uint32_t insn) {
    unsigned xo = (insn >> 1) & 1023;
    return (insn >> 26) == 31 && (xo == 1014 || xo == 86 || xo == 54 || xo == 470 || xo == 982 ||
                                  xo == 278 || xo == 246);
}

// Effective address of an integer load, store or cache operation.
static bool access_ea(uint32_t insn, uint32_t& ea) {
    unsigned op = insn >> 26, ra = (insn >> 16) & 31, rb = (insn >> 11) & 31;
    unsigned xo = (insn >> 1) & 1023, rd;
    int reverse;
    uint32_t base = ra ? ppc_state.gpr[ra] : 0;
    if (op >= 32 && op <= 47) { ea = base + uint32_t(int32_t(int16_t(insn))); return true; }
    if (op != 31) return false;
    if (xo == 597 || xo == 725) { ea = base; return true; }
    if (load_target(insn, rd, reverse) || store_class(insn) || cache_op(insn) || xo == 533 ||
        xo == 310 || xo == 438) {
        ea = base + ppc_state.gpr[rb];
        return true;
    }
    return false;
}

// PEM divw/divwu: rD and CR0[LT,GT,EQ] are undefined for a zero divisor or
// 0x80000000 / -1.
static bool divide_undefined(uint32_t insn) {
    unsigned xo = (insn >> 1) & 511;
    if ((insn >> 26) != 31 || (xo != 491 && xo != 459)) return false;
    uint32_t a = ppc_state.gpr[(insn >> 16) & 31], b = ppc_state.gpr[(insn >> 11) & 31];
    return b == 0 || (xo == 491 && a == 0x80000000U && b == 0xffffffffU);
}

// UM 2.1.1: the PVR revision field is implementation data.
static bool pvr_read(uint32_t insn) {
    unsigned spr = ((insn >> 16) & 31) | (((insn >> 11) & 31) << 5);
    return (insn >> 26) == 31 && ((insn >> 1) & 1023) == 339 && spr == 287;
}

// PEM Table 6-12: alignment DSISR[27-31] holds rA only for update forms and
// load multiple/string; otherwise it is undefined.
static bool alignment_names_ra(uint32_t insn) {
    unsigned op = insn >> 26, xo = (insn >> 1) & 1023;
    if (op == 46 || op == 33 || op == 35 || op == 37 || op == 39 || op == 41 || op == 43 ||
        op == 45 || op == 49 || op == 51 || op == 53 || op == 55)
        return true;
    return op == 31 && (xo == 597 || xo == 533 || xo == 55 || xo == 119 || xo == 183 || xo == 247 ||
                        xo == 311 || xo == 375 || xo == 439 || xo == 567 || xo == 631 ||
                        xo == 695 || xo == 759);
}

static void set_msr(uint32_t value) {
#if SUPPORTS_PPC_LITTLE_ENDIAN_MODE
    ppc_change_endian(value & MSR::LE);
#endif
    uint32_t old = ppc_state.msr;
    ppc_state.msr = value;
    ppc_msr_did_change(old, value, false);
    exec_flags = 0;
}

// The reference aborts on what it does not model; name the RTL records first.
static std::deque<std::string>* abort_context;
static void on_abort(int) {
    if (abort_context)
        for (auto& r : *abort_context) std::cerr << "  rtl: " << r.substr(0, 200) << '\n';
    std::signal(SIGABRT, SIG_DFL);
}

struct Region { uint32_t base, bytes; uint8_t* host; };

// Little-endian mode fetches from EA XOR 4 and munges a data access of
// n < 8 bytes with XOR 8 - n (PEM 3.1.4).
static uint32_t munge(uint32_t ea, unsigned n) {
#if SUPPORTS_PPC_LITTLE_ENDIAN_MODE
    if (ppc_state.is_LE && n < 8) return ea ^ (8 - n);
#endif
    (void)n;
    return ea;
}

// The word at PC as the reference fetches it, through its instruction
// translation. A fetch that faults (and takes the exception) returns false.
static bool fetch_word(uint32_t& word) {
    jmp_buf outer;
    std::memcpy(outer, exc_env, sizeof(outer));
    volatile bool ok = false;
    if (!setjmp(exc_env)) {
        word = ppc_read_instruction(mmu_translate_imem(ppc_state.pc));
        ok = true;
    }
    std::memcpy(exc_env, outer, sizeof(outer));
    return ok;
}

int main(int argc, char** argv) {
    try {
        // image.hex trace [ram=base:bytes] [io=base:bytes] [exit=addr] [spr=n:value]
        //   [records=n] [keep=path] [mutate=record:field] [mutate=record:st]
        //   [mutate=record:stlate] [mutate=record:staddr] [mutate=record:lrbl]
        //   [drop=record] [fpu]
        // image.hex holds 64-bit words loaded at the first RAM. records=n stops
        // after n records without needing the exit store; keep copies the first
        // 200000 records; mutate and drop corrupt the RTL trace for negative
        // tests (staddr moves a store to the other word of its doubleword;
        // lrbl corrupts LR in the first record from there after a removed bl).
        if (argc < 3) throw std::runtime_error("usage: machine_runner image.hex trace [key=value...]");
        loguru::g_stderr_verbosity = loguru::Verbosity_WARNING;
        std::vector<std::pair<uint32_t, uint32_t>> rams;
        std::vector<std::pair<unsigned, uint32_t>> presets;
        uint32_t io_base = 0, io_bytes = 0, exit_addr = 0;
        bool exit_io = false, exit_mailbox = false;
        uint64_t max_records = ~0ULL, drop = ~0ULL;
        std::map<uint64_t, std::string> mutations;
        std::string keep;
        for (int i = 3; i < argc; ++i) {
            std::string arg = argv[i];
            size_t eq = arg.find('='), colon = arg.find(':');
            std::string key = arg.substr(0, eq), value = arg.substr(eq + 1);
            if (key == "ram" || key == "io" || key == "spr") {
                colon = value.find(':');
                uint32_t a = key == "spr" ? uint32_t(std::stoul(value.substr(0, colon))) : hex(value.substr(0, colon));
                uint32_t b = hex(value.substr(colon + 1));
                if (key == "ram") rams.push_back({a, b});
                else if (key == "io") { io_base = a; io_bytes = b; }
                else presets.push_back({a, b});
            } else if (key == "exit") { exit_addr = hex(value); }
            else if (key == "records") { max_records = std::stoull(value); }
            else if (arg == "fpu") { adapter_fpu = true; }
            else if (key == "keep") { keep = value; }
            else if (key == "drop") { drop = std::stoull(value); }
            else if (key == "mutate") {
                colon = value.find(':');
                mutations[std::stoull(value.substr(0, colon))] = value.substr(colon + 1);
            }
            else throw std::runtime_error("bad option " + arg);
            (void)colon;
        }
        if (rams.empty()) throw std::runtime_error("no RAM region");
        MemCtrlBase memory;
        std::vector<Region> regions;
        for (auto [base, bytes] : rams) {
            if (!memory.add_ram_region(base, bytes)) throw std::runtime_error("RAM region " + h8(base));
            uint8_t* host = memory.get_region_hostmem_ptr(base);
            std::memset(host, 0, bytes);
            regions.push_back({base, bytes, host});
        }
        InjectedIo io;
        io.base = io_base;
        if (io_bytes && !memory.add_mmio_region(io_base, io_bytes, &io))
            throw std::runtime_error("I/O region");
        exit_io = io_bytes && exit_addr >= io_base && exit_addr - io_base < io_bytes;
        exit_mailbox = !exit_io && exit_addr;
        auto ram_byte = [&](uint32_t a) -> uint8_t* {
            for (auto& r : regions)
                if (a - r.base < r.bytes) return r.host + (a - r.base);
            return nullptr;
        };
        {
            std::ifstream image(argv[1]);
            if (!image) throw std::runtime_error("cannot open image");
            std::string line;
            uint64_t offset = 0;
            while (std::getline(image, line)) {
                if (line.empty() || line[0] == '/') continue;
                if (line[0] == '@') { offset = uint64_t(std::stoull(line.substr(1), nullptr, 16)) * 8; continue; }
                uint64_t word = std::stoull(line, nullptr, 16);
                if (offset + 8 > regions[0].bytes) throw std::runtime_error("image exceeds RAM");
                for (int b = 0; b < 8; ++b) regions[0].host[offset + b] = uint8_t(word >> (56 - 8 * b));
                offset += 8;
            }
        }
        is_deterministic = true;
        gProfilerObj.reset(new Profiler());
        ppc_cpu_init(&memory, PPC_VER::MPC603EV, false, 25000000ULL);
        ppc_state.spr[SPR::PVR] = 0x00070200U;  // UM 1.3.1.2 PID7v level
        for (auto [spr, value] : presets) {
            ppc_state.gpr[0] = value;
            dppc_interpreter::ppc_mtspr((31U << 26) | ((spr & 31U) << 16) | ((spr >> 5) << 11) | (467U << 1));
            ppc_state.gpr[0] = 0;
        }

        std::ifstream trace(argv[2]);
        if (!trace) throw std::runtime_error("cannot open trace");
        std::array<uint32_t, FIELDS> rtl{};
        std::deque<std::string> recent;
        abort_context = &recent;
        std::signal(SIGABRT, on_abort);
        uint64_t records = 0, instructions = 0, exceptions = 0, async = 0, stores = 0,
                 store_bytes = 0, timing = 0;
        bool done = false, miss_vector = false, direct_vector = false;
        uint64_t misses = 0, direct = 0, failed_conditional = 0, undefined = 0, discarded_loads = 0;
        uint64_t removed = 0, late_stores = 0, deferred_bytes = 0;
        bool removed_bl = false;
        uint64_t removed_links = 0;
        // Bytes of retired stores the RTL trace has not yet written: the store
        // queue performs a store after younger instructions retire (UM 1.1.4.3).
        uint64_t bytes_owed = 0;
        // RAM bytes written while younger retired stores are owed, by address,
        // holding the RTL's newest value. A younger store may already have
        // written the same byte in the reference, so these are compared once
        // no byte is owed.
        std::map<uint32_t, uint8_t> late_bytes;
        std::set<uint32_t> discarded;
        std::string line;
        std::ofstream kept;
        if (!keep.empty()) kept.open(keep);
        uint64_t read = 0;
        auto fail = [&](const std::string& why) {
            std::ostringstream text;
            text << "record " << records << ": " << why << "\n  recent RTL records:";
            for (auto& r : recent) text << "\n    " << r.substr(0, 200);
            throw std::runtime_error(text.str());
        };
        // Branches the RTL removed at dispatch (UM 6.3.1): no CTR write, and
        // LR only from a bl through the shadow LR, which the next record
        // carries. They retire without a record and the reference steps them.
        auto step_removed = [&](unsigned n) {
            for (unsigned i = 0; i < n; ++i) {
                uint32_t w = 0, at = ppc_state.pc;
                if (!fetch_word(w)) fail("removed instruction at " + h8(at) + " faulted on fetch");
                uint32_t op = w >> 26, xo = (w >> 1) & 1023;
                bool branch = op == 18 || op == 16 || (op == 19 && (xo == 16 || xo == 528));
                bool ctr = op != 18 && !((w >> 23) & 1);
                if (!branch || ((w & 1) && op != 18) || ctr)
                    fail("removed instruction at " + h8(ppc_state.pc) + " " + h8(w) +
                         " is not a branch without CTR writes, and LR only as a bl");
                uint64_t step_exceptions = exceptions_processed;
                ppc_exec_single();
                if (exceptions_processed != step_exceptions)
                    fail("removed branch at " + h8(w) + " took an exception");
                removed_bl |= op == 18 && (w & 1);
                removed_links += op == 18 && (w & 1);
                ++removed;
                ++instructions;
            }
        };
        while (!done && std::getline(trace, line)) {
            if (records >= max_records) { done = true; break; }
            if (kept.is_open() && read < 200000) kept << line << '\n';
            if (read++ == drop) continue;
            recent.push_back(line);
            if (recent.size() > 6) recent.pop_front();
            std::istringstream in(line);
            std::string pc_text, insn_text, token;
            unsigned count = 0, fault = 0, removed0 = 0, removed1 = 0;
            in >> pc_text >> insn_text >> count >> fault;
            uint32_t pc = hex(pc_text), insn = hex(insn_text);
            // The trace's last record may carry only stores the queue drained.
            if (pc == 0xffffffffU && count == 0) pc = ppc_state.pc;
            std::vector<std::array<uint32_t, 3>> rtl_stores;
            while (in >> token) {
                size_t eq = token.find('=');
                std::string name = token.substr(0, eq), value = token.substr(eq + 1);
                if (name == "rb") {
                    size_t c = value.find(',');
                    removed0 = unsigned(std::stoul(value.substr(0, c)));
                    removed1 = unsigned(std::stoul(value.substr(c + 1)));
                } else if (name == "st") {
                    size_t c1 = value.find(','), c2 = value.find(',', c1 + 1);
                    rtl_stores.push_back({hex(value.substr(0, c1)), hex(value.substr(c1 + 1, c2 - c1 - 1)),
                                          hex(value.substr(c2 + 1))});
                } else rtl[field_index(name)] = hex(value);
            }
            removed_bl = false;
            auto m = mutations.find(records);
            if (m != mutations.end() && m->second != "stlate" && m->second != "lrbl") {
                bool store = m->second == "st" || m->second == "staddr";
                if (!store) rtl[field_index(m->second)] ^= 1;
                else if (rtl_stores.empty()) mutations[records + 1] = m->second;
                else if (m->second == "st") rtl_stores[0][2] ^= 0x01010101U;
                else rtl_stores[0][0] ^= 4;
            }
            step_removed(removed0);
            // An interrupt is taken between retirements; enter it where the RTL did.
            uint32_t vector = pc & 0x000fffffU;
            if (ppc_state.pc != pc && (vector == 0x500 || vector == 0x900)) {
                int_pin = false;
                dec_exception_pending = false;
                uint32_t resume = ppc_state.pc;
                ppc_exception_handler(vector == 0x500 ? Except_Type::EXC_EXT_INT : Except_Type::EXC_DECR, 0);
                // Taken between instructions, so SRR0 is the next one to run.
                ppc_state.spr[SPR::SRR0] = resume;
                ppc_state.pc = ppc_next_instruction_address;
                exec_flags = 0;
                ++async;
            }
            // A software TLB reload vector: the reference translates by table
            // search, so the RTL's miss entry was applied and only its PC is taken.
            if (miss_vector && (vector == 0x1000 || vector == 0x1100 || vector == 0x1200))
                ppc_state.pc = pc;
            if (direct_vector && (vector == 0x300 || vector == 0x400)) ppc_state.pc = pc;
            miss_vector = direct_vector = false;
            if (ppc_state.pc != pc)
                fail("pc: rtl " + h8(pc) + " reference " + h8(ppc_state.pc));
            // Register value as the RTL holds it, mapping r0-r3 to t0-t3 in TGPR mode.
            auto rtl_reg = [&](unsigned d) { return tgpr_on() && d < 4 ? rtl[45 + d] : rtl[d]; };
            uint64_t before = exceptions_processed;
            bool tlb_miss = fault && (rtl[36] & MSR::TGPR) && !tgpr_on();
            if (tlb_miss) {
                // Miss entry: the instruction does not execute; state comes from the RTL.
                std::memcpy(saved, ppc_state.gpr, sizeof(saved));
                std::memcpy(ppc_state.gpr, tgpr, sizeof(tgpr));
                ppc_state.spr[SPR::SRR0] = rtl[37];
                ppc_state.spr[SPR::SRR1] = rtl[38];
                set_msr(rtl[36]);
                ppc_state.cr = rtl[32];
                miss_vector = true;
                ++misses;
                count = 0;
            }
            // UM 7.4.x: the 603e does not implement direct-store segments; an
            // access to a T=1 segment takes DSI with DSISR[5] set and DAR = EA.
            // The reference aborts on them, so the RTL's entry is checked and taken.
            // PEM 7.4.1: fetching from a direct-store segment takes ISI with SRR1[3].
            if (count == 1 && !tlb_miss && (ppc_state.msr & MSR::IR) &&
                (ppc_state.sr[pc >> 28] & 0x80000000U)) {
                if (!fault || !(rtl[38] & 0x10000000U) || rtl[37] != pc)
                    fail("fetch from direct-store segment without the ISI the manual gives");
                ppc_state.spr[SPR::SRR0] = rtl[37];
                ppc_state.spr[SPR::SRR1] = rtl[38];
                set_msr(rtl[36]);
                direct_vector = true;
                tlb_miss = true;
                ++direct;
                count = 0;
            }
            uint32_t ea = 0;
            if (count == 1 && !tlb_miss && (ppc_state.msr & MSR::DR) && access_ea(insn, ea) &&
                (ppc_state.sr[ea >> 28] & 0x80000000U)) {
                if (!fault && cache_op(insn)) {
                    // PEM 5.1.5: cache operations to direct-store segments are no-ops.
                    ppc_state.pc += 4;
                    ++instructions;
                    ++direct;
                    count = 0;
                    goto compare;
                }
                if (!fault || !(rtl[40] & 0x04000000U) || rtl[39] != ea)
                    fail("direct-store access " + h8(ea) + " without the DSI the manual gives");
                ppc_state.spr[SPR::SRR0] = rtl[37];
                ppc_state.spr[SPR::SRR1] = rtl[38];
                ppc_state.spr[SPR::DAR] = rtl[39];
                ppc_state.spr[SPR::DSISR] = rtl[40];
                set_msr(rtl[36]);
                direct_vector = true;
                tlb_miss = true;
                ++direct;
                count = 0;
            }
            if (count == 1 && miss_spr_read(insn)) {
                ppc_state.gpr[(insn >> 21) & 31] = rtl_reg((insn >> 21) & 31);
                ppc_state.pc += 4;
                ++timing;
                ++instructions;
                count = 0;
            }
            for (unsigned k = 0; k < count; ++k) {
                uint32_t step_insn = k == 0 ? insn : 0;
                unsigned rd = 0;
                int reverse = 0;
                io.have_pending = false;
                if (k == 0 && load_target(step_insn, rd, reverse)) {
                    uint32_t v = rtl_reg(rd);
                    if (reverse == 4) v = __builtin_bswap32(v);
                    if (reverse == 2) v = __builtin_bswap16(uint16_t(v));
                    io.pending = v;
                    io.have_pending = true;
                }
                if (k > 0) {
                    // CQ[1] carries an integer, branch or load; an I/O load there
                    // also retires with its value in rtl.
                    step_removed(removed1);
                    uint32_t next = 0;
                    if (uint8_t* p = ram_byte(munge(ppc_state.pc, 4)))
                        next = uint32_t(p[0]) << 24 | uint32_t(p[1]) << 16 | uint32_t(p[2]) << 8 | p[3];
                    if (load_target(next, rd, reverse)) { io.pending = rtl_reg(rd); io.have_pending = true; }
                    step_insn = next;
                }
                int_pin = false;
                dec_exception_pending = false;
                uint64_t step_exceptions = exceptions_processed;
                bool was_tgpr = tgpr_on();
                uint32_t msr_before = ppc_state.msr, srr1_before = ppc_state.spr[SPR::SRR1];
                patch_table();
                bool undefined_divide = divide_undefined(step_insn);
                uint32_t step_ea = 0;
                bool has_ea = access_ea(step_insn, step_ea);
                ppc_exec_single();
                adapter_after_step(step_exceptions);
                if (k == 0 && exceptions_processed == step_exceptions) bytes_owed += store_size(step_insn);
                unsigned d = (step_insn >> 21) & 31;
                if (timing_read(step_insn) && exceptions_processed == step_exceptions) {
                    ppc_state.gpr[d] = rtl_reg(d);
                    ++timing;
                }
                // Fields the manuals leave undefined take the RTL's value.
                if (undefined_divide && exceptions_processed == step_exceptions) {
                    ppc_state.gpr[d] = rtl_reg(d);
                    if (step_insn & 1) ppc_state.cr = (ppc_state.cr & ~0xe0000000U) | (rtl[32] & 0xe0000000U);
                    ++undefined;
                }
                // PEM dcbi discards a modified block, so what later loads see
                // depends on the cache. Loads from such blocks take the RTL
                // value, which is written into the reference's memory.
                if (has_ea && exceptions_processed == step_exceptions) {
                    unsigned xo = (step_insn >> 1) & 1023;
                    if ((step_insn >> 26) == 31 && xo == 470) discarded.insert(step_ea & ~31U);
                    unsigned ld = 0;
                    int reverse = 0;
                    unsigned size = scalar_size(step_insn);
                    uint32_t op = step_insn >> 26;
                    if (op == 34 || op == 35 || (op == 31 && (xo == 87 || xo == 119))) size = 1;
                    if (load_target(step_insn, ld, reverse) && size && !reverse &&
                        discarded.count(step_ea & ~31U) && ppc_state.gpr[ld] != rtl_reg(ld)) {
                        ppc_state.gpr[ld] = rtl_reg(ld);
                        for (unsigned b = 0; b < size; ++b)
                            if (uint8_t* p = ram_byte(munge(step_ea, size) + b))
                                *p = uint8_t(rtl_reg(ld) >> (8 * (size - 1 - b)));
                        ++discarded_loads;
                    }
                }
                if (pvr_read(step_insn) && exceptions_processed == step_exceptions) {
                    if ((ppc_state.gpr[d] ^ rtl_reg(d)) >> 16) fail("PVR version differs");
                    ppc_state.gpr[d] = rtl_reg(d);
                    ++undefined;
                }
                if (exceptions_processed != step_exceptions && (ppc_state.pc & 0xfffffU) == 0x600 &&
                    !alignment_names_ra(step_insn)) {
                    ppc_state.spr[SPR::DSISR] = (ppc_state.spr[SPR::DSISR] & ~31U) | (rtl[40] & 31U);
                    ++undefined;
                }
                // PEM rfi: only MSR[16-23,25-27,30-31] come from SRR1, and the
                // 603e clears MSR[TGPR]. The reference copies every SRR1 bit
                // it implements, including reserved bit 0, and keeps TGPR.
                if (step_insn == 0x4c000064U && exceptions_processed == step_exceptions) {
                    uint32_t want = ((msr_before & ~0x0000ff73U) | (srr1_before & 0x0000ff73U)) &
                                    ~uint32_t(MSR::TGPR);
                    if (ppc_state.msr != want) set_msr(want);
                }
                if (was_tgpr && !tgpr_on()) {
                    std::memcpy(tgpr, ppc_state.gpr, sizeof(tgpr));
                    std::memcpy(ppc_state.gpr, saved, sizeof(saved));
                } else if (!was_tgpr && tgpr_on()) {
                    std::memcpy(saved, ppc_state.gpr, sizeof(saved));
                    std::memcpy(ppc_state.gpr, tgpr, sizeof(tgpr));
                }
                ++instructions;
            }
        compare:
            io.have_pending = false;
            bool took = exceptions_processed != before;
            exceptions += took;
            if (fault && !took && !tlb_miss) fail("rtl faulted, reference took no exception");
            if (m != mutations.end() && m->second == "lrbl") {
                if (removed_bl) rtl[field_index("lr")] ^= 4;
                else mutations[records + 1] = "lrbl";
            }
            auto ref = reference_state();
            std::string diff;
            for (int i = 0; i < FIELDS; ++i)
                if (ref[i] != rtl[i])
                    diff += " " + field_name(i) + " rtl=" + h8(rtl[i]) + " ref=" + h8(ref[i]);
            if (!diff.empty()) fail("state after " + h8(pc) + " " + h8(insn) + ":" + diff);
            // stwcx. offers its write before the reservation decides it; a failed
            // one (CR0[EQ] clear) wrote nothing.
            if ((insn >> 26) == 31 && ((insn >> 1) & 1023) == 150 && !(rtl[32] & 0x20000000U)) {
                failed_conditional += !rtl_stores.empty();
                rtl_stores.clear();
            }
            bool late = false;
            if (!rtl_stores.empty()) {
                uint64_t n = 0;
                for (auto& st : rtl_stores) n += __builtin_popcount(st[1]);
                if (n > bytes_owed) fail("store effects with no store retired " + h8(insn));
                late_stores += !store_class(insn);
                bytes_owed -= n;
                late = bytes_owed != 0;
            }
            // stlate corrupts the first store written while a younger one is owed.
            if (m != mutations.end() && m->second == "stlate") {
                if (late) rtl_stores[0][2] ^= 0x01010101U;
                else mutations[records + 1] = "stlate";
            }
            // Every RTL store byte must match the reference's memory or its I/O writes.
            size_t io_used = 0;
            for (auto& st : rtl_stores) {
                ++stores;
                for (int lane = 0; lane < 4; ++lane) {
                    if (!((st[1] >> (3 - lane)) & 1)) continue;
                    uint32_t a = st[0] + lane;
                    uint8_t want = uint8_t(st[2] >> (24 - 8 * lane));
                    ++store_bytes;
                    if (uint8_t* p = ram_byte(a)) {
                        if (late || late_bytes.count(a)) {
                            late_bytes[a] = want;
                            ++deferred_bytes;
                        } else if (*p != want)
                            fail("store byte " + h8(a) + " rtl=" + std::to_string(want) + " ref=" + std::to_string(*p));
                    } else if (io_bytes && a - io_base < io_bytes) {
                        if (io_used >= io.writes.size() || io.writes[io_used].first != a ||
                            io.writes[io_used].second != want)
                            fail("I/O store byte " + h8(a) + " differs or is missing in the reference");
                        ++io_used;
                        if (exit_io && a == exit_addr + 3) done = true;
                    } else fail("store outside modeled memory " + h8(a));
                }
            }
            // The reference's I/O writes wait while an RTL store is owed.
            io.writes.erase(io.writes.begin(), io.writes.begin() + io_used);
            if (!io.writes.empty() && !bytes_owed) fail("reference I/O store absent from the RTL");
            if (exit_mailbox) {
                uint8_t* p = ram_byte(exit_addr);
                if (p && (p[0] | p[1] | p[2] | p[3])) done = true;
            }
            if (!bytes_owed) {
                for (auto [a, want] : late_bytes)
                    if (*ram_byte(a) != want)
                        fail("store byte " + h8(a) + " rtl=" + std::to_string(want) + " ref=" + std::to_string(*ram_byte(a)));
                late_bytes.clear();
            }
            ++records;
        }
        if (exit_io && done && bytes_owed)
            throw std::runtime_error(std::to_string(bytes_owed) + " store bytes owed at the exit store");
        if (records == max_records) done = true;
        if (!done) throw std::runtime_error("trace ended after " + std::to_string(records) +
                                            " records without the exit store");
        uint64_t trailing = 0;
        while (std::getline(trace, line)) ++trailing;
        std::cout << "PASS machine: records=" << records << " instructions=" << instructions
                  << " exceptions=" << exceptions << " tlb_misses=" << misses << " direct_store=" << direct << " interrupts=" << async << " stores=" << stores
                  << " store_bytes=" << store_bytes << " failed_stwcx=" << failed_conditional << " io_reads=" << io.reads
                  << " timing_reads=" << timing << " removed_branches=" << removed
                  << " removed_bl=" << removed_links
                  << " late_stores=" << late_stores << " deferred_bytes=" << deferred_bytes
#if SUPPORTS_PPC_LITTLE_ENDIAN_MODE
                  << " le_misaligned=" << le_misaligned_count << " le_fp_split=" << le_fp_split_count
#endif
                  << " undefined_fields=" << undefined << " dcbi_loads=" << discarded_loads << " trailing=" << trailing << '\n';
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "machine reference error: " << e.what() << '\n';
        return 2;
    }
}
