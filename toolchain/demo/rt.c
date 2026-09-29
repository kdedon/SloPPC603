/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* Freestanding runtime for the demo system: console, formatted output,
 * framebuffer helpers, a bump allocator and the string functions the
 * benchmarks use. */
#include "soc.h"

uint64_t soc_cycles(void)
{
  uint32_t lo = SOC_CYCLE_LO;
  return ((uint64_t)SOC_CYCLE_HI << 32) | lo;
}

uint64_t soc_retired(void)
{
  uint32_t lo = SOC_RETIRED_LO;
  return ((uint64_t)SOC_RETIRED_HI << 32) | lo;
}

struct demo_result demo_hello, demo_dhry, demo_cm;

uint64_t soc_timebase(void)
{
  uint32_t hi, lo, again;
  do {
    __asm__ volatile("mftbu %0" : "=r"(hi));
    __asm__ volatile("mftb %0" : "=r"(lo));
    __asm__ volatile("mftbu %0" : "=r"(again));
  } while (hi != again);
  return ((uint64_t)hi << 32) | lo;
}

/* ---- framebuffer ---------------------------------------------------------- */

void fb_rect(int x, int y, int w, int h, uint8_t color)
{
  uint32_t fill = color * 0x01010101u;
  for (int row = y; row < y + h; row++) {
    volatile uint8_t *p = SOC_FB + row * SOC_FB_WIDTH + x;
    int n = w;
    while (n > 0 && ((uintptr_t)p & 3)) { *p++ = color; n--; }
    while (n >= 4) { *(volatile uint32_t *)p = fill; p += 4; n -= 4; }
    while (n > 0) { *p++ = color; n--; }
  }
}

void fb_clear(uint8_t color)
{
  fb_rect(0, 0, SOC_FB_WIDTH, SOC_FB_HEIGHT, color);
}

/* Entries 0-15: a VGA-like text palette; 16-255: a colour ramp. */
void fb_palette_default(void)
{
  static const uint32_t base[16] = {
    0x000000, 0x0000aa, 0x00aa00, 0x00aaaa, 0xaa0000, 0xaa00aa, 0xaa5500, 0xaaaaaa,
    0x555555, 0x5555ff, 0x55ff55, 0x55ffff, 0xff5555, 0xff55ff, 0xffff55, 0xffffff};
  for (int i = 0; i < 16; i++) SOC_PALETTE(i) = base[i];
  for (int i = 16; i < 256; i++) {
    uint32_t t = (uint32_t)(i - 16) * 6;  /* 0..1434 over six segments */
    uint32_t seg = t / 240, f = (t % 240) * 255 / 239, r, g, b;
    switch (seg) {
    case 0: r = 0; g = 0; b = f; break;
    case 1: r = 0; g = f; b = 255; break;
    case 2: r = 0; g = 255; b = 255 - f; break;
    case 3: r = f; g = 255; b = 0; break;
    case 4: r = 255; g = 255 - f; b = 0; break;
    default: r = 255; g = f; b = f; break;
    }
    SOC_PALETTE(i) = (r << 16) | (g << 8) | b;
  }
}

/* ---- console -------------------------------------------------------------- */

#define COLS (SOC_FB_WIDTH / 8)
#define ROWS (SOC_FB_HEIGHT / 8)

static int con_on, con_col, con_row;
static uint8_t con_fg = 15, con_bg = 0;

void con_screen(int enable) { con_on = enable; }
void con_goto(int col, int row) { con_col = col; con_row = row; }
void con_color(uint8_t fg, uint8_t bg) { con_fg = fg; con_bg = bg; }

static void draw_glyph(int col, int row, int c)
{
  const uint8_t *g = font8x8[(c < 0x20 || c > 0x7e) ? 0 : c - 0x20];
  volatile uint32_t *p = (volatile uint32_t *)(SOC_FB + row * 8 * SOC_FB_WIDTH + col * 8);
  for (int y = 0; y < 8; y++, p += SOC_FB_WIDTH / 4) {
    uint32_t w[2];
    for (int half = 0; half < 2; half++) {
      uint32_t v = 0;
      for (int x = 0; x < 4; x++)
        v = (v << 8) | ((g[y] << (4 * half + x)) & 0x80 ? con_fg : con_bg);
      w[half] = v;
    }
    p[0] = w[0];
    p[1] = w[1];
  }
}

static void con_newline(void)
{
  con_col = 0;
  if (++con_row == ROWS) con_row = 0;
  /* The screen wraps: clear the line about to be written. */
  fb_rect(0, con_row * 8, SOC_FB_WIDTH, 8, con_bg);
}

void con_putc(int c)
{
  SOC_CONSOLE = (uint8_t)c;
  if (!con_on) return;
  if (c == '\n') { con_newline(); return; }
  if (c == '\r') { con_col = 0; return; }
  if (con_col == COLS) con_newline();
  draw_glyph(con_col++, con_row, c);
}

void con_puts(const char *s)
{
  while (*s) con_putc(*s++);
}

/* ---- formatted output ----------------------------------------------------- */

typedef struct {
  char *buf;
  size_t size, len;
} sink_t;

static void emit(sink_t *s, char c)
{
  if (s->buf) {
    if (s->len + 1 < s->size) s->buf[s->len] = c;
  } else
    con_putc(c);
  s->len++;
}

