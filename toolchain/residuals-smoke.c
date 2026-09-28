/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
#include <stdint.h>

/* Formerly diagnostic cases, run under translation. BAT writes keep any
 * value with reserved fields cleared, overlapping DBATs resolve to the
 * lowest-numbered entry and a BL outside the table masks bitwise. SDR1,
 * HASH1 and DMISS are written and read with IR/DR set, and a non-contiguous
 * HTABMASK still yields a hash. Every exception taken with MSR[TGPR] = 1
 * clears it (UM Table 4-7) and a TLB miss sets it again. tlbld with IR/DR
 * set ignores H, API and the RPA reserved and R bits, replaces a duplicate
 * in the other way, and with V = 0 leaves the entry invalid. */

#define MSR_KERNEL 0x70u
#define MSR_TGPR 0x20000u
#define MSR_PR 0x4000u
#define MSR_EE 0x8000u
#define MSR_SE 0x400u

volatile uint32_t tohost __attribute__((section(".tohost")));
volatile uint32_t trap_log[16][4];
volatile uint32_t log_n;
volatile uint32_t dsi_dsisr, dsi_dar, miss_hash1, miss_dmiss;
volatile uint32_t scratch;
volatile uint32_t page_a[1024] __attribute__((aligned(4096))) = {[4] = 0x11111111u};
volatile uint32_t page_b[1024] __attribute__((aligned(4096))) = {[4] = 0x22222222u};
extern char at_sc[], at_trap[], at_illegal[], at_dsi[], at_align[], at_trace[];
extern char at_iabr[], at_miss[], at_bat_dsi[];

#define WRITE_SPR(n, v) __asm__ volatile("mtspr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")
#define READ_SPR(n) ({ uint32_t v_; __asm__ volatile("mfspr %0," #n : "=r"(v_)); v_; })
#define ADDR(x) ((uint32_t)(uintptr_t)(x))
/* Enter MSR value m, then run body with r0-r3 on the temporary bank. */
#define TGPR_CASE(m, body) \
    __asm__ volatile("lis 5,%0; ori 5,5,%1; mtmsr 5; isync\n" body \
                     :: "i"((m) >> 16), "i"((m) & 0xffffu) : "r5", "ctr", "memory")

static uint32_t mfmsr(void) {
    uint32_t v;
    __asm__ volatile("mfmsr %0" : "=r"(v));
    return v;
}

static void mtmsr(uint32_t v) {
    __asm__ volatile("mtmsr %0; isync" :: "r"(v) : "memory");
}

static int logged(uint32_t i, uint32_t vec, uint32_t srr0, uint32_t srr1, uint32_t msr) {
    return log_n == i + 1 && trap_log[i][0] == vec && trap_log[i][1] == srr0 &&
           trap_log[i][2] == srr1 && trap_log[i][3] == msr;
}

static uint32_t load(uint32_t ea) {
    uint32_t v;
    __asm__ volatile("lwz %0,0(%1)" : "=r"(v) : "b"(ea) : "memory");
    return v;
}

static void tlbld(uint32_t ea, uint32_t dcmp, uint32_t rpa, uint32_t way) {
    WRITE_SPR(977, dcmp);
    WRITE_SPR(982, rpa);
    WRITE_SPR(27, way ? 0x00020000u : 0u);
    __asm__ volatile("sync; tlbld %0; isync" :: "r"(ea) : "memory");
}

