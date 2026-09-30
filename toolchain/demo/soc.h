/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
#ifndef DEMO_SOC_H
#define DEMO_SOC_H

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

/* Memory map (docs/DEMO_SOC.md). The framebuffer's address and geometry
 * come from the registers (fb_init). */
#define SOC_IO_BASE 0xf0100000u
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
/* Clock in MHz (31:16) and host mode bits (7:0). */
#define SOC_MODE SOC_REG(0x30)
#define SOC_TENURES SOC_REG(0x34)
#define SOC_RETIRED_LO SOC_REG(0x38)
#define SOC_RETIRED_HI SOC_REG(0x3c)
#define SOC_PALETTE(i) SOC_REG(0x400 + 4 * (i))


/* Runtime (rt.c). */
uint64_t soc_cycles(void);
uint64_t soc_timebase(void);
uint64_t soc_retired(void);

/* Each program's result for the MiSTer summary: a timed window and its
 * score in thousandths; ok is set when the program's own checks pass. */
struct demo_result {
  uint64_t cycles, retired;
  uint32_t count, milli, ok;
};
extern struct demo_result demo_hello, demo_dhry, demo_cm;
/* Run lengths, set before a program starts. */
extern int demo_dhry_runs, demo_cm_iterations;
/* Framebuffer, 8-bit indexed, read from the registers by fb_init(), which
 * the fb_ and con_ functions call on first use. */
extern volatile uint8_t *fb_pixels;
extern int fb_width, fb_height, fb_stride;
/* Screen text: 8x8 glyphs scaled by con_scale (1 below 640 pixels wide,
 * 3 at 1920), con_cols by con_rows cells of con_cell pixels. */
extern int con_scale, con_cell, con_cols, con_rows;
void fb_init(void);
void con_putc(int c);
void con_puts(const char *s);
void con_screen(int enable);
/* Text rows from top down form the text area: con_goto rows count from its
 * top, the text wraps within it, and con_clear fills it. */
void con_window(int top);
void con_clear(uint8_t bg);
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