static void emit_num(sink_t *s, unsigned long long v, unsigned base, int upper,
                     int neg, int width, int zero, int left)
{
  char tmp[24];
  const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
  int n = 0;
  do { tmp[n++] = digits[v % base]; v /= base; } while (v);
  int len = n + neg;
  if (neg && zero) emit(s, '-');
  if (!left)
    for (; width > len; width--) emit(s, zero ? '0' : ' ');
  if (neg && !zero) emit(s, '-');
  while (n) emit(s, tmp[--n]);
  if (left)
    for (; width > len; width--) emit(s, ' ');
}

static int format(sink_t *s, const char *fmt, va_list ap)
{
  for (; *fmt; fmt++) {
    if (*fmt != '%') { emit(s, *fmt); continue; }
    int zero = 0, left = 0, width = 0, prec = -1, lng = 0;
    for (;; fmt++) {
      if (fmt[1] == '0') zero = 1;
      else if (fmt[1] == '-') left = 1;
      else break;
    }
    while (fmt[1] >= '0' && fmt[1] <= '9') width = width * 10 + (*++fmt - '0');
    if (fmt[1] == '.') {
      fmt++;
      prec = 0;
      while (fmt[1] >= '0' && fmt[1] <= '9') prec = prec * 10 + (*++fmt - '0');
    }
    while (fmt[1] == 'l') { lng++; fmt++; }
    switch (*++fmt) {
    case 'd': case 'i': {
      long long v = lng > 1 ? va_arg(ap, long long) : lng ? va_arg(ap, long) : va_arg(ap, int);
      emit_num(s, v < 0 ? -(unsigned long long)v : (unsigned long long)v, 10, 0, v < 0, width, zero, left);
      break;
    }
    case 'u': case 'x': case 'X': {
      unsigned long long v = lng > 1 ? va_arg(ap, unsigned long long)
                           : lng ? va_arg(ap, unsigned long) : va_arg(ap, unsigned);
      emit_num(s, v, *fmt == 'u' ? 10 : 16, *fmt == 'X', 0, width, zero, left);
      break;
    }
    case 'p':
      emit(s, '0'); emit(s, 'x');
      emit_num(s, (uintptr_t)va_arg(ap, void *), 16, 0, 0, 8, 1, 0);
      break;
    case 'c':
      emit(s, (char)va_arg(ap, int));
      break;
    case 's': {
      const char *str = va_arg(ap, const char *);
      int len = (int)strlen(str);
      if (prec >= 0 && prec < len) len = prec;
      if (!left) for (; width > len; width--) emit(s, ' ');
      for (int i = 0; i < len; i++) emit(s, str[i]);
      if (left) for (; width > len; width--) emit(s, ' ');
      break;
    }
    case 'f':
      /* No floating point here: consume the argument, print a marker. */
      (void)va_arg(ap, double);
      emit(s, '?');
      break;
    case '%':
      emit(s, '%');
      break;
    default:
      emit(s, '%');
      emit(s, *fmt);
      break;
    }
  }
  return (int)s->len;
}

int vprintf(const char *fmt, va_list ap)
{
  sink_t s = {0, 0, 0};
  return format(&s, fmt, ap);
}

int printf(const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  int n = vprintf(fmt, ap);
  va_end(ap);
  return n;
}

int snprintf(char *buf, size_t size, const char *fmt, ...)
{
  sink_t s = {buf, size, 0};
  va_list ap;
  va_start(ap, fmt);
  format(&s, fmt, ap);
  va_end(ap);
  if (size) buf[s.len < size ? s.len : size - 1] = 0;
  return (int)s.len;
}

void fail(const char *what)
{
  printf("FAIL: %s\n", what);
  SOC_EXIT = 1;
  for (;;) {}
}

/* ---- memory and strings --------------------------------------------------- */

extern char __heap_start[], __heap_end[];
static char *heap_next = __heap_start;

void *malloc(size_t size)
{
  char *p = heap_next;
  size = (size + 7) & ~(size_t)7;
  if ((size_t)(__heap_end - p) < size) fail("out of heap");
  heap_next = p + size;
  return p;
}

void *memcpy(void *dst, const void *src, size_t n)
{
  uint8_t *d = dst;
  const uint8_t *s = src;
  if ((((uintptr_t)d | (uintptr_t)s) & 3) == 0) {
    for (; n >= 4; n -= 4, d += 4, s += 4) *(uint32_t *)d = *(const uint32_t *)s;
  }
  while (n--) *d++ = *s++;
  return dst;
}

void *memset(void *dst, int c, size_t n)
{
  uint8_t *d = dst;
  while (n--) *d++ = (uint8_t)c;
  return dst;
}

int memcmp(const void *a, const void *b, size_t n)
{
  const uint8_t *x = a, *y = b;
  for (; n; n--, x++, y++)
    if (*x != *y) return *x - *y;
  return 0;
}

char *strcpy(char *dst, const char *src)
{
  char *d = dst;
  while ((*d++ = *src++)) {}
  return dst;
}

int strcmp(const char *a, const char *b)
{
  while (*a && *a == *b) { a++; b++; }
  return (unsigned char)*a - (unsigned char)*b;
}

size_t strlen(const char *s)
{
  size_t n = 0;
  while (s[n]) n++;
  return n;
}
