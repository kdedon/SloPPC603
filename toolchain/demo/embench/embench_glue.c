/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Runs the Embench-IoT benchmarks (fetched upstream sources) in sequence:
 * initialise, warm once, time benchmark() on the cycle counter, then check
 * the result with the benchmark's own verify_benchmark(). Each benchmark
 * repeats LOCAL_SCALE_FACTOR / EMB_DIV times (at least once). The score is
 * Embench's speed per MHz: the geometric mean over benchmarks of the
 * reference platform's cycles for the same work (reference milliseconds at
 * 1 MHz) divided by this system's cycles. */
#include <math.h>
#include <stdint.h>
#include "bench.h"
#include "soc.h"
#include "emb_table.h"

#ifndef EMB_DIV
#define EMB_DIV 1
#endif
#define WARMUP_HEAT 1

#define DECLARE(id, name, ref_ms, scale) \
  void emb_##id##_init(void); \
  void emb_##id##_warm(int heat); \
  int emb_##id##_benchmark(void); \
  int emb_##id##_verify(int result);
EMBENCH_LIST(DECLARE)

struct emb {
  const char *name;
  uint32_t ref_ms, scale;
  void (*init)(void);
  void (*warm)(int);
  int (*run)(void);
  int (*verify)(int);
};

#define ENTRY(id, name, ref_ms, scale) \
  {name, ref_ms, scale, emb_##id##_init, emb_##id##_warm, emb_##id##_benchmark, emb_##id##_verify},
static const struct emb embs[] = {EMBENCH_LIST(ENTRY)};
#define COUNT (int)(sizeof embs / sizeof embs[0])

int main(void)
{
  uint32_t clock = bench_clock_hz();
  double log_sum = 0, log_sq = 0;
  int failed = 0;

  bench_stack_paint();
  bench_screen("Embench-IoT 1.0");
  printf("%lu MHz, repeats scale/%d\n", (unsigned long)(clock / 1000000), EMB_DIV);
  printf("benchmark          cycles  /MHz\n");

  perf_start();
  for (int i = 0; i < COUNT; i++) {
    const struct emb *e = &embs[i];
    uint32_t repeats = e->scale / EMB_DIV + (e->scale < EMB_DIV);
    e->init();
    e->warm(WARMUP_HEAT);
    uint64_t c0 = soc_cycles();
    int result = e->run();
    uint64_t cycles = soc_cycles() - c0;
    int ok = e->verify(result);
    double rel = (double)e->ref_ms * 1000.0 * repeats / ((double)e->scale * (double)cycles);
    double l = log(rel);
    log_sum += l;
    log_sq += l * l;
    failed += !ok;
    printf("%-14s %10llu", e->name, (unsigned long long)cycles);
    bench_print_fixed(rel, 3, 7);
    printf(" %s\n", ok ? "ok" : "FAIL");
  }
  perf_stop();

  double mean = log_sum / COUNT;
  double var = log_sq / COUNT - mean * mean;
  double gmean = exp(mean), gsd = exp(sqrt(var > 0 ? var : 0));
  printf("speed/MHz geomean ");
  bench_print_fixed(gmean, 3, 0);
  printf(" gsd ");
  bench_print_fixed(gsd, 3, 0);
  printf("\nrange ");
  bench_print_fixed(gmean / gsd, 3, 0);
  printf(" - ");
  bench_print_fixed(gmean * gsd, 3, 0);
  printf(", %d of %d verified\n", COUNT - failed, COUNT);
  perf_report("embench");
  bench_stack_check();

  con_color(failed ? 12 : 10, 1);
  printf("EMBENCH %luMHz ", (unsigned long)(clock / 1000000));
  bench_print_fixed(gmean, 3, 0);
  printf("/MHz %d/%d %s\n", COUNT - failed, COUNT, failed ? "FAIL" : "PASS");
  if (failed) fail("Embench verification");
  return 0;
}
