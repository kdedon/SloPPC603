// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Runs a compiled firmware image on the unmodified DingusPPC CPU, MMU and
// exception code. See REFERENCE_FIRMWARE.md.
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
#include <stdexcept>
#include <string>
#include <vector>

// No machine is created, so nothing reaches the debugger or power-off paths.
static constexpr uint32_t BASE = 0xfff00000U, RAM_BYTES = 0x00100000U;

// Adapter corrections where DingusPPC omits documented 603e behavior. Each
// raises the reference's own exception entry; see REFERENCE_FIRMWARE.md.
static uint32_t multiple_ea(uint32_t opcode) {
    unsigned ra = (opcode >> 16) & 31;
    return uint32_t(int32_t(int16_t(opcode))) + (ra ? ppc_state.gpr[ra] : 0);
}
// UM 4.5.6: lmw/stmw with an EA that is not word aligned take alignment,
// and the 603e note in 4.5.6.2 puts EA + 4 in DAR.
// UM Table 4-13 sets DSISR[27-31] to rA for lmw.
static bool multiple_misaligned = false;
static uint32_t multiple_dsisr_ra = 0;
static void lmw_checked(uint32_t opcode) {
    uint32_t ea = multiple_ea(opcode);
    if (ea & 3) {
        multiple_misaligned = true;
        multiple_dsisr_ra = (opcode >> 16) & 31;
        ppc_alignment_exception(opcode, ea);
    }
    else dppc_interpreter::ppc_lmw(opcode);
}
static void stmw_checked(uint32_t opcode) {
    uint32_t ea = multiple_ea(opcode);
    if (ea & 3) { multiple_misaligned = true; ppc_alignment_exception(opcode, ea); }
    else dppc_interpreter::ppc_stmw(opcode);
}
// UM 4.5.6: lwarx with an EA that is not word aligned takes alignment.
static void lwarx_checked(uint32_t opcode) {
    unsigned ra = (opcode >> 16) & 31, rb = (opcode >> 11) & 31;
    uint32_t ea = ppc_state.gpr[rb] + (ra ? ppc_state.gpr[ra] : 0);
    if (ea & 3) ppc_alignment_exception(opcode, ea);
    else dppc_interpreter::ppc_lwarx(opcode);
}
// PEM 6.4.3: eciwx/ecowx with EAR[E] = 0 set DSISR bit 11 (bit 6 also for
// ecowx) and DAR = EA; the reference enters DSI without either.
static void external_control(uint32_t opcode, bool store) {
    if (!(ppc_state.spr[SPR::EAR] & 0x80000000U)) {
        unsigned ra = (opcode >> 16) & 31, rb = (opcode >> 11) & 31;
        ppc_state.spr[SPR::DAR] = ppc_state.gpr[rb] + (ra ? ppc_state.gpr[ra] : 0);
        ppc_state.spr[SPR::DSISR] = 0x00100000U | (store ? 0x02000000U : 0U);
        ppc_exception_handler(Except_Type::EXC_DSI, 0);
    }
    if (store) dppc_interpreter::ppc_ecowx(opcode);
    else dppc_interpreter::ppc_eciwx(opcode);
}
static void eciwx_checked(uint32_t opcode) { external_control(opcode, false); }
static void ecowx_checked(uint32_t opcode) { external_control(opcode, true); }
// PEM tw: trap when rA compares to rB under TO. The reference reads the
// fields swapped, so hand it an opcode with rA and rB exchanged.
static void tw_ordered(uint32_t opcode) {
    uint32_t ra = (opcode >> 16) & 31, rb = (opcode >> 11) & 31;
    dppc_interpreter::ppc_tw((opcode & ~0x001ff800U) | (rb << 16) | (ra << 11));
}
// The 603e does not implement tlbia; it is an illegal instruction.
static void tlbia_illegal(uint32_t) {
    ppc_exception_handler(Except_Type::EXC_PROGRAM, Exc_Cause::ILLEGAL_OP);
}
// MSR[FP] selects between two tables, so patch whichever is current.
static void patch_table() {
    PPCOpcode* table = ppc_opcode_grabber;
    if (table[46U << 11] == lmw_checked) return;
    for (uint32_t mod = 0; mod < 2048; ++mod) {
        table[(46U << 11) | mod] = lmw_checked;
        table[(47U << 11) | mod] = stmw_checked;
    }
    table[(31U << 11) | (4U << 1)] = tw_ordered;
    table[(31U << 11) | (20U << 1)] = lwarx_checked;
    table[(31U << 11) | (310U << 1)] = eciwx_checked;
    table[(31U << 11) | (438U << 1)] = ecowx_checked;
    table[(31U << 11) | (370U << 1)] = tlbia_illegal;
    table[(31U << 11) | (370U << 1) | 1U] = tlbia_illegal;
}

static uint32_t hex(const std::string& text) {
    size_t used = 0;
    unsigned long value = std::stoul(text, &used, 16);
    if (used != text.size() || value > 0xffffffffUL) throw std::runtime_error("bad hex " + text);
    return uint32_t(value);
}

static uint32_t read_word(const uint8_t* ram, uint32_t address) {
    uint32_t o = address - BASE;
    return uint32_t(ram[o]) << 24 | uint32_t(ram[o + 1]) << 16 | uint32_t(ram[o + 2]) << 8 | ram[o + 3];
}

