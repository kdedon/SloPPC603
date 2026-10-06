/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Quake timedemo on the demo system: the platform hooks of qport.c and the
 * result screen. pak0.pak is read in place where Load data put it. The
 * results of earlier passes are kept in an uncleared section.
 *
 * In little-endian mode a word access to address A reaches A ^ 4 and a byte
 * access A ^ 7, so device words are addressed through IO_XOR and screen
 * bytes through PIX_XOR. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "plat.h"
#include "qport.h"

extern const uint8_t font8x8[95][8];

#ifdef __LITTLE_ENDIAN__
#define IO_XOR 4u
#define PIX_XOR 7u
#else
#define IO_XOR 0u
#define PIX_XOR 0u
#endif

#define IO_BASE 0xf0100000u
#define REG(off) (*(volatile uint32_t *)((IO_BASE + (off)) ^ IO_XOR))
#define R_CYCLE_LO 0x08
#define R_CYCLE_HI 0x0c
#define R_CONSOLE 0x10
#define R_EXIT 0x14
#define R_FB_ADDR 0x20
#define R_FB_STRIDE 0x24
#define R_FB_SIZE 0x28
#define R_MODE 0x30
#define R_PALETTE(i) (0x400 + 4 * (i))

#define MAX_SCALE 3
/* Quake palette indices for text. */
#define TEXT_FG 15
#define TEXT_BG 0
#define PASSES_SHOWN 8
#define RESULT_MAGIC 0x5155414bu

extern char __heap_start[], __heap_end[];

const uint8_t *plat_wad;
size_t plat_wad_size;
char *plat_heap_start = __heap_start, *plat_heap_end = __heap_end;

static struct {
  uint32_t magic, passes;
  uint32_t frames[PASSES_SHOWN], ms[PASSES_SHOWN], fps10[PASSES_SHOWN], ok[PASSES_SHOWN];
} results __attribute__((section(".noinit")));

static uint32_t fb_base, fb_stride, fb_w, fb_h, scale, pic_x, text_y;
static uint32_t mhz;

uint64_t plat_cycles(void)
{
  uint32_t hi, lo;
  do {
    hi = REG(R_CYCLE_HI);
    lo = REG(R_CYCLE_LO);
  } while (hi != REG(R_CYCLE_HI));
  return ((uint64_t)hi << 32) | lo;
}

static uint64_t timebase(void)
{
  uint32_t hi, lo, again;
  do {
    __asm__ volatile("mftbu %0" : "=r"(hi));
    __asm__ volatile("mftb %0" : "=r"(lo));
    __asm__ volatile("mftbu %0" : "=r"(again));
  } while (hi != again);
  return ((uint64_t)hi << 32) | lo;
}

/* The time base runs at a quarter of the processor clock. */
uint64_t plat_micros(void) { return timebase() * 4u / mhz; }

void plat_sleep_us(uint32_t us)
{
  uint64_t end = plat_micros() + us;
  while (plat_micros() < end) ;
}

void plat_putc(int c, int err)
{
  (void)err;
  REG(R_CONSOLE) = (uint8_t)c;
}

/* ---- screen ------------------------------------------------------------------- */
static inline void put_pixel(uint32_t x, uint32_t y, uint8_t c)
{
  *(volatile uint8_t *)((fb_base + y * fb_stride + x) ^ PIX_XOR) = c;
}

static void fill(uint32_t y0, uint32_t h, uint8_t c)
{
  uint32_t w = c * 0x01010101u;
  for (uint32_t y = y0; y < y0 + h && y < fb_h; y++)
    for (uint32_t x = 0; x + 4 <= fb_w; x += 4)
      *(volatile uint32_t *)((fb_base + y * fb_stride + x) ^ IO_XOR) = w;
}

static void text(uint32_t col, uint32_t row, const char *s)
{
  uint32_t s8 = scale, cell = 8 * s8;
  for (; *s; s++, col++) {
    int ch = *s < 0x20 || *s > 0x7e ? 0 : *s - 0x20;
    for (uint32_t y = 0; y < cell; y++)
      for (uint32_t x = 0; x < cell; x++) {
        uint32_t px = col * cell + x, py = text_y + row * cell + y;
        if (px < fb_w && py < fb_h)
          put_pixel(px, py, (font8x8[ch][y / s8] << (x / s8)) & 0x80 ? TEXT_FG : TEXT_BG);
      }
  }
}

static void set_palette(const uint8_t *pal)
{
  for (int i = 0; i < 256; i++)
    REG(R_PALETTE(i)) = (uint32_t)pal[3 * i] << 16 | (uint32_t)pal[3 * i + 1] << 8 | pal[3 * i + 2];
}

static void screen_init(void)
{
  static const uint8_t grey[768] = {[45] = 0xeb, [46] = 0xeb, [47] = 0xeb};
  fb_base = REG(R_FB_ADDR);
  fb_stride = REG(R_FB_STRIDE);
  fb_w = REG(R_FB_SIZE) >> 16;
  fb_h = REG(R_FB_SIZE) & 0xffff;
  scale = 1;
  while (scale < MAX_SCALE && (scale + 1) * QPORT_W <= fb_w &&
         (scale + 1) * QPORT_H + 8 * 10 * (scale + 1) <= fb_h)
    scale++;
  pic_x = (fb_w - scale * QPORT_W) / 2 & ~3u;
  text_y = scale * QPORT_H + 4 * scale;
  fill(0, fb_h, TEXT_BG);
  set_palette(grey);
}

