/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
#include <stdint.h>

/* Page replacement, invalidation, R/C, direct-store and page-fault checks,
   a page-crossing branch storm, BAT remap/WIMG/IR and BAT-over-TLB checks,
   and segment and SDR1 context changes, repeated under asynchronous
   external and decrementer interrupts. Every
   expected value is computed here from the page table this program builds;
   interrupt handlers run in real mode and never touch a TLB. */
volatile uint32_t tohost __attribute__((section(".tohost"), used));
volatile uint32_t miss_type_count[3];
volatile uint32_t miss_total;
volatile uint32_t miss_log[64][4];
volatile uint32_t fault_log[8];
volatile uint32_t stress_ext_count;
volatile uint32_t stress_dec_count;
volatile uint32_t stress_mc_count;
/* Outside .bss so the startup clear is not mistaken for an IRQ ack. */
volatile uint32_t irq_ack __attribute__((section(".data.irq_ack"))) = 0u;
volatile uint32_t stress_iterations;

extern uint32_t stress_load(uint32_t ea);
extern void stress_store(uint32_t ea, uint32_t value);
extern char stress_load_pc[], stress_store_pc[];
extern const uint32_t storm_blob[128];

#define WSPR(n,v) __asm__ volatile("mtspr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")
#define WSR(n,v) __asm__ volatile("mtsr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")
#define ITERATIONS 4u

enum { HTAB = 0xfff10000u, HTAB2 = 0xfff30000u, FRAMES = 0xfff20000u };
enum { VSID1 = 0x000321u, VSID2 = 0x000654u, VSID3 = 0x000987u };
/* Data pages A, B, C share DTLB set 0; E is set 1. Code pages P0..P2 share
   ITLB set 0. U has no PTE; R is read-only. */
enum {
  PAGE_A = 0x10000000u, PAGE_B = 0x10020000u, PAGE_C = 0x10040000u,
  PAGE_E = 0x10001000u, PAGE_U = 0x10060000u, PAGE_R = 0x10080000u,
  PAGE_P0 = 0x20000000u, PAGE_P1 = 0x20020000u, PAGE_P2 = 0x20040000u,
  PAGE_Q0 = 0x20060000u, PAGE_Q1 = 0x20061000u, DIRECT = 0x30000010u
};
/* Code for the BAT checks: returns ID_X at image offset 0xe000, ID_Y at
   frame 14 and ID_Z at image offset 0. Frame 12 holds a decoy. */
enum { ID_X = 0x301u, ID_Y = 0x302u, ID_Z = 0x303u, ID_DECOY = 0xbadu };
enum { CODE_X = 0xfff0e000u, CODE_Y = 0xfff2e000u, CODE_Z = 0xfff00000u };
#define STORM ((uint32_t (*)(uint32_t, uint32_t))(uintptr_t)(PAGE_Q0 + 0xfc0u))

static uint32_t frame(unsigned n) { return FRAMES + (n << 12); }
static uint32_t signature(unsigned n) { return 0x5a000000u | (n << 8) | n; }

static uint32_t pteg_address(uint32_t htab, uint32_t vsid, uint32_t ea,
                             int secondary) {
  uint32_t hash = (vsid & 0x7ffffu) ^ ((ea >> 12) & 0xffffu);
  if (secondary) hash = ~hash;
  return htab | ((hash & 0x3ffu) << 6);
}

static void clear_pteg_in(uint32_t htab, uint32_t vsid, uint32_t ea,
                          int secondary) {
  volatile uint32_t *g =
    (volatile uint32_t *)(uintptr_t)pteg_address(htab, vsid, ea, secondary);
  for (unsigned w = 0; w < 16; ++w) g[w] = 0;
}

static void clear_pteg(uint32_t vsid, uint32_t ea, int secondary) {
  clear_pteg_in(HTAB, vsid, ea, secondary);
}

