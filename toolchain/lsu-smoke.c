#include <stdint.h>

/* Load/store extensions in real mode: compiler-generated stmw/lmw prologues,
 * lwarx/stwcx. atomics and a lock, string moves, byte-reverse accesses and
 * unaligned packed-struct fields split by hardware. Unaligned lmw and lwarx
 * reach the alignment handler, which records DAR/DSISR/SRR0 and skips. */

volatile uint32_t tohost __attribute__((section(".tohost")));
volatile uint32_t align_count, align_dar, align_dsisr, align_srr0;
extern char probe_lmw[], probe_lwarx[];

/* UM Table 4-13 syndromes for lmw r29,0(r11) and lwarx r12,0,r11 (rA = 0). */
#define DSISR_LMW 0x00001fabu
#define DSISR_LWARX 0x00000180u

static volatile uint32_t counter;
static volatile uint32_t lock;
static volatile uint8_t buf_src[64] __attribute__((aligned(4)));
static volatile uint8_t buf_dst[64] __attribute__((aligned(4)));
static volatile uint32_t words[8];

struct __attribute__((packed)) odd {
    uint8_t tag;
    uint32_t w;       /* offset 1 */
    uint16_t h;       /* offset 5 */
    uint8_t pad[2];
    uint32_t x;       /* offset 9 */
};
static volatile struct odd odd_array[4];

/* Clobbers every nonvolatile GPR; size optimization makes -mmultiple save
 * and restore them with stmw/lmw. */
__attribute__((noinline, optimize("Os"))) static uint32_t scramble(uint32_t seed) {
    __asm__ volatile(
        "li 14,-1\n li 15,-1\n li 16,-1\n li 17,-1\n li 18,-1\n li 19,-1\n"
        "li 20,-1\n li 21,-1\n li 22,-1\n li 23,-1\n li 24,-1\n li 25,-1\n"
        "li 26,-1\n li 27,-1\n li 28,-1\n li 29,-1\n li 30,-1\n li 31,-1\n"
        ::: "r14", "r15", "r16", "r17", "r18", "r19", "r20", "r21", "r22",
            "r23", "r24", "r25", "r26", "r27", "r28", "r29", "r30", "r31");
    return seed * 3u + 1u;
}

/* Many values live across calls: they sit in nonvolatile registers that the
 * callee's lmw must restore. */
__attribute__((noinline)) static uint32_t keep_live(uint32_t s) {
    uint32_t a = s + 1, b = s + 2, c = s + 3, d = s + 4, e = s + 5, f = s + 6;
    uint32_t g = s + 7, h = s + 8, i = s + 9, j = s + 10, k = s + 11, l = s + 12;
    uint32_t t = scramble(s);
    t += scramble(t);
    return t ^ (a + (b << 1) + (c << 2) + (d << 3) + (e << 4) + (f << 5) +
                (g << 6) + (h << 7) + (i << 8) + (j << 9) + (k << 10) + (l << 11));
}

static uint32_t expect_keep_live(uint32_t s) {
    uint32_t t = s * 3u + 1u;
    t += t * 3u + 1u;
    uint32_t sum = 0;
    for (uint32_t n = 1; n <= 12; n++) sum += (s + n) << (n - 1);
    return t ^ sum;
}

static void spin_lock(volatile uint32_t *p) {
    while (__atomic_exchange_n(p, 1u, __ATOMIC_SEQ_CST) != 0) {
    }
}

static void spin_unlock(volatile uint32_t *p) {
    __atomic_store_n(p, 0u, __ATOMIC_SEQ_CST);
}

/* lwarx, then two stwcx.: the first stores, the second finds no reservation.
 * Returns CR0 of both in bits 7:4 and 3:0. */
static uint32_t reservation_pair(volatile uint32_t *p, uint32_t v) {
    uint32_t old, cr1, cr2;
    __asm__ volatile(
        "lwarx %0,0,%3\n"
        "stwcx. %4,0,%3\n"
        "mfcr %1\n"
        "stwcx. %0,0,%3\n"
        "mfcr %2\n"
        : "=&r"(old), "=&r"(cr1), "=&r"(cr2)
        : "r"(p), "r"(v)
        : "cr0", "memory");
    return ((cr1 >> 28) << 4) | (cr2 >> 28) | (old == 0x1234u ? 0x100u : 0u);
}

/* lswi/stswi with an immediate count through r5..r12. */
#define STRING_IMM(n, src, dst)                                                 \
    __asm__ volatile("lswi 5,%0," #n "\n stswi 5,%1," #n                         \
                     :: "b"(src), "b"(dst)                                       \
                     : "r5", "r6", "r7", "r8", "r9", "r10", "r11", "r12", "memory")

/* lswx/stswx with the XER byte count. */
static void string_indexed(uint32_t count, volatile void *src, volatile void *dst) {
    __asm__ volatile("mtxer %0\n lswx 5,0,%1\n stswx 5,0,%2"
                     :: "r"(count), "r"(src), "r"(dst)
                     : "r5", "r6", "r7", "r8", "r9", "r10", "r11", "r12", "xer", "memory");
}

/* Non-volatile pointers let the compiler fold the swap into the access. */
__attribute__((noinline)) static uint32_t load_reversed(const uint32_t *p) {
    return __builtin_bswap32(*p);
}

/* GCC does not fold the swap into a store here; name the forms directly. */
__attribute__((noinline)) static void store_reversed(uint32_t *p, uint32_t v) {
    __asm__ volatile("stwbrx %0,0,%1" :: "r"(v), "r"(p) : "memory");
}

