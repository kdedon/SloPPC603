#include <stdint.h>

volatile uint32_t tohost __attribute__((section(".tohost"), used));
volatile uint32_t fault_dar, fault_dsisr, fault_pc, fault_msr, fault_count;
static volatile uint32_t data_words[4] = {
    UINT32_C(0x10203040), UINT32_C(0x50607080),
    UINT32_C(0x90a0b0c0), UINT32_C(0xd0e0f000),
};
extern const char alignment_load_site[], alignment_store_site[];

/* The supported RTL profile traps these accesses; this is not a claim that
 * every such access traps on real 603e silicon. The handler skips each fault. */
int main(void) {
  for (uint32_t i = 0; i < 12; ++i) {
    uintptr_t base = (uintptr_t)data_words + 1;
    const uintptr_t original_base = base;
    uint32_t loaded = UINT32_C(0x13579bdf);
    __asm__ volatile (
        ".globl alignment_load_site\n"
        "alignment_load_site:\n\t"
        "lwzu %0,4(%1)"
        : "+&r"(loaded), "+&b"(base) : : "memory");
    if (loaded != UINT32_C(0x13579bdf) || base != original_base)
      return (int)UINT32_C(0x80000001);
    if (fault_dar != original_base + 4 ||
        fault_pc != (uintptr_t)alignment_load_site || fault_msr != 0x40 ||
        fault_count != 2*i + 1)
      return (int)UINT32_C(0x80000002);
    /* 603e manual Table 4-13: D-form instruction fields are copied into
     * DSISR. Read our linked instruction so register allocation may change. */
    uint32_t insn = *(const volatile uint32_t *)(const void *)alignment_load_site;
    uint32_t expected_dsisr = ((insn >> 26) & 1U) << 14 |
                             ((insn >> 27) & 15U) << 10 |
                             ((insn >> 16) & 1023U);
    if (fault_dsisr != expected_dsisr)
      return (int)UINT32_C(0x80000005);
    const uint32_t store = UINT32_C(0xdeadbeef);
    __asm__ volatile (
        ".globl alignment_store_site\n"
        "alignment_store_site:\n\t"
        "stwu %1,4(%0)"
        : "+&b"(base) : "r"(store) : "memory");
    if (base != original_base || data_words[0] != UINT32_C(0x10203040) ||
        data_words[1] != UINT32_C(0x50607080) ||
        data_words[2] != UINT32_C(0x90a0b0c0) ||
        data_words[3] != UINT32_C(0xd0e0f000))
      return (int)UINT32_C(0x80000003);
    if (fault_dar != original_base + 4 ||
        fault_pc != (uintptr_t)alignment_store_site || fault_msr != 0x40 ||
        fault_count != 2*i + 2)
      return (int)UINT32_C(0x80000004);
    insn = *(const volatile uint32_t *)(const void *)alignment_store_site;
    expected_dsisr = ((insn >> 26) & 1U) << 14 |
                    ((insn >> 27) & 15U) << 10 |
                    ((insn >> 16) & 1023U);
    if (fault_dsisr != expected_dsisr)
      return (int)UINT32_C(0x80000006);
  }
  return 1;
}
