#include <stdint.h>
volatile uint32_t tohost __attribute__((section(".tohost")));
volatile uint32_t irq_count, dec_count, event_order, irq_xer, dec_xer;
volatile uint32_t irq_msr, irq_srr0, irq_srr1, irq_dar, irq_dsisr;
volatile uint32_t dec_msr, dec_srr0, dec_srr1, dec_dar, dec_dsisr;
extern char page_enable_resume[];
extern uint32_t tlbie_data_probe(uint32_t);
#ifdef PAGE_MISS_STORE_PROBE
extern void page_miss_store_probe(uint32_t, uint32_t);
#endif
#define WRITE_SPR(n,v) __asm__ volatile("mtspr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")
#define WRITE_SR(n,v) __asm__ volatile("isync; mtsr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")
static inline void seed_data(uint32_t ea, uint32_t vsid, uint32_t way, uint32_t pa) {
    WRITE_SPR(977,0x80000000u | (vsid<<7) | ((ea>>22)&63));
    WRITE_SPR(982,pa | 0x182); /* R is accepted but ignored; C=1, PP=2. */
    WRITE_SPR(27,way<<17);
    __asm__ volatile("sync; isync; tlbld %0; sync; isync" :: "r"(ea) : "memory");
}
static inline void seed_instruction(uint32_t ea, uint32_t vsid, uint32_t pa) {
    WRITE_SPR(981,0x80000000u | (vsid<<7) | ((ea>>22)&63));
    WRITE_SPR(982,pa | 0x182);
    WRITE_SPR(27,0);
    __asm__ volatile("sync; isync; tlbli %0; sync; isync" :: "r"(ea) : "memory");
}
int main(void) {
    volatile uint32_t *alias=(volatile uint32_t *)(uintptr_t)0x10008000;
    volatile uint32_t *a=(volatile uint32_t *)(uintptr_t)0xfff08000;
    volatile uint32_t *b=(volatile uint32_t *)(uintptr_t)0xfff09000;
    uint32_t (*probe)(uint32_t)=(uint32_t (*)(uint32_t))(uintptr_t)0x20000000;
    uint32_t translated=0x70,enabled=0x8070;
    /* CPU software seeds every TLB entry while IR=DR=0. No fixture preload. */
    seed_data(0x10008000,0x1234,0,0xfff08000);
    seed_data(0x10008000,0x2345,1,0xfff09000);
    seed_instruction(0x20000000,0x5678,0xfff06000);
    seed_instruction(0x20008000,0x5678,0xfff06000);
    WRITE_SPR(529,0xfff00002); WRITE_SPR(528,0xfff00002);
    WRITE_SPR(537,0xfff00002); WRITE_SPR(536,0xfff00002);
    WRITE_SR(1,0x1234); WRITE_SR(2,0x5678);
    __asm__ volatile("mtmsr %0; isync" :: "r"(translated) : "memory");
    *alias=0x13579bdf;
    if(*alias!=0x13579bdf || *a!=0x13579bdf || *b) return 0x87000001;
    if(probe(25)!=42) return 0x87000002;
    WRITE_SR(1,0x2345);
    if(*alias) return 0x87000003;
    *alias=0x2468ace0;
    if(*alias!=0x2468ace0 || *b!=0x2468ace0 || *a!=0x13579bdf) return 0x87000004;
    WRITE_SR(1,0x1234);
    if(*alias!=0x13579bdf) return 0x87000005;
    *(volatile uint32_t *)(uintptr_t)0xfff0a004=1;
    WRITE_SPR(22,0); WRITE_SPR(22,0x80000000);
    WRITE_SR(1,0x2345);
    if(*alias!=0x2468ace0 || irq_count || dec_count) return 0x87000006;
    __asm__ volatile("mtmsr %0\n.globl page_enable_resume\npage_enable_resume:\nisync" :: "r"(enabled) : "memory");
    if(irq_count!=1 || dec_count!=1 || event_order!=0x12 ||
       irq_msr!=0x40 || dec_msr!=0x40 || irq_srr1!=enabled || dec_srr1!=enabled ||
       irq_srr0!=(uint32_t)(uintptr_t)page_enable_resume ||
       dec_srr0!=(uint32_t)(uintptr_t)page_enable_resume) return 0x87000007;
    /* GPR0 is an ordinary EA source; set31 must leave set0/set8 intact. */
    __asm__ volatile("lis 0,0xdead; ori 0,0,0xf000; sync; isync; tlbie 0; sync; isync" ::: "r0","memory");
    if(probe(56)!=73 || *alias!=0x2468ace0) return 0x87000008;
    WRITE_SR(1,0x1234);
    if(*alias!=0x13579bdf) return 0x87000009;
    if(((uint32_t (*)(uint32_t))(uintptr_t)0x20008000)(7)!=24) return 0x88000001;
    uint32_t mode=*(volatile uint32_t *)(uintptr_t)0xfff0b000;
    if(mode>2) return 0x88000002;
    tohost=1; /* Arms the expected terminal diagnostic; this is not success alone. */
    uint32_t invalidated=0xdeac8234; /* Same set8; different segment, tag and offset. */
    __asm__ volatile("sync; isync; tlbie %0; sync; isync" :: "r"(invalidated) : "memory");
    if(probe(83)!=100) return 0x88000003; /* Neighbor ITLB set0 must survive. */
    if(mode==1) {
        (void)((uint32_t (*)(uint32_t))(uintptr_t)0x20008000)(9);
    } else {
        if(mode==2) WRITE_SR(1,0x2345); /* Both indexed DTLB ways must be gone. */
#ifdef PAGE_MISS_STORE_PROBE
        if(mode==2) page_miss_store_probe(0x10008000,0xaabbccdd);
        else
#endif
        (void)tlbie_data_probe(0x10008000);
    }
    return 0x88000004; /* Reaching here means the invalidation failed. */
}
