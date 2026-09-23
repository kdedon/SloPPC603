// SPDX-License-Identifier: GPL-3.0-or-later
// Adapter for the unmodified DingusPPC integer handlers. See REFERENCE_RUNNER.md.
#include <cpu/ppc/ppcemu.h>
#include <cpu/ppc/ppcmmu.h>
#include <array>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <vector>

// The selected register-only handlers need no machine, timers or MMU. These
// definitions replace the whole-machine runtime, not instruction semantics.
SetPRS ppc_state{};
unsigned exec_flags = 0;
uint32_t ppc_next_instruction_address = 0;
bool is_601 = false;
using namespace dppc_interpreter;

#ifdef REFERENCE_FLAT_RAM
// Explicit service replacement, NOT an implementation of the original MMU.
// The original instruction handlers supply EA, access size and store value.
static constexpr uint32_t RAM_BASE = 0x1000, RAM_BYTES = 256;
static std::array<uint8_t,RAM_BYTES> flat_ram{};
static uint32_t ram_offset(uint32_t address, unsigned size) {
    if ((address & (size-1)) != 0)
        throw std::runtime_error("flat RAM misaligned access");
    if (address < RAM_BASE || uint64_t(address) + size > uint64_t(RAM_BASE) + RAM_BYTES)
        throw std::runtime_error("flat RAM outside range");
    return address-RAM_BASE;
}
template<class T> T mmu_read_vmem(uint32_t, uint32_t address) {
    unsigned offset=ram_offset(address,sizeof(T));
    T value=0;
    for (unsigned i=0;i<sizeof(T);++i) value=T((value<<8)|flat_ram[offset+i]);
    return value;
}
template<class T> void mmu_write_vmem(uint32_t, uint32_t address, T value) {
    unsigned offset=ram_offset(address,sizeof(T));
    for (unsigned i=0;i<sizeof(T);++i) flat_ram[offset+i]=uint8_t(value >> (8*(sizeof(T)-1-i)));
}
template uint8_t mmu_read_vmem<uint8_t>(uint32_t,uint32_t);
template uint16_t mmu_read_vmem<uint16_t>(uint32_t,uint32_t);
template uint32_t mmu_read_vmem<uint32_t>(uint32_t,uint32_t);
template void mmu_write_vmem<uint8_t>(uint32_t,uint32_t,uint8_t);
template void mmu_write_vmem<uint16_t>(uint32_t,uint32_t,uint16_t);
template void mmu_write_vmem<uint32_t>(uint32_t,uint32_t,uint32_t);
void ppc_exception_handler(Except_Type, uint32_t) {
    throw std::runtime_error("unsupported original reference exception");
}

static PPCOpcode memory_handler(uint32_t w) {
    unsigned primary=w>>26, xo=(w>>1)&1023;
    unsigned ra=(w>>16)&31, rt=(w>>21)&31;
    bool update=false, load=false;
    PPCOpcode selected=nullptr;
    switch (primary) {
    case 32: selected=ppc_lz<uint32_t>; load=true; break;
    case 33: selected=ppc_lzu<uint32_t>; load=update=true; break;
    case 34: selected=ppc_lz<uint8_t>; load=true; break;
    case 35: selected=ppc_lzu<uint8_t>; load=update=true; break;
    case 36: selected=ppc_st<uint32_t>; break;
    case 37: selected=ppc_stu<uint32_t>; update=true; break;
    case 38: selected=ppc_st<uint8_t>; break;
    case 39: selected=ppc_stu<uint8_t>; update=true; break;
    case 40: selected=ppc_lz<uint16_t>; load=true; break;
    case 41: selected=ppc_lzu<uint16_t>; load=update=true; break;
    case 42: selected=ppc_lha; load=true; break;
    case 43: selected=ppc_lhau; load=update=true; break;
    case 44: selected=ppc_st<uint16_t>; break;
    case 45: selected=ppc_stu<uint16_t>; update=true; break;
    case 31:
        if (w&1) return nullptr;
        switch (xo) {
        case 23: selected=ppc_lzx<uint32_t>; load=true; break;
        case 55: selected=ppc_lzux<uint32_t>; load=update=true; break;
        case 87: selected=ppc_lzx<uint8_t>; load=true; break;
        case 119: selected=ppc_lzux<uint8_t>; load=update=true; break;
        case 151: selected=ppc_stx<uint32_t>; break;
        case 183: selected=ppc_stux<uint32_t>; update=true; break;
        case 215: selected=ppc_stx<uint8_t>; break;
        case 247: selected=ppc_stux<uint8_t>; update=true; break;
        case 279: selected=ppc_lzx<uint16_t>; load=true; break;
        case 311: selected=ppc_lzux<uint16_t>; load=update=true; break;
        case 343: selected=ppc_lhax; load=true; break;
        case 375: selected=ppc_lhaux; load=update=true; break;
        case 407: selected=ppc_stx<uint16_t>; break;
        case 439: selected=ppc_stux<uint16_t>; update=true; break;
        default: return nullptr;
        }
        break;
    default: return nullptr;
    }
    if (update && (ra==0 || (load && ra==rt))) return nullptr;
    return selected;
}
#endif

