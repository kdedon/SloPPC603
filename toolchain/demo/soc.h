/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
#ifndef DEMO_SOC_H
#define DEMO_SOC_H

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

/* Memory map (docs/DEMO_SOC.md). */
#define SOC_FB_BASE 0xf0000000u
#define SOC_IO_BASE 0xf0100000u
#define SOC_FB_WIDTH 320
#define SOC_FB_HEIGHT 240
#define SOC_CLOCK_HZ 50000000u

#define SOC_REG(off) (*(volatile uint32_t *)(SOC_IO_BASE + (off)))
#define SOC_ID SOC_REG(0x00)
#define SOC_CTRL SOC_REG(0x04)
#define SOC_CYCLE_LO SOC_REG(0x08)
#define SOC_CYCLE_HI SOC_REG(0x0c)
#define SOC_CONSOLE SOC_REG(0x10)
#define SOC_EXIT SOC_REG(0x14)
#define SOC_FRAMES SOC_REG(0x18)
#define SOC_STATUS SOC_REG(0x1c)
#define SOC_FB_ADDR SOC_REG(0x20)
#define SOC_FB_STRIDE SOC_REG(0x24)
#define SOC_FB_SIZE SOC_REG(0x28)
#define SOC_FB_FORMAT SOC_REG(0x2c)
#define SOC_PALETTE(i) SOC_REG(0x400 + 4 * (i))

#define SOC_FB ((volatile uint8_t *)SOC_FB_BASE)

/* Runtime (rt.c). */
uint64_t soc_cycles(void);
uint64_t soc_timebase(void);
void con_putc(int c);
void con_puts(const char *s);
/* Screen text: 8x8 cells, 40 columns by 30 rows. */
void con_screen(int enable);
void con_goto(int col, int row);
void con_color(uint8_t fg, uint8_t bg);
int printf(const char *fmt, ...);
int vprintf(const char *fmt, va_list ap);
int snprintf(char *buf, size_t size, const char *fmt, ...);
void fb_clear(uint8_t color);
void fb_rect(int x, int y, int w, int h, uint8_t color);
void fb_palette_default(void);
void *malloc(size_t size);
void *memcpy(void *dst, const void *src, size_t n);
void *memset(void *dst, int c, size_t n);
int memcmp(const void *a, const void *b, size_t n);
char *strcpy(char *dst, const char *src);
int strcmp(const char *a, const char *b);
size_t strlen(const char *s);
/* Reports a failed check on the console and exits with code 1. */
void fail(const char *what);

extern const uint8_t font8x8[95][8];

#endif
