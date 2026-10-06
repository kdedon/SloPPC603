/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
#include <stdint.h>

/* Complete decode under translation: illegal words and invalid forms reach
 * the program handler as illegal, tw/twi trap on each TO condition, an HID0
 * access in problem state is privileged, FP instructions reach the
 * FP-unavailable handler (which emulates fmr on a soft FPR file), rfi cannot
 * set MSR[FP], PVR/HID0 read back, HID0 ICE/ICFI writes keep code running,
 * eciwx/ecowx take DSI with EAR[E] = 0 and transfer with EAR[E] = 1, and
 * lwarx/stwcx. complete. */

volatile uint32_t tohost __attribute__((section(".tohost")));
volatile uint32_t dsi_count, dsi_dar, dsi_dsisr, dsi_srr0;
volatile uint32_t prog_illegal, prog_priv, prog_trap, prog_other;
volatile uint32_t prog_srr0, prog_srr1;
volatile uint32_t fp_count, fp_emulated, fp_srr0, fp_srr1;
volatile uint32_t soft_fpr[64] __attribute__((aligned(8)));
volatile uint32_t ext_word = 0x13572468u, ext_out, atomic_word = 5;
extern char at_tlbia[], at_fmr[], at_lfd[], at_eciwx_off[], at_ecowx_off[];
extern char at_hid0_user[], after_rfi[];

#define WRITE_SPR(n, v) __asm__ volatile("mtspr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")
#define READ_SPR(n) ({ uint32_t v_; __asm__ volatile("mfspr %0," #n : "=r"(v_)); v_; })
#define MSR_KERNEL 0x70u
#define ADDR(x) ((uint32_t)(uintptr_t)(x))

static uint32_t mfmsr(void) {
    uint32_t v;
    __asm__ volatile("mfmsr %0" : "=r"(v));
    return v;
}

static uint32_t __attribute__((noinline)) work(uint32_t n) {
    uint32_t s = 0;
    for (uint32_t i = 0; i < n; i++) s += i * 3u + 1u;
    return s;
}

static int traps(void) {
    int32_t m = -1, p = 1;
    __asm__ volatile("tw 16,%0,%1" :: "r"(m), "r"(p));   /* <  taken */
    __asm__ volatile("tw 16,%0,%1" :: "r"(p), "r"(m));
    __asm__ volatile("tw 8,%0,%1" :: "r"(p), "r"(m));    /* >  taken */
    __asm__ volatile("tw 8,%0,%1" :: "r"(m), "r"(p));
    __asm__ volatile("tw 4,%0,%0" :: "r"(m));            /* =  taken */
    __asm__ volatile("tw 4,%0,%1" :: "r"(m), "r"(p));
    __asm__ volatile("tw 2,%0,%1" :: "r"(p), "r"(m));    /* <u taken */
    __asm__ volatile("tw 2,%0,%1" :: "r"(m), "r"(p));
    __asm__ volatile("tw 1,%0,%1" :: "r"(m), "r"(p));    /* >u taken */
    __asm__ volatile("tw 1,%0,%1" :: "r"(p), "r"(m));
    __asm__ volatile("tw 24,%0,%0" :: "r"(p));           /* lt|gt, equal */
    __asm__ volatile("twi 0,%0,0" :: "r"(m));
    __asm__ volatile("twi 31,%0,0" :: "r"(m));           /* always */
    __asm__ volatile("twi 16,%0,0" :: "r"(m));           /* taken */
    __asm__ volatile("twi 1,%0,1" :: "r"(p));
    return prog_trap == 7 && !prog_illegal && !prog_priv && !prog_other &&
           (prog_srr1 & 0xffff0000u) == 0x00020000u && (prog_srr1 & 0xffffu) == MSR_KERNEL;
}