// Fix the authorized SPR bits before invoking the ORIGINAL generic handler.
// Flatten+LTO lets GCC remove unreachable timer/MMU branches; no such service
// is stubbed. A failed specialization is a link failure, not a fake oracle.
template<unsigned spr, bool write>
__attribute__((flatten)) static void fixed_spr(uint32_t w) {
    uint32_t opcode = (31U << 26) | (w & 0x03e00000U) |
                      ((spr & 31U) << 16) | ((spr >> 5) << 11) |
                      ((write ? 467U : 339U) << 1);
    if constexpr (write) ppc_mtspr(opcode);
    else ppc_mfspr(opcode);
}

#define RO(f) return oe ? (rc ? f<RC1, OV1> : f<RC0, OV1>) : (rc ? f<RC1, OV0> : f<RC0, OV0>)
#define CRO(f,c) return oe ? (rc ? f<c, RC1, OV1> : f<c, RC0, OV1>) : (rc ? f<c, RC1, OV0> : f<c, RC0, OV0>)
#define LOGIC(f) return rc ? ppc_logical<f, RC1> : ppc_logical<f, RC0>
#define BR(f) return aa ? (rc ? f<LK1, AA1> : f<LK0, AA1>) : (rc ? f<LK1, AA0> : f<LK0, AA0>)

static bool valid_bo(unsigned bo) {
    switch (bo) {
    case 0: case 1: case 2: case 3: case 4: case 5:
    case 8: case 9: case 10: case 11: case 12: case 13:
    case 16: case 17: case 18: case 19: case 20: return true;
    default: return false;
    }
}

