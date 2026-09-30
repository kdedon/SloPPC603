/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* Runs Dhrystone 2.1 (fetched upstream source) and checks it. Every
 * "should be" line it prints is compared with the value printed just
 * before it, and the final global state is checked directly. Timing uses
 * the SoC cycle counter through times(). */
#define DEMO_DHRYSTONE
#include "dhry.h"
#undef printf
#undef scanf
#include "soc.h"

#ifndef DHRY_RUNS
#define DHRY_RUNS 2000
#endif
int demo_dhry_runs = DHRY_RUNS;
static uint64_t retired0, retired1;
static int times_calls;

extern Rec_Pointer Ptr_Glob, Next_Ptr_Glob;
extern int Int_Glob, Arr_1_Glob[50], Arr_2_Glob[50][50];
extern Boolean Bool_Glob;
extern char Ch_1_Glob, Ch_2_Glob;
extern long Begin_Time, End_Time;
int dhry_main(void);

static int last_int, checks, mismatches;
static char last_char;
static const char *last_str = "";

static int ends_with(const char *s, const char *tail)
{
  size_t n = strlen(s), m = strlen(tail);
  return n >= m && strcmp(s + n - m, tail) == 0;
}

static void check(int ok, const char *fmt)
{
  checks++;
  if (!ok) {
    mismatches++;
    printf("MISMATCH at: %s", fmt);
  }
}

int dhry_printf(const char *fmt, ...)
{
  static const char expect[] = "        should be:   ";
  va_list ap;
  va_start(ap, fmt);
  if (memcmp(fmt, expect, sizeof expect - 1) == 0) {
    const char *what = fmt + sizeof expect - 1;
    va_list copy;
    va_copy(copy, ap);
    if (strcmp(what, "%d\n") == 0) check(last_int == va_arg(copy, int), fmt);
    else if (strcmp(what, "%c\n") == 0) check(last_char == (char)va_arg(copy, int), fmt);
    else if (strcmp(what, "Number_Of_Runs + 10\n") == 0) check(last_int == demo_dhry_runs + 10, fmt);
    else if (memcmp(what, "DHRYSTONE", 9) == 0)
      check(memcmp(last_str, what, strlen(what) - 1) == 0 && strlen(last_str) == strlen(what) - 1, fmt);
    va_end(copy);
  } else {
    va_list copy;
    va_copy(copy, ap);
    if (ends_with(fmt, "%d\n")) last_int = va_arg(copy, int);
    else if (ends_with(fmt, "%c\n")) last_char = (char)va_arg(copy, int);
    else if (ends_with(fmt, "%s\n")) last_str = va_arg(copy, const char *);
    va_end(copy);
  }
  int n = vprintf(fmt, ap);
  va_end(ap);
  return n;
}

int dhry_scanf(const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  if (strcmp(fmt, "%d") != 0) fail("unexpected scanf format");
  *va_arg(ap, int *) = demo_dhry_runs;
  va_end(ap);
  printf("%d", demo_dhry_runs);
  return 1;
}

int times(struct tms *buf)
{
  /* Dhrystone reads the time just before and just after its loop. */
  if (times_calls++ == 0) retired0 = soc_retired();
  buf->tms_utime = (clock_t)(uint32_t)soc_cycles();
  if (times_calls == 2) retired1 = soc_retired();
  buf->tms_stime = buf->tms_cutime = buf->tms_cstime = 0;
  return (int)buf->tms_utime;
}

int main(void)
{
  fb_palette_default();
  con_clear(1);
  con_color(15, 1);
  con_screen(1);
  printf("Dhrystone 2.1, %d runs\n", demo_dhry_runs);
  con_screen(0);

  dhry_main();

  check(Int_Glob == 5 && Bool_Glob == 1 && Ch_1_Glob == 'A' && Ch_2_Glob == 'B', "globals\n");
  check(Arr_1_Glob[8] == 7 && Arr_2_Glob[8][7] == demo_dhry_runs + 10, "arrays\n");
  check(Next_Ptr_Glob->Ptr_Comp == Ptr_Glob->Ptr_Comp && Ptr_Glob->Discr == 0 &&
        Ptr_Glob->variant.var_1.Enum_Comp == 2 && Ptr_Glob->variant.var_1.Int_Comp == 17 &&
        Next_Ptr_Glob->variant.var_1.Enum_Comp == 1 &&
        Next_Ptr_Glob->variant.var_1.Int_Comp == 18, "records\n");

  uint32_t cycles = (uint32_t)(End_Time - Begin_Time);
  uint64_t runs = (uint64_t)demo_dhry_runs;
  uint32_t per_sec = (uint32_t)(runs * SOC_CLOCK_HZ / cycles);
  /* DMIPS/MHz = runs / cycles * 1e6 / 1757, kept to three decimals. */
  uint32_t dmips_mhz_milli = (uint32_t)(runs * 1000000000ull / ((uint64_t)cycles * 1757));
  uint32_t cycles_per_run_tenth = (uint32_t)((uint64_t)cycles * 10 / runs);

  con_screen(1);
  con_goto(0, 3);
  printf("cycles:          %lu\n", (unsigned long)cycles);
  printf("cycles/run:      %lu.%lu\n", (unsigned long)(cycles_per_run_tenth / 10),
         (unsigned long)(cycles_per_run_tenth % 10));
  printf("Dhrystones/s:    %lu at %lu MHz\n", (unsigned long)per_sec,
         (unsigned long)(SOC_CLOCK_HZ / 1000000));
  printf("DMIPS/MHz:       %lu.%03lu\n", (unsigned long)(dmips_mhz_milli / 1000),
         (unsigned long)(dmips_mhz_milli % 1000));
  printf("checks:          %d, mismatches %d\n", checks, mismatches);
  if (mismatches != 0 || checks < 20) fail("Dhrystone results");
  demo_dhry = (struct demo_result){cycles, retired1 - retired0, (uint32_t)runs, dmips_mhz_milli, 1};
  con_color(10, 1);
  printf("dhrystone: PASS\n");
  return 0;
}
