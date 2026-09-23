#include <stdint.h>

volatile uint32_t tohost __attribute__((section(".tohost")));
volatile uint32_t handler_msr, handler_srr0, handler_srr1, handler_count;
volatile uint32_t handler_dar, handler_dsisr;
extern char irq_enable_resume[], irq_store_resume[];

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
    uint32_t dar = 0xa5a51234, dsisr = 0x13572468;
    uint32_t enabled = 0x8070, value = 0x13579bdf;
    __asm__ volatile("mtspr 19,%0; mtspr 18,%1" :: "r"(dar), "r"(dsisr) : "memory");
    if (read_msr() != 0x40 || handler_count != 0) return 0x80000001;
    write_msr(0x70);
    if (read_msr() != 0x70 || handler_count != 0) return 0x80000002;
    /* The held interrupt must precede this next instruction after EE enables. */
    __asm__ volatile("mtmsr %0\n.globl irq_enable_resume\nirq_enable_resume:\nisync"
                     :: "r"(enabled) : "memory");
    if (handler_count != 1 || handler_msr != 0x40 || handler_srr1 != enabled ||
        handler_srr0 != (uint32_t)(uintptr_t)irq_enable_resume ||
        handler_dar != dar || handler_dsisr != dsisr || read_msr() != enabled)
        return 0x80000003;
    /* The responder asserts the second interrupt while this store is pending. */
    __asm__ volatile("stw %0,0(%1)\n.globl irq_store_resume\nirq_store_resume:"
                     :: "r"(value), "r"(alias) : "memory");
    if (handler_count != 2 || handler_msr != 0x40 || handler_srr1 != enabled ||
        handler_srr0 != (uint32_t)(uintptr_t)irq_store_resume ||
        handler_dar != dar || handler_dsisr != dsisr || *alias != value)
        return 0x80000004;
    write_msr(0x40);
    if (read_msr() != 0x40 || *physical != value || handler_count != 2)
        return 0x80000005;
    return 1;
}
