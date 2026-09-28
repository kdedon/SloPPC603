/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
#include <stdint.h>

/* Cache control instructions under translation: generated code must be fresh
 * after dcbst/sync/icbi/isync, touches and permitted probes have no effect,
 * dcbz reaches the alignment handler (which zeroes the block), and probes on
 * read-only or no-access blocks take DSI with load or store syndromes. */

volatile uint32_t tohost __attribute__((section(".tohost")));
volatile uint32_t dsi_count, dsi_dar, dsi_dsisr, dsi_srr0;
volatile uint32_t align_count, align_dar, align_dsisr, align_srr0;
volatile uint32_t irq_count, dec_count;
extern char probe_dcbz_rw[], probe_ro_dcbi[], probe_ro_dcbz[];
extern char probe_na_dcbf[], probe_na_dcbst[], probe_na_dcbi[];

#define WRITE_SPR(n, v) __asm__ volatile("mtspr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")

#define BLOCK_ADDR 0xfff0a000u
#define BLOCK ((volatile uint32_t *)(uintptr_t)BLOCK_ADDR)
#define CODE_BASE 0xfff0b000u   /* four pages; equal offsets share a cache set */
#define RO_ALIAS 0x40000000u    /* DBAT1: read-only view of the image */
#define NA_ALIAS 0x50000000u    /* DBAT2: no-access view */
#define DCBZ_DSISR 0x00017c00u  /* UM Table 4-13 for dcbz 0,rB */
#define DSI_LOAD 0x08000000u
#define DSI_STORE 0x0a000000u

typedef uint32_t (*fn_t)(uint32_t);
static uint32_t slot_value[4][8];

static uint32_t slot_addr(unsigned page, unsigned line) {
    return CODE_BASE + page * 0x1000u + line * 32u;
}

static uint32_t patch_and_call(unsigned page, unsigned line, uint32_t k, uint32_t arg) {
    uint32_t addr = slot_addr(page, line);
    volatile uint32_t *word = (volatile uint32_t *)(uintptr_t)addr;
    word[0] = 0x38630000u | k; /* addi r3,r3,k */
    word[1] = 0x4e800020u;     /* blr */
    __asm__ volatile("dcbst 0,%0; sync; icbi 0,%0; isync" :: "r"(addr) : "memory");
    slot_value[page][line] = k;
    return ((fn_t)(uintptr_t)addr)(arg);
}

static int dsi_is(uint32_t count, uint32_t dar, uint32_t dsisr, const char *pc) {
    return dsi_count == count && dsi_dar == dar && dsi_dsisr == dsisr &&
           dsi_srr0 == (uint32_t)(uintptr_t)pc;
}

int main(void) {
    uint32_t ro = RO_ALIAS + (BLOCK_ADDR & 0xffffu) + 4;
    uint32_t na = NA_ALIAS + (BLOCK_ADDR & 0xffffu) + 8;

    WRITE_SPR(530, 0); WRITE_SPR(532, 0); WRITE_SPR(534, 0); WRITE_SPR(542, 0);
    WRITE_SPR(529, 0xfff00002); WRITE_SPR(528, 0xfff00002);
    WRITE_SPR(537, 0xfff00002); WRITE_SPR(536, 0xfff00002);
    WRITE_SPR(539, 0xfff00001); WRITE_SPR(538, RO_ALIAS | 2);
    WRITE_SPR(541, 0xfff00000); WRITE_SPR(540, NA_ALIAS | 2);
    WRITE_SPR(22, 3000);
    __asm__ volatile("mtmsr %0; isync" :: "r"(0x8070u) : "memory");

    for (uint32_t n = 0; n < 64; n++) {
        unsigned page = n & 3, line = (n >> 2) & 7, other = (page + 3) & 3;
        uint32_t k = (n * 13u + 5u) & 0x7fffu;
        if (patch_and_call(page, line, k, n) != n + k) return 0x80000100 | n;
        if (slot_value[other][line] &&
            ((fn_t)(uintptr_t)slot_addr(other, line))(7) != 7 + slot_value[other][line])
            return 0x80000200 | n;
    }

    for (unsigned i = 0; i < 16; i++) BLOCK[i] = 0xa5a50000u | i;
    __asm__ volatile("dcbt 0,%0; dcbtst 0,%0; dcbf 0,%0; dcbst 0,%0; dcbi 0,%0"
                     :: "r"(BLOCK_ADDR) : "memory");
    __asm__ volatile("dcbt 0,%0; dcbtst 0,%0" :: "r"(na) : "memory");
    for (unsigned i = 0; i < 16; i++)
        if (BLOCK[i] != (0xa5a50000u | i)) return 0x80000300 | i;
    if (dsi_count || align_count) return 0x80000301;

    __asm__ volatile(".globl probe_dcbz_rw\nprobe_dcbz_rw: dcbz 0,%0"
                     :: "r"(BLOCK_ADDR + 0x24) : "memory");
    if (align_count != 1 || align_dar != BLOCK_ADDR + 0x24 ||
        align_dsisr != DCBZ_DSISR || align_srr0 != (uint32_t)(uintptr_t)probe_dcbz_rw)
        return 0x80000400;
    for (unsigned i = 0; i < 16; i++)
        if (BLOCK[i] != (i < 8 ? (0xa5a50000u | i) : 0)) return 0x80000410 | i;

    __asm__ volatile("dcbf 0,%0; dcbst 0,%0" :: "r"(ro) : "memory");
    if (dsi_count) return 0x80000500;
    __asm__ volatile(".globl probe_ro_dcbi\nprobe_ro_dcbi: dcbi 0,%0" :: "r"(ro) : "memory");
    if (!dsi_is(1, ro, DSI_STORE, probe_ro_dcbi)) return 0x80000501;
    __asm__ volatile(".globl probe_ro_dcbz\nprobe_ro_dcbz: dcbz 0,%0" :: "r"(ro) : "memory");
    if (!dsi_is(2, ro, DSI_STORE, probe_ro_dcbz) || align_count != 1) return 0x80000502;
    __asm__ volatile(".globl probe_na_dcbf\nprobe_na_dcbf: dcbf 0,%0" :: "r"(na) : "memory");
    if (!dsi_is(3, na, DSI_LOAD, probe_na_dcbf)) return 0x80000503;
    __asm__ volatile(".globl probe_na_dcbst\nprobe_na_dcbst: dcbst 0,%0" :: "r"(na) : "memory");
    if (!dsi_is(4, na, DSI_LOAD, probe_na_dcbst)) return 0x80000504;
    __asm__ volatile(".globl probe_na_dcbi\nprobe_na_dcbi: dcbi 0,%0" :: "r"(na) : "memory");
    if (!dsi_is(5, na, DSI_STORE, probe_na_dcbi)) return 0x80000505;
    for (unsigned i = 0; i < 16; i++)
        if (BLOCK[i] != (i < 8 ? (0xa5a50000u | i) : 0)) return 0x80000600 | i;

    if (dec_count == 0) return 0x80000700;
    return 1;
}
