// SPDX-License-Identifier: MIT
#include "Vss_fpu_candidate.h"
#include "verilated.h"
#include <algorithm>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <stdexcept>
#include <tuple>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc != 3) throw std::runtime_error("usage: driver vectors results");
    std::ifstream input(argv[1]);
    std::ofstream output(argv[2]);
    if (!input || !output) throw std::runtime_error("vector/result file open failed");
    Vss_fpu_candidate dut;
    auto tick = [&]() {
        dut.clk = 0; dut.eval();
        dut.clk = 1; dut.eval();
        dut.clk = 0; dut.eval();
    };
    dut.req = 0; dut.stall = 0; dut.flush = 0; dut.reset_n = 0;
    dut.fs1 = 0; dut.fs2 = 0; dut.fop = 0; dut.sdi = 1; dut.sdo = 1; dut.rd = 0;
    tick(); tick(); tick();
    dut.reset_n = 1;
    for (int i = 0; i < 12; ++i) tick();
    // A killed request must not leave a completion behind.
    dut.fop = 8; dut.sdi = 1; dut.sdo = 1;
    dut.fs1 = 0x3ff0000000000000ULL; dut.fs2 = 0x4000000000000000ULL;
    dut.req = 1; tick(); dut.req = 0;
    dut.flush = 1; tick(); dut.flush = 0;
    for (int i = 0; i < 32; ++i) {
        tick();
        if (dut.fin) throw std::runtime_error("completion after flush");
    }
    dut.req = 1; tick(); dut.req = 0;
    dut.reset_n = 0; tick(); tick(); dut.reset_n = 1;
    for (int i = 0; i < 32; ++i) {
        tick();
        if (dut.fin) throw std::runtime_error("completion after reset");
    }
    unsigned op, sd, sdo, rn;
    uint64_t a, b;
    unsigned count = 0, minimum = 1024, maximum = 0;
    std::map<std::tuple<unsigned, unsigned>, std::tuple<unsigned, unsigned, unsigned>> latency;
    while (input >> std::dec >> op >> sd >> sdo >> rn >> std::hex >> a >> b) {
        unsigned wait = 0;
        while (!dut.rdy) { tick(); if (++wait > 1024) throw std::runtime_error("ready timeout"); }
        const bool unary = op == 2 || op == 3 || op == 11;
        dut.fop = op; dut.sdi = op == 3 ? 0 : sd; dut.sdo = sdo; dut.rd = rn;
        dut.fs1 = unary ? 0 : sd ? a : a << 32;
        const uint64_t operand = unary ? a : b;
        dut.fs2 = op == 3 ? operand << 32 : sd ? operand : operand << 32;
        dut.req = 1;
        tick();
        dut.req = 0;
        unsigned cycles = 1;
        while (!dut.fin) { tick(); if (++cycles > 1024) throw std::runtime_error("finish timeout"); }
        uint64_t bits = op == 6 ? dut.fcc : op == 2 ? uint32_t(dut.fd >> 32) : sdo ? dut.fd : dut.fd >> 32;
        output << std::hex << bits << ' ' << unsigned(dut.exc) << ' ' << unsigned(dut.unf) << ' ' << cycles
               << ' ' << unsigned(dut.round_increment) << ' ' << unsigned(dut.invalid_causes) << '\n';
        minimum = std::min(minimum, cycles); maximum = std::max(maximum, cycles);
        auto& entry = latency[{op, sd}];
        if (std::get<0>(entry) == 0) entry = {cycles, cycles, 0};
        std::get<0>(entry) = std::min(std::get<0>(entry), cycles);
        std::get<1>(entry) = std::max(std::get<1>(entry), cycles);
        ++std::get<2>(entry);
        if (count == 0) {
            dut.stall = 1;
            tick();
            if (!dut.fin) throw std::runtime_error("stalled completion dropped");
            const uint64_t held = dut.fd;
            tick();
            if (!dut.fin || dut.fd != held) throw std::runtime_error("stalled result changed");
            dut.stall = 0;
        }
        tick();
        if (dut.fin) throw std::runtime_error("duplicate completion");
        ++count;
    }
    dut.final();
    std::cout << "PASS transport vectors=" << count << " latency_min=" << minimum << " latency_max=" << maximum << '\n';
    for (const auto& [key, range] : latency)
        std::cout << "LATENCY op=" << std::get<0>(key) << " sd=" << std::get<1>(key)
                  << " min=" << std::get<0>(range) << " max=" << std::get<1>(range)
                  << " count=" << std::get<2>(range) << '\n';
}
