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
#include <cstring>
#include <deque>
#include <fstream>
#include <iostream>
#include <map>
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
                                    "dar", "dsisr", "sprg0", "sprg1", "sprg2", "sprg3"};
static constexpr int FIELDS = 45;

static std::array<uint32_t, FIELDS> reference_state() {
    std::array<uint32_t, FIELDS> s{};
    std::memcpy(s.data(), ppc_state.gpr, 32 * 4);
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

struct Region { uint32_t base, bytes; uint8_t* host; };

int main(int argc, char** argv) {
    try {
        // image.hex trace [ram=base:bytes] [io=base:bytes] [exit=addr] [spr=n:value]
        //   [records=n] [keep=path] [mutate=record:field] [mutate=record:st]
        //   [drop=record]
        // image.hex holds 64-bit words loaded at the first RAM. records=n stops
        // after n records without needing the exit store; keep copies the first
        // 200000 records; mutate and drop corrupt the RTL trace for negative tests.
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
        for (auto [spr, value] : presets) {
            ppc_state.gpr[0] = value;
            dppc_interpreter::ppc_mtspr((31U << 26) | ((spr & 31U) << 16) | ((spr >> 5) << 11) | (467U << 1));
            ppc_state.gpr[0] = 0;
        }

        std::ifstream trace(argv[2]);
        if (!trace) throw std::runtime_error("cannot open trace");
        std::array<uint32_t, FIELDS> rtl{};
        std::deque<std::string> recent;
        uint64_t records = 0, instructions = 0, exceptions = 0, async = 0, stores = 0,
                 store_bytes = 0, timing = 0;
        bool done = false;
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
        while (!done && std::getline(trace, line)) {
            if (records >= max_records) { done = true; break; }
            if (kept.is_open() && read < 200000) kept << line << '\n';
            if (read++ == drop) continue;
            recent.push_back(line);
            if (recent.size() > 6) recent.pop_front();
            std::istringstream in(line);
            std::string pc_text, insn_text, token;
            unsigned count = 0, fault = 0;
            in >> pc_text >> insn_text >> count >> fault;
            uint32_t pc = hex(pc_text), insn = hex(insn_text);
            std::vector<std::array<uint32_t, 3>> rtl_stores;
            while (in >> token) {
                size_t eq = token.find('=');
                std::string name = token.substr(0, eq), value = token.substr(eq + 1);
                if (name == "st") {
                    size_t c1 = value.find(','), c2 = value.find(',', c1 + 1);
                    rtl_stores.push_back({hex(value.substr(0, c1)), hex(value.substr(c1 + 1, c2 - c1 - 1)),
                                          hex(value.substr(c2 + 1))});
                } else rtl[field_index(name)] = hex(value);
            }
            if (auto m = mutations.find(records); m != mutations.end()) {
                if (m->second != "st") rtl[field_index(m->second)] ^= 1;
                else if (!rtl_stores.empty()) rtl_stores[0][2] ^= 0x01010101U;
                else mutations[records + 1] = "st";
            }
            // An interrupt is taken between retirements; enter it where the RTL did.
            uint32_t vector = pc & 0x000fffffU;
            if (ppc_state.pc != pc && (vector == 0x500 || vector == 0x900)) {
                int_pin = false;
                dec_exception_pending = false;
                ppc_exception_handler(vector == 0x500 ? Except_Type::EXC_EXT_INT : Except_Type::EXC_DECR, 0);
                ++async;
            }
            if (ppc_state.pc != pc)
                fail("pc: rtl " + h8(pc) + " reference " + h8(ppc_state.pc));
            uint64_t before = exceptions_processed;
            for (unsigned k = 0; k < count; ++k) {
                uint32_t step_insn = k == 0 ? insn : 0;
                unsigned rd = 0;
                int reverse = 0;
                io.have_pending = false;
                if (k == 0 && load_target(step_insn, rd, reverse)) {
                    uint32_t v = rtl[rd];
                    if (reverse == 4) v = __builtin_bswap32(v);
                    if (reverse == 2) v = __builtin_bswap16(uint16_t(v));
                    io.pending = v;
                    io.have_pending = true;
                }
                if (k > 0) {
                    // CQ[1] carries an integer, branch or load; an I/O load there
                    // also retires with its value in rtl.
                    uint32_t next = 0;
                    if (uint8_t* p = ram_byte(ppc_state.pc))
                        next = uint32_t(p[0]) << 24 | uint32_t(p[1]) << 16 | uint32_t(p[2]) << 8 | p[3];
                    if (load_target(next, rd, reverse)) { io.pending = rtl[rd]; io.have_pending = true; }
                    step_insn = next;
                }
                int_pin = false;
                dec_exception_pending = false;
                uint64_t step_exceptions = exceptions_processed;
                patch_table();
                ppc_exec_single();
                adapter_after_step(step_exceptions);
                if (timing_read(step_insn) && exceptions_processed == step_exceptions) {
                    unsigned d = (step_insn >> 21) & 31;
                    ppc_state.gpr[d] = rtl[d];
                    ++timing;
                }
                ++instructions;
            }
            io.have_pending = false;
            bool took = exceptions_processed != before;
            exceptions += took;
            if (fault && !took) fail("rtl faulted, reference took no exception");
            auto ref = reference_state();
            std::string diff;
            for (int i = 0; i < FIELDS; ++i)
                if (ref[i] != rtl[i])
                    diff += " " + field_name(i) + " rtl=" + h8(rtl[i]) + " ref=" + h8(ref[i]);
            if (!diff.empty()) fail("state after " + h8(pc) + " " + h8(insn) + ":" + diff);
            if (!rtl_stores.empty() && !store_class(insn))
                fail("store effects from a non-store " + h8(insn));
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
                        if (*p != want)
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
            if (io_used != io.writes.size()) fail("reference I/O store absent from the RTL");
            io.writes.clear();
            if (exit_mailbox) {
                uint8_t* p = ram_byte(exit_addr);
                if (p && (p[0] | p[1] | p[2] | p[3])) done = true;
            }
            ++records;
        }
        if (records == max_records) done = true;
        if (!done) throw std::runtime_error("trace ended after " + std::to_string(records) +
                                            " records without the exit store");
        uint64_t trailing = 0;
        while (std::getline(trace, line)) ++trailing;
        std::cout << "PASS machine: records=" << records << " instructions=" << instructions
                  << " exceptions=" << exceptions << " interrupts=" << async << " stores=" << stores
                  << " store_bytes=" << store_bytes << " io_reads=" << io.reads
                  << " timing_reads=" << timing << " trailing=" << trailing << '\n';
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "machine reference error: " << e.what() << '\n';
        return 2;
    }
}