int main(void) {
    uint32_t v, r3_before, r3_after, hash, expected;

    /* Identity IBAT0/DBAT0 over the image. */
    WRITE_SPR(530, 0); WRITE_SPR(532, 0); WRITE_SPR(534, 0);
    WRITE_SPR(538, 0); WRITE_SPR(540, 0); WRITE_SPR(542, 0);
    WRITE_SPR(529, 0xfff00002); WRITE_SPR(528, 0xfff00003);
    WRITE_SPR(537, 0xfff00002); WRITE_SPR(536, 0xfff00003);
    mtmsr(MSR_KERNEL);

    /* Reserved BAT fields read back as zero; the block still maps. */
    WRITE_SPR(543, 0xfff1ff86u);
    WRITE_SPR(542, 0x3001e003u);
    if (READ_SPR(542) != 0x30000003u || READ_SPR(543) != 0xfff00002u) return 0x80000100;
    if (load(0x30000100u) != 0x60000000u) return 0x80000101;
    /* BL 0b10 is not a table value: EA bit 18 leaves the compare. */
    WRITE_SPR(542, 0x3000000bu);
    if (READ_SPR(542) != 0x3000000bu || load(0x30000100u) != 0x60000000u) return 0x80000102;
    WRITE_SPR(542, 0);

    /* Overlapping DBAT1 (read-only) and DBAT2 (read/write): DBAT1 wins. */
    v = 0x20000000u | (ADDR(&scratch) & 0x1ffffu);
    WRITE_SPR(539, 0xfff00001u); WRITE_SPR(538, 0x20000003u);
    WRITE_SPR(541, 0xfff00002u); WRITE_SPR(540, 0x20000003u);
    if (load(0x20000100u) != 0x60000000u) return 0x80000200;
    __asm__ volatile(".globl at_bat_dsi\nat_bat_dsi: stw %0,0(%1)"
                     :: "r"(0x5a5a5a5au), "b"(v) : "memory");
    if (!logged(0, 0x300, ADDR(at_bat_dsi), MSR_KERNEL, 0x40) ||
        dsi_dsisr != 0x0a000000u || dsi_dar != v || scratch != 0) return 0x80000201;
    WRITE_SPR(539, 0xfff00002u); WRITE_SPR(541, 0xfff00001u);
    __asm__ volatile("stw %0,0(%1)" :: "r"(0x5a5a5a5au), "b"(v) : "memory");
    if (log_n != 1 || scratch != 0x5a5a5a5au) return 0x80000202;
    WRITE_SPR(540, 0);
    /* DBAT1 stays: a read-only window over the image for the TGPR DSI. */
    WRITE_SPR(539, 0xfff00001u);

    /* SDR1 with translation on; HTABORG unaligned to a non-contiguous mask. */
    WRITE_SPR(25, 0x00f00005u);
    if (READ_SPR(25) != 0x00f00005u) return 0x80000300;

    /* Exceptions with TGPR set: each clears TGPR, SRR1 never holds it. */
    __asm__ volatile("mr %0,3" : "=r"(r3_before));
    TGPR_CASE(MSR_KERNEL | MSR_PR | MSR_TGPR,
              "li 3,0x1111\n.globl at_sc\nat_sc: sc");
    __asm__ volatile("mr %0,3" : "=r"(r3_after));
    if (!logged(1, 0xc00, ADDR(at_sc) + 4, MSR_KERNEL | MSR_PR, 0x40) ||
        mfmsr() != MSR_KERNEL || r3_after != r3_before) return 0x80000400;
    TGPR_CASE(MSR_KERNEL | MSR_TGPR, ".globl at_trap\nat_trap: twi 31,0,0");
    if (!logged(2, 0x700, ADDR(at_trap), 0x00020000u | MSR_KERNEL, 0x40) ||
        mfmsr() != MSR_KERNEL) return 0x80000401;
    TGPR_CASE(MSR_KERNEL | MSR_TGPR, ".globl at_illegal\nat_illegal: .long 0x04000000");
    if (!logged(3, 0x700, ADDR(at_illegal), 0x00080000u | MSR_KERNEL, 0x40))
        return 0x80000402;
    TGPR_CASE(MSR_KERNEL | MSR_TGPR,
              "lis 3,0x2000; ori 3,3,0x100\n.globl at_dsi\nat_dsi: stw 2,0(3)");
    if (!logged(4, 0x300, ADDR(at_dsi), MSR_KERNEL, 0x40) ||
        dsi_dsisr != 0x0a000000u || dsi_dar != 0x20000100u) return 0x80000403;
    TGPR_CASE(MSR_KERNEL | MSR_TGPR,
              "lis 3,scratch@ha; addi 3,3,scratch@l; addi 3,3,1\n"
              ".globl at_align\nat_align: lwarx 2,0,3");
    if (!logged(5, 0x600, ADDR(at_align), MSR_KERNEL, 0x40)) return 0x80000404;
    TGPR_CASE(MSR_KERNEL | MSR_TGPR | MSR_SE, ".globl at_trace\nat_trace: nop");
    if (!logged(6, 0xd00, ADDR(at_trace) + 4, MSR_KERNEL | MSR_SE, 0x40) ||
        mfmsr() != MSR_KERNEL) return 0x80000405;
    WRITE_SPR(1010, ADDR(at_iabr) | 2u);
    TGPR_CASE(MSR_KERNEL | MSR_TGPR, ".globl at_iabr\nat_iabr: nop");
    if (!logged(7, 0x1300, ADDR(at_iabr), MSR_KERNEL, 0x40) || READ_SPR(1010) != 0)
        return 0x80000406;
    WRITE_SPR(22, 100);
    TGPR_CASE(MSR_KERNEL | MSR_EE | MSR_TGPR, "li 3,5000; mtctr 3; 1: bdnz 1b");
    if (log_n != 9 || trap_log[8][0] != 0x900 || trap_log[8][2] != (MSR_KERNEL | MSR_EE) ||
        trap_log[8][3] != 0x40 || mfmsr() != (MSR_KERNEL | MSR_EE)) return 0x80000407;
    mtmsr(MSR_KERNEL);

    /* A data TLB miss in TGPR mode enters with TGPR set again; its HASH1
     * uses the non-contiguous mask bitwise (PEM 7.6.1.4.2). */
    __asm__ volatile("mtsr 5,%0; isync" :: "r"(0x00007c56u) : "memory");
    TGPR_CASE(MSR_KERNEL | MSR_TGPR,
              "lis 3,0x5000; ori 3,3,0x1234\n.globl at_miss\nat_miss: lwz 2,0(3)");
    if (log_n != 10 || trap_log[9][0] != 0x1100 || trap_log[9][1] != ADDR(at_miss) ||
        (trap_log[9][2] & 0xffffu) != MSR_KERNEL || trap_log[9][3] != (0x40 | MSR_TGPR) ||
        mfmsr() != MSR_KERNEL) return 0x80000500;
    hash = (0x00007c56u & 0x7ffffu) ^ ((0x50001234u >> 12) & 0xffffu);
    expected = ((0x00f0u | ((hash >> 10) & 0x005u)) << 16) | ((hash & 0x3ffu) << 6);
    if (miss_hash1 != expected || miss_dmiss != 0x50001234u ||
        READ_SPR(978) != expected || READ_SPR(976) != 0x50001234u) return 0x80000501;

    /* tlbld with IR/DR set: H=1, API mismatch, RPA reserved and R bits. */
    __asm__ volatile("mtsr 4,%0; isync" :: "r"(0x00000123u) : "memory");
    tlbld(0x40000000u, 0x80000000u | (0x123u << 7) | 0x40u | 0x3fu,
          ADDR(page_a) | 0xe00u | 0x180u | 0x4u | 0x2u, 0);
    if (load(0x40000010u) != 0x11111111u) return 0x80000600;
    /* The same tag in the other way replaces the first entry. */
    tlbld(0x40000000u, 0x80000000u | (0x123u << 7), ADDR(page_b) | 0x82u, 1);
    if (load(0x40000010u) != 0x22222222u) return 0x80000601;
    tlbld(0x40000000u, 0x80000000u | (0x123u << 7), ADDR(page_a) | 0x82u, 0);
    if (load(0x40000010u) != 0x11111111u || log_n != 10) return 0x80000602;
    /* V=0 leaves the entry invalid: the next access misses. */
    tlbld(0x40000000u, (0x123u << 7), ADDR(page_b) | 0x82u, 0);
    v = load(0x40000010u);
    if (log_n != 11 || trap_log[10][0] != 0x1100 || miss_dmiss != 0x40000010u)
        return 0x80000603;
    (void)v;
    return 1;
}
