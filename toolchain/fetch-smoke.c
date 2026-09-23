#include <stdint.h>

volatile uint32_t tohost __attribute__((section(".tohost"), used));
volatile uint32_t fault_dar, fault_dsisr, fault_pc, fault_msr, fault_count;
extern int fetch_protection_probe(void);
extern int fetch_guarded_probe(void);

/* Each isolated probe receives one typed synchronous fault from the abstract
 * memory test environment. RFI retries the same PC; no MMU refill is claimed. */
int main(void) {
  const uint32_t dar = UINT32_C(0xa5a51234);
  const uint32_t dsisr = UINT32_C(0x13572468);
  __asm__ volatile ("mtspr 19,%0\n\tmtspr 18,%1" : : "r"(dar), "r"(dsisr) : "memory");
  if (fetch_protection_probe() != 0x1234)
    return (int)UINT32_C(0x80000001);
  if (fault_count != 1 || fault_pc != (uintptr_t)fetch_protection_probe ||
      fault_msr != UINT32_C(0x08000040) || fault_dar != dar || fault_dsisr != dsisr)
    return (int)UINT32_C(0x80000002);
  if (fetch_guarded_probe() != 0x5678)
    return (int)UINT32_C(0x80000003);
  if (fault_count != 2 || fault_pc != (uintptr_t)fetch_guarded_probe ||
      fault_msr != UINT32_C(0x10000040) || fault_dar != dar || fault_dsisr != dsisr)
    return (int)UINT32_C(0x80000004);
  if (fetch_protection_probe() != 0x1234 || fetch_guarded_probe() != 0x5678 || fault_count != 2)
    return (int)UINT32_C(0x80000005);
  return 1;
}
