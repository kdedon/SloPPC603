#include <stdint.h>

/* Real-mode PTEGs are populated by the CPU, never by the testbench. */
volatile uint32_t tohost __attribute__((section(".tohost"), used));
volatile uint32_t miss_count;
volatile uint32_t miss_records[4][8];

extern uint32_t miss_load(uint32_t ea);
extern void miss_store(uint32_t ea, uint32_t value);
extern char miss_load_pc[], miss_store_pc[];

#define WSPR(n,v) __asm__ volatile("mtspr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")
#define WSR(n,v) __asm__ volatile("mtsr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")

/* Each PTEG is 64 bytes: eight big-endian {PTE0,PTE1} pairs. */
const uint32_t pteg_bases[8] __attribute__((used)) = {
  0xfff19e00u, 0xfff161c0u, /* instruction primary, secondary */
  0xfff18f00u, 0xfff170c0u, /* data load primary, secondary */
  0xfff18f40u, 0xfff17080u, /* data store primary, secondary */
  0xfff18f80u, 0xfff17040u  /* resident C=0 primary, secondary */
};
volatile uint32_t pte_before[8][16];

static volatile uint32_t *pteg(unsigned group) {
  return (volatile uint32_t *)(uintptr_t)pteg_bases[group];
}

static void clear_ptegs(void) {
  for (unsigned group = 0; group < 8; ++group) {
    volatile uint32_t *entry = pteg(group);
    for (unsigned word = 0; word < 16; ++word) entry[word] = 0;
  }
}

/* A wrong V, H, VSID, and API must each fail the full-word comparison. */
static void seed_target(unsigned group, unsigned slot, uint32_t high,
                        uint32_t low) {
  static const uint32_t wrong_field[4] = {
    0x80000000u, 0x00000040u, 0x00000080u, 0x00000001u
  };
  volatile uint32_t *entry = pteg(group);
  for (unsigned kind = 0; kind < 4; ++kind) {
    unsigned decoy_slot = (slot == 3 && kind == 3) ? 4 : kind;
    entry[decoy_slot * 2] = high ^ wrong_field[kind];
    entry[decoy_slot * 2 + 1] =
      0xdec00002u + (group << 16) + (decoy_slot << 12);
  }
  entry[slot * 2] = high;
  entry[slot * 2 + 1] = low;
}

static void seed_ptegs(void) {
  clear_ptegs();
  seed_target(0, 7, 0x802b3c00u, 0xfff06002u); /* I primary slot 7 */
  seed_target(3, 6, 0x80091a40u, 0xfff08002u); /* D load secondary slot 6 */
  seed_target(4, 3, 0x80091a00u, 0xfff09002u); /* D store primary slot 3 */
  seed_target(7, 7, 0x80091a40u, 0xfff0a002u); /* C=0 secondary slot 7 */
  /* Secondary targets must not match their primary search key. */
  pteg(2)[10] = 0x80091a40u;
  pteg(2)[11] = 0xdec20502u;
  pteg(6)[10] = 0x80091a40u;
  pteg(6)[11] = 0xdec60502u;
  for (unsigned group = 0; group < 8; ++group) {
    volatile uint32_t *entry = pteg(group);
    for (unsigned word = 0; word < 16; ++word)
      pte_before[group][word] = entry[word];
  }
}

static int tables_changed_exactly(void) {
  static const unsigned hit_group[4] = {0, 3, 4, 7};
  static const unsigned hit_word[4] = {15, 13, 7, 15};
  static const uint32_t final_low[4] = {
    0xfff06102u, 0xfff08102u, 0xfff09182u, 0xfff0a182u
  };
  for (unsigned group = 0; group < 8; ++group) {
    volatile uint32_t *entry = pteg(group);
    for (unsigned word = 0; word < 16; ++word) {
      uint32_t expected = pte_before[group][word];
      for (unsigned hit = 0; hit < 4; ++hit)
        if (group == hit_group[hit] && word == hit_word[hit])
          expected = final_low[hit];
      if (entry[word] != expected) return 0;
    }
  }
  return 1;
}

static int record(unsigned n, uint32_t ea, uint32_t cmp,
                  uint32_t hash1, uint32_t hash2, uint32_t pc,
                  uint32_t flags) {
  return miss_records[n][0] == ea && miss_records[n][1] == cmp &&
    miss_records[n][2] == hash1 && miss_records[n][3] == hash2 &&
    miss_records[n][4] == pc &&
    (miss_records[n][5] & 0x0fffffffu) == flags &&
    miss_records[n][6] == 0x00020040u && miss_records[n][7] == n + 1;
}

int main(void) {
  seed_ptegs();
  __asm__ volatile("sync" ::: "memory");
  WSPR(25, 0xfff10000u); /* SDR1: aligned 64-KiB HTAB, mask zero. */
  WSPR(529, 0xfff00002u); WSPR(528, 0xfff00002u);
  WSPR(537, 0xfff00002u); WSPR(536, 0xfff00002u);
  WSR(1, 0x00001234u); WSR(2, 0x00005678u);

  /* This resident C=0 translation occupies way 1 before the first store. */
  WSPR(977, 0x80091a00u);
  WSPR(982, 0xfff0a002u);
  WSPR(27, 0x00020000u);
  uint32_t changed_ea = 0x1000a00cu;
  __asm__ volatile("tlbld %0; isync" :: "r"(changed_ea) : "memory");

  *(volatile uint32_t *)(uintptr_t)0xfff08004u = 0x13579bdfu;
  uint32_t mode = 0x00000070u; /* IP=IR=DR=1. */
  __asm__ volatile("mtmsr %0; isync" :: "r"(mode) : "memory");

  if (((uint32_t (*)(uint32_t))0x20000000u)(25u) != 42u || miss_count != 1u)
    return 0x8e000001u;
  if (miss_load(0x10008004u) != 0x13579bdfu || miss_count != 2u)
    return 0x8e000002u;
  miss_store(0x10009008u, 0x2468ace0u);
  if (*(volatile uint32_t *)(uintptr_t)0xfff09008u != 0x2468ace0u ||
      miss_count != 3u) return 0x8e000003u;
  miss_store(changed_ea, 0xaabbccddu);
  if (*(volatile uint32_t *)(uintptr_t)0xfff0a00cu != 0xaabbccddu ||
      miss_count != 4u) return 0x8e000004u;

  if (!record(0, 0x20000000u, 0x802b3c00u, 0xfff19e00u,
              0xfff161c0u, 0x20000000u, 0x00040070u)) return 0x8e000005u;
  if (!record(1, 0x10008004u, 0x80091a00u, 0xfff18f00u,
              0xfff170c0u, (uint32_t)(uintptr_t)miss_load_pc,
              0x00000070u)) return 0x8e000006u;
  if (!record(2, 0x10009008u, 0x80091a00u, 0xfff18f40u,
              0xfff17080u, (uint32_t)(uintptr_t)miss_store_pc,
              0x00010070u)) return 0x8e000007u;
  if (!record(3, changed_ea, 0x80091a00u, 0xfff18f80u,
              0xfff17040u, (uint32_t)(uintptr_t)miss_store_pc,
              0x00030070u)) return 0x8e000008u;
  if (!tables_changed_exactly()) return 0x8e000009u;
  return 1;
}
