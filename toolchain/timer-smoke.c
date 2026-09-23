#include <stdint.h>

volatile uint32_t tohost __attribute__((section(".tohost")));
volatile uint32_t irq_count, dec_count, event_order;
volatile uint32_t irq_xer, dec_xer;
volatile uint32_t irq_msr, irq_srr0, irq_srr1, irq_dar, irq_dsisr;
volatile uint32_t dec_msr, dec_srr0, dec_srr1, dec_dar, dec_dsisr;
extern char timer_enable_resume[], timer_store_resume[];

static inline uint32_t read_msr(void) {
    uint32_t v; __asm__ volatile("mfmsr %0" : "=r"(v)); return v;
}
static inline void write_msr(uint32_t v) {
    __asm__ volatile("mtmsr %0; isync" :: "r"(v) : "memory");
}
static inline void write_dec(uint32_t v) {
    __asm__ volatile("mtspr 22,%0" :: "r"(v) : "memory");
}
static inline uint32_t read_tbl(void) {
    uint32_t v; __asm__ volatile("mftb %0,268" : "=r"(v)); return v;
}
static inline uint32_t read_tbu(void) {
    uint32_t v; __asm__ volatile("mftb %0,269" : "=r"(v)); return v;
}

int main(void) {
    volatile uint32_t *phase = (volatile uint32_t *)(uintptr_t)0xfff03004;
    volatile uint32_t *alias = (volatile uint32_t *)(uintptr_t)0x10003000;
    uint32_t dar=0xa5a51234, dsisr=0x13572468, hi, lo, again, attempts=0;
    uint32_t enabled=0x8070, value=0x13579bdf;
    uint32_t raw_xer, carry_xer, cleared_xer, scratch, resumed_xer;
    __asm__ volatile("mtxer %4; mfxer %0; li %3,0; addic %3,%3,0; "
                     "mfxer %1; mcrxr 7; mfxer %2; mtxer %3"
                     : "=&r"(raw_xer), "=&r"(carry_xer), "=&r"(cleared_xer),
                       "=&r"(scratch) : "r"(0xffffffff) : "xer", "cr7");
    if (raw_xer!=0xe000007f || carry_xer!=0xc000007f || cleared_xer!=0x7f)
        return 0x80000009;
    __asm__ volatile("mtspr 19,%0; mtspr 18,%1" :: "r"(dar),"r"(dsisr) : "memory");
    if (read_msr()!=0x40 || read_tbl()!=0 || read_tbu()!=0)
        return 0x80000001;
    __asm__ volatile("mtspr 284,%0; mtspr 285,%1; mtspr 284,%2"
                     :: "r"(0),"r"(0x1234),"r"(0xffffffff) : "memory");
    if (read_tbl()!=0xffffffff || read_tbu()!=0x1234) return 0x80000002;
    /* The harness starts TB after the first upper read, forcing a retry. */
    *phase=1;
    do {
        hi=read_tbu(); lo=read_tbl(); again=read_tbu(); attempts++;
        if (attempts>8) return 0x80000003;
    } while (hi!=again);
    if (attempts<2 || hi!=0x1235 || lo>4096) return 0x80000004;
    write_msr(0x70);
    *phase=2; /* Pause ticks and hold EXT; EE remains zero. */
    write_dec(0);
    write_dec(0x80000000);
    if (irq_count || dec_count) return 0x80000005;
    __asm__ volatile("mtxer %2; mtmsr %1\n.globl timer_enable_resume\n"
                     "timer_enable_resume:\nmfxer %0; isync"
                     : "=&r"(resumed_xer) : "r"(enabled), "r"(0xa0000055)
                     : "xer", "memory");
    if (resumed_xer!=0xa0000055 || irq_xer!=resumed_xer || dec_xer!=resumed_xer)
        return 0x8000000a;
    if (irq_count!=1 || dec_count!=1 || event_order!=0x12 ||
        irq_msr!=0x40 || dec_msr!=0x40 || irq_srr1!=enabled || dec_srr1!=enabled ||
        irq_srr0!=(uint32_t)(uintptr_t)timer_enable_resume ||
        dec_srr0!=(uint32_t)(uintptr_t)timer_enable_resume ||
        irq_dar!=dar || dec_dar!=dar || irq_dsisr!=dsisr || dec_dsisr!=dsisr ||
        read_msr()!=enabled) return 0x80000006;
    *phase=3; /* Pause ticks until the alias store has been accepted. */
    write_dec(0);
    __asm__ volatile("stw %0,0(%1)\n.globl timer_store_resume\ntimer_store_resume:"
                     :: "r"(value),"r"(alias) : "memory");
    if (irq_count!=1 || dec_count!=2 || event_order!=0x122 || dec_msr!=0x40 ||
        dec_srr1!=enabled || dec_srr0!=(uint32_t)(uintptr_t)timer_store_resume ||
        dec_dar!=dar || dec_dsisr!=dsisr || *alias!=value || read_msr()!=enabled)
        return 0x80000007;
    write_msr(0x40);
    if (*(volatile uint32_t *)(uintptr_t)0xfff03000!=value) return 0x80000008;
    return 1;
}
