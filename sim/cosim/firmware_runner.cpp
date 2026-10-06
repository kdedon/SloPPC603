// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Kevin Dedon
// Runs a compiled firmware image on the unmodified DingusPPC CPU, MMU and
// exception code. See REFERENCE_FIRMWARE.md.
#include <cpu/ppc/ppcemu.h>
#include <cpu/ppc/ppcmmu.h>
#include <devices/memctrl/memctrlbase.h>
#include <loguru.hpp>
#include <utils/profiler.h>
#include "reference_adapter.h"
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
        ppc_state.spr[SPR::PVR] = 0x00070200U;  // UM 1.3.1.2 PID7v level
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
            adapter_after_step(exceptions);
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
