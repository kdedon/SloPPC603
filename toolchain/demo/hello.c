/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* Colour bars, a fixed-point Mandelbrot set and console text. Checks the
 * framebuffer geometry registers, the timebase against the cycle counter,
 * and a checksum of the Mandelbrot iteration counts. */
#include "soc.h"

#define MAX_ITER 48
#define MB_W 320
#define MB_H 160
#define MB_Y 48
/* Host-computed with the same integer arithmetic. */
#define MB_CHECKSUM 0xadb5c49fu

/* Iteration count at c = (cr, ci), Q4.12 fixed point. */
static int mandel(int32_t cr, int32_t ci)
{
  int32_t zr = 0, zi = 0;
  int n;
  for (n = 0; n < MAX_ITER; n++) {
    int32_t zr2 = (zr * zr) >> 12, zi2 = (zi * zi) >> 12;
    if (zr2 + zi2 > (4 << 12)) break;
    zi = ((zr * zi) >> 11) + ci;
    zr = zr2 - zi2 + cr;
  }
  return n;
}

int main(void)
{
  if (SOC_ID != 0x36303365u) fail("SOC_ID");
  if (SOC_FB_ADDR != SOC_FB_BASE || SOC_FB_STRIDE != SOC_FB_WIDTH ||
      SOC_FB_SIZE != ((SOC_FB_WIDTH << 16) | SOC_FB_HEIGHT) || SOC_FB_FORMAT != 3)
    fail("framebuffer geometry registers");

  fb_palette_default();
  fb_clear(0);
  for (int i = 0; i < 16; i++) fb_rect(i * 20, 16, 20, 24, (uint8_t)i);

  con_screen(1);
  con_color(15, 0);
  con_goto(0, 0);
  printf("PowerPC 603e demo system");

  uint64_t r0 = soc_retired(), c0 = soc_cycles(), t0 = soc_timebase();
  uint32_t sum = 0;
  /* Real axis -2.25..0.75, imaginary -1.0..1.0. */
  for (int y = 0; y < MB_H; y++) {
    int32_t ci = -(1 << 12) + ((y * (2 << 12)) / MB_H);
    volatile uint32_t *row = (volatile uint32_t *)(SOC_FB + (MB_Y + y) * SOC_FB_WIDTH);
    for (int x = 0; x < MB_W; x += 4) {
      uint32_t word = 0;
      for (int k = 0; k < 4; k++) {
        int32_t cr = -(9 << 10) + (((x + k) * (3 << 12)) / MB_W);
        int n = mandel(cr, ci);
        sum = sum * 31 + (uint32_t)n;
        word = (word << 8) | (n == MAX_ITER ? 0 : 16 + (uint32_t)n * 239 / MAX_ITER);
      }
      row[x / 4] = word;
    }
  }
  uint64_t cycles = soc_cycles() - c0, ticks = soc_timebase() - t0;
  uint64_t retired = soc_retired() - r0;

  /* The timebase counts once per four processor clocks. */
  uint64_t expect = cycles / 4;
  if (sum != MB_CHECKSUM) fail("Mandelbrot checksum");
  if (ticks + 64 < expect || ticks > expect + 64) {
    printf("\ntimebase %lu ticks, cycles/4 %lu\n", (unsigned long)ticks, (unsigned long)expect);
    fail("timebase does not track the cycle counter");
  }

  SOC_CONSOLE = '\n';
  con_goto(0, 26);
  con_color(14, 0);
  printf("Mandelbrot %dx%d: %lu cycles\n", MB_W, MB_H, (unsigned long)cycles);
  printf("timebase %lu ticks, sum %08x\n", (unsigned long)ticks, (unsigned)sum);
  con_color(10, 0);
  demo_hello = (struct demo_result){cycles, retired, (uint32_t)sum, 0, 1};
  printf("hello: PASS");
  SOC_CONSOLE = '\n';
  return 0;
}