/* Install into the last free slot so the search scans past empty slots. */
static volatile uint32_t *install_in(uint32_t htab, uint32_t vsid, uint32_t ea,
                                     int secondary, unsigned rpn_frame,
                                     uint32_t pp) {
  volatile uint32_t *g =
    (volatile uint32_t *)(uintptr_t)pteg_address(htab, vsid, ea, secondary);
  for (int slot = 7; slot >= 0; --slot) {
    if (g[slot * 2] & 0x80000000u) continue;
    g[slot * 2 + 1] = frame(rpn_frame) | pp;
    g[slot * 2] = 0x80000000u | (vsid << 7) |
                  (secondary ? 0x40u : 0u) | ((ea >> 22) & 0x3fu);
    return &g[slot * 2];
  }
  return 0;
}

static volatile uint32_t *install(uint32_t vsid, uint32_t ea, int secondary,
                                  unsigned rpn_frame, uint32_t pp) {
  return install_in(HTAB, vsid, ea, secondary, rpn_frame, pp);
}

static volatile uint32_t *pte_a, *pte_b, *pte_r;

static int build_tables(void) {
  static const uint32_t data_pages[6] = {
    PAGE_A, PAGE_B, PAGE_C, PAGE_E, PAGE_U, PAGE_R
  };
  static const uint32_t code_pages[5] = {
    PAGE_P0, PAGE_P1, PAGE_P2, PAGE_Q0, PAGE_Q1
  };
  for (unsigned i = 0; i < 6; ++i) {
    clear_pteg(VSID1, data_pages[i], 0);
    clear_pteg(VSID1, data_pages[i], 1);
  }
  clear_pteg(VSID3, PAGE_A, 0);
  clear_pteg(VSID3, PAGE_A, 1);
  for (unsigned i = 0; i < 2; ++i) {
    clear_pteg_in(HTAB2, VSID1, PAGE_A, i);
    clear_pteg_in(HTAB2, VSID1, PAGE_E, i);
  }
  for (unsigned i = 0; i < 5; ++i) {
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
  /* Q0 and Q1 are contiguous EAs in separate frames 11 and 13. */
  volatile uint32_t *q0 = install(VSID2, PAGE_Q0, 0, 11, 2);
  volatile uint32_t *q1 = install(VSID2, PAGE_Q1, 1, 13, 2);
  /* A second context: A under VSID3, and A alone in the table at HTAB2. */
  volatile uint32_t *a3 = install(VSID3, PAGE_A, 1, 6, 2);
  volatile uint32_t *a2 = install_in(HTAB2, VSID1, PAGE_A, 0, 7, 2);
  __asm__ volatile("sync" ::: "memory");
  return pte_a && pte_b && c && e && pte_r && p0 && p1 && p2 && q0 && q1 &&
         a3 && a2;
}

/* Lane loop, run through IBAT2 at EA 0x40000000 + PA offset: chunks at
   offset 0x800 of frames 8, 9, 10 and 12, then the last 0x18 bytes of frame
   14 falling into frame 15. Chunk k loads from data frame k; the tail loads
   frames 5 and 6 just before the page boundary. Both sides cycle through
   more pages than a four-entry micro-TLB holds, so instruction and data
   translations compete. */
static const uint8_t lane_frames[4] = { 8, 9, 10, 12 };
enum { LANE_BIAS = 0x40000000u - FRAMES, LANE_DATA = 0x20u };
enum { LANE_TAIL = 0xfff2efe8u, LANE_COUNT = 24u };
static uint32_t lane_ea(unsigned k) {
  return (k < 4 ? frame(lane_frames[k]) + 0x800u : LANE_TAIL) + LANE_BIAS;
}
static uint32_t lwz(unsigned rd, unsigned frame_n) {
  return 0x80030000u | (rd << 21) | ((frame_n << 12) + LANE_DATA);
}
static uint32_t branch(uint32_t from, uint32_t to) {
  return 0x48000000u | ((to - from) & 0x03fffffcu);
}

static void write_lanes(void) {
  for (unsigned k = 0; k < 4; ++k) {
    volatile uint32_t *code =
      (volatile uint32_t *)(uintptr_t)(frame(lane_frames[k]) + 0x800u);
    unsigned i = 0;
    if (k == 0) {
      code[i++] = 0x7c8903a6u;                      /* mtctr r4 */
      code[i++] = 0x38a00000u;                      /* li r5,0 */
    }
    code[i++] = lwz(9, k);
    code[i++] = 0x7ca54a14u;                        /* add r5,r5,r9 */
    code[i] = branch(lane_ea(k) + 4u * i, lane_ea(k + 1));
  }
  static const uint32_t tail[9] = {
    0x81234020u,                                    /* lwz r9,frame 4 */
    0x7ca54a14u,                                    /* add r5,r5,r9 */
    0x81435020u,                                    /* lwz r10,frame 5 */
    0x7ca55214u,                                    /* add r5,r5,r10 */
    0x60000000u,                                    /* nop */
    0x81436020u,                                    /* lwz r10,frame 6 */
    0x7ca55214u,                                    /* add r5,r5,r10 (frame 15) */
    0u,                                             /* bdnz */
    0x7ca32b78u                                     /* mr r3,r5 */
  };
  volatile uint32_t *code = (volatile uint32_t *)(uintptr_t)LANE_TAIL;
  for (unsigned i = 0; i < 9; ++i) code[i] = tail[i];
  code[7] = 0x42000000u | ((lane_ea(0) + 8u - (lane_ea(4) + 28u)) & 0xfffcu);
  code[9] = 0x4e800020u;                            /* blr */
}

static uint32_t lane_expected(void) {
  uint32_t sum = 0;
  for (unsigned k = 0; k < 7; ++k) sum += signature(k);
  return LANE_COUNT * sum;
}

/* Defined by the chip boot code, which turns the data cache on. */
extern const uint32_t chip_boot __attribute__((weak));

/* Written code leaves the data cache before anything fetches it. */
static void flush_code(uint32_t base, uint32_t bytes) {
  if (!&chip_boot) return;
  for (uint32_t a = base; a < base + bytes; a += 32u)
    __asm__ volatile("dcbst 0,%0" :: "r"(a) : "memory");
  __asm__ volatile("sync" ::: "memory");
  for (uint32_t a = base; a < base + bytes; a += 32u)
    __asm__ volatile("icbi 0,%0" :: "r"(a) : "memory");
  __asm__ volatile("sync; isync" ::: "memory");
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
  volatile uint32_t *q0 = (volatile uint32_t *)(uintptr_t)(frame(11) + 0xf00u);
  volatile uint32_t *q1 = (volatile uint32_t *)(uintptr_t)frame(13);
  volatile uint32_t *decoy = (volatile uint32_t *)(uintptr_t)frame(12);
  for (unsigned w = 0; w < 64; ++w) {
    q0[w] = storm_blob[w];
    q1[w] = storm_blob[64 + w];
    decoy[w] = (w & 1) ? 0x4e800020u : (0x38600000u | ID_DECOY);
  }
  write_lanes();
  static const uint32_t code_at[3] = { CODE_X, CODE_Y, CODE_Z };
  static const uint32_t code_id[3] = { ID_X, ID_Y, ID_Z };
  for (unsigned i = 0; i < 3; ++i) {
    volatile uint32_t *code = (volatile uint32_t *)(uintptr_t)code_at[i];
    code[0] = 0x38600000u | code_id[i];
    code[1] = 0x4e800020u;
    flush_code(code_at[i], 8u);
  }
  flush_code(frame(8), 8u << 12);
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

static uint32_t storm_ref(uint32_t r3, uint32_t n) {
  for (uint32_t r5 = 1; r5 <= n; ++r5) {
    uint32_t r6 = r5 & 3u;
    if (r6 == 0) r3 -= r5;
    else r3 = (r6 == 2 ? r3 + 0x11u : r3 ^ r5) + r5;
    r3 = ((r3 << 3) | (r3 >> 29)) ^ 0x5a5au;
  }
  return r3;
}

/* Three storm calls; tlbie Q1 before the last two makes each one take an
   instruction miss at the page boundary in the middle of a loop. */
static uint32_t branch_storm(unsigned it) {
  uint32_t before = miss_type_count[1];
  for (unsigned call = 0; call < 3; ++call) {
    if (call) {
      __asm__ volatile("sync" ::: "memory");
      tlbie(PAGE_Q1);
      __asm__ volatile("sync; tlbsync; sync; isync" ::: "memory");
    }
    uint32_t seed = 0x1234567u * (it * 3u + call + 1u);
    uint32_t count = 40u + 8u * call;
    if (STORM(seed, count) != storm_ref(seed, count)) return 0xa0u + call;
  }
  if (miss_type_count[1] - before != 4u) return 0xa3u;
  return 0;
}

static void write_ibat(unsigned n, uint32_t upper, uint32_t lower) {
  /* Invalidate first so no half-written pair is ever valid. */
  if (n == 2) { WSPR(532, 0); WSPR(533, lower); WSPR(532, upper); }
  else { WSPR(534, 0); WSPR(535, lower); WSPR(534, upper); }
}

/* BAT remap, WIMG and IR changes over cached lines, and BAT precedence over
   resident TLB entries on both sides. */
static uint32_t bat_phase(void) {
  invalidate_all();
  write_ibat(2, 0x40000002u, 0xfff00002u);
  if (call_page(0x4000e000u) != ID_X || call_page(0x4000e000u) != ID_X)
    return 0xb0u;
  write_ibat(2, 0x40000002u, 0xfff20002u);
  if (call_page(0x4000e000u) != ID_Y) return 0xb1u;
  uint32_t lanes =
    ((uint32_t (*)(uint32_t, uint32_t))(uintptr_t)lane_ea(0))(FRAMES, LANE_COUNT);
  if (lanes != lane_expected()) return 0xbau;
  /* Halfword store and load at word offset 0. */
  volatile uint16_t *half = (volatile uint16_t *)(uintptr_t)(frame(7) + 0x30u);
  *half = 0x1234u;
  if (*half != 0x1234u ||
      *(volatile uint32_t *)(uintptr_t)(frame(7) + 0x30u) !=
        ((signature(7) & 0xffffu) | 0x12340000u)) return 0xbbu;
  write_ibat(2, 0x40000002u, 0xfff20022u); /* I=1: bypass the cache */
  if (call_page(0x4000e000u) != ID_Y) return 0xb2u;
  write_ibat(2, 0, 0);
  __asm__ volatile("mtmsr %0; isync" :: "r"(0x00009052u) : "memory");
  uint32_t real_y = call_page(CODE_Y), real_x = call_page(CODE_X);
  __asm__ volatile("mtmsr %0; isync" :: "r"(0x00009072u) : "memory");
  if (real_y != ID_Y || real_x != ID_X) return 0xb3u;

  uint32_t fetches = miss_type_count[1];
  if (call_page(PAGE_P0) != 0x108u) return 0xb4u;
  write_ibat(3, 0x20000002u, 0xfff00002u);
  if (call_page(PAGE_P0) != ID_Z || call_page(PAGE_P0 + 0xe000u) != ID_X)
    return 0xb5u;
  write_ibat(3, 0, 0);
  if (call_page(PAGE_P0) != 0x108u || miss_type_count[1] - fetches != 1u)
    return 0xb6u;

  uint32_t loads = miss_type_count[0];
  if (load_page(PAGE_A + 12u) != signature(3)) return 0xb7u;
  WSPR(540, 0); WSPR(541, 0xfff20002u); WSPR(540, 0x10000002u);
  if (load_page(PAGE_A + 12u) != signature(0) ||
      load_page(PAGE_E + 12u) != signature(1)) return 0xb8u;
  WSPR(540, 0);
  if (load_page(PAGE_A + 12u) != signature(3) ||
      miss_type_count[0] - loads != 1u) return 0xb9u;
  return 0;
}

/* SDR1 changes only with IR=DR=0 (PEM Table 2-22), after a sync. */
static void set_sdr1(uint32_t value) {
  __asm__ volatile("mtmsr %1; isync; sync; mtspr 25,%0; isync; mtmsr %2; isync"
                   :: "r"(value), "r"(0x00009042u), "r"(0x00009072u) : "memory");
}

/* Segment and page-table changes: the TLB tags VSIDs, and after SDR1 moves
   the miss handler searches only the new table. */
static uint32_t context_phase(void) {
  invalidate_all();
  uint32_t loads = miss_type_count[0];
  if (load_page(PAGE_A + 16u) != signature(3)) return 0xc0u;
  WSR(1, VSID3);
  uint32_t other = load_page(PAGE_A + 16u);
  WSR(1, VSID1);
  if (other != signature(6)) return 0xc1u;
  if (load_page(PAGE_A + 16u) != signature(3) ||
      miss_type_count[0] - loads != 2u) return 0xc2u;

  invalidate_all();
  uint32_t dsi = fault_log[0];
  set_sdr1(HTAB2);
  uint32_t moved = load_page(PAGE_A + 16u);
  uint32_t absent = load_page(PAGE_E + 12u);
  set_sdr1(HTAB);
  if (moved != signature(7)) return 0xc3u;
  if (absent != PAGE_E + 12u || fault_log[0] != dsi + 1u ||
      fault_log[2] != 0x40000000u) return 0xc4u;
  invalidate_all();
  if (load_page(PAGE_A + 16u) != signature(3) ||
      miss_type_count[0] - loads != 5u) return 0xc5u;
  return 0;
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

  r = branch_storm(it);
  if (r) return r;
  r = bat_phase();
  if (r) return r;
  r = context_phase();
  if (r) return r;
  stress_iterations = it + 1u;
  return 0;
}

/* Page-table WIMG over frame 15: W=1 (WM), I=1 G=1, cacheable (M=0) and
   M=1 G=1 pages, each on its own line, with an I=1 G=1 alias to read memory
   behind the cache. The stale-alias check needs the data cache on. */
enum {
  PAGE_WT = 0x100a0000u, PAGE_CI = 0x100c0000u, PAGE_CB = 0x100e0000u,
  PAGE_MG = 0x10100000u
};
#define WORD(ea) (*(volatile uint32_t *)(uintptr_t)(ea))
#define CACHE_OP(op, ea) __asm__ volatile(op " 0,%0; sync" :: "r"(ea) : "memory")
static uint32_t wimg_phase(void) {
  uint32_t hid0;
  __asm__ volatile("mfspr %0,1008" : "=r"(hid0));
  if (!install(VSID1, PAGE_WT, 0, 15, 2u | (0xau << 3)) ||
      !install(VSID1, PAGE_CI, 0, 15, 2u | (0x5u << 3)) ||
      !install(VSID1, PAGE_CB, 0, 15, 2u) ||
      !install(VSID1, PAGE_MG, 0, 15, 2u | (0x3u << 3))) return 0xd0u;
  __asm__ volatile("sync" ::: "memory");
  WORD(PAGE_WT + 0x40u) = 0x77000001u;
  if (WORD(PAGE_CI + 0x40u) != 0x77000001u) return 0xd1u;
  if (WORD(PAGE_WT + 0x40u) != 0x77000001u) return 0xd2u;
  WORD(PAGE_CI + 0x80u) = 0x77000002u;
  if (WORD(PAGE_CB + 0x80u) != 0x77000002u) return 0xd3u;
  WORD(PAGE_CB + 0x80u) = 0x77000003u;
  if ((hid0 & 0x4000u) && WORD(PAGE_CI + 0x80u) != 0x77000002u) return 0xd4u;
  CACHE_OP("dcbst", PAGE_CB + 0x80u);
  if (WORD(PAGE_CI + 0x80u) != 0x77000003u) return 0xd5u;
  WORD(PAGE_MG + 0xc0u) = 0x77000004u;
  if (WORD(PAGE_MG + 0xc0u) != 0x77000004u) return 0xd6u;
  CACHE_OP("dcbf", PAGE_MG + 0xc0u);
  if (WORD(PAGE_CI + 0xc0u) != 0x77000004u) return 0xd7u;
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
  uint32_t mode = 0x00009072u; /* EE, ME, IP, IR, DR, RI */
  __asm__ volatile("mtmsr %0; isync" :: "r"(mode) : "memory");
  for (unsigned it = 0; it < ITERATIONS; ++it) {
    uint32_t r = iteration(it);
    if (r) {
      __asm__ volatile("mtmsr %0; isync" :: "r"(0x00001072u) : "memory");
      return (int)(0x8e000000u | (it << 12) | r);
    }
  }
  __asm__ volatile("mtmsr %0; isync" :: "r"(0x00001072u) : "memory");
  if (miss_type_count[0] != ITERATIONS * 17u ||
      miss_type_count[1] != ITERATIONS * 11u ||
      miss_type_count[2] != ITERATIONS) return 0x8e0000f0;
  uint32_t w = wimg_phase();
  if (w) return (int)(0x8e000000u | w);
  return 1;
}