// Closed, adapter-owned legality/dispatch gate. The selected function executes
// the original reference's register extraction and arithmetic/flag semantics.
static PPCOpcode handler(uint32_t w) {
#ifdef REFERENCE_FLAT_RAM
    if (auto memory=memory_handler(w)) return memory;
#endif
    bool rc = w & 1, oe = w & 0x400, aa = w & 2;
    unsigned xo = (w >> 1) & 1023, bo = (w >> 21) & 31;
    switch (w >> 26) {
    case 7: return ppc_mulli;
    case 8: return ppc_subfic;
    case 10: return (w & 0x600000) ? nullptr : ppc_cmpli;
    case 11: return (w & 0x600000) ? nullptr : ppc_cmpi;
    case 12: return ppc_addic<RC0>;
    case 13: return ppc_addic<RC1>;
    case 14: return ppc_addi<SHFT0>;
    case 15: return ppc_addi<SHFT1>;
    case 16: if (!valid_bo(bo)) return nullptr; BR(ppc_bc);
    case 18: BR(ppc_b);
    case 20: return ppc_rlwimi;
    case 21: return ppc_rlwinm;
    case 23: return ppc_rlwnm;
    case 24: return ppc_ori<SHFT0>;
    case 25: return ppc_ori<SHFT1>;
    case 26: return ppc_xori<SHFT0>;
    case 27: return ppc_xori<SHFT1>;
    case 28: return ppc_andirc<SHFT0>;
    case 29: return ppc_andirc<SHFT1>;
    case 19:
        if (xo == 0) return (w & 0x0063f801U) ? nullptr : ppc_mcrf;
        if ((xo == 16 || xo == 528) && !(w & 0xf800) && valid_bo(bo)) {
            if (xo == 16) return rc ? ppc_bclr<LK1> : ppc_bclr<LK0>;
            if (!(bo & 4)) return nullptr;
            return rc ? ppc_bcctr<LK1, NOT601> : ppc_bcctr<LK0, NOT601>;
        }
        if (rc) return nullptr;
        switch (xo) {
        case 257: return ppc_crand;
        case 129: return ppc_crandc;
        case 289: return ppc_creqv;
        case 225: return ppc_crnand;
        case 33: return ppc_crnor;
        case 449: return ppc_cror;
        case 417: return ppc_crorc;
        case 193: return ppc_crxor;
        default: return nullptr;
        }
    case 31:
        switch (xo & 511) {
        case 266: CRO(ppc_add, CARRY0);
        case 10: CRO(ppc_add, CARRY1);
        case 138: RO(ppc_adde);
        case 234: if (w & 0xf800) return nullptr; RO(ppc_addme);
        case 202: if (w & 0xf800) return nullptr; RO(ppc_addze);
        case 40: CRO(ppc_subf, CARRY0);
        case 8: CRO(ppc_subf, CARRY1);
        case 136: RO(ppc_subfe);
        case 232: if (w & 0xf800) return nullptr; RO(ppc_subfme);
        case 200: if (w & 0xf800) return nullptr; RO(ppc_subfze);
        case 104: if (w & 0xf800) return nullptr; RO(ppc_neg);
        case 235: RO(ppc_mullw);
        case 459: RO(ppc_divwu);
        case 491: RO(ppc_divw);
        default: break;
        }
        switch (xo) {
        case 75: return rc ? ppc_mulhw<RC1> : ppc_mulhw<RC0>;
        case 11: return rc ? ppc_mulhwu<RC1> : ppc_mulhwu<RC0>;
        case 26: if (w & 0xf800) return nullptr; return rc ? ppc_cntlzw<RC1> : ppc_cntlzw<RC0>;
        case 954: if (w & 0xf800) return nullptr; return rc ? ppc_exts<int8_t, RC1> : ppc_exts<int8_t, RC0>;
        case 922: if (w & 0xf800) return nullptr; return rc ? ppc_exts<int16_t, RC1> : ppc_exts<int16_t, RC0>;
        case 19: return (w & 0x001ff801U) ? nullptr : ppc_mfcr;
        case 144: return (w & 0x00100801U) ? nullptr : ppc_mtcrf;
        case 512: return (w & 0x007ff801U) ? nullptr : ppc_mcrxr;
        case 339: case 467: {
            unsigned spr = ((w >> 16) & 31) | ((w >> 6) & 992);
            if (rc) return nullptr;
            if (spr == 8) return xo == 467 ? fixed_spr<8,true> : fixed_spr<8,false>;
            if (spr == 9) return xo == 467 ? fixed_spr<9,true> : fixed_spr<9,false>;
            return nullptr;
        }
        case 0: return (w & 0x600001) ? nullptr : ppc_cmp;
        case 32: return (w & 0x600001) ? nullptr : ppc_cmpl;
        case 28: LOGIC(ppc_and);
        case 60: LOGIC(ppc_andc);
        case 284: LOGIC(ppc_eqv);
        case 476: LOGIC(ppc_nand);
        case 124: LOGIC(ppc_nor);
        case 444: LOGIC(ppc_or);
        case 412: LOGIC(ppc_orc);
        case 316: LOGIC(ppc_xor);
        case 24: return rc ? ppc_shift<LEFT1, RC1> : ppc_shift<LEFT1, RC0>;
        case 536: return rc ? ppc_shift<RIGHT0, RC1> : ppc_shift<RIGHT0, RC0>;
        case 792: return rc ? ppc_sraw<RC1> : ppc_sraw<RC0>;
        case 824: return rc ? ppc_srawi<RC1> : ppc_srawi<RC0>;
        default: return nullptr;
        }
    default: return nullptr;
    }
}

