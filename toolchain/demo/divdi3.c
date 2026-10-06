/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* 64-bit division for little-endian images: the toolchain's libgcc is
 * big-endian only. */
#include <stdint.h>

static uint64_t udivmod(uint64_t n, uint64_t d, uint64_t *rem) {
  uint64_t q = 0, r = 0;
  for (int i = 63; i >= 0; i--) {
    r = r << 1 | ((n >> i) & 1);
    if (r >= d) {
      r -= d;
      q |= (uint64_t)1 << i;
    }
  }
  *rem = r;
  return q;
}

uint64_t __udivdi3(uint64_t n, uint64_t d);
uint64_t __umoddi3(uint64_t n, uint64_t d);
int64_t __divdi3(int64_t n, int64_t d);
int64_t __moddi3(int64_t n, int64_t d);

uint64_t __udivdi3(uint64_t n, uint64_t d) {
  uint64_t r;
  return udivmod(n, d, &r);
}

uint64_t __umoddi3(uint64_t n, uint64_t d) {
  uint64_t r;
  udivmod(n, d, &r);
  return r;
}

int64_t __divdi3(int64_t n, int64_t d) {
  uint64_t r, q = udivmod(n < 0 ? -(uint64_t)n : (uint64_t)n, d < 0 ? -(uint64_t)d : (uint64_t)d, &r);
  return (n < 0) != (d < 0) ? -(int64_t)q : (int64_t)q;
}

int64_t __moddi3(int64_t n, int64_t d) {
  uint64_t r;
  udivmod(n < 0 ? -(uint64_t)n : (uint64_t)n, d < 0 ? -(uint64_t)d : (uint64_t)d, &r);
  return n < 0 ? -(int64_t)r : (int64_t)r;
}