__attribute__((noinline)) static uint16_t load_reversed16(const uint16_t *p) {
    return __builtin_bswap16(*p);
}

__attribute__((noinline)) static void store_reversed16(uint16_t *p, uint16_t v) {
    __asm__ volatile("sthbrx %0,0,%1" :: "r"(v), "r"(p) : "memory");
}

static void fill_source(void) {
    for (unsigned n = 0; n < 64; n++) buf_src[n] = (uint8_t)(0x40u + 7u * n);
}

static void clear_destination(void) {
    for (unsigned n = 0; n < 64; n++) buf_dst[n] = 0xeeu;
}

static int string_ok(unsigned src_off, unsigned dst_off, unsigned count) {
    for (unsigned n = 0; n < 64; n++) {
        uint8_t want = (n >= dst_off && n < dst_off + count) ?
                       buf_src[src_off + n - dst_off] : 0xeeu;
        if (buf_dst[n] != want) return 0;
    }
    return 1;
}

int main(void) {
    /* Nonvolatile save/restore through stmw/lmw. */
    for (uint32_t s = 0; s < 40; s += 7)
        if (keep_live(s) != expect_keep_live(s)) return 0x81000000 | s;

    /* Atomic increment and a spin lock (lwarx/stwcx. loops). */
    counter = 0;
    for (unsigned n = 0; n < 25; n++) {
        spin_lock(&lock);
        __atomic_fetch_add(&counter, 2u, __ATOMIC_SEQ_CST);
        spin_unlock(&lock);
    }
    if (counter != 50 || lock != 0) return 0x82000001;
    uint32_t prev = __atomic_fetch_sub(&counter, 8u, __ATOMIC_SEQ_CST);
    if (prev != 50 || counter != 42) return 0x82000002;

    /* Reservation is consumed by the first stwcx. */
    words[0] = 0x1234u;
    uint32_t pair = reservation_pair(&words[0], 0xbeefu);
    if (pair != 0x120u || words[0] != 0xbeefu) return 0x82000003 | (pair << 8);

    /* Strings at every source/destination offset pair. */
    fill_source();
    for (unsigned so = 0; so < 4; so++) {
        for (unsigned doff = 0; doff < 4; doff++) {
            clear_destination();
            STRING_IMM(7, &buf_src[so], &buf_dst[doff]);
            if (!string_ok(so, doff, 7)) return 0x83000000 | (so << 4) | doff;
            clear_destination();
            STRING_IMM(0, &buf_src[so], &buf_dst[doff]);
            if (!string_ok(so, doff, 32)) return 0x83000100 | (so << 4) | doff;
            for (uint32_t count = 0; count <= 28; count += 5) {
                clear_destination();
                string_indexed(count, &buf_src[so + 1], &buf_dst[doff + 2]);
                if (!string_ok(so + 1, doff + 2, count))
                    return 0x83010000 | (count << 8) | (so << 4) | doff;
            }
        }
    }

    /* Byte-reverse loads and stores. */
    words[1] = 0x11223344u;
    if (load_reversed((const uint32_t *)&words[1]) != 0x44332211u) return 0x84000001;
    store_reversed((uint32_t *)&words[2], 0xa1b2c3d4u);
    if (words[2] != 0xd4c3b2a1u) return 0x84000002;
    volatile uint16_t *half = (volatile uint16_t *)&words[3];
    half[0] = 0x5566u;
    if (load_reversed16((const uint16_t *)&half[0]) != 0x6655u) return 0x84000003;
    store_reversed16((uint16_t *)&half[1], 0x7788u);
    if (half[1] != 0x8877u) return 0x84000004;

    /* Unaligned scalar fields: hardware splits crossing accesses. */
    for (unsigned n = 0; n < 4; n++) {
        odd_array[n].tag = (uint8_t)n;
        odd_array[n].w = 0x10203040u + n;
        odd_array[n].h = (uint16_t)(0x5060u + n);
        odd_array[n].x = 0x708090a0u ^ n;
    }
    for (unsigned n = 0; n < 4; n++) {
        if (odd_array[n].tag != n || odd_array[n].w != 0x10203040u + n ||
            odd_array[n].h != (uint16_t)(0x5060u + n) ||
            odd_array[n].x != (0x708090a0u ^ n))
            return 0x85000000 | n;
    }

    /* Unaligned lmw and lwarx take the alignment exception. */
    align_count = 0;
    uint32_t odd_ea = (uint32_t)(uintptr_t)&words[4] + 2u;
    __asm__ volatile("mr 11,%0\n"
                     ".globl probe_lmw\n"
                     "probe_lmw: lmw 29,0(11)\n"
                     :: "r"(odd_ea) : "r11", "r29", "r30", "r31", "memory");
    if (align_count != 1 || align_dar != odd_ea + 4u || align_dsisr != DSISR_LMW ||
        align_srr0 != (uint32_t)(uintptr_t)probe_lmw)
        return 0x86000001;
    __asm__ volatile("mr 11,%0\n"
                     ".globl probe_lwarx\n"
                     "probe_lwarx: lwarx 12,0,11\n"
                     :: "r"(odd_ea) : "r11", "r12", "memory");
    if (align_count != 2 || align_dar != odd_ea || align_dsisr != DSISR_LWARX ||
        align_srr0 != (uint32_t)(uintptr_t)probe_lwarx)
        return 0x86000002;
    return 1;
}
