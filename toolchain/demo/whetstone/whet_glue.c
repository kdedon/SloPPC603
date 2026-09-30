/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* Runs the netlib C Whetstone (fetched upstream source, built with
 * -Dmain=whet_main and its output and clock routed here) at WHET_LOOP,
 * repeating until WHET_SECS seconds have passed (at least once). Its
 * PRINTOUT values, one line per module, are captured every run and checked
 * against a host model; its clock reads return 1 and 2 so the program sees
 * one second while the cycle counter times the run. The rating is the
 * program's: 100 * LOOP thousand Whetstone instructions per run. */
#include <stdarg.h>
#include <stdint.h>
#include "bench.h"
#include "soc.h"

struct whet_pout {
  long n, j, k;
  double x[4];
};
#include "whet_ref.h"

#define MODULES (int)(sizeof whet_expected / sizeof whet_expected[0])
#ifndef WHET_SECS
#define WHET_SECS 0
#endif
#ifdef _SOFT_FLOAT
#define WHET_FP "soft-float"
#else
#define WHET_FP "FPU"
#endif

int whet_main(int argc, char *argv[]);

static uint64_t stamp[2];
static int stamps;
static struct whet_pout seen[16];
static int lines;

long whet_time(long *t)
{
  (void)t;
  stamp[stamps & 1] = soc_cycles();
  return ++stamps;
}

long whet_atol(const char *s)
{
  long v = 0;
  while (*s >= '0' && *s <= '9') v = v * 10 + (*s++ - '0');
  return v;
}

/* Keeps the module lines ("%7ld %7ld %7ld %12.4e ..."); drops the rest. */
int whet_printf(const char *fmt, ...)
{
  if (fmt[0] == '%' && fmt[1] == '7') {
    va_list ap;
    va_start(ap, fmt);
    struct whet_pout *p = &seen[lines < 16 ? lines : 15];
    p->n = va_arg(ap, long);
    p->j = va_arg(ap, long);
    p->k = va_arg(ap, long);
    for (int i = 0; i < 4; i++) p->x[i] = va_arg(ap, double);
    va_end(ap);
    lines++;
  }
  return 0;
}

static int close_enough(double a, double b, int *exact)
{
  if (a == b) return 1;
  *exact = 0;
  double d = a - b, m = b < 0 ? -b : b;
  if (d < 0) d = -d;
  return d <= m * 1e-12;
}

/* Modules whose printed values match the model. */
static int check_run(int *exact)
{
  int ok = 0;
  for (int i = 0; i < MODULES && i < lines; i++) {
    const struct whet_pout *e = &whet_expected[i], *s = &seen[i];
    int good = s->n == e->n && s->j == e->j && s->k == e->k;
    for (int k = 0; k < 4; k++) good &= close_enough(s->x[k], e->x[k], exact);
    ok += good;
  }
  return lines == MODULES ? ok : 0;
}

int main(void)
{
  static char loop_arg[12];
  char *argv[] = {"whetstone", loop_arg, 0};
  uint32_t clock = bench_clock_hz();
  uint64_t cycles = 0;
  uint32_t runs = 0;
  int failed = 0, exact = 1, ok = 0;

  bench_stack_paint();
  /* The notice must travel with the program. */
  __asm__ volatile("" : : "r"(whet_notice));
  snprintf(loop_arg, sizeof loop_arg, "%d", WHET_LOOP);
  bench_screen("Whetstone 1.2 (netlib, double precision)");
  printf("(c) 1998 Painter Engineering, Inc.\n");
  printf("%lu MHz, %s, LOOP %d\n", (unsigned long)(clock / 1000000), WHET_FP, WHET_LOOP);

  perf_start();
  do {
    stamps = lines = 0;
    if (whet_main(2, argv) != 0 || stamps != 2) fail("Whetstone run");
    cycles += stamp[1] - stamp[0];
    runs++;
    ok = check_run(&exact);
    failed |= ok != MODULES;
  } while (!failed && cycles < (uint64_t)WHET_SECS * clock);
  perf_stop();

  /* KIPS = 100 * LOOP * runs / seconds; MWIPS = KIPS / 1000. */
  double work = 100.0 * WHET_LOOP * runs;
  double mwips = work * clock / (double)cycles / 1000.0;
  double per_mhz = work * 1000.0 / (double)cycles;
  printf("runs %lu, cycles %llu\n", (unsigned long)runs, (unsigned long long)cycles);
  printf("modules %d/%d match %s\n", ok, MODULES, exact ? "exactly" : "within 1e-12");
  printf("MWIPS ");
  bench_print_fixed(mwips, 3, 0);
  printf(", MWIPS/MHz ");
  bench_print_fixed(per_mhz, 4, 0);
  printf("\n");
  perf_report("whetstone");
  bench_stack_check();

  con_color(failed ? 12 : 10, 1);
  printf("WHETSTONE %luMHz %s ", (unsigned long)(clock / 1000000), WHET_FP);
  bench_print_fixed(mwips, 3, 0);
  printf(" MWIPS ");
  bench_print_fixed(per_mhz, 4, 0);
  printf("/MHz %s\n", failed ? "FAIL" : "PASS");
  if (failed) fail("Whetstone module values");
  return 0;
}
