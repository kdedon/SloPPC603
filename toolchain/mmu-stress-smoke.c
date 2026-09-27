#include <stdint.h>

/* Page replacement, invalidation, R/C, direct-store and page-fault checks
   repeated under asynchronous external and decrementer interrupts. Every
   expected value is computed here from the page table this program builds;
   interrupt handlers run in real mode and never touch a TLB. */
volatile uint32_t tohost __attribute__((section(".tohost"), used));
volatile uint32_t miss_type_count[3];
volatile uint32_t miss_total;
volatile uint32_t miss_log[64][4];
volatile uint32_t fault_log[8];
volatile uint32_t stress_ext_count;
volatile uint32_t stress_dec_count;
/* Outside .bss so the startup clear is not mistaken for an IRQ ack. */
volatile uint32_t irq_ack __attribute__((section(".data.irq_ack"))) = 1u;
volatile uint32_t stress_iterations;

extern uint32_t stress_load(uint32_t ea);
extern void stress_store(uint32_t ea, uint32_t value);
extern char stress_load_pc[], stress_store_pc[];

#define WSPR(n,v) __asm__ volatile("mtspr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")
#define WSR(n,v) __asm__ volatile("mtsr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")
#define ITERATIONS 4u

enum { HTAB = 0xfff10000u, FRAMES = 0xfff20000u };
enum { VSID1 = 0x000321u, VSID2 = 0x000654u };
/* Data pages A, B, C share DTLB set 0; E is set 1. Code pages P0..P2 share
   ITLB set 0. U has no PTE; R is read-only. */
enum {
  PAGE_A = 0x10000000u, PAGE_B = 0x10020000u, PAGE_C = 0x10040000u,
  PAGE_E = 0x10001000u, PAGE_U = 0x10060000u, PAGE_R = 0x10080000u,
  PAGE_P0 = 0x20000000u, PAGE_P1 = 0x20020000u, PAGE_P2 = 0x20040000u,
  DIRECT = 0x30000010u
};

static uint32_t frame(unsigned n) { return FRAMES + (n << 12); }
static uint32_t signature(unsigned n) { return 0x5a000000u | (n << 8) | n; }

static uint32_t pteg_address(uint32_t vsid, uint32_t ea, int secondary) {
  uint32_t hash = (vsid & 0x7ffffu) ^ ((ea >> 12) & 0xffffu);
  if (secondary) hash = ~hash;
  return HTAB | ((hash & 0x3ffu) << 6);
}

static void clear_pteg(uint32_t vsid, uint32_t ea, int secondary) {
  volatile uint32_t *g =
    (volatile uint32_t *)(uintptr_t)pteg_address(vsid, ea, secondary);
  for (unsigned w = 0; w < 16; ++w) g[w] = 0;
}

/* Install into the last free slot so the search scans past empty slots. */
static volatile uint32_t *install(uint32_t vsid, uint32_t ea, int secondary,
                                  unsigned rpn_frame, uint32_t pp) {
  volatile uint32_t *g =
    (volatile uint32_t *)(uintptr_t)pteg_address(vsid, ea, secondary);
  for (int slot = 7; slot >= 0; --slot) {
    if (g[slot * 2] & 0x80000000u) continue;
    g[slot * 2 + 1] = frame(rpn_frame) | pp;
    g[slot * 2] = 0x80000000u | (vsid << 7) |
                  (secondary ? 0x40u : 0u) | ((ea >> 22) & 0x3fu);
    return &g[slot * 2];
  }
  return 0;
}

static volatile uint32_t *pte_a, *pte_b, *pte_r;

static int build_tables(void) {
  static const uint32_t data_pages[6] = {
    PAGE_A, PAGE_B, PAGE_C, PAGE_E, PAGE_U, PAGE_R
  };
  static const uint32_t code_pages[3] = { PAGE_P0, PAGE_P1, PAGE_P2 };
  for (unsigned i = 0; i < 6; ++i) {
    clear_pteg(VSID1, data_pages[i], 0);
    clear_pteg(VSID1, data_pages[i], 1);
  }
  for (unsigned i = 0; i < 3; ++i) {
    clear_pteg(VSID2, code_pages[i], 0);
    clear_pteg(VSID2, code_pages[i], 1);
  }
  pte_a = install(VSID1, PAGE_A, 0, 0, 2);
  pte_b = install(VSID1, PAGE_B, 1, 1, 2);
  volatile uint32_t *c = install(VSID1, PAGE_C, 0, 2, 2);
  volatile uint32_t *e = install(VSID1, PAGE_E, 1, 4, 2);
  pte_r = install(VSID1, PAGE_R, 0, 5, 3);
  volatile uint32_t *p0 = install(VSID2, PAGE_P0, 0, 8, 2);
  volatile uint32_t *p1 = install(VSID2, PAGE_P1, 1, 9, 2);
  volatile uint32_t *p2 = install(VSID2, PAGE_P2, 0, 10, 2);
  __asm__ volatile("sync" ::: "memory");
  return pte_a && pte_b && c && e && pte_r && p0 && p1 && p2;
}

