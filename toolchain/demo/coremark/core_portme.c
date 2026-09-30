/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* CoreMark port and driver for the demo system. CoreMark's own validation
 * decides pass or fail: it prints the performance-run banner for the seeds
 * it recognises and an ERROR line for each CRC that differs from the known
 * value. Both are watched as they are printed. The run is far shorter than
 * the ten seconds a reportable CoreMark needs, which CoreMark itself flags. */
#include "coremark.h"
#include "soc.h"

#ifndef ITERATIONS
#define ITERATIONS 10
#endif

volatile ee_s32 seed1_volatile = 0x0;
volatile ee_s32 seed2_volatile = 0x0;
volatile ee_s32 seed3_volatile = 0x66;
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;
ee_u32 default_num_contexts = 1;

int demo_cm_iterations = ITERATIONS;
static CORE_TICKS start_ticks, stop_ticks;
static uint64_t start_retired, stop_retired;
static int performance_run, crc_errors, crcfinal_seen;
static unsigned crcfinal;

void start_time(void)
{
  perf_start();
  start_retired = soc_retired();
  start_ticks = (CORE_TICKS)soc_cycles();
}

void stop_time(void)
{
  stop_ticks = (CORE_TICKS)soc_cycles();
  stop_retired = soc_retired();
  perf_stop();
}

CORE_TICKS get_time(void) { return stop_ticks - start_ticks; }
secs_ret time_in_secs(CORE_TICKS ticks) { return ticks / SOC_CLOCK_HZ; }

void portable_init(core_portable *p, int *argc, char *argv[])
{
  (void)argc;
  (void)argv;
  p->portable_id = 1;
}

void portable_fini(core_portable *p) { p->portable_id = 0; }

static int contains(const char *s, const char *part)
{
  size_t n = strlen(part);
  for (; *s; s++)
    if (memcmp(s, part, n) == 0) return 1;
  return 0;
}

int ee_printf(const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  if (contains(fmt, "2K performance run parameters")) performance_run = 1;
  if (contains(fmt, "ERROR! list crc") || contains(fmt, "ERROR! matrix crc") ||
      contains(fmt, "ERROR! state crc") || contains(fmt, "is not a"))
    crc_errors++;
  if (contains(fmt, "crcfinal")) {
    va_list copy;
    va_copy(copy, ap);
    (void)va_arg(copy, int);
    crcfinal = va_arg(copy, unsigned);
    crcfinal_seen = 1;
    va_end(copy);
  }
  int n = vprintf(fmt, ap);
  va_end(ap);
  return n;
}

int coremark_main(void);

int main(void)
{
  fb_palette_default();
  con_clear(4);
  con_color(15, 4);
  con_screen(1);
  seed4_volatile = demo_cm_iterations;
  printf("CoreMark, %d iterations\n", demo_cm_iterations);
  if (demo_cm_iterations < 300) printf("(simulation-sized: not a valid\n CoreMark result)\n");
  con_screen(0);

  coremark_main();

  CORE_TICKS cycles = get_time();
  uint64_t iters = (uint64_t)demo_cm_iterations;
  uint32_t per_sec_milli = (uint32_t)(iters * SOC_CLOCK_HZ * 1000 / cycles);
  /* CoreMark/MHz = iterations / cycles * 1e6, three decimals. */
  uint32_t per_mhz_milli = (uint32_t)(iters * 1000000000ull / cycles);

  con_screen(1);
  con_goto(0, 4);
  printf("cycles:        %lu\n", (unsigned long)cycles);
  printf("cycles/iter:   %lu\n", (unsigned long)(cycles / iters));
  printf("iter/s:        %lu.%03lu at %lu MHz\n", (unsigned long)(per_sec_milli / 1000),
         (unsigned long)(per_sec_milli % 1000), (unsigned long)(SOC_CLOCK_HZ / 1000000));
  printf("CoreMark/MHz:  %lu.%03lu\n", (unsigned long)(per_mhz_milli / 1000),
         (unsigned long)(per_mhz_milli % 1000));
  printf("crcfinal:      0x%04x\n", crcfinal);
  if (!performance_run || crc_errors != 0 || !crcfinal_seen) {
    printf("performance seeds %d, crc errors %d\n", performance_run, crc_errors);
    fail("CoreMark validation");
  }
  con_screen(0);
  perf_report("coremark");
  con_screen(1);
  demo_cm = (struct demo_result){
      .cycles = cycles, .retired = stop_retired - start_retired,
      .count = (uint32_t)iters, .milli = per_mhz_milli, .ok = 1};
  perf_brief(&demo_cm);
  con_color(10, 4);
  printf("CRCs match: coremark PASS\n");
  return 0;
}
