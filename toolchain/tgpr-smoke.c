#include <stdint.h>
volatile uint32_t tohost __attribute__((section(".tohost"), used));
extern uint32_t tgpr_probe(void);
int main(void) { return tgpr_probe()==1 ? 1 : 0x8c000001; }
