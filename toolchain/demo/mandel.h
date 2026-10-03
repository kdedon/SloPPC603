/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Mandelbrot arithmetic shared by the firmware and the host tool that
 * computes its checksums (mandel_sum.c): fixed point in Q4.12 for hello.c,
 * and the same view in double precision (mbd_) for fmandel.c. Both sides
 * build the double version without contraction, so the one fused
 * multiply-add is the explicit one. */
#ifndef DEMO_MANDEL_H
#define DEMO_MANDEL_H

#include <stdint.h>

#define MB_MAX_ITER 48

/* Iteration count at c = (cr, ci). */
static inline int mb_iter(int32_t cr, int32_t ci)
{
  int32_t zr = 0, zi = 0;
  int n;
  for (n = 0; n < MB_MAX_ITER; n++) {
    int32_t zr2 = (zr * zr) >> 12, zi2 = (zi * zi) >> 12;
    if (zr2 + zi2 > (4 << 12)) break;
    zi = ((zr * zi) >> 11) + ci;
    zr = zr2 - zi2 + cr;
  }
  return n;
}

/* Pixel pitch for a w x h view that fits real -2.25..0.75 and imaginary
 * -1.125..1.125, centred on -0.75. */
static inline int32_t mb_pitch(int w, int h)
{
  int32_t a = ((3 << 12) + w - 1) / w, b = ((9 << 10) + h - 1) / h;
  return a > b ? a : b;
}

static inline int32_t mb_cr(int x, int w, int32_t pitch) { return -(3 << 10) + (x - w / 2) * pitch; }
static inline int32_t mb_ci(int y, int h, int32_t pitch) { return (y - h / 2) * pitch; }

/* Double precision: the same view, iteration limit and escape test. */
static inline int mbd_iter(double cr, double ci)
{
  double zr = 0.0, zi = 0.0;
  int n;
  for (n = 0; n < MB_MAX_ITER; n++) {
    double zr2 = zr * zr, zi2 = zi * zi;
    if (zr2 + zi2 > 4.0) break;
    zi = __builtin_fma(zr + zr, zi, ci);
    zr = zr2 - zi2 + cr;
  }
  return n;
}

static inline double mbd_pitch(int w, int h)
{
  double a = 3.0 / w, b = 2.25 / h;
  return a > b ? a : b;
}

static inline double mbd_cr(int x, int w, double pitch) { return -0.75 + (x - w / 2) * pitch; }
static inline double mbd_ci(int y, int h, double pitch) { return (y - h / 2) * pitch; }

/* Palette index: black inside the set, the colour ramp (16-255) outside. */
static inline uint8_t mb_color(int n)
{
  return n == MB_MAX_ITER ? 0 : (uint8_t)(16 + n * 239 / MB_MAX_ITER);
}

/* Checksum term of one pixel; the sum does not depend on drawing order. */
static inline uint32_t mb_weight(int n, int x, int y, int w)
{
  return (uint32_t)n * (uint32_t)(y * w + x + 1);
}

#endif