static void seed_frames(void) {
  for (unsigned n = 0; n < 8; ++n)
    *(volatile uint32_t *)(uintptr_t)frame(n) = signature(n);
  /* Code frames: li r3,id; blr. Written once per boot, before any fetch. */
  for (unsigned n = 8; n < 11; ++n) {
    volatile uint32_t *code = (volatile uint32_t *)(uintptr_t)frame(n);
    code[0] = 0x38600000u | (0x100u + n);
    code[1] = 0x4e800020u;
  }
  __asm__ volatile("sync" ::: "memory");
}

static void tlbie(uint32_t ea) {
  __asm__ volatile("tlbie %0" :: "r"(ea) : "memory");
}

static void invalidate_all(void) {
  __asm__ volatile("sync; isync" ::: "memory");
  for (uint32_t set = 0; set < 32; ++set) tlbie(set << 12);
  __asm__ volatile("sync; tlbsync; sync; isync" ::: "memory");
}

static uint32_t load_page(uint32_t ea) { return stress_load(ea); }
static uint32_t call_page(uint32_t ea) {
  return ((uint32_t (*)(void))(uintptr_t)ea)();
}

/* SRR1[14] is WAY in manual numbering: HDL bit 17. */
static uint32_t last_way(void) {
  return (miss_log[(miss_total - 1u) & 63u][1] >> 17) & 1u;
}

struct step { uint32_t page; uint8_t frame; uint8_t miss; uint8_t way; };

/* Two ways, per-set LRU. After A,B: A,C evicts B; A hits; B evicts C;
   C evicts A; B hits; A evicts C. Ways are relative to the first miss:
   invalidation leaves the LRU bit, so each iteration may start in either. */
static const struct step lru_steps[9] = {
  { PAGE_A, 0, 1, 0 }, { PAGE_B, 1, 1, 1 }, { PAGE_A, 0, 0, 0 },
  { PAGE_C, 2, 1, 1 }, { PAGE_A, 0, 0, 0 }, { PAGE_B, 1, 1, 1 },
  { PAGE_C, 2, 1, 0 }, { PAGE_B, 1, 0, 0 }, { PAGE_A, 0, 1, 0 }
};

static uint32_t data_lru(uint32_t *first_way) {
  for (unsigned i = 0; i < 9; ++i) {
    uint32_t before = miss_type_count[0];
    uint32_t value = load_page(lru_steps[i].page + 4u * i);
    if (i == 0) *first_way = last_way();
    if (value != signature(lru_steps[i].frame)) return 0x10u + i;
    if (miss_type_count[0] - before != lru_steps[i].miss) return 0x20u + i;
    if (lru_steps[i].miss &&
        last_way() != (lru_steps[i].way ^ *first_way)) return 0x30u + i;
  }
  return 0;
}

static uint32_t code_lru(void) {
  static const uint32_t pages[3] = { PAGE_P0, PAGE_P1, PAGE_P2 };
  static const uint8_t order[9] = { 0, 1, 0, 2, 0, 1, 2, 1, 0 };
  uint32_t first_way = 0;
  for (unsigned i = 0; i < 9; ++i) {
    uint32_t before = miss_type_count[1];
    uint32_t value = call_page(pages[order[i]]);
    if (i == 0) first_way = last_way();
    if (value != 0x108u + order[i]) return 0x40u + i;
    if (miss_type_count[1] - before != lru_steps[i].miss) return 0x50u + i;
    if (lru_steps[i].miss &&
        last_way() != (lru_steps[i].way ^ first_way)) return 0x60u + i;
  }
  return 0;
}

