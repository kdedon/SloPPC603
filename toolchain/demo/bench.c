/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
#include "bench.h"
#include "soc.h"

/* Without the SoC performance counters: cycles and retirements only. */
static uint64_t perf_c0, perf_r0, perf_c1, perf_r1;

__attribute__((weak)) void perf_start(void)
{
  perf_c0 = soc_cycles();
  perf_r0 = soc_retired();
}

__attribute__((weak)) void perf_stop(void)
{
  perf_c1 = soc_cycles();
  perf_r1 = soc_retired();
}

__attribute__((weak)) void perf_report(const char *name)
{
  uint64_t c = perf_c1 - perf_c0, r = perf_r1 - perf_r0;
  uint64_t cpi = r ? c * 1000 / r : 0;
  printf("perf %s: cycles %llu retired %llu cpi %lu.%03lu\n", name,
         (unsigned long long)c, (unsigned long long)r,
         (unsigned long)(cpi / 1000), (unsigned long)(cpi % 1000));
}

uint32_t bench_clock_hz(void)
{
  uint32_t mhz = SOC_MODE >> 16;
  return mhz ? mhz * 1000000u : SOC_CLOCK_HZ;
}

void bench_print_fixed(double v, int decimals, int width)
{
  long long scale = 1;
  for (int i = 0; i < decimals; i++) scale *= 10;
  int neg = v < 0;
  if (neg) v = -v;
  unsigned long long n = (unsigned long long)(v * (double)scale + 0.5);
  char buf[32];
  int len = 0;
  for (int i = 0; i < decimals; i++) {
    buf[len++] = (char)('0' + n % 10);
    n /= 10;
  }
  if (decimals) buf[len++] = '.';
  do {
    buf[len++] = (char)('0' + n % 10);
    n /= 10;
  } while (n && len < 30);
  if (neg) buf[len++] = '-';
  for (int i = len; i < width; i++) con_putc(' ');
  while (len) con_putc(buf[--len]);
}

#define STACK_PAINT 0x5a5aa5a5u
extern uint32_t __heap_end[], __stack_top[];

void bench_stack_paint(void)
{
  uint32_t *sp = __builtin_frame_address(0);
  for (uint32_t *p = __heap_end; p < sp - 64; p++) *p = STACK_PAINT;
}

void bench_stack_check(void)
{
  uint32_t *p = __heap_end;
  uint32_t size = (uint32_t)((char *)__stack_top - (char *)__heap_end);
  if (*p != STACK_PAINT) fail("stack overflow");
  while (*p == STACK_PAINT) p++;
  printf("stack %lu of %lu bytes\n", (unsigned long)((char *)__stack_top - (char *)p),
         (unsigned long)size);
}

void bench_screen(const char *title)
{
  fb_palette_default();
  fb_clear(1);
  con_color(15, 1);
  con_screen(1);
  printf("%s\n", title);
}
