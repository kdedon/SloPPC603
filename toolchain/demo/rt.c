/* SPDX-License-Identifier: GPL-2.0-or-later
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

void perf_start(void)
{
  SOC_PERF_CTRL = 2;
  SOC_PERF_CTRL = 1;
}

void perf_stop(void) { SOC_PERF_CTRL = 0; }

static void perf_line(const char *label, uint64_t count, uint64_t retired)
{
  uint64_t milli = count * 1000 / retired;
  printf("perf %-16s %10llu %2lu.%03lu\n", label, (unsigned long long)count,
         (unsigned long)(milli / 1000), (unsigned long)(milli % 1000));
}

const char *const perf_short[SOC_PERF_SLOTS] = {
  "disp", "fetch", "icmiss", "brref", "exref", "drbr", "drmem", "droth",
  "spec", "lsu", "dcmiss", "cqfull", "rsfull", "flags", "other"};

void perf_add(struct perf_totals *t)
{
  t->cycles += SOC_PERF_CYCLES;
  t->retired += SOC_PERF_RETIRED;
  t->iq_full += SOC_PERF_IQ_FULL;
  t->branches += SOC_PERF_BRANCHES;
  t->memory += SOC_PERF_MEMORY;
  t->redirects += SOC_PERF_REDIRECTS;
  for (int n = 0; n < SOC_PERF_SLOTS; n++) t->slot[n] += SOC_PERF_SLOT(n);
}

void perf_brief_totals(const struct perf_totals *t, struct demo_result *r)
{
  uint64_t retired = t->retired ? t->retired : 1;
  for (int k = 0; k < 3; k++) {
    uint64_t best = 0;
    int slot = 0;
    for (int n = 1; n < SOC_PERF_SLOTS; n++) {
      int taken = 0;
      for (int j = 0; j < k; j++) taken |= r->stall[j] == n;
      if (!taken && t->slot[n] > best) {
        best = t->slot[n];
        slot = n;
      }
    }
    r->stall[k] = (uint8_t)slot;
    r->stall_cpi[k] = (uint16_t)(best * 100 / retired);
  }
}

void perf_brief(struct demo_result *r)
{
  struct perf_totals t = {0};
  perf_add(&t);
  perf_brief_totals(&t, r);
}

void perf_print(const char *name, const struct perf_totals *t)
{
  static const char *const slot[SOC_PERF_SLOTS] = {
    "dispatch", "fetch_empty", "icache_miss", "branch_refetch",
    "except_refetch", "drain_branch", "drain_memory", "drain_other",
    "special_busy", "lsu_busy", "dcache_miss", "cq_full", "rs_full",
    "flags_wait", "other"};
  uint64_t retired = t->retired ? t->retired : 1, sum = 0;
  printf("perf %s: cycles %llu retired %llu\n", name, (unsigned long long)t->cycles,
         (unsigned long long)t->retired);
  perf_line("cpi", t->cycles, retired);
  for (int n = 0; n < SOC_PERF_SLOTS; n++) {
    sum += t->slot[n];
    perf_line(slot[n], t->slot[n], retired);
  }
  perf_line("iq_full", t->iq_full, retired);
  perf_line("branches", t->branches, retired);
  perf_line("loads_stores", t->memory, retired);
  perf_line("redirects", t->redirects, retired);
  if (sum != t->cycles) fail("perf slot counts do not sum to cycles");
}

void perf_report(const char *name)
{
  struct perf_totals t = {0};
  perf_add(&t);
  perf_print(name, &t);
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

volatile uint8_t *fb_pixels;
int fb_width, fb_height, fb_stride;
int con_scale = 1, con_cell = 8, con_cols, con_rows;

void fb_init(void)
{
  fb_pixels = (volatile uint8_t *)SOC_FB_ADDR;
  fb_stride = (int)SOC_FB_STRIDE;
  fb_width = (int)(SOC_FB_SIZE >> 16);
  fb_height = (int)(SOC_FB_SIZE & 0xffff);
  con_scale = fb_width >= 1280 ? 3 : fb_width >= 640 ? 2 : 1;
  con_cell = 8 * con_scale;
  con_cols = fb_width / con_cell;
  con_rows = fb_height / con_cell;
}

void fb_rect(int x, int y, int w, int h, uint8_t color)
{
  uint32_t fill = color * 0x01010101u;
  if (!fb_width) fb_init();
  for (int row = y; row < y + h; row++) {
    volatile uint8_t *p = fb_pixels + row * fb_stride + x;
    int n = w;
    while (n > 0 && ((uintptr_t)p & 3)) { *p++ = color; n--; }
    while (n >= 4) { *(volatile uint32_t *)p = fill; p += 4; n -= 4; }
    while (n > 0) { *p++ = color; n--; }
  }
}

static void con_forget(int top);

void fb_clear(uint8_t color)
{
  if (!fb_width) fb_init();
  fb_rect(0, 0, fb_width, fb_height, color);
  con_forget(0);
}

/* Entries 0-15: a VGA-like text palette; 16-255: a colour ramp through
 * the gradient stops below. */