static uint32_t iteration(unsigned it) {
  if (!build_tables()) return 0x01u;
  for (unsigned n = 0; n < 8; ++n)
    for (unsigned w = 0; w < 16; ++w)
      *(volatile uint32_t *)(uintptr_t)(frame(n) + 4u * w) = signature(n);
  invalidate_all();

  uint32_t way_a = 0;
  uint32_t r = data_lru(&way_a);
  if (r) return r;
  if ((pte_a[1] & 0x180u) != 0x100u) return 0x70u;

  /* Store to a resident R-only entry: C=0 miss reports the matched way. */
  uint32_t stores = miss_type_count[2];
  stress_store(PAGE_A + 0x40u, 0xc0de0000u + it);
  if (miss_type_count[2] - stores != 1u || last_way() != way_a) return 0x71u;
  if (miss_log[(miss_total - 1u) & 63u][3] != (uint32_t)(uintptr_t)stress_store_pc)
    return 0x72u;
  if (*(volatile uint32_t *)(uintptr_t)(frame(0) + 0x40u) != 0xc0de0000u + it)
    return 0x73u;
  if ((pte_a[1] & 0x180u) != 0x180u) return 0x74u;
  stress_store(PAGE_A + 0x44u, it);
  if (miss_type_count[2] - stores != 1u) return 0x75u;

  /* tlbie clears set 0 in both ways only; remap A to frame 3. */
  uint32_t loads = miss_type_count[0];
  if (load_page(PAGE_E + 12u) != signature(4) ||
      miss_type_count[0] - loads != 1u) return 0x76u;
  pte_a[1] = frame(3) | 2u;
  __asm__ volatile("sync" ::: "memory");
  tlbie(PAGE_A);
  __asm__ volatile("sync; tlbsync; sync; isync" ::: "memory");
  loads = miss_type_count[0];
  if (load_page(PAGE_A + 12u) != signature(3) ||
      miss_type_count[0] - loads != 1u) return 0x77u;
  if (load_page(PAGE_E + 12u) != signature(4) ||
      miss_type_count[0] - loads != 1u) return 0x78u;
  if (load_page(PAGE_B + 4u) != signature(1) ||
      miss_type_count[0] - loads != 2u) return 0x79u;

  r = code_lru();
  if (r) return r;

  /* Direct-store segment: DSI DSISR[5] (+[6] store), ISI SRR1[3]. */
  uint32_t dsi = fault_log[0];
  if (load_page(DIRECT) != DIRECT || fault_log[0] != dsi + 1u ||
      fault_log[1] != DIRECT || fault_log[2] != 0x04000000u ||
      fault_log[3] != (uint32_t)(uintptr_t)stress_load_pc) return 0x80u;
  stress_store(DIRECT + 4u, 0xdeadu);
  if (fault_log[0] != dsi + 2u || fault_log[1] != DIRECT + 4u ||
      fault_log[2] != 0x06000000u ||
      fault_log[3] != (uint32_t)(uintptr_t)stress_store_pc) return 0x81u;
  uint32_t isi = fault_log[4];
  call_page(DIRECT & ~0xfffu);
  if (fault_log[4] != isi + 1u || fault_log[5] != (DIRECT & ~0xfffu) ||
      (fault_log[6] & 0x78000000u) != 0x10000000u) return 0x82u;

  /* Software-synthesized page fault; hardware PP DSI on a TLB hit. */
  if (load_page(PAGE_U + 8u) != PAGE_U + 8u || fault_log[0] != dsi + 3u ||
      fault_log[1] != PAGE_U + 8u || fault_log[2] != 0x40000000u) return 0x83u;
  if (load_page(PAGE_R) != signature(5)) return 0x84u;
  stress_store(PAGE_R + 8u, 1u);
  if (fault_log[0] != dsi + 4u || fault_log[1] != PAGE_R + 8u ||
      fault_log[2] != 0x0a000000u || (pte_r[1] & 0x80u)) return 0x85u;
  stress_iterations = it + 1u;
  return 0;
}

int main(void) {
  seed_frames();
  WSPR(25, HTAB);
  /* IBAT0/DBAT0: 128 KiB image and HTAB; DBAT1: 128 KiB physical frames. */
  WSPR(529, 0xfff00002u); WSPR(528, 0xfff00002u);
  WSPR(537, 0xfff00002u); WSPR(536, 0xfff00002u);
  WSPR(539, 0xfff20002u); WSPR(538, 0xfff20002u);
  WSR(1, VSID1); WSR(2, VSID2); WSR(3, 0x80000000u);
  WSPR(22, 400u);
  uint32_t mode = 0x00008070u; /* EE, IP, IR, DR */
  __asm__ volatile("mtmsr %0; isync" :: "r"(mode) : "memory");
  for (unsigned it = 0; it < ITERATIONS; ++it) {
    uint32_t r = iteration(it);
    if (r) {
      __asm__ volatile("mtmsr %0; isync" :: "r"(0x00000070u) : "memory");
      return (int)(0x8e000000u | (it << 12) | r);
    }
  }
  __asm__ volatile("mtmsr %0; isync" :: "r"(0x00000070u) : "memory");
  if (miss_type_count[0] != ITERATIONS * 11u ||
      miss_type_count[1] != ITERATIONS * 6u ||
      miss_type_count[2] != ITERATIONS) return 0x8e0000f0;
  return 1;
}
