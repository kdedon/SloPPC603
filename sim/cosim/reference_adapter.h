// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Kevin Dedon
// 603e corrections applied around DingusPPC steps; shared by the firmware
// and machine runners. See REFERENCE_FIRMWARE.md.
#pragma once
#include <cpu/ppc/ppcemu.h>
#include <cpu/ppc/ppcmmu.h>
#include <algorithm>
#include <cstdint>

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
// UM 4.5.6: lwarx and stwcx. with an EA that is not word aligned take alignment.
static void lwarx_checked(uint32_t opcode) {
    unsigned ra = (opcode >> 16) & 31, rb = (opcode >> 11) & 31;
    uint32_t ea = ppc_state.gpr[rb] + (ra ? ppc_state.gpr[ra] : 0);
    if (ea & 3) ppc_alignment_exception(opcode, ea);
    else dppc_interpreter::ppc_lwarx(opcode);
}
// UM Table 4-13, X-form: DSISR[15-21] from the XO bits, [22-26] rS, [27-31] rA.
// The reference leaves bits 15-21 clear for stwcx.
static bool conditional_misaligned = false;
static uint32_t conditional_dsisr = 0;
static void stwcx_checked(uint32_t opcode) {
    unsigned ra = (opcode >> 16) & 31, rb = (opcode >> 11) & 31;
    uint32_t ea = ppc_state.gpr[rb] + (ra ? ppc_state.gpr[ra] : 0);
    if (ea & 3) {
        conditional_misaligned = true;
        conditional_dsisr = ((opcode >> 1) & 3U) << 15 | ((opcode >> 6) & 1U) << 14 |
                            ((opcode >> 7) & 15U) << 10 | ((opcode >> 21) & 31U) << 5 | ra;
        ppc_alignment_exception(opcode, ea);
    }
    else dppc_interpreter::ppc_stwcx(opcode);
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
// 603e UM: tlbld and tlbli are supervisor-level; in problem state they take a
// privileged program exception. The reference's placeholders do not check.
static void tlb_load_checked(uint32_t opcode) {
    if (ppc_state.msr & MSR::PR)
        ppc_exception_handler(Except_Type::EXC_PROGRAM, Exc_Cause::NOT_ALLOWED);
    if (((opcode >> 1) & 1023) == 978) dppc_interpreter::ppc_tlbld(opcode);
    else dppc_interpreter::ppc_tlbli(opcode);
}
// UM 4.5.6.1: with data translation on, a misaligned halfword or word access
// that crosses a 4-Kbyte page takes alignment; the reference splits it.
static PPCOpcode scalar_original[2][64 << 11];
static PPCOpcode* scalar_table[2];
static unsigned scalar_size(uint32_t opcode) {
    unsigned op = opcode >> 26, xo = (opcode >> 1) & 1023;
    if (op == 32 || op == 33 || op == 36 || op == 37) return 4;
    if (op >= 40 && op <= 45) return 2;
    if (op != 31) return 0;
    if (xo == 23 || xo == 55 || xo == 151 || xo == 183 || xo == 534 || xo == 662) return 4;
    if (xo == 279 || xo == 311 || xo == 343 || xo == 375 || xo == 407 || xo == 439 || xo == 790 ||
        xo == 918)
        return 2;
    return 0;
}
static void scalar_checked(uint32_t opcode) {
    unsigned op = opcode >> 26, ra = (opcode >> 16) & 31;
    uint32_t base = ra ? ppc_state.gpr[ra] : 0;
    uint32_t ea = op == 31 ? base + ppc_state.gpr[(opcode >> 11) & 31] : base + uint32_t(int32_t(int16_t(opcode)));
    if ((ppc_state.msr & MSR::DR) && (ea & 0xfffU) + scalar_size(opcode) > 0x1000U)
        ppc_alignment_exception(opcode, ea);
    unsigned index = op == 31 ? (31U << 11) | (opcode & 0x7ffU) : (op << 11) | (opcode & 0x7ffU);
    (scalar_table[1] == ppc_opcode_grabber ? scalar_original[1] : scalar_original[0])[index](opcode);
}
static void patch_scalars(PPCOpcode* table) {
    unsigned slot = scalar_table[0] && scalar_table[0] != table ? 1 : 0;
    scalar_table[slot] = table;
    std::copy(table, table + (64 << 11), scalar_original[slot]);
    for (uint32_t index = 0; index < (64U << 11); ++index) {
        uint32_t opcode = (index >> 11) << 26 | (index & 0x7ffU);
        if (scalar_size(opcode)) table[index] = scalar_checked;
    }
}
// UM 4.5.6: dcbz to write-through or caching-inhibited memory takes alignment.
// Only BAT-mapped data is classified; DSISR[22-26] is undefined for dcbz.
static bool dcbz_misaligned = false;
static uint32_t dcbz_dsisr = 0;
static void dcbz_checked(uint32_t opcode) {
    unsigned ra = (opcode >> 16) & 31;
    uint32_t ea = ppc_state.gpr[(opcode >> 11) & 31] + (ra ? ppc_state.gpr[ra] : 0);
    if (ppc_state.msr & MSR::DR) {
        for (unsigned bat = 0; bat < 4; ++bat) {
            uint32_t upper = ppc_state.spr[536 + 2 * bat], lower = ppc_state.spr[537 + 2 * bat];
            uint32_t mask = ~(((upper >> 2) & 0x7ffU) << 17) & 0xfffe0000U;
            bool valid = (ppc_state.msr & MSR::PR) ? (upper & 1U) : (upper & 2U);
            if (valid && ((ea ^ upper) & mask) == 0) {
                if (lower & 0x60U) {
                    dcbz_misaligned = true;
                    dcbz_dsisr = ((opcode >> 1) & 3U) << 15 | ((opcode >> 6) & 1U) << 14 |
                                 ((opcode >> 7) & 15U) << 10 | ra;
                    ppc_alignment_exception(opcode, ea);
                }
                break;
            }
        }
    }
    dppc_interpreter::ppc_dcbz(opcode);
}
// MSR[FP] selects between two tables, so patch whichever is current.
static void patch_table() {
    PPCOpcode* table = ppc_opcode_grabber;
    if (table[46U << 11] == lmw_checked) return;
    patch_scalars(table);
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
    table[(31U << 11) | (150U << 1) | 1U] = stwcx_checked;
    table[(31U << 11) | (1014U << 1)] = dcbz_checked;
    table[(31U << 11) | (978U << 1)] = tlb_load_checked;
    table[(31U << 11) | (1010U << 1)] = tlb_load_checked;
}

// Corrections after one reference step; exceptions is the count before it.
static void adapter_after_step(uint64_t exceptions) {
    if (multiple_misaligned) {
        ppc_state.spr[SPR::DAR] += 4;
        ppc_state.spr[SPR::DSISR] = (ppc_state.spr[SPR::DSISR] & ~31U) | multiple_dsisr_ra;
    }
    multiple_misaligned = false;
    multiple_dsisr_ra = 0;
    if (conditional_misaligned) ppc_state.spr[SPR::DSISR] = conditional_dsisr;
    conditional_misaligned = false;
    if (dcbz_misaligned) ppc_state.spr[SPR::DSISR] = dcbz_dsisr;
    dcbz_misaligned = false;
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
}
