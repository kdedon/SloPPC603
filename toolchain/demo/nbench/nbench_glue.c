/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Runs nbench 2.2.3 (BYTEmark, fetched upstream source) on the demo system,
 * in place of its own driver and system layer: memory from a LIFO arena,
 * the stopwatch on the cycle counter, NNET.DAT from the image. Each test
 * runs once, fixed-size (NB_SMOKE) or self-calibrated for NB_SECS seconds,
 * and the indices are the driver's geometric means. The tests' own checks
 * (built with DEBUG) report "OK" or an error, which nb_printf counts. */
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include "bench.h"
#include "soc.h"
#include "nmglobal.h"
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-variable"
#pragma GCC diagnostic ignored "-Wstrict-prototypes"
#pragma GCC diagnostic ignored "-Wdiscarded-qualifiers"
#include "nbench0.h"
#pragma GCC diagnostic pop
#include "nnet_dat.h"

#ifndef NB_SECS
#define NB_SECS 2
#endif

const struct demo_file_image demo_files[] = {{"NNET.DAT", nnet_dat}, {0, 0}};

/* ---- check lines -------------------------------------------------------- */

/* The OK lines come from inside the timed loops, once per iteration: they
 * are counted, once per check, and not printed. Errors are printed. */
static const char *const ok_lines[] = {"Numeric sort: OK", "String sort: OK", "IDEA: OK",
                                       "Huffman: OK"};
static int ok_mask, checks_bad;

int nb_printf(const char *fmt, ...)
{
  for (int i = 0; i < 4; i++)
    if (strncmp(fmt, ok_lines[i], strlen(ok_lines[i])) == 0) {
      ok_mask |= 1 << i;
      return 0;
    }
  int bad = strncmp(fmt, "Sort Error", 10) == 0 || strncmp(fmt, "IDEA Error", 10) == 0 ||
            strncmp(fmt, "Error at", 8) == 0 || strncmp(fmt, "CPU:", 4) == 0 ||
            strncmp(fmt, "FPU:", 4) == 0 || strncmp(fmt, "\n CPU:", 6) == 0;
  if (!bad) return 0;
  checks_bad++;
  va_list ap;
  va_start(ap, fmt);
  int n = vprintf(fmt, ap);
  va_end(ap);
  return n;
}

/* ---- memory ------------------------------------------------------------- */

/* Blocks stack up from the heap start; freeing marks a block, and free
 * blocks on top of the stack are released. */
struct block {
  struct block *prev;
  uint32_t size, free;
  uint32_t pad;
};
extern char __heap_start[], __heap_end[];
static struct block *top;
static char *arena_next = __heap_start;
static uint32_t arena_peak;

void *AllocateMemory(unsigned long nbytes, int *errorcode)
{
  unsigned long size = (nbytes + sizeof(struct block) + 7) & ~7ul;
  if ((unsigned long)(__heap_end - arena_next) < size) {
    *errorcode = ERROR_MEMORY;
    return 0;
  }
  struct block *b = (struct block *)arena_next;
  *b = (struct block){top, (uint32_t)size, 0, 0};
  top = b;
  arena_next += size;
  if ((uint32_t)(arena_next - __heap_start) > arena_peak) arena_peak = arena_next - __heap_start;
  *errorcode = 0;
  return b + 1;
}

void FreeMemory(void *p, int *errorcode)
{
  *errorcode = 0;
  if (!p) return;
  ((struct block *)p - 1)->free = 1;
  while (top && top->free) {
    arena_next = (char *)top;
    top = top->prev;
  }
}

void MoveMemory(void *dst, void *src, unsigned long n) { memmove(dst, src, n); }

void ReportError(char *context, int errorcode)
{
  printf("nbench: %s, error %d\n", context, errorcode);
  checks_bad++;
}

void ErrorExit(void) { fail("nbench error"); }

/* ---- stopwatch: one tick per processor cycle ----------------------------- */

unsigned long StartStopwatch(void) { return (unsigned long)soc_cycles(); }
unsigned long StopStopwatch(unsigned long start) { return (unsigned long)soc_cycles() - start; }
unsigned long TicksToSecs(unsigned long ticks) { return ticks / bench_clock_hz(); }
double TicksToFracSecs(unsigned long ticks) { return (double)ticks / (double)bench_clock_hz(); }

/* ---- driver ------------------------------------------------------------- */

static const char *const short_names[NUMTESTS] = {
  "numsort", "strsort", "bitfield", "fpemu", "fourier",
  "assign", "idea", "huffman", "nnet", "lu"};

static void configure(void)
{
  unsigned long secs = NB_SECS;
#ifdef NB_SMOKE
  int adjust = 1;
  secs = 0;
#else
  int adjust = 0;
#endif
  /* Sixty microseconds, the reference's minimum with a microsecond clock. */
  global_min_ticks = bench_clock_hz() / 1000000 * MINIMUM_TICKS;
  global_numsortstruct = (SortStruct){adjust, secs, 0, 1, NB_NUMARRAYSIZE};
  global_strsortstruct = (SortStruct){adjust, secs, 0, 1, NB_STRARRAYSIZE};
  global_bitopstruct = (BitOpStruct){adjust, secs, 0, NB_BITOPS, NB_BITFARRAYSIZE};
  global_emfloatstruct = (EmFloatStruct){adjust, secs, NB_EMFARRAYSIZE, 1, 0};
  global_fourierstruct = (FourierStruct){adjust, secs, NB_FOURIERSIZE, 0};
  global_assignstruct = (AssignStruct){adjust, secs, 1, 0};
  global_ideastruct = (IDEAStruct){adjust, secs, NB_IDEAARRAYSIZE, 1, 0};
  global_huffstruct = (HuffStruct){adjust, secs, NB_HUFFARRAYSIZE, 1, 0};
  global_nnetstruct = (NNetStruct){adjust, secs, 1, 0};
  /* One system per iteration, which is what calibration settles on here:
   * a single solve takes far longer than the minimum interval. Skipping it
   * saves the calibration's spare matrix. */
  global_lustruct = (LUStruct){1, secs, 1, 0};
}

