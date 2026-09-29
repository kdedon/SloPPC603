/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* MiSTer image: runs the program selected in the MODE register (hello,
 * Dhrystone, CoreMark or all three) at full or smoke-test length, then draws
 * a results summary on the bottom rows of the screen and echoes it to the
 * console. A failed check stops in fail() with its message on screen. */
#include "soc.h"

#ifndef GIT_SHORT
#define GIT_SHORT "unknown"
#endif

#define MODE_PROGRAM(m) ((m) & 3u)
#define MODE_FULL(m) (((m) >> 2) & 1u)
#define MODE_MHZ(m) ((m) >> 16)

enum { PROG_HELLO, PROG_DHRY, PROG_CM, PROG_ALL };

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

static void put_milli(uint32_t v)
{
  printf("%lu.%03lu", (unsigned long)(v / 1000), (unsigned long)(v % 1000));
}

static void summary(uint32_t program, uint32_t mode)
{
  uint64_t cycles = soc_cycles(), retired = soc_retired();
  uint32_t tenures = SOC_TENURES;

  con_screen(1);
  fb_rect(0, 22 * 8, SOC_FB_WIDTH, 8 * 8, 0);
  con_color(15, 0);
  con_goto(0, 22);
  SOC_CONSOLE = '\n';
  printf("603e PVR %08lx %luMHz %s%s\n", (unsigned long)read_pvr(),
         (unsigned long)MODE_MHZ(mode), GIT_SHORT, MODE_FULL(mode) ? "" : " smoke");
  if (program == PROG_HELLO || program == PROG_ALL) {
    printf("Hello MB %lu cyc ", (unsigned long)demo_hello.cycles);
    put_cpi(demo_hello.cycles, demo_hello.retired);
    printf("\n");
  }
  if (program == PROG_DHRY || program == PROG_ALL) {
    printf("Dhry %lu/%lu ", (unsigned long)demo_dhry.cycles, (unsigned long)demo_dhry.count);
    put_milli(demo_dhry.milli);
    printf(" DMIPS/MHz\n     ");
    put_cpi(demo_dhry.cycles, demo_dhry.retired);
    printf(" ret %lu\n", (unsigned long)demo_dhry.retired);
  }
  if (program == PROG_CM || program == PROG_ALL) {
    printf("CM ");
    put_milli(demo_cm.milli);
    printf("/MHz %lu it CRC ok ", (unsigned long)demo_cm.count);
    put_cpi(demo_cm.cycles, demo_cm.retired);
    printf("\n   cyc %lu ret %lu\n", (unsigned long)demo_cm.cycles,
           (unsigned long)demo_cm.retired);
  }
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

  if (program == PROG_HELLO || program == PROG_ALL) hello_main();
  if (program == PROG_DHRY || program == PROG_ALL) dhry_demo();
  if (program == PROG_CM || program == PROG_ALL) coremark_demo();
  summary(program, mode);
  return 0;
}
