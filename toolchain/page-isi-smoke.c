#include <stdint.h>

volatile uint32_t tohost __attribute__((section(".tohost"), used));
volatile uint32_t fault_pc, fault_srr1, fault_entry_msr, fault_count;
volatile uint32_t repair_rpa;
extern uint32_t page_probe(uint32_t);

#define WRITE_SPR(n, v) __asm__ volatile("mtspr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")
#define WRITE_SR(n, v) __asm__ volatile("isync; mtsr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")

static void seed_instruction(uint32_t rpa) {
  const uint32_t ea = 0x20000000;
  WRITE_SPR(981, 0x80000000u | (0x5678u << 7) | ((ea >> 22) & 63u));
  WRITE_SPR(982, rpa);
  WRITE_SPR(27, 0); /* WAY 0; bounded TLB load runs with IR=DR=0. */
  __asm__ volatile("sync; isync; tlbli %0; sync; isync" :: "r"(ea) : "memory");
}

static int fault_state(uint32_t count, uint32_t syndrome) {
  return fault_count == count && fault_pc == 0x20000000 &&
         fault_srr1 == (0x60u | syndrome) && fault_entry_msr == 0x40;
}

int main(void) {
  uint32_t (*probe)(uint32_t) = (uint32_t (*)(uint32_t))(uintptr_t)0x20000000;
  uint32_t mode;
  /* The CPU installs physical bootstrap BATs and the instruction TLB entry. */
  WRITE_SPR(528, 0); WRITE_SPR(530, 0); WRITE_SPR(532, 0); WRITE_SPR(534, 0);
  WRITE_SPR(536, 0); WRITE_SPR(538, 0); WRITE_SPR(540, 0); WRITE_SPR(542, 0);
  WRITE_SPR(529, 0xfff00002); WRITE_SPR(528, 0xfff00002);
  WRITE_SPR(537, 0xfff00002); WRITE_SPR(536, 0xfff00002);
  WRITE_SR(2, 0x40005678); /* Ks=1 makes PP=00 deny instruction fetch. */
  seed_instruction(0xfff06180);
  repair_rpa = 0xfff06182;
  mode = 0x60; /* IP=1, IR=1, DR=0. */
  __asm__ volatile("mtmsr %0; isync" :: "r"(mode) : "memory");
  if (probe(25) != 42 || !fault_state(1, 0x08000000)) return 0x8a000001;

  mode = 0x40;
  __asm__ volatile("mtmsr %0; isync" :: "r"(mode) : "memory");
  WRITE_SR(2, 0x50005678); /* N denies even while the allowed entry remains. */
  mode = 0x60;
  __asm__ volatile("mtmsr %0; isync" :: "r"(mode) : "memory");
  if (probe(56) != 73 || !fault_state(2, 0x10000000)) return 0x8a000002;

  mode = 0x40;
  __asm__ volatile("mtmsr %0; isync" :: "r"(mode) : "memory");
  seed_instruction(0xfff0618a); /* WIMG.G=1, PP=10, C=1. */
  repair_rpa = 0xfff06182;
  mode = 0x60;
  __asm__ volatile("mtmsr %0; isync" :: "r"(mode) : "memory");
  if (probe(83) != 100 || !fault_state(3, 0x10000000)) return 0x8a000003;

  mode = 0x40;
  __asm__ volatile("mtmsr %0; isync" :: "r"(mode) : "memory");
  if (fault_count != 3 || page_probe(7) != 24) return 0x8a000004;
  return 1;
}
