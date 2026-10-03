/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* The Mandelbrot set of hello.c in double precision, built hard-float: the
 * same view, iteration limit, block passes and drawing, so its cycle count
 * compares with hello's fixed-point one. Checks a checksum of the
 * iteration counts. Alone, it draws its own screen; after hello it redraws
 * hello's set and prints in the text window. */
#include "soc.h"
#include "mandel.h"

/* Checksums for the supported geometries, from mandel_sum <w> <h> double. */
static const struct { int w, h; uint32_t sum; } mbd_sums[] = {
  {320, 128, 0xba382525u},   /* 320 x 240 */
  {1920, 744, 0x3d84bb7eu},  /* 1920 x 1080 */
};

struct demo_result demo_fpmb;

static uint32_t mandelbrot(int y0, int w, int h)
{
  double pitch = mbd_pitch(w, h);
  uint32_t sum = 0;
  for (int b = 16; b >= 1; b /= 2)
    for (int y = 0; y < h; y += b)
      for (int x = 0; x < w; x += b) {
        /* Points on the coarser grid were drawn by the previous pass. */
        if (b < 16 && !(x & b) && !(y & b)) continue;
        int n = mbd_iter(mbd_cr(x, w, pitch), mbd_ci(y, h, pitch));
        sum += mb_weight(n, x, y, w);
        fb_rect(x, y0 + y, x + b > w ? w - x : b, y + b > h ? h - y : b, mb_color(n));
      }
  return sum;
}

int fpmb_demo(int alone)
{
  if (alone) {
    fb_palette_default();
    fb_clear(0);
    con_screen(1);
    con_color(15, 0);
    con_goto(0, 0);
    printf("PowerPC 603e demo system, FPU");
    SOC_CONSOLE = '\n';
    con_window(con_rows - 11);
  }

  int mb_y = 3 * con_cell, mb_w = fb_width, mb_h = (con_rows - 14) * con_cell;
  uint32_t expect_sum = 0;
  int known = 0;
  for (unsigned i = 0; i < sizeof mbd_sums / sizeof mbd_sums[0]; i++)
    if (mbd_sums[i].w == mb_w && mbd_sums[i].h == mb_h) {
      expect_sum = mbd_sums[i].sum;
      known = 1;
    }

  perf_start();
  uint64_t r0 = soc_retired(), c0 = soc_cycles();
  uint32_t sum = mandelbrot(mb_y, mb_w, mb_h);
  uint64_t cycles = soc_cycles() - c0, retired = soc_retired() - r0;
  perf_stop();

  if (!known) fail("no FP Mandelbrot checksum for this screen size");
  if (sum != expect_sum) fail("FP Mandelbrot checksum");

  con_clear(1);
  con_color(15, 1);
  printf("FP Mandelbrot %dx%d, double\n", mb_w, mb_h);
  printf("%lu cycles, sum %08x\n", (unsigned long)cycles, (unsigned)sum);
  demo_fpmb = (struct demo_result){
      .cycles = cycles, .retired = retired, .count = sum, .milli = 0, .ok = 1};
  perf_brief(&demo_fpmb);
  con_color(10, 1);
  printf("fpmb: PASS");
  SOC_CONSOLE = '\n';
  return 0;
}
