/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Host build of the Doom smoke run: the same engine, arguments and WAD as
 * the processor's smoke image, stopping at the same gametic and printing the
 * same checksum of the frame and palette. Run it in a directory holding
 * doom1.wad.  Usage: doom-host <gametic> */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "doomgeneric.h"
#include "doomtype.h"
#include "i_video.h"

extern int gametic;

void DG_Init(void) {}
void DG_DrawFrame(void) {}
void DG_SleepMs(uint32_t ms) { (void)ms; }
int DG_GetKey(int *pressed, unsigned char *key) { (void)pressed; (void)key; return 0; }
void DG_SetWindowTitle(const char *title) { (void)title; }

uint32_t DG_GetTicksMs(void)
{
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

static uint32_t crc32(uint32_t crc, const uint8_t *p, size_t n)
{
  crc = ~crc;
  while (n--) {
    crc ^= *p++;
    for (int k = 0; k < 8; k++) crc = crc >> 1 ^ (0xedb88320u & -(crc & 1));
  }
  return ~crc;
}

int main(int argc, char **argv)
{
  if (argc != 2) return 2;
  int tics = atoi(argv[1]);
  static char *args[] = {"doom", "-iwad", "doom1.wad", "-timedemo", "demo3", "-nogui", NULL};
  doomgeneric_Create(6, args);
  for (;;) {
    doomgeneric_Tick();
    if (gametic >= tics) {
      uint8_t pal[768];
      for (int i = 0; i < 256; i++) {
        pal[3 * i] = colors[i].r;
        pal[3 * i + 1] = colors[i].g;
        pal[3 * i + 2] = colors[i].b;
      }
      uint32_t crc = crc32(crc32(0, DG_ScreenBuffer, 320 * 200), pal, sizeof pal);
      printf("doom: gametic %d frame crc %08lx\n", gametic, (unsigned long)crc);
      return 0;
    }
  }
}
