/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* MiSTer image: runs the program selected in the MODE register (hello,
 * Dhrystone, CoreMark or all three) at full or smoke-test length, then draws
 * a results summary on the bottom rows of the screen and echoes it to the
 * console. In Run all, the benchmarks write in the bottom text rows only,
 * so hello's Mandelbrot set stays on screen above the summary. The layout
 * follows the framebuffer geometry the registers report. A failed check
 * stops in fail() with its message on screen. With MISTER_FPU, the image
 * for the core with the floating-point unit adds Whetstone and the
 * double-precision Mandelbrot set; the program number then has bit 2 in
 * MODE bit 3. */
#include "soc.h"

#ifndef GIT_SHORT
#define GIT_SHORT "unknown"
#endif

#define MODE_FULL(m) (((m) >> 2) & 1u)
#define MODE_MHZ(m) ((m) >> 16)

#ifdef MISTER_FPU
#define MODE_PROGRAM(m) (((m) & 3u) | (((m) >> 1) & 4u))
enum { PROG_HELLO, PROG_DHRY, PROG_CM, PROG_WHET, PROG_FPMB, PROG_ALL };
int whet_demo(void);
int fpmb_demo(int alone);
#else
#define MODE_PROGRAM(m) ((m) & 3u)
enum { PROG_HELLO, PROG_DHRY, PROG_CM, PROG_ALL };
#endif

int hello_main(void);
int dhry_demo(void);
int coremark_demo(void);

static uint32_t read_pvr(void)
{
  uint32_t v;
  __asm__ volatile("mfspr %0,287" : "=r"(v));
  return v;
}

/* CPI in hundredths, as "x.xx". */
static void put_cpi(uint64_t cycles, uint64_t retired)
{
  uint32_t c = retired ? (uint32_t)(cycles * 100 / retired) : 0;
  printf("CPI %lu.%02lu", (unsigned long)(c / 100), (unsigned long)(c % 100));
}

/* The three largest stall causes, when the line has room for them. */
static void put_stalls(const struct demo_result *r, int used)
{
  if (con_cols - used < 36) return;
  for (int k = 0; k < 3; k++)
    printf(" %s %lu.%02lu", perf_short[r->stall[k]], (unsigned long)(r->stall_cpi[k] / 100),
           (unsigned long)(r->stall_cpi[k] % 100));
}

static void put_milli(uint32_t v)
{
  printf("%lu.%03lu", (unsigned long)(v / 1000), (unsigned long)(v % 1000));
}

static void summary(uint32_t program, uint32_t mode)
{
  uint64_t cycles = soc_cycles(), retired = soc_retired();
  uint32_t tenures = SOC_TENURES;
#ifdef MISTER_FPU
  int rows = program == PROG_ALL ? 10 : 8;
#else
  int rows = 8;
#endif

  con_screen(1);
  con_window(0);
  fb_rect(0, (con_rows - rows) * con_cell, fb_width, rows * con_cell, 0);
  con_color(15, 0);
  con_goto(0, con_rows - rows);
  SOC_CONSOLE = '\n';
  printf("603e PVR %08lx %luMHz %s%s\n", (unsigned long)read_pvr(),
         (unsigned long)MODE_MHZ(mode), GIT_SHORT, MODE_FULL(mode) ? "" : " smoke");
  if (program == PROG_HELLO || program == PROG_ALL) {
    printf("Hello MB %lu cyc ", (unsigned long)demo_hello.cycles);
    put_cpi(demo_hello.cycles, demo_hello.retired);
    put_stalls(&demo_hello, 32);
    printf("\n");
  }
#ifdef MISTER_FPU
  if (program == PROG_FPMB || program == PROG_ALL) {
    /* Milliseconds at the reported clock, to compare with the line above. */
    uint32_t us = (uint32_t)(demo_fpmb.cycles / (MODE_MHZ(mode) ? MODE_MHZ(mode) : 1));
    printf("FP MB %lu cyc ", (unsigned long)demo_fpmb.cycles);
    put_milli(us);
    printf(" ms ");
    put_cpi(demo_fpmb.cycles, demo_fpmb.retired);
    printf("\n");
  }
#endif
  if (program == PROG_DHRY || program == PROG_ALL) {
    printf("Dhry %lu/%lu ", (unsigned long)demo_dhry.cycles, (unsigned long)demo_dhry.count);
    put_milli(demo_dhry.milli);
    printf(" DMIPS/MHz\n     ");
    put_cpi(demo_dhry.cycles, demo_dhry.retired);
    printf(" ret %lu", (unsigned long)demo_dhry.retired);
    put_stalls(&demo_dhry, 28);
    printf("\n");
  }
  if (program == PROG_CM || program == PROG_ALL) {
    printf("CM ");
    put_milli(demo_cm.milli);
    printf("/MHz %lu it CRC ok ", (unsigned long)demo_cm.count);
    put_cpi(demo_cm.cycles, demo_cm.retired);
    printf("\n   cyc %lu ret %lu", (unsigned long)demo_cm.cycles,
           (unsigned long)demo_cm.retired);
    put_stalls(&demo_cm, 26);
    printf("\n");
  }
#ifdef MISTER_FPU
  if (program == PROG_WHET || program == PROG_ALL) {
    /* count is thousands of Whetstone instructions: MWIPS/MHz in
     * ten-thousandths is count * 1e7 / cycles. */
    uint64_t c = demo_whet.cycles ? demo_whet.cycles : 1;
    uint32_t per_mhz = (uint32_t)((uint64_t)demo_whet.count * 10000000u / c);
    uint32_t mwips = (uint32_t)((uint64_t)demo_whet.count * MODE_MHZ(mode) * 1000000u / c);
    printf("Whet ");
    put_milli(mwips);
    printf(" MWIPS %lu.%04lu/MHz ", (unsigned long)(per_mhz / 10000),
           (unsigned long)(per_mhz % 10000));
    put_cpi(demo_whet.cycles, demo_whet.retired);
    printf("\n");
  }
#endif
  printf("All cyc %lu ret %lu\n", (unsigned long)cycles, (unsigned long)retired);
  put_cpi(cycles, retired);
  printf(" bus %lu ", (unsigned long)tenures);
  con_color(10, 0);
  printf("PASS");
  SOC_CONSOLE = '\n';
}

int main(void)
{
  uint32_t mode = SOC_MODE;
  uint32_t program = MODE_PROGRAM(mode);
  int full = (int)MODE_FULL(mode);

  /* Full length: Dhrystone about 7 s and CoreMark about 12 s at 50 MHz. */
  demo_dhry_runs = full ? 100000 : 200;
  demo_cm_iterations = full ? 400 : 1;
#ifdef MISTER_FPU
  /* Whetstone: about 10 s at 50 MHz, or one short run. */
  demo_whet_full = full;
  if (!(mode & SOC_MODE_FPU)) fail("this image needs the floating-point unit");
#endif

  fb_init();
  if (program == PROG_HELLO || program == PROG_ALL) hello_main();
  /* Keep the set: the benchmarks get the text rows below it. */
  if (program == PROG_ALL) con_window(con_rows - 11);
#ifdef MISTER_FPU
  /* After hello, the double-precision set redraws the same view. */
  if (program == PROG_FPMB || program == PROG_ALL) fpmb_demo(program == PROG_FPMB);
#endif
  if (program == PROG_DHRY || program == PROG_ALL) dhry_demo();
  if (program == PROG_CM || program == PROG_ALL) coremark_demo();
#ifdef MISTER_FPU
  if (program == PROG_WHET || program == PROG_ALL) whet_demo();
#endif
  summary(program, mode);
  return 0;
}