static void show_results(void)
{
  char line[64];
  snprintf(line, sizeof line, "Quake timedemo demo1, pass %lu", (unsigned long)results.passes + 1);
  text(0, 0, line);
  uint32_t first = results.passes > PASSES_SHOWN ? results.passes - PASSES_SHOWN : 0;
  for (uint32_t p = first; p < results.passes; p++) {
    uint32_t i = p % PASSES_SHOWN;
    snprintf(line, sizeof line, "%3lu: %4lu frames %4lu.%03lu s %4lu.%lu fps%s", (unsigned long)p + 1,
             (unsigned long)results.frames[i], (unsigned long)results.ms[i] / 1000,
             (unsigned long)results.ms[i] % 1000, (unsigned long)results.fps10[i] / 10,
             (unsigned long)results.fps10[i] % 10, results.ok[i] ? "" : " DESYNC");
    text(0, 1 + p - first, line);
  }
}

void plat_frame(const uint8_t *pix, const uint8_t *pal, int pal_changed)
{
  if (pal_changed) set_palette(pal);
  const uint8_t *src = pix;
  for (uint32_t y = 0; y < QPORT_H; y++, src += QPORT_W)
    for (uint32_t r = 0; r < scale; r++) {
      uint32_t row = fb_base + (y * scale + r) * fb_stride + pic_x;
      if (scale == 1) {
        for (uint32_t x = 0; x < QPORT_W; x += 4) {
          uint32_t w = (uint32_t)src[x] << 24 | (uint32_t)src[x + 1] << 16 |
                       (uint32_t)src[x + 2] << 8 | src[x + 3];
          *(volatile uint32_t *)((row + x) ^ IO_XOR) = w;
        }
      } else {
        uint32_t w = 0, n = 0, addr = row;
        for (uint32_t x = 0; x < QPORT_W; x++)
          for (uint32_t k = 0; k < scale; k++) {
            w = w << 8 | src[x];
            if (++n == 4) {
              *(volatile uint32_t *)(addr ^ IO_XOR) = w;
              addr += 4;
              n = 0;
            }
          }
      }
    }
}

void plat_pass(uint32_t frames, uint32_t ms, uint32_t fps10, int ok)
{
  uint32_t i = results.passes % PASSES_SHOWN;
  results.frames[i] = frames;
  results.ms[i] = ms;
  results.fps10[i] = fps10;
  results.ok[i] = (uint32_t)ok;
  results.passes++;
  printf("quake: pass %lu frames %lu ms %lu fps %lu.%lu%s\n", (unsigned long)results.passes,
         (unsigned long)frames, (unsigned long)ms, (unsigned long)fps10 / 10,
         (unsigned long)fps10 % 10, ok ? "" : " desync");
  show_results();
}

static void halt(uint32_t code) __attribute__((noreturn));
static void halt(uint32_t code)
{
  REG(R_EXIT) = code;
  __asm__ volatile("sync");
  for (;;) ;
}

/* As hex lines on the console, for comparison with the host's frame. */
void plat_dump(const uint8_t *pix, const uint8_t *pal)
{
  static const char hex[] = "0123456789abcdef";
  for (uint32_t off = 0; off < QPORT_W * QPORT_H + 768; off += 64) {
    char line[160], *p = line;
    p += snprintf(line, sizeof line, "quake: frame %05lx ", (unsigned long)off);
    for (uint32_t k = 0; k < 64; k++) {
      uint8_t b = off + k < QPORT_W * QPORT_H ? pix[off + k] : pal[off + k - QPORT_W * QPORT_H];
      *p++ = hex[b >> 4];
      *p++ = hex[b & 15];
    }
    *p = 0;
    puts(line);
  }
}

void plat_stop(const char *error)
{
  if (!error) halt(0);
  text_y = 0;
  text(0, 0, "Quake stopped:");
  text(0, 1, error);
  halt(0xd0000000u);
}

/* The engine's exit paths all end in plat_stop. */
void exit(int code)
{
  printf("quake: exit %d\n", code);
  halt(code ? 0xd0000000u | ((uint32_t)code & 0xffff) : 0);
}

int plat_main(int restarted);
int plat_main(int restarted)
{
  mhz = REG(R_MODE) >> 16;
  if (!mhz) mhz = 50;
  if (!restarted || results.magic != RESULT_MAGIC) {
    results.magic = RESULT_MAGIC;
    results.passes = 0;
  }
  screen_init();
  show_results();

  const uint8_t *pak = (const uint8_t *)PLAT_WAD_ADDR;
  if (memcmp(pak, "PACK", 4)) {
    printf("quake: no pak0.pak at %08x (Load data%s)\n", PLAT_WAD_ADDR,
#ifdef __LITTLE_ENDIAN__
           " (little-endian)"
#else
           ""
#endif
    );
    text(0, 2, "No pak0.pak loaded: use Load data, then reload the program");
    halt(0xd0000001u);
  }
  /* The directory ends the file: its offset and length from offset 4. */
  uint32_t dir = pak[4] | pak[5] << 8 | pak[6] << 16 | (uint32_t)pak[7] << 24;
  uint32_t len = pak[8] | pak[9] << 8 | pak[10] << 16 | (uint32_t)pak[11] << 24;
  plat_wad = pak;
  plat_wad_size = dir + len;
  if (plat_wad_size > PLAT_WAD_MAX) halt(0xd0000002u);
  qport_run();
  return 0;
}
