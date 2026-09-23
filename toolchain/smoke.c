#include <stdint.h>

volatile uint32_t tohost __attribute__((section(".tohost"), used));

static volatile const uint32_t operands[] = {
    UINT32_C(0x10203040),
    UINT32_C(0x01020304),
    UINT32_C(0xa5a5a5a5),
};

int main(void) {
  const uint32_t result = (operands[0] + operands[1]) ^ operands[2];
  return result == UINT32_C(0xb48796e1) ? 1 : (int)UINT32_C(0x80000001);
}