int main(int argc, char** argv) {
    try {
        // image tohost trace memdump max_steps [spr=value ...]
        if (argc < 6) throw std::runtime_error("usage: firmware_runner image.hex tohost trace memdump steps [spr=value...]");
        loguru::g_stderr_verbosity = loguru::Verbosity_WARNING;
        uint32_t tohost = hex(argv[2]);
        uint64_t max_steps = std::stoull(argv[5]);
        MemCtrlBase memory;
        if (!memory.add_ram_region(BASE, RAM_BYTES)) throw std::runtime_error("RAM region");
        uint8_t* ram = memory.get_region_hostmem_ptr(BASE);
        std::memset(ram, 0, RAM_BYTES);
        std::ifstream image(argv[1]);
        if (!image) throw std::runtime_error("cannot open image");
        std::string line;
        for (uint32_t offset = 0; std::getline(image, line); ++offset) {
            if (offset >= 0x10000) throw std::runtime_error("image exceeds 64 KiB");
            ram[offset] = uint8_t(hex(line));
        }
        is_deterministic = true;
        gProfilerObj.reset(new Profiler());
        ppc_cpu_init(&memory, PPC_VER::MPC603EV, false, 25000000ULL);
        // Harness-installed state (BATs), applied through the reference's SPR path.
        for (int i = 6; i < argc; ++i) {
            std::string arg = argv[i];
            size_t eq = arg.find('=');
            if (eq == std::string::npos) throw std::runtime_error("bad preset " + arg);
            unsigned spr = unsigned(std::stoul(arg.substr(0, eq)));
            uint32_t value = hex(arg.substr(eq + 1));
            ppc_state.gpr[0] = value;
            dppc_interpreter::ppc_mtspr((31U << 26) | ((spr & 31U) << 16) | ((spr >> 5) << 11) | (467U << 1));
            ppc_state.gpr[0] = 0;
        }
        std::ofstream trace(argv[3]);
        if (!trace) throw std::runtime_error("cannot open trace");
        trace << std::hex << std::setfill('0');
        for (uint64_t step = 0;; ++step) {
            if (step >= max_steps) throw std::runtime_error("step limit before mailbox store");
            uint32_t pc = ppc_state.pc;
            std::array<uint32_t, 32> before;
            std::memcpy(before.data(), ppc_state.gpr, sizeof(before));
            uint64_t exceptions = exceptions_processed;
            patch_table();
            ppc_exec_single();
            if (multiple_misaligned) {
                ppc_state.spr[SPR::DAR] += 4;
                ppc_state.spr[SPR::DSISR] = (ppc_state.spr[SPR::DSISR] & ~31U) | multiple_dsisr_ra;
            }
            multiple_misaligned = false;
            multiple_dsisr_ra = 0;
            // MVP configuration, not a manual rule: without an FPU, RFI leaves
            // MSR[FP] clear. Match it so later state stays comparable.
            if (ppc_state.msr & MSR::FP) {
                uint32_t old_msr = ppc_state.msr;
                ppc_state.msr &= ~uint32_t(MSR::FP);
                ppc_msr_did_change(old_msr, ppc_state.msr, false);
                exec_flags = 0;
            }
            // UM Table 2-2: HID0 reserved bits read as zero; the reference keeps them.
            ppc_state.spr[SPR::HID0] &= 0xbff9fc99U;
            // PEM 7.7.1.1: SDR1 bits 16-22 are reserved; the reference keeps them.
            ppc_state.spr[SPR::SDR1] &= 0xffff01ffU;
            // UM 4.5.8 and 4.5.10: FP unavailable and system call clear SRR1
            // bits 0-15; the reference sets bit 11 and bit 14 respectively.
            if (exceptions_processed != exceptions) {
                uint32_t vector = ppc_state.pc & 0x000fffffU;
                if (vector == 0x00000800U) ppc_state.spr[SPR::SRR1] &= ~0x00100000U;
                if (vector == 0x00000c00U) ppc_state.spr[SPR::SRR1] &= ~0x00020000U;
            }
            trace << std::setw(8) << pc << ' ' << (exceptions_processed != exceptions ? 1 : 0);
            for (unsigned r = 0; r < 32; ++r)
                if (ppc_state.gpr[r] != before[r])
                    trace << ' ' << std::dec << r << std::hex << '=' << std::setw(8) << ppc_state.gpr[r];
            trace << '\n';
            if (read_word(ram, tohost) != 0) break;
        }
        std::ofstream dump(argv[4]);
        dump << std::hex << std::setfill('0');
        for (uint32_t o = 0; o < RAM_BYTES; ++o) dump << std::setw(2) << unsigned(ram[o]) << '\n';
        std::cout << std::hex << std::setfill('0') << "final";
        for (unsigned r = 0; r < 32; ++r) std::cout << " r" << std::dec << r << std::hex << '=' << std::setw(8) << ppc_state.gpr[r];
        std::cout << " cr=" << std::setw(8) << ppc_state.cr << " xer=" << std::setw(8) << ppc_state.spr[SPR::XER]
                  << " lr=" << std::setw(8) << ppc_state.spr[SPR::LR] << " ctr=" << std::setw(8) << ppc_state.spr[SPR::CTR]
                  << " msr=" << std::setw(8) << ppc_state.msr << " srr0=" << std::setw(8) << ppc_state.spr[SPR::SRR0]
                  << " srr1=" << std::setw(8) << ppc_state.spr[SPR::SRR1] << '\n';
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "firmware reference error: " << e.what() << '\n';
        return 2;
    }
}
