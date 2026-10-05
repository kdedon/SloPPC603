/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Host build of the Quake smoke run: the same engine and port as the
 * processor's smoke image. Run it in a directory holding id1/pak0.pak; it
 * prints the same checksum and writes the last frame and palette to
 * quake-frame.bin. */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "qport.h"

uint64_t plat_micros(void)
{
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * 1000000u + (uint64_t)ts.tv_nsec / 1000u;
}

uint64_t plat_cycles(void) { return 0; }

void plat_frame(const uint8_t *pix, const uint8_t *pal, int pal_changed)
{
  (void)pix, (void)pal, (void)pal_changed;
}

void plat_pass(uint32_t frames, uint32_t ms, uint32_t fps10, int ok)
{
  printf("quake: pass %u frames %u ms %u.%u fps%s\n", frames, ms, fps10 / 10, fps10 % 10,
         ok ? "" : " desync");
  exit(ok ? 0 : 1);
}

void plat_dump(const uint8_t *pix, const uint8_t *pal)
{
  FILE *f = fopen("quake-frame.bin", "wb");
  if (!f || fwrite(pix, 1, QPORT_W * QPORT_H, f) != QPORT_W * QPORT_H || fwrite(pal, 1, 768, f) != 768)
    exit(2);
  fclose(f);
}

void plat_stop(const char *error) { exit(error ? 1 : 0); }

int main(void) { qport_run(); }
