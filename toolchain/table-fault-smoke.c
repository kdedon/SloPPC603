#include <stdint.h>

volatile uint32_t tohost __attribute__((section(".tohost"), used));
volatile uint32_t case_marker __attribute__((section(".case_marker"), used));
volatile uint32_t miss_count;
volatile uint32_t miss_records[4][8];
volatile uint32_t fault_count;
volatile uint32_t fault_records[16][6];
volatile uint32_t fault_cr_scratch, fault_kind_scratch;
volatile uint32_t pte_before[12][16];

extern uint32_t miss_load(uint32_t ea);
extern void miss_store(uint32_t ea, uint32_t value);
extern uint32_t fault_load_byte(uint32_t ea);
extern char miss_load_pc[], miss_store_pc[], fault_load_byte_pc[];

#define WSPR(n,v) __asm__ volatile("mtspr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")
#define WSR(n,v) __asm__ volatile("mtsr " #n ",%0; isync" :: "r"((uint32_t)(v)) : "memory")

/* PTEGs are CPU-initialized physical RAM, not ELF or harness preload data. */
const uint32_t fault_pteg_bases[12] __attribute__((used)) = {
  0xfff19e40u, 0xfff16180u, /* marker 1: I page absent */
  0xfff18e00u, 0xfff171c0u, /* marker 2: D byte absent */
  0xfff18e40u, 0xfff17180u, /* marker 3: D store absent */
  0xfff19e80u, 0xfff16140u, /* marker 4: I guarded */
  0xfff19ec0u, 0xfff16100u, /* marker 5: I PP denied */
  0xfff18fc0u, 0xfff17000u  /* markers 16–31: D PP/key matrix */
};
static volatile uint32_t *pteg(unsigned group) {
  return (volatile uint32_t *)(uintptr_t)fault_pteg_bases[group];
}
static void snapshot_ptegs(void) {
  for (unsigned group = 0; group < 12; ++group) {
    volatile uint32_t *entry = pteg(group);
    for (unsigned word = 0; word < 16; ++word)
      pte_before[group][word] = entry[word];
  }
}
static void seed_ptegs(void) {
  for (unsigned group = 0; group < 12; ++group) {
    volatile uint32_t *entry = pteg(group);
    for (unsigned word = 0; word < 16; ++word) entry[word] = 0;
  }
  pteg(6)[8] = 0x802b3c00u;  /* guarded I, primary slot 4 */
  pteg(6)[9] = 0xfff0d00au;  /* R=0, C=0, G=1, PP=2 */
  pteg(8)[4] = 0x802b3c00u;  /* I PP denied, primary slot 2 */
  pteg(8)[5] = 0xfff0e000u;  /* R=0, C=0, G=0, PP=0 */
  pteg(10)[10] = 0x80091a00u; /* D matrix, primary slot 5 */
  pteg(10)[11] = 0xfff0c000u; /* PP set per case */
  snapshot_ptegs();
}
static int ptegs_changed_only(unsigned change_group, unsigned change_word,
                              uint32_t changed_value) {
  for (unsigned group = 0; group < 12; ++group) {
    volatile uint32_t *entry = pteg(group);
    for (unsigned word = 0; word < 16; ++word) {
      uint32_t expected = pte_before[group][word];
      if (group == change_group && word == change_word)
        expected = changed_value;
      if (entry[word] != expected) return 0;
    }
  }
  return 1;
}
static void invalidate(uint32_t ea) {
  __asm__ volatile("sync; tlbie %0; sync; isync" :: "r"(ea) : "memory");
}
static void begin_case(uint32_t marker, uint32_t ea) {
  case_marker = marker;
  miss_count = 0;
  for (unsigned i = 0; i < 4; ++i)
    for (unsigned j = 0; j < 8; ++j) miss_records[i][j] = 0;
  invalidate(ea);
}
static int one_miss(uint32_t ea, uint32_t compare,
                    uint32_t hash1, uint32_t hash2, uint32_t key) {
  return miss_count == 1 && miss_records[0][0] == ea &&
    miss_records[0][1] == compare && miss_records[0][2] == hash1 &&
    miss_records[0][3] == hash2 &&
    miss_records[0][6] == 0x00020040u && miss_records[0][7] == 1 &&
    ((miss_records[0][5] >> 19) & 1u) == key;
}
static int fault_record(uint32_t index, uint32_t marker, uint32_t pc,
                        uint32_t srr1, uint32_t dar, uint32_t dsisr,
                        int data_fault) {
  return fault_count == index + 1 &&
    fault_records[index][0] == marker && fault_records[index][1] == pc &&
    fault_records[index][2] == srr1 &&
    (!data_fault || (fault_records[index][3] == dar &&
                     fault_records[index][4] == dsisr)) &&
    fault_records[index][5] == 0x00000040u;
}