static double score(int i)
{
  switch (i) {
  case TF_NUMSORT: return global_numsortstruct.sortspersec;
  case TF_SSORT: return global_strsortstruct.sortspersec;
  case TF_BITOP: return global_bitopstruct.bitopspersec;
  case TF_FPEMU: return global_emfloatstruct.emflops;
  case TF_FFPU: return global_fourierstruct.fflops;
  case TF_ASSIGN: return global_assignstruct.iterspersec;
  case TF_IDEA: return global_ideastruct.iterspersec;
  case TF_HUFF: return global_huffstruct.iterspersec;
  case TF_NNET: return global_nnetstruct.iterspersec;
  default: return global_lustruct.iterspersec;
  }
}

static double root(double product, int n) { return n ? exp(log(product) / n) : 0; }

int main(void)
{
  double p90_int = 1, p90_fp = 1, k6_mem = 1, k6_int = 1, k6_fp = 1;
  int fp_tests = 0;
  uint32_t clock = bench_clock_hz();

  bench_stack_paint();
  bench_screen("nbench 2.2.3 (BYTEmark)");
#ifdef NB_SMOKE
  printf("smoke sizes: indices not comparable\n");
#else
  printf("%lu s per test\n", (unsigned long)NB_SECS);
#endif
#ifdef _SOFT_FLOAT
  printf("soft float\n");
#else
  printf("hard float\n");
#endif
  printf("LU %dx%d (reference 101)\n", NB_LU_N, NB_LU_N);
  printf("%lu MHz\n", (unsigned long)(clock / 1000000));
  printf("test         iter/s    P90     K6\n");
  configure();

  /* The counts cover the tests, not the output between them; a total over
   * all tests would overflow the 32-bit counters. */
  struct perf_totals totals = {0};
  for (int i = 0; i < NUMTESTS; i++) {
#ifdef NB_SMOKE
    /* Training takes hundreds of millions of cycles. */
    if (i == TF_NNET) {
      printf("nnet     skipped at smoke size\n");
      continue;
    }
#endif
    /* The name shows which test is running; some take a minute. */
    printf("%-8s", short_names[i]);
    perf_start();
    uint64_t c0 = soc_cycles();
    funcpointer[i]();
    uint64_t cycles = soc_cycles() - c0;
    perf_stop();
    perf_add(&totals);
    double s = score(i), p90 = s / bindex[i], k6 = s / lx_bindex[i];
    bench_print_fixed(s, 3, 14);
    bench_print_fixed(p90, 3, 8);
    bench_print_fixed(k6, 3, 8);
    printf("\n");
    con_screen(0);
    printf("         %llu cycles\n", (unsigned long long)cycles);
    con_screen(1);
    if (i == TF_FFPU || i == TF_NNET || i == TF_LU) {
      p90_fp *= p90;
      k6_fp *= k6;
      fp_tests++;
    } else {
      p90_int *= p90;
      if (i == TF_NUMSORT || i == TF_FPEMU || i == TF_IDEA || i == TF_HUFF) k6_int *= k6;
      else k6_mem *= k6;
    }
  }

  p90_int = root(p90_int, 7);
  p90_fp = root(p90_fp, fp_tests);
  k6_mem = root(k6_mem, 3);
  k6_int = root(k6_int, 4);
  k6_fp = root(k6_fp, fp_tests);
  printf("P90 (BYTE) INT ");
  bench_print_fixed(p90_int, 3, 0);
  printf(" FP ");
  bench_print_fixed(p90_fp, 3, 0);
  printf("\nK6/233 MEM ");
  bench_print_fixed(k6_mem, 3, 0);
  printf(" INT ");
  bench_print_fixed(k6_int, 3, 0);
  printf(" FP ");
  bench_print_fixed(k6_fp, 3, 0);
  int passed = __builtin_popcount((unsigned)ok_mask);
  printf("\nchecks %d ok, %d failed; heap peak %lu KiB\n", passed, checks_bad,
         (unsigned long)((arena_peak + 1023) / 1024));
  /* The full report goes to the console only, so the screen keeps the
   * results; the screen gets the three largest stall causes. */
  con_screen(0);
  perf_print("nbench", &totals);
  con_screen(1);
  struct demo_result r;
  perf_brief_totals(&totals, &r);
  printf("stalls");
  for (int k = 0; k < 3; k++)
    printf(" %s %u.%02u", perf_short[r.stall[k]], r.stall_cpi[k] / 100u, r.stall_cpi[k] % 100u);
  printf(" CPI\n");
  bench_stack_check();

  int pass = checks_bad == 0 && passed == 4;
  con_color(pass ? 10 : 12, 1);
  printf("NBENCH %luMHz INT ", (unsigned long)(clock / 1000000));
  bench_print_fixed(p90_int, 2, 0);
  printf(" FP ");
  bench_print_fixed(p90_fp, 2, 0);
  printf(" %s\n", pass ? "PASS" : "FAIL");
  if (!pass) fail("nbench checks");
  return 0;
}
