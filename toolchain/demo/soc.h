/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
#ifndef DEMO_SOC_H
#define DEMO_SOC_H

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

/* Memory map (docs/DEMO_SOC.md). The framebuffer's address and geometry
 * come from the registers (fb_init). */
#define SOC_IO_BASE 0xf0100000u
/* Clock when the MODE register reports none (soc_clock_hz). */
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
/* Clock in MHz (31:16), FPU present (8) and host mode bits (7:0). */
#define SOC_MODE SOC_REG(0x30)
#define SOC_MODE_FPU 0x100u

static inline uint32_t soc_clock_hz(void)
{
  uint32_t mhz = SOC_MODE >> 16;
  return mhz ? mhz * 1000000u : SOC_CLOCK_HZ;
}
#define SOC_TENURES SOC_REG(0x34)
#define SOC_RETIRED_LO SOC_REG(0x38)
#define SOC_RETIRED_HI SOC_REG(0x3c)
/* Host input, read-only: bits 3:0 right, left, down, up; 4 A (or Enter);
 * 5 B (or Esc); 31 set when an input device is present (MiSTer). */
#define SOC_INPUT SOC_REG(0x40)
#define SOC_IN_RIGHT 0x01u
#define SOC_IN_LEFT 0x02u
#define SOC_IN_DOWN 0x04u
#define SOC_IN_UP 0x08u
#define SOC_IN_A 0x10u
#define SOC_IN_B 0x20u
#define SOC_IN_PRESENT 0x80000000u
#define SOC_PALETTE(i) SOC_REG(0x400 + 4 * (i))
/* Performance counters: PERF_CTRL bit 0 runs them, writing bit 1 clears. */
#define SOC_PERF_CTRL SOC_REG(0x100)
#define SOC_PERF_CYCLES SOC_REG(0x104)
#define SOC_PERF_RETIRED SOC_REG(0x108)
#define SOC_PERF_IQ_FULL SOC_REG(0x10c)
#define SOC_PERF_SLOT(n) SOC_REG(0x110 + 4 * (n))
#define SOC_PERF_SLOTS 15
#define SOC_PERF_BRANCHES SOC_REG(0x150)
#define SOC_PERF_MEMORY SOC_REG(0x154)
#define SOC_PERF_REDIRECTS SOC_REG(0x158)


/* Runtime (rt.c). */
uint64_t soc_cycles(void);
uint64_t soc_timebase(void);
uint64_t soc_retired(void);

/* Each program's result for the MiSTer summary: a timed window and its
 * score in thousandths; ok is set when the program's own checks pass. */
struct demo_result {
  uint64_t cycles, retired;
  uint32_t count, milli, ok;
  /* The largest non-dispatch slot causes and their CPI in hundredths. */
  uint8_t stall[3];
  uint16_t stall_cpi[3];
};
extern struct demo_result demo_hello, demo_dhry, demo_cm;
/* FPU image only: Whetstone (count in thousands of its instructions) and
 * the double-precision Mandelbrot. */
extern struct demo_result demo_whet, demo_fpmb;
/* Run lengths, set before a program starts. */
extern int demo_dhry_runs, demo_cm_iterations, demo_whet_full;
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
/* Whether screen text is also written to the console register (default). */
void con_console(int enable);
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
/* Performance counters over a measured window; the report prints the
 * cycles per retired instruction by dispatch-slot cause. */
void perf_start(void);
void perf_stop(void);
void perf_report(const char *name);
/* Fills r's stall fields from the stopped counters. */
void perf_brief(struct demo_result *r);
extern const char *const perf_short[SOC_PERF_SLOTS];

extern const uint8_t font8x8[95][8];

#endif