int main(void) {
    uint32_t v;

    /* Identity IBAT0/DBAT0 over the image, user and supervisor valid. */
    WRITE_SPR(530, 0); WRITE_SPR(532, 0); WRITE_SPR(534, 0);
    WRITE_SPR(538, 0); WRITE_SPR(540, 0); WRITE_SPR(542, 0);
    WRITE_SPR(529, 0xfff00002); WRITE_SPR(528, 0xfff00003);
    WRITE_SPR(537, 0xfff00002); WRITE_SPR(536, 0xfff00003);
    __asm__ volatile("mtmsr %0; isync" :: "r"(MSR_KERNEL) : "memory");

    /* Illegal opcodes and invalid forms. */
    __asm__ volatile(".long 0x04000000");                /* primary 1 */
    __asm__ volatile(".long 0xfc00002c");                /* fsqrt */
    __asm__ volatile(".long 0x00000000");
    __asm__ volatile(".long 0x84630000");                /* lwzu r3,0(r3) */
    __asm__ volatile(".globl at_tlbia\nat_tlbia: .long 0x7c0002e4");
    if (prog_illegal != 5 || prog_srr0 != ADDR(at_tlbia) ||
        prog_srr1 != (0x00080000u | MSR_KERNEL)) return 0x80000100;
    prog_illegal = 0;

    if (!traps()) return 0x80000200 | prog_trap;
    prog_trap = 0;

    /* FP unavailable: fmr is emulated, lfd is skipped. */
    soft_fpr[2] = 0x400921fbu; soft_fpr[3] = 0x54442d18u;
    __asm__ volatile(".globl at_fmr\nat_fmr: .long 0xfca00890" ::: "memory");  /* fmr 5,1 */
    __asm__ volatile(".globl at_lfd\nat_lfd: .long 0xc8000000" ::: "memory");     /* lfd 0,0(0) */
    if (fp_count != 2 || fp_emulated != 1 || fp_srr0 != ADDR(at_lfd) ||
        fp_srr1 != MSR_KERNEL || soft_fpr[10] != 0x400921fbu || soft_fpr[11] != 0x54442d18u)
        return 0x80000300 | fp_count;
    /* rfi with SRR1[FP] = 1 leaves MSR[FP] clear. */
    WRITE_SPR(27, MSR_KERNEL | 0x2000u);
    __asm__ volatile("lis 9,after_rfi@ha; addi 9,9,after_rfi@l; mtspr 26,9; rfi\n"
                     ".globl after_rfi\nafter_rfi:" ::: "r9", "memory");
    if (mfmsr() != MSR_KERNEL) return 0x80000310;
    __asm__ volatile(".long 0xfca00890" ::: "memory");
    if (fp_count != 3) return 0x80000311;

    /* PVR and HID0; ICE starts set (the cache reset mode). DCE stays as
       the boot code left it: the data cache may hold modified lines. */
    unsigned dce = READ_SPR(1008) & 0x00004000u;
    if (READ_SPR(287) != 0x00070200u) return 0x80000400;
    if (READ_SPR(1008) != (0x00008000u | dce)) return 0x80000401;
    v = work(40);
    WRITE_SPR(1008, 0x00008800u | dce);     /* ICFI: flash invalidate */
    WRITE_SPR(1008, 0x00008000u | dce);     /* no change: no request */
    if (work(40) != v) return 0x80000402;
    WRITE_SPR(1008, dce);                   /* ICE off: single-beat fetch */
    if (work(40) != v || READ_SPR(1008) != dce) return 0x80000403;
    WRITE_SPR(1008, 0x00008000u | dce);     /* ICE on */
    if (work(40) != v) return 0x80000404;
    /* Every bit, less DCFI while the data cache is on. */
    WRITE_SPR(1008, dce ? ~0x00000400u : 0xffffffffu);
    if (READ_SPR(1008) != (dce ? 0xbff9f899u : 0xbff9fc99u)) return 0x80000405;
    WRITE_SPR(1008, 0x00008000u | dce);     /* ICE unchanged: no request */
    if (work(40) != v) return 0x80000406;

    /* eciwx/ecowx: DSI with EAR[E] = 0, transfers with EAR[E] = 1. */
    WRITE_SPR(282, 0);
    __asm__ volatile(".globl at_eciwx_off\nat_eciwx_off: eciwx %0,0,%1"
                     : "=r"(v) : "r"(&ext_word) : "memory");
    if (dsi_count != 1 || dsi_dsisr != 0x00100000u || dsi_dar != ADDR(&ext_word) ||
        dsi_srr0 != ADDR(at_eciwx_off)) return 0x80000500;
    __asm__ volatile(".globl at_ecowx_off\nat_ecowx_off: ecowx %0,0,%1"
                     :: "r"(1u), "r"(&ext_out) : "memory");
    if (dsi_count != 2 || dsi_dsisr != 0x02100000u || dsi_srr0 != ADDR(at_ecowx_off) ||
        ext_out != 0) return 0x80000501;
    WRITE_SPR(282, 0x80000005u);
    if (READ_SPR(282) != 0x80000005u) return 0x80000502;
    /* External transfers bypass the data cache: keep both words out of it. */
    __asm__ volatile("dcbf 0,%0; dcbf 0,%1; sync" :: "r"(&ext_word), "r"(&ext_out) : "memory");
    __asm__ volatile("eciwx %0,0,%1" : "=r"(v) : "r"(&ext_word) : "memory");
    if (v != 0x13572468u) return 0x80000503;
    __asm__ volatile("ecowx %0,0,%1" :: "r"(0x2468aceu), "r"(&ext_out) : "memory");
    if (ext_out != 0x2468aceu) return 0x80000504;
    WRITE_SPR(282, 0x8000000au);
    __asm__ volatile("eciwx %0,0,%1" : "=r"(v) : "r"(&ext_word) : "memory");
    if (v != 0x13572468u || dsi_count != 2) return 0x80000505;

    /* lwarx/stwcx. */
    __asm__ volatile("1: lwarx %0,0,%1; addi %0,%0,1; stwcx. %0,0,%1; bne- 1b"
                     : "=&r"(v) : "r"(&atomic_word) : "cr0", "memory");
    if (atomic_word != 6) return 0x80000600;

    /* Problem state: HID0 is privileged; sc returns to supervisor. */
    __asm__ volatile("mtmsr %0; isync" :: "r"(MSR_KERNEL | 0x4000u) : "memory");
    __asm__ volatile(".globl at_hid0_user\nat_hid0_user: mfspr %0,1008" : "=r"(v));
    __asm__ volatile(".long 0x04000000");
    __asm__ volatile("sc" ::: "memory");
    if (prog_priv != 1 || prog_illegal != 1 || prog_trap || prog_other ||
        prog_srr1 != (0x00080000u | 0x4000u | MSR_KERNEL) || mfmsr() != MSR_KERNEL)
        return 0x80000700;
    return 1;
}
