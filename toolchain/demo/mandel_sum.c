/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* Host tool: prints the checksum hello.c expects for a w x h Mandelbrot
 * view. Usage: mandel_sum <w> <h>. */
#include <stdio.h>
#include <stdlib.h>

#include "mandel.h"

int main(int argc, char **argv)
{
  if (argc != 3) {
    fprintf(stderr, "usage: %s <w> <h>\n", argv[0]);
    return 2;
  }
  int w = atoi(argv[1]), h = atoi(argv[2]);
  int32_t pitch = mb_pitch(w, h);
  uint32_t sum = 0;
  for (int y = 0; y < h; y++)
    for (int x = 0; x < w; x++)
      sum += mb_weight(mb_iter(mb_cr(x, w, pitch), mb_ci(y, h, pitch)), x, y, w);
  printf("{%d, %d, 0x%08xu}\n", w, h, (unsigned)sum);
  return 0;
}
