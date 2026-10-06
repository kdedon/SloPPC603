/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Platform services for the Doom port's C library (platform.c). */
#ifndef DOOM_PLAT_H
#define DOOM_PLAT_H
#include <stddef.h>
#include <stdint.h>

/* The data file, loaded by the core's Load data at a fixed address. A port
 * may name another file and size. */
#ifndef PLAT_WAD_NAME
#define PLAT_WAD_NAME "doom1.wad"
#define PLAT_WAD_MAX 0x00800000u
#endif
#define PLAT_WAD_ADDR 0x01800000u

extern const uint8_t *plat_wad;
extern size_t plat_wad_size;
extern char *plat_heap_start, *plat_heap_end;

/* Console output; err marks standard error, which is also kept for exit. */
void plat_putc(int c, int err);
void plat_sleep_us(uint32_t us);
uint64_t plat_micros(void);

#endif
