#include <stdint.h>

volatile uint32_t tohost __attribute__((section(".tohost")));
volatile uint32_t handler_msr, handler_srr1, handler_count;

static inline uint32_t read_msr(void) {
    uint32_t value;
    __asm__ volatile("mfmsr %0" : "=r"(value));
    return value;
}

static inline void write_msr(uint32_t value) {
    __asm__ volatile("mtmsr %0; isync" :: "r"(value) : "memory");
}

int main(void) {
    volatile uint32_t *alias = (volatile uint32_t *)(uintptr_t)0x10003000;
    volatile uint32_t *physical = (volatile uint32_t *)(uintptr_t)0xfff03000;
    if (read_msr() != 0x40) return 0x80000001;
    *physical = 0;
    /* Code and stack have identical mappings before and after this change. */
    write_msr(0x70);
    if (read_msr() != 0x70) return 0x80000002;
    *alias = 0x2468ace0;
    if (*alias != 0x2468ace0) return 0x80000003;
    __asm__ volatile("sc" ::: "memory");
    if (handler_count != 1 || handler_msr != 0x40 || handler_srr1 != 0x70)
        return 0x80000004;
    if (read_msr() != 0x70 || *alias != 0x2468ace0) return 0x80000005;
    write_msr(0x40);
    if (read_msr() != 0x40 || *physical != 0x2468ace0) return 0x80000006;
    return 1;
}
