#include <stdint.h>
volatile uint32_t tohost __attribute__((section(".tohost")));
volatile uint32_t irq_count, dec_count, event_order, irq_xer, dec_xer;
volatile uint32_t irq_msr, irq_srr0, irq_srr1, irq_dar, irq_dsisr;
volatile uint32_t dec_msr, dec_srr0, dec_srr1, dec_dar, dec_dsisr;
extern char segment_enable_resume[];
#define WRITE_SPR(n,v) __asm__ volatile("mtspr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")
#define CHECK_SR(n,v) do { uint32_t value; __asm__ volatile("mfsr %0," #n : "=r"(value)); if(value!=(uint32_t)(v)) return 0x84000000u+(n); } while(0)
#define WRITE_SR(n,v) __asm__ volatile("isync; mtsr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")
int main(void) {
    uint32_t got, translated=0x70, enabled=0x8070, real=0x40;
    WRITE_SPR(529,0xfff00002); WRITE_SPR(528,0xfff00002);
    WRITE_SPR(537,0xfff00002); WRITE_SPR(536,0xfff00002);
    for(uint32_t i=0;i<16;i++) {
        uint32_t value=(i<<28)|0x0f123400|i;
        uint32_t address=(i<<28)|((15-i)<<16)|0xa5c3;
        __asm__ volatile("isync; mtsrin %0,%1; isync" :: "r"(value),"r"(address) : "memory");
    }
    CHECK_SR(0,0x00123400);
    CHECK_SR(1,0x10123401);
    CHECK_SR(2,0x20123402);
    CHECK_SR(3,0x30123403);
    CHECK_SR(4,0x40123404);
    CHECK_SR(5,0x50123405);
    CHECK_SR(6,0x60123406);
    CHECK_SR(7,0x70123407);
    CHECK_SR(8,0x8f123408);
    CHECK_SR(9,0x9f123409);
    CHECK_SR(10,0xaf12340a);
    CHECK_SR(11,0xbf12340b);
    CHECK_SR(12,0xcf12340c);
    CHECK_SR(13,0xdf12340d);
    CHECK_SR(14,0xef12340e);
    CHECK_SR(15,0xff12340f);
    __asm__ volatile("mtmsr %0; isync" :: "r"(translated) : "memory");
    WRITE_SR(0,0x0fabc000);
    WRITE_SR(1,0x0fabc001);
    WRITE_SR(2,0x0fabc002);
    WRITE_SR(3,0x0fabc003);
    WRITE_SR(4,0x0fabc004);
    WRITE_SR(5,0x0fabc005);
    WRITE_SR(6,0x0fabc006);
    WRITE_SR(7,0x0fabc007);
    WRITE_SR(8,0x0fabc008);
    WRITE_SR(9,0x0fabc009);
    WRITE_SR(10,0x0fabc00a);
    WRITE_SR(11,0x0fabc00b);
    WRITE_SR(12,0x0fabc00c);
    WRITE_SR(13,0x0fabc00d);
    WRITE_SR(14,0x0fabc00e);
    WRITE_SR(15,0x0fabc00f);
    for(uint32_t i=0;i<16;i++) {
        uint32_t address=(i<<28)|((15-i)<<16)|0x5a3c;
        __asm__ volatile("mfsrin %0,%1" : "=r"(got) : "r"(address));
        if(got!=0x00abc000+i) return 0x85000000+i;
    }
    got=0xcf654321;
    __asm__ volatile("isync; mtsrin %0,%0; isync" :: "r"(got) : "memory");
    got=0xc000000f;
    __asm__ volatile("mfsrin %0,%0" : "+r"(got));
    if(got!=0xcf654321) return 0x86000001;
    __asm__ volatile("lis 0,0x0f01; ori 0,0,0x0203; isync; mtsr 0,0; isync; mfsr %0,0" : "=r"(got) :: "r0","memory");
    if(got!=0x00010203) return 0x86000002;
    __asm__ volatile("lis 0,0xf000; ori 0,0,0x005a; mfsrin %0,0" : "=r"(got) :: "r0");
    if(got!=0x00abc00f) return 0x86000003;
    __asm__ volatile("lis 0,0xff01; ori 0,0,0x0203; isync; mtsrin 0,0; isync; mfsr %0,15" : "=r"(got) :: "r0","memory");
    if(got!=0xff010203) return 0x86000004;
    *(volatile uint32_t *)(uintptr_t)0xfff08004=1;
    WRITE_SPR(22,0); WRITE_SPR(22,0x80000000);
    WRITE_SR(7,0x7fabcdef); CHECK_SR(7,0x70abcdef);
    if(irq_count || dec_count) return 0x86000005;
    __asm__ volatile("mtmsr %0\n.globl segment_enable_resume\nsegment_enable_resume:\nisync" :: "r"(enabled) : "memory");
    if(irq_count!=1 || dec_count!=1 || event_order!=0x12 ||
       irq_msr!=0x40 || dec_msr!=0x40 || irq_srr1!=enabled || dec_srr1!=enabled ||
       irq_srr0!=(uint32_t)(uintptr_t)segment_enable_resume ||
       dec_srr0!=(uint32_t)(uintptr_t)segment_enable_resume) return 0x86000006;
    __asm__ volatile("mtmsr %0; isync" :: "r"(real) : "memory");
    CHECK_SR(7,0x70abcdef);
    return 1;
}