void fb_palette_default(void)
{
  static const uint32_t base[16] = {
    0x000000, 0x0000aa, 0x00aa00, 0x00aaaa, 0xaa0000, 0xaa00aa, 0xaa5500, 0xaaaaaa,
    0x555555, 0x5555ff, 0x55ff55, 0x55ffff, 0xff5555, 0xff55ff, 0xffff55, 0xffffff};
  for (int i = 0; i < 16; i++) SOC_PALETTE(i) = base[i];
  /* Position (0-239) and colour of each stop: deep blue, azure, white,
   * gold, crimson, violet, near black. */
  static const uint32_t stop[7][2] = {
    {0, 0x000764}, {42, 0x206bcb}, {84, 0xedffff}, {126, 0xffaa00},
    {168, 0xb3122e}, {210, 0x5a1a8c}, {239, 0x0a0214}};
  for (int i = 16; i < 256; i++) {
    uint32_t t = (uint32_t)(i - 16), k = 0, rgb = 0;
    while (k < 5 && t >= stop[k + 1][0]) k++;
    uint32_t span = stop[k + 1][0] - stop[k][0], f = t - stop[k][0];
    for (int sh = 16; sh >= 0; sh -= 8) {
      uint32_t c0 = (stop[k][1] >> sh) & 0xff, c1 = (stop[k + 1][1] >> sh) & 0xff;
      rgb |= ((c0 * (span - f) + c1 * f) / span) << sh;
    }
    SOC_PALETTE(i) = rgb;
  }
}

/* ---- console -------------------------------------------------------------- */

static int con_on, con_col, con_row, con_top, con_echo = 1;
static uint8_t con_fg = 15, con_bg = 0;

void con_screen(int enable) { con_on = enable; }
void con_console(int enable) { con_echo = enable; }
void con_color(uint8_t fg, uint8_t bg) { con_fg = fg; con_bg = bg; }

void con_goto(int col, int row)
{
  con_col = col;
  con_row = con_top + row;
}

void con_window(int top)
{
  con_top = top;
  con_goto(0, 0);
}

/* The framebuffer cannot be read back, so the console keeps a copy of the
 * text it drew, with colours 0-15: scrolling redraws the cells that change.
 * A screen larger than the copy wraps to the top of the text area. */
#define CON_MAX_COLS 80
#define CON_MAX_ROWS 48
struct con_char {
  uint8_t c, color; /* background in the high nibble */
};
static struct con_char con_text[CON_MAX_ROWS][CON_MAX_COLS];
static uint8_t con_len[CON_MAX_ROWS];

static int con_scrolls(void) { return con_cols <= CON_MAX_COLS && con_rows <= CON_MAX_ROWS; }

static void con_forget(int top)
{
  for (int r = top; r < CON_MAX_ROWS; r++) con_len[r] = 0;
}

void con_clear(uint8_t bg)
{
  if (!fb_width) fb_init();
  fb_rect(0, con_top * con_cell, fb_width, fb_height - con_top * con_cell, bg);
  con_forget(con_top);
  con_goto(0, 0);
}

/* One glyph row at a time: each font bit is con_scale pixels wide and each
 * row con_scale lines tall, stored as words (a cell is a multiple of four
 * pixels wide and starts on a word boundary). */
static void draw_glyph(int col, int row, int c, uint8_t fg, uint8_t bg)
{
  const uint8_t *g = font8x8[(c < 0x20 || c > 0x7e) ? 0 : c - 0x20];
  int s = con_scale, words = con_cell / 4;
  volatile uint8_t *p = fb_pixels + row * con_cell * fb_stride + col * con_cell;
  for (int y = 0; y < 8; y++) {
    uint32_t line[6];
    for (int k = 0; k < words; k++) {
      uint32_t v = 0;
      for (int b = 0; b < 4; b++) {
        int px = (4 * k + b) / s;
        v = (v << 8) | ((g[y] << px) & 0x80 ? fg : bg);
      }
      line[k] = v;
    }
    for (int r = 0; r < s; r++, p += fb_stride)
      for (int k = 0; k < words; k++) ((volatile uint32_t *)p)[k] = line[k];
  }
}

/* Moves the text area up one row, drawing only the cells that differ. */
static void con_scroll(void)
{
  for (int r = con_top; r < con_rows - 1; r++) {
    struct con_char *to = con_text[r], *from = con_text[r + 1];
    int n = con_len[r] > con_len[r + 1] ? con_len[r] : con_len[r + 1];
    for (int c = 0; c < n; c++) {
      if (c >= con_len[r + 1]) {
        fb_rect(c * con_cell, r * con_cell, (n - c) * con_cell, con_cell, con_bg);
        break;
      }
      if (c < con_len[r] && to[c].c == from[c].c && to[c].color == from[c].color) continue;
      to[c] = from[c];
      draw_glyph(c, r, to[c].c, to[c].color & 15, to[c].color >> 4);
    }
    con_len[r] = con_len[r + 1];
  }
}

static void con_newline(void)
{
  con_col = 0;
  if (++con_row >= con_rows) {
    if (con_scrolls() && con_rows - con_top > 1) {
      con_scroll();
      con_row = con_rows - 1;
    } else {
      con_row = con_top;
    }
  }
  /* Clear the line about to be written. */
  fb_rect(0, con_row * con_cell, fb_width, con_cell, con_bg);
  if (con_row < CON_MAX_ROWS) con_len[con_row] = 0;
}

void con_putc(int c)
{
  if (con_echo) SOC_CONSOLE = (uint8_t)c;
  if (!con_on) return;
  if (!fb_width) fb_init();
  if (c == '\n') { con_newline(); return; }
  if (c == '\r') { con_col = 0; return; }
  if (con_col == con_cols) con_newline();
  if (con_scrolls()) {
    /* Cells skipped by con_goto hold the background. */
    uint8_t color = (uint8_t)((con_bg << 4) | (con_fg & 15));
    for (int k = con_len[con_row]; k < con_col; k++)
      con_text[con_row][k] = (struct con_char){' ', color};
    con_text[con_row][con_col] = (struct con_char){(uint8_t)c, color};
    if (con_len[con_row] <= con_col) con_len[con_row] = (uint8_t)(con_col + 1);
  }
  draw_glyph(con_col++, con_row, c, con_fg, con_bg);
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