int main(void) {
  seed_ptegs();
  __asm__ volatile("sync" ::: "memory");
  WSPR(25, 0xfff10000u);
  WSPR(529, 0xfff00002u); WSPR(528, 0xfff00002u);
  WSPR(537, 0xfff00002u); WSPR(536, 0xfff00002u);
  WSR(1, 0x00001234u); WSR(2, 0x00005678u);
  uint32_t mode = 0x00000070u; /* IP=IR=DR=1. */
  __asm__ volatile("mtmsr %0; isync" :: "r"(mode) : "memory");

  begin_case(1, 0x20001004u);
  if (((uint32_t (*)(uint32_t))0x20001004u)(17u) != 17u)
    return 0x8f000001u;
  if (!one_miss(0x20001004u, 0x802b3c00u,
                0xfff19e40u, 0xfff16180u, 0u) ||
      !fault_record(0, 1, 0x20001004u, 0x40000070u, 0, 0, 0) ||
      !ptegs_changed_only(12, 16, 0)) return 0x8f000002u;

  begin_case(2, 0x1000c003u);
  if (fault_load_byte(0x1000c003u) != 0x1000c003u)
    return 0x8f000003u;
  if (!one_miss(0x1000c003u, 0x80091a00u,
                0xfff18e00u, 0xfff171c0u, 0u) ||
      !fault_record(1, 2, (uint32_t)(uintptr_t)fault_load_byte_pc,
                    0x00000070u, 0x1000c003u, 0x40000000u, 1) ||
      !ptegs_changed_only(12, 16, 0)) return 0x8f000004u;

  begin_case(3, 0x1000d008u);
  miss_store(0x1000d008u, 0x77777777u);
  if (!one_miss(0x1000d008u, 0x80091a00u,
                0xfff18e40u, 0xfff17180u, 0u) ||
      !fault_record(2, 3, (uint32_t)(uintptr_t)miss_store_pc,
                    0x00000070u, 0x1000d008u, 0x42000000u, 1) ||
      !ptegs_changed_only(12, 16, 0)) return 0x8f000005u;

  begin_case(4, 0x20002008u);
  if (((uint32_t (*)(uint32_t))0x20002008u)(23u) != 23u)
    return 0x8f000006u;
  if (!one_miss(0x20002008u, 0x802b3c00u,
                0xfff19e80u, 0xfff16140u, 0u) ||
      !fault_record(3, 4, 0x20002008u, 0x10000070u, 0, 0, 0) ||
      !ptegs_changed_only(12, 16, 0)) return 0x8f000007u;

  WSR(2, 0x40005678u); /* Ks=1 rejects PP=00 instruction fetch. */
  begin_case(5, 0x2000300cu);
  if (((uint32_t (*)(uint32_t))0x2000300cu)(29u) != 29u)
    return 0x8f000008u;
  if (!one_miss(0x2000300cu, 0x802b3c00u,
                0xfff19ec0u, 0xfff16100u, 1u) ||
      !fault_record(4, 5, 0x2000300cu, 0x08000070u, 0, 0, 0) ||
      !ptegs_changed_only(12, 16, 0)) return 0x8f000009u;
  WSR(2, 0x00005678u);

  /* All 16 KEY x PP x {load,store} combinations use one resident PTEG.
     Every case starts with R=C=0 and an invalidated TLB set. */
  uint32_t expected_faults = 5;
  for (uint32_t key = 0; key < 2; ++key) {
    WSR(1, 0x00001234u | (key ? 0x40000000u : 0));
    for (uint32_t pp = 0; pp < 4; ++pp) {
      for (uint32_t write = 0; write < 2; ++write) {
        uint32_t marker = 16u + key * 8u + pp * 2u + write;
        uint32_t initial = 0xfff0c000u | pp;
        uint32_t data_initial = 0x11223344u;
        pteg(10)[11] = initial;
        *(volatile uint32_t *)(uintptr_t)0xfff0c004u = data_initial;
        __asm__ volatile("sync" ::: "memory");
        snapshot_ptegs();
        begin_case(marker, 0x1000b004u);
        uint32_t before_faults = fault_count;
        uint32_t store_value = 0xabc00000u | marker;
        uint32_t load_value = 0;
        if (write) miss_store(0x1000b004u, store_value);
        else load_value = miss_load(0x1000b004u);
        int denied = (key && pp == 0u) ||
                     (write && (pp == 3u || (key && pp == 1u)));
        uint32_t expected_low = initial;
        if (!denied) expected_low |= write ? 0x180u : 0x100u;
        if (!one_miss(0x1000b004u, 0x80091a00u,
                      0xfff18fc0u, 0xfff17000u, key))
          return 0x8f001000u | marker;
        if (!ptegs_changed_only(10, 11, expected_low))
          return 0x8f002000u | marker;
        if (denied) {
          uint32_t pc = write ? (uint32_t)(uintptr_t)miss_store_pc :
                                (uint32_t)(uintptr_t)miss_load_pc;
          uint32_t syndrome = 0x08000000u | (write ? 0x02000000u : 0u);
          if (!fault_record(before_faults, marker, pc, 0x00000070u,
                            0x1000b004u, syndrome, 1) ||
              *(volatile uint32_t *)(uintptr_t)0xfff0c004u != data_initial ||
              (!write && load_value != 0x1000b004u))
            return 0x8f003000u | marker;
          ++expected_faults;
        } else {
          if (fault_count != before_faults ||
              (write && *(volatile uint32_t *)(uintptr_t)0xfff0c004u != store_value) ||
              (!write && load_value != data_initial))
            return 0x8f004000u | marker;
        }
      }
    }
  }
  if (expected_faults != 10u || fault_count != 10u)
    return 0x8f005000u;
  return 1;
}
