#include <stdint.h>

volatile uint32_t tohost __attribute__((section(".tohost"), used));
volatile uint32_t fault_dar, fault_dsisr, fault_pc, fault_srr1;
volatile uint32_t fault_entry_msr, fault_count, repair_rpa, denied_word;
extern const char page_dsi_load_site[], page_dsi_store_site[];

#define WRITE_SPR(n, v) __asm__ volatile("mtspr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")
#define WRITE_SR(n, v) __asm__ volatile("isync; mtsr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")

static void seed_page(uint32_t rpa) {
  const uint32_t ea = 0x10008000;
  WRITE_SPR(977, 0x80000000u | (0x1234u << 7) | ((ea >> 22) & 63u));
  WRITE_SPR(982, rpa);
  WRITE_SPR(27, 0); /* WAY 0; IR=DR=0 as required by this bounded load profile. */
  __asm__ volatile("sync; isync; tlbld %0; sync; isync" :: "r"(ea) : "memory");
}

static int fault_state(uint32_t count, const char *pc, uint32_t syndrome) {
  return fault_count == count && fault_pc == (uint32_t)(uintptr_t)pc &&
    fault_dar == 0x10008000 && fault_dsisr == syndrome &&
    fault_srr1 == 0x50 && fault_entry_msr == 0x40 &&
    denied_word == 0x13579bdf;
}

int main(void) {
  volatile uint32_t *physical = (volatile uint32_t *)(uintptr_t)0xfff08000;
  volatile uint32_t *alias = (volatile uint32_t *)(uintptr_t)0x10008000;
  uint32_t mode;

  /* Only CPU instructions install the bootstrap BAT and the protected page. */
  WRITE_SPR(528, 0); WRITE_SPR(530, 0); WRITE_SPR(532, 0); WRITE_SPR(534, 0);
  WRITE_SPR(536, 0); WRITE_SPR(538, 0); WRITE_SPR(540, 0); WRITE_SPR(542, 0);
  WRITE_SPR(529, 0xfff00002); WRITE_SPR(528, 0xfff00002);
  WRITE_SPR(537, 0xfff00002); WRITE_SPR(536, 0xfff00002);
  *physical = 0x13579bdf;
  WRITE_SR(1, 0x40001234); /* Supervisor key Ks=1: PP=00 denies load. */
  seed_page(0xfff08180);
  repair_rpa = 0xfff08182;
  mode = 0x50; /* IP=1, DR=1, IR=0; exception entry runs the handler in real mode. */
  __asm__ volatile("mtmsr %0; isync" :: "r"(mode) : "memory");

  uintptr_t base = 0x10007ffc;
  uint32_t loaded = 0x76543210;
  __asm__ volatile(".globl page_dsi_load_site\npage_dsi_load_site:\nlwzu %0,4(%1)"
    : "+&r"(loaded), "+&b"(base) :: "memory");
  if (loaded != 0x13579bdf || base != 0x10008000 ||
      !fault_state(1, page_dsi_load_site, 0x08000000)) return 0x89000001;

  /* Switch to PP=01 with Ks=1: a read is allowed, but a store is denied. */
  mode = 0x40;
  __asm__ volatile("mtmsr %0; isync" :: "r"(mode) : "memory");
  seed_page(0xfff08181);
  if (*physical != 0x13579bdf) return 0x89000002;
  repair_rpa = 0xfff08182;
  mode = 0x50;
  __asm__ volatile("mtmsr %0; isync" :: "r"(mode) : "memory");
  base = 0x10007ffc;
  const uint32_t written = 0x2468ace0;
  __asm__ volatile(".globl page_dsi_store_site\npage_dsi_store_site:\nstwu %1,4(%0)"
    : "+&b"(base) : "r"(written) : "memory");
  if (base != 0x10008000 || fault_count != 2 ||
      !fault_state(2, page_dsi_store_site, 0x0a000000) ||
      *alias != written) return 0x89000003;

  mode = 0x40;
  __asm__ volatile("mtmsr %0; isync" :: "r"(mode) : "memory");
  if (*physical != written) return 0x89000004;
  return 1;
}
