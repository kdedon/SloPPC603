/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
#include <stdint.h>

/* Machine check, trace and IABR under translation on the cached 60x top.
 * The bench terminates every tenure in [0xfff0dff0, 0xfff0e100) with TEA:
 * a load and a store there take machine checks and skip, and a call to
 * bad_routine fails its line fill on the third beat. Handler returns restore
 * ME, so each later TEA is again a machine check. Then single step, branch
 * trace and IABR. Mode word 1 selects the ME=0 checkstop control. */

volatile uint32_t tohost __attribute__((section(".tohost")));
volatile uint32_t mc_count, mc_srr0, mc_srr1, mc_msr;
volatile uint32_t trace_count, trace_srr1, trace_log[16];
volatile uint32_t iabr_count, iabr_srr0;
extern char mc_load_probe[], mc_store_probe[], bad_routine[];
extern char trace_body[], trace_after[], branch_taken[], branch_target[];
extern char iabr_target[];
uint32_t trace_run(void);
uint32_t branch_run(void);

#define WRITE_SPR(n, v) __asm__ volatile("mtspr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")
#define MODE_WORD (*(volatile uint32_t *)0xfff0c000u)
#define BAD_DATA 0xfff0e000u
#define MSR_RUN 0x1072u      /* ME IP IR DR RI */
#define SRR1_TEA 0x00040000u

typedef uint32_t (*fn_t)(uint32_t);

static uint32_t read_msr(void) {
    uint32_t v;
    __asm__ volatile("mfmsr %0" : "=r"(v));
    return v;
}

static uint32_t read_iabr(void) {
    uint32_t v;
    __asm__ volatile("mfspr %0,1010" : "=r"(v));
    return v;
}

static int mc_is(uint32_t count, const char *pc) {
    return mc_count == count && mc_srr0 == (uint32_t)(uintptr_t)pc &&
           mc_srr1 == (SRR1_TEA | MSR_RUN) && mc_msr == 0x40u;
}

int main(void) {
    /* BAT0 maps the image with WIMG=0000, so fetches fill cache lines. */
    WRITE_SPR(529, 0xfff00002); WRITE_SPR(528, 0xfff00002);
    WRITE_SPR(537, 0xfff00002); WRITE_SPR(536, 0xfff00002);

    if (MODE_WORD == 1) {
        /* Negative control: ME=0, so this TEA must checkstop. */
        __asm__ volatile("mtmsr %0; isync" :: "r"(MSR_RUN & ~0x1000u) : "memory");
        (void)*(volatile uint32_t *)(uintptr_t)BAD_DATA;
        return 0x80000f00;
    }

    __asm__ volatile("mtmsr %0; isync" :: "r"(MSR_RUN) : "memory");
    if (read_msr() != MSR_RUN) return 0x80000100;

    uint32_t v = 0x1234;
    __asm__ volatile("sync\n.globl mc_load_probe\nmc_load_probe: lwz %0,0(%1)\nsync"
                     : "+r"(v) : "b"(BAD_DATA) : "memory");
    if (v != 0x1234 || !mc_is(1, mc_load_probe)) return 0x80000200;
    if (read_msr() != MSR_RUN) return 0x80000201;

    __asm__ volatile("sync\n.globl mc_store_probe\nmc_store_probe: stw %0,4(%1)\nsync"
                     :: "r"(v), "b"(BAD_DATA) : "memory");
    if (!mc_is(2, mc_store_probe)) return 0x80000300;

    if (((fn_t)(uintptr_t)bad_routine)(0) != 0x0badf00du) return 0x80000400;
    if (!mc_is(3, bad_routine)) return 0x80000401;
    if (read_msr() != MSR_RUN) return 0x80000402;

    trace_count = 0;
    if (trace_run() != 3) return 0x80000500;
    {
        uint32_t base = (uint32_t)(uintptr_t)trace_body;
        const uint32_t expect[5] = {base + 4, base + 8, base + 16, base + 20,
                                    (uint32_t)(uintptr_t)trace_after};
        if (trace_count != 5) return 0x80000501;
        for (unsigned i = 0; i < 5; i++)
            if (trace_log[i] != expect[i]) return 0x80000510 | i;
        if (trace_srr1 != MSR_RUN) return 0x80000502;
    }

    trace_count = 0;
    branch_run();
    if (trace_count != 2 || trace_log[0] != (uint32_t)(uintptr_t)branch_taken ||
        trace_log[1] != (uint32_t)(uintptr_t)branch_target ||
        trace_srr1 != (MSR_RUN | 0x200u))
        return 0x80000600;

    WRITE_SPR(1010, (uint32_t)(uintptr_t)iabr_target | 2u);
    if (read_iabr() != ((uint32_t)(uintptr_t)iabr_target | 2u)) return 0x80000700;
    if (((fn_t)(uintptr_t)iabr_target)(0) != 7) return 0x80000701;
    if (iabr_count != 1 || iabr_srr0 != (uint32_t)(uintptr_t)iabr_target || read_iabr() != 0)
        return 0x80000702;
    /* IABR[30] clear: the compare is disabled. */
    WRITE_SPR(1010, (uint32_t)(uintptr_t)iabr_target);
    if (((fn_t)(uintptr_t)iabr_target)(0) != 7 || iabr_count != 1) return 0x80000703;
    WRITE_SPR(1010, 0);

    if (trace_count != 2 || mc_count != 3) return 0x80000800;
    return 1;
}