static uint32_t word(const std::string& token) {
    if (token.empty() || token.size() > 8 || token.find_first_not_of("0123456789abcdefABCDEF") != std::string::npos)
        throw std::runtime_error("program requires one 1..8-digit hexadecimal word per line");
    return uint32_t(std::stoul(token, nullptr, 16));
}

int main(int argc, char** argv) {
    try {
        if (argc < 2 || argc > 3) throw std::runtime_error("usage: reference_runner program.hex [MPC603EV|MPC603E]");
        std::string model = argc == 3 ? argv[2] : "MPC603EV";
        if (model != "MPC603EV" && model != "MPC603E") throw std::runtime_error("unsupported model (602/601/LE disabled)");
        ppc_state.spr[SPR::PVR] = model == "MPC603EV" ? PPC_VER::MPC603EV : PPC_VER::MPC603E;
        std::ifstream input(argv[1]);
        if (!input) throw std::runtime_error("cannot open program");
        std::vector<uint32_t> words;
        std::string line;
        while (std::getline(input, line)) {
            if (!line.empty() && line.back() == '\r') line.pop_back();
            uint32_t w = word(line);
            if (!handler(w)) throw std::runtime_error("unsupported or reserved opcode at word " + std::to_string(words.size()));
            words.push_back(w);
        }
        if (words.empty() || words.size() > 65536) throw std::runtime_error("program size must be 1..65536 words");
        std::cout << std::hex << std::setfill('0');
#ifdef REFERENCE_FLAT_RAM
        std::cout << "#ppc-reference-v2 ram_base=00001000 ram_bytes=00000100\n";
#endif
        for (unsigned step = 0; ppc_state.pc != words.size()*4; ++step) {
            uint32_t pc = ppc_state.pc;
            if (step >= 100000 || (pc & 3) || pc / 4 >= words.size())
                throw std::runtime_error("step limit or branch outside program");
            uint32_t w = words[pc / 4];
            if ((w >> 26) == 31 && (((w >> 1) & 511) == 459 || ((w >> 1) & 511) == 491)) {
                uint32_t a = ppc_state.gpr[(w >> 16) & 31];
                uint32_t b = ppc_state.gpr[(w >> 11) & 31];
                if (b == 0 || ((((w >> 1) & 511) == 491) && a == 0x80000000U && b == 0xffffffffU))
                    throw std::runtime_error("undefined divide result at PC " + std::to_string(pc));
            }
            exec_flags = 0;
            ppc_next_instruction_address = pc + 4;
            handler(w)(w);
            if (exec_flags & ~EXEF_BRANCH) throw std::runtime_error("reference exception/unsupported effect");
            ppc_state.pc = (exec_flags & EXEF_BRANCH) ? ppc_next_instruction_address : pc + 4;
            auto out = [](uint32_t v) { std::cout << std::setw(8) << v << ' '; };
            out(pc); out(w);
            for (auto v : ppc_state.gpr) out(v);
            out(ppc_state.cr); out(ppc_state.spr[SPR::XER]);
            out(ppc_state.spr[SPR::LR]); out(ppc_state.spr[SPR::CTR]);
#ifdef REFERENCE_FLAT_RAM
            for (unsigned offset=0;offset<RAM_BYTES;offset+=4)
                out(mmu_read_vmem<uint32_t>(0,RAM_BASE+offset));
#endif
            std::cout << '\n';
        }
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "reference unsupported/error: " << e.what() << '\n';
        return 2;
    }
}
