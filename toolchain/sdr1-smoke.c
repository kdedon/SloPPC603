#include <stdint.h>
volatile uint32_t tohost __attribute__((section(".tohost"), used));
#define READ(v) __asm__ volatile("mfspr %0,25" : "=r"(v))
#define WRITE(v) __asm__ volatile("sync; mtspr 25,%0; isync" :: "r"((uint32_t)(v)) : "memory")
int main(void) {
  uint32_t value;
  READ(value); if(value) return 0x8b000001;
  WRITE(0xffffffff); READ(value); if(value!=0xffffffff) return 0x8b000002;
  WRITE(0x12345678); READ(value); if(value!=0x12345678) return 0x8b000003;
  WRITE(0x80000000); READ(value); if(value!=0x80000000) return 0x8b000004;
  WRITE(0); READ(value); if(value) return 0x8b000005;
  return 1;
}
