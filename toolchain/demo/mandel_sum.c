/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* Host tool: prints the checksum hello.c expects for a w x h Mandelbrot
 * view, or with "double" the one fmandel.c expects. Usage:
 * mandel_sum <w> <h> [double]; build with -ffp-contract=off -lm. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mandel.h"

int main(int argc, char **argv)
{
  if (argc < 3 || argc > 4 || (argc == 4 && strcmp(argv[3], "double") != 0)) {
    fprintf(stderr, "usage: %s <w> <h> [double]\n", argv[0]);
    return 2;
  }
  int w = atoi(argv[1]), h = atoi(argv[2]);
  uint32_t sum = 0;
  if (argc == 4) {
    double pitch = mbd_pitch(w, h);
    for (int y = 0; y < h; y++)
      for (int x = 0; x < w; x++)
        sum += mb_weight(mbd_iter(mbd_cr(x, w, pitch), mbd_ci(y, h, pitch)), x, y, w);
  } else {
    int32_t pitch = mb_pitch(w, h);
    for (int y = 0; y < h; y++)
      for (int x = 0; x < w; x++)
        sum += mb_weight(mb_iter(mb_cr(x, w, pitch), mb_ci(y, h, pitch)), x, y, w);
  }
  printf("{%d, %d, 0x%08xu}\n", w, h, (unsigned)sum);
  return 0;
}
