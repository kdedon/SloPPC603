#include <stdint.h>
volatile uint32_t tohost __attribute__((section(".tohost"),used));
volatile uint32_t fault_dar, fault_dsisr, fault_pc, fault_msr, fault_entry_msr, fault_count, repair;
extern const char dsi_load_site[], dsi_store_site[], dsi_retry_site[];
#define WRITE_SPR(n,v) __asm__ volatile("mtspr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")
static int fault_state(uint32_t count, const char *pc, uint32_t syndrome) {
  return fault_count==count && fault_pc==(uint32_t)(uintptr_t)pc &&
    fault_dar==0x10008000 && fault_dsisr==syndrome && fault_msr==0x70 && fault_entry_msr==0x40;
}
int main(void) {
  volatile uint32_t *physical=(volatile uint32_t *)(uintptr_t)0xfff08000;
  volatile uint32_t *alias=(volatile uint32_t *)(uintptr_t)0x10008000;
  WRITE_SPR(528,0);WRITE_SPR(530,0);WRITE_SPR(532,0);WRITE_SPR(534,0);
  WRITE_SPR(536,0);WRITE_SPR(538,0);WRITE_SPR(540,0);WRITE_SPR(542,0);
  WRITE_SPR(529,0xfff00002);WRITE_SPR(528,0xfff00002);
  WRITE_SPR(537,0xfff00002);WRITE_SPR(536,0xfff00002);
  WRITE_SPR(539,0xfff00000);WRITE_SPR(538,0x10000002);
  *physical=0x13579bdf;
  uint32_t mode=0x70;
  __asm__ volatile("mtmsr %0; isync" :: "r"(mode) : "memory");
  for(uint32_t i=0;i<4;i++) {
    uintptr_t base=0x10007ffc;
    uint32_t loaded=0x76543210;
    repair=0;WRITE_SPR(539,0xfff00000);
    __asm__ volatile(".globl dsi_load_site\ndsi_load_site:\nlwzu %0,4(%1)"
      : "+&r"(loaded), "+&b"(base) :: "memory");
    if(loaded!=0x76543210 || base!=0x10007ffc || !fault_state(3*i+1,dsi_load_site,0x08000000))return 0x83000001;
    WRITE_SPR(539,0xfff00001);
    const uint32_t forbidden=0xdeadbeef;
    __asm__ volatile(".globl dsi_store_site\ndsi_store_site:\nstwu %1,4(%0)"
      : "+&b"(base) : "r"(forbidden) : "memory");
    if(base!=0x10007ffc || *physical!=0x13579bdf || !fault_state(3*i+2,dsi_store_site,0x0a000000))return 0x83000002;
    repair=1;WRITE_SPR(539,0xfff00000);
    __asm__ volatile(".globl dsi_retry_site\ndsi_retry_site:\nlwzu %0,4(%1)"
      : "+&r"(loaded), "+&b"(base) :: "memory");
    if(loaded!=0x13579bdf || base!=0x10008000 || !fault_state(3*i+3,dsi_retry_site,0x08000000))return 0x83000003;
  }
  *alias=0x2468ace0;
  mode=0x40;__asm__ volatile("mtmsr %0; isync" :: "r"(mode) : "memory");
  if(*physical!=0x2468ace0 || fault_count!=12)return 0x83000004;
  return 1;
}
