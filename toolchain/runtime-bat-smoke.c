#include <stdint.h>

volatile uint32_t tohost __attribute__((section(".tohost")));
volatile uint32_t irq_count, dec_count, event_order, irq_xer, dec_xer;
volatile uint32_t irq_msr, irq_srr0, irq_srr1, irq_dar, irq_dsisr;
volatile uint32_t dec_msr, dec_srr0, dec_srr1, dec_dar, dec_dsisr;
extern char runtime_enable_resume[];
#define WRITE_SPR(n,v) __asm__ volatile("mtspr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")
#define CHECK_SPR(n,v) do { uint32_t got; __asm__ volatile("mfspr %0," #n : "=r"(got)); if (got!=(uint32_t)(v)) return 0x81000000u+(n); } while (0)

int main(void) {
    volatile uint32_t *alias=(volatile uint32_t *)(uintptr_t)0x10008000;
    volatile uint32_t *old=(volatile uint32_t *)(uintptr_t)0xfff08000;
    volatile uint32_t *new=(volatile uint32_t *)(uintptr_t)0xfff28000;
    volatile uint32_t *phase=(volatile uint32_t *)(uintptr_t)0xfff08004;
    uint32_t enabled=0x8070, translated=0x70, real=0x40, got;
    /* Software owns all BAT programming; the harness only starts real mode. */
    WRITE_SPR(528,0);
    WRITE_SPR(530,0);
    WRITE_SPR(532,0);
    WRITE_SPR(534,0);
    WRITE_SPR(536,0);
    WRITE_SPR(538,0);
    WRITE_SPR(540,0);
    WRITE_SPR(542,0);
    WRITE_SPR(529,0);
    WRITE_SPR(531,0);
    WRITE_SPR(533,0);
    WRITE_SPR(535,0);
    WRITE_SPR(537,0);
    WRITE_SPR(539,0);
    WRITE_SPR(541,0);
    WRITE_SPR(543,0);
    WRITE_SPR(529,0xfff00002); WRITE_SPR(528,0xfff00002);
    WRITE_SPR(537,0xfff00002); WRITE_SPR(536,0xfff00002);
    WRITE_SPR(539,0xfff00002); WRITE_SPR(538,0x10000002);
    CHECK_SPR(528,0xfff00002);
    CHECK_SPR(529,0xfff00002);
    CHECK_SPR(530,0);
    CHECK_SPR(531,0);
    CHECK_SPR(532,0);
    CHECK_SPR(533,0);
    CHECK_SPR(534,0);
    CHECK_SPR(535,0);
    CHECK_SPR(536,0xfff00002);
    CHECK_SPR(537,0xfff00002);
    CHECK_SPR(538,0x10000002);
    CHECK_SPR(539,0xfff00002);
    CHECK_SPR(540,0);
    CHECK_SPR(541,0);
    CHECK_SPR(542,0);
    CHECK_SPR(543,0);
    /* GNU as restricts the mnemonic to TB selectors; exercise the defined alias encoding. */
    __asm__ volatile(".long (31<<26)|(%0<<21)|(16<<16)|(16<<11)|(371<<1)" : "=r"(got));
    if(got!=0xfff00002) return 0x82000001;
    __asm__ volatile("mtmsr %0; isync" :: "r"(translated) : "memory");
    *alias=0x13579bdf;
    if(*alias!=0x13579bdf || *old!=0x13579bdf) return 0x82000002;
    *phase=1; /* Hold EXT and a masked DEC request across mapping replacement. */
    WRITE_SPR(22,0); WRITE_SPR(22,0x80000000);
    /* Inactive intermediate mapping is legal; executing identity map stays live. */
    WRITE_SPR(538,0); WRITE_SPR(539,0xfff20002); WRITE_SPR(538,0x10000002);
    CHECK_SPR(538,0x10000002); CHECK_SPR(539,0xfff20002);
    if(*alias!=0 || *old!=0x13579bdf || irq_count || dec_count) return 0x82000003;
    __asm__ volatile("mtmsr %0\n.globl runtime_enable_resume\nruntime_enable_resume:\nisync"
                     :: "r"(enabled) : "memory");
    if(irq_count!=1 || dec_count!=1 || event_order!=0x12 ||
       irq_msr!=0x40 || dec_msr!=0x40 || irq_srr1!=enabled || dec_srr1!=enabled ||
       irq_srr0!=(uint32_t)(uintptr_t)runtime_enable_resume ||
       dec_srr0!=(uint32_t)(uintptr_t)runtime_enable_resume) return 0x82000004;
    *alias=0x2468ace0;
    if(*alias!=0x2468ace0 || *old!=0x13579bdf) return 0x82000005;
    __asm__ volatile("mtmsr %0; isync" :: "r"(real) : "memory");
    if(*new!=0x2468ace0 || *old!=0x13579bdf) return 0x82000006;
    return 1;
}
