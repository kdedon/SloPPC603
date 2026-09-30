/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* Colour bars, a fixed-point Mandelbrot set and console text, laid out for
 * the framebuffer geometry the registers report. The set is drawn in passes
 * of 16, 8, 4, 2 and 1 pixel blocks, so it fills in progressively. Checks
 * the framebuffer geometry registers, the timebase against the cycle
 * counter, and a checksum of the Mandelbrot iteration counts. */
#include "soc.h"
#include "mandel.h"

/* Checksums for the view sizes the supported geometries give, from
 * mandel_sum (the same arithmetic on the host). */
static const struct { int w, h; uint32_t sum; } mb_sums[] = {
  {320, 128, 0xba35ce9du},   /* 320 x 240 */
  {1920, 744, 0x39393e84u},  /* 1920 x 1080 */
};

/* Draws a w x h view from row y0 and returns its checksum. */
static uint32_t mandelbrot(int y0, int w, int h)
{
  int32_t pitch = mb_pitch(w, h);
  uint32_t sum = 0;
  for (int b = 16; b >= 1; b /= 2)
    for (int y = 0; y < h; y += b)
      for (int x = 0; x < w; x += b) {
        /* Points on the coarser grid were drawn by the previous pass. */
        if (b < 16 && !(x & b) && !(y & b)) continue;
        int n = mb_iter(mb_cr(x, w, pitch), mb_ci(y, h, pitch));
        sum += mb_weight(n, x, y, w);
        fb_rect(x, y0 + y, x + b > w ? w - x : b, y + b > h ? h - y : b, mb_color(n));
      }
  return sum;
}

int main(void)
{
  if (SOC_ID != 0x36303365u) fail("SOC_ID");
  fb_init();
  if (SOC_FB_STRIDE != (uint32_t)fb_width || SOC_FB_FORMAT != 3 || fb_width % 16 != 0 ||
      con_rows < 20)
    fail("framebuffer geometry registers");

  fb_palette_default();
  fb_clear(0);
  for (int i = 0; i < 16; i++)
    fb_rect(i * fb_width / 16, con_cell, fb_width / 16, 2 * con_cell, (uint8_t)i);

  con_screen(1);
  con_color(15, 0);
  con_goto(0, 0);
  printf("PowerPC 603e demo system");

  /* The set sits between the bars and the bottom 11 text rows. */
  int mb_y = 3 * con_cell, mb_w = fb_width, mb_h = (con_rows - 14) * con_cell;
  uint32_t expect_sum = 0;
  int known = 0;
  for (unsigned i = 0; i < sizeof mb_sums / sizeof mb_sums[0]; i++)
    if (mb_sums[i].w == mb_w && mb_sums[i].h == mb_h) {
      expect_sum = mb_sums[i].sum;
      known = 1;
    }

  perf_start();
  uint64_t r0 = soc_retired(), c0 = soc_cycles(), t0 = soc_timebase();
  uint32_t sum = mandelbrot(mb_y, mb_w, mb_h);
  uint64_t cycles = soc_cycles() - c0, ticks = soc_timebase() - t0;
  uint64_t retired = soc_retired() - r0;
  perf_stop();

  /* The timebase counts once per four processor clocks. */
  uint64_t expect = cycles / 4;
  if (!known) fail("no Mandelbrot checksum for this screen size");
  if (sum != expect_sum) fail("Mandelbrot checksum");
  if (ticks + 64 < expect || ticks > expect + 64) {
    printf("\ntimebase %lu ticks, cycles/4 %lu\n", (unsigned long)ticks, (unsigned long)expect);
    fail("timebase does not track the cycle counter");
  }

  SOC_CONSOLE = '\n';
  con_goto(0, con_rows - 11);
  con_color(14, 0);
  printf("Mandelbrot %dx%d: %lu cycles\n", mb_w, mb_h, (unsigned long)cycles);
  printf("timebase %lu ticks, sum %08x\n", (unsigned long)ticks, (unsigned)sum);
  con_color(10, 0);
  demo_hello = (struct demo_result){
      .cycles = cycles, .retired = retired,
      .count = (uint32_t)sum, .milli = 0, .ok = 1};
  perf_brief(&demo_hello);
  printf("hello: PASS");
  SOC_CONSOLE = '\n';
  return 0;
}
