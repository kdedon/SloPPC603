/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Doom timedemo on the demo system: doomgeneric's platform functions, the
 * benchmark loop and the result screen. Each pass runs -timedemo demo3 from
 * a fresh start (data copied, BSS cleared); the results of earlier passes
 * survive in an uncleared section. With DOOM_SMOKE_TICS the program stops at
 * that gametic and reports a checksum of the frame and palette.
 *
 * In little-endian mode a word access to address A reaches A ^ 4 and a byte
 * access A ^ 7, so device words are addressed through IO_XOR and screen
 * bytes through PIX_XOR. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "doomgeneric.h"
#include "doomtype.h"
#include "i_video.h"
#include "plat.h"

extern int gametic;
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

#define DOOM_W 320
#define DOOM_H 200
/* Largest screen scale; the copy to the screen is part of each frame. */
#define MAX_SCALE 3
/* Doom palette indices for text. */
#define TEXT_FG 4
#define TEXT_BG 0
#define PASSES_SHOWN 8
#define RESULT_MAGIC 0x444f4f4du
/* demo3's length; a pass of another length has lost sync. */
#define DEMO3_GAMETICS 2134u

extern char __heap_start[], __heap_end[];

const uint8_t *plat_wad;
size_t plat_wad_size;
char *plat_heap_start = __heap_start, *plat_heap_end = __heap_end;

/* Kept across passes: not cleared at start-up. */
static struct {
  uint32_t magic, passes;
  uint32_t gametics[PASSES_SHOWN], realtics[PASSES_SHOWN];
} results __attribute__((section(".noinit")));

static uint32_t fb_base, fb_stride, fb_w, fb_h, scale, pic_x, pic_y, text_y;
static uint32_t mhz;
static char err_line[160];
static size_t err_len;

void plat_restart(void) __attribute__((noreturn));

#ifdef DOOM_SMOKE_TICS
static uint64_t cycles(void)
{
  uint32_t hi, lo;
  do {
    hi = REG(R_CYCLE_HI);
    lo = REG(R_CYCLE_LO);
  } while (hi != REG(R_CYCLE_HI));
  return ((uint64_t)hi << 32) | lo;
}
#endif

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
  REG(R_CONSOLE) = (uint8_t)c;
  if (err) {
    if (c == '\n') err_len = 0;
    else if (err_len + 1 < sizeof err_line) {
      err_line[err_len++] = (char)c;
      err_line[err_len] = 0;
    }
  }
}

/* ---- screen -------------------------------------------------------------------- */
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

static void screen_init(void)
{
  fb_base = REG(R_FB_ADDR);
  fb_stride = REG(R_FB_STRIDE);
  fb_w = REG(R_FB_SIZE) >> 16;
  fb_h = REG(R_FB_SIZE) & 0xffff;
  scale = 1;
  while (scale < MAX_SCALE && (scale + 1) * DOOM_W <= fb_w && (scale + 1) * DOOM_H + 8 * 9 * (scale + 1) <= fb_h)
    scale++;
  pic_x = (fb_w - scale * DOOM_W) / 2 & ~3u;
  pic_y = 0;
  text_y = scale * DOOM_H + 4 * scale;
  fill(0, fb_h, TEXT_BG);
}

static void show_results(void)
{
  char line[64];
  snprintf(line, sizeof line, "Doom timedemo demo3, pass %lu", (unsigned long)results.passes + 1);
  text(0, 0, line);
  uint32_t first = results.passes > PASSES_SHOWN ? results.passes - PASSES_SHOWN : 0;
  for (uint32_t p = first; p < results.passes; p++) {
    uint32_t i = p % PASSES_SHOWN, g = results.gametics[i], r = results.realtics[i];
    uint32_t fps10 = r ? (g * 350u + r / 2) / r : 0;
    snprintf(line, sizeof line, "%3lu: %5lu gametics %6lu realtics %4lu.%lu fps%s",
             (unsigned long)p + 1, (unsigned long)g, (unsigned long)r,
             (unsigned long)fps10 / 10, (unsigned long)fps10 % 10,
             g == DEMO3_GAMETICS ? "" : " DESYNC");
    text(0, 1 + p - first, line);
  }
}

/* ---- doomgeneric ----------------------------------------------------------------- */
void DG_Init(void) {}

void DG_DrawFrame(void)
{
  if (palette_changed) {
    for (int i = 0; i < 256; i++)
      REG(R_PALETTE(i)) = (uint32_t)colors[i].r << 16 | (uint32_t)colors[i].g << 8 | colors[i].b;
    palette_changed = false;
  }
  const uint8_t *src = DG_ScreenBuffer;
  for (uint32_t y = 0; y < DOOM_H; y++, src += DOOM_W)
    for (uint32_t r = 0; r < scale; r++) {
      uint32_t row = fb_base + (pic_y + y * scale + r) * fb_stride + pic_x;
      if (scale == 1) {
        for (uint32_t x = 0; x < DOOM_W; x += 4) {
          uint32_t w = (uint32_t)src[x] << 24 | (uint32_t)src[x + 1] << 16 |
                       (uint32_t)src[x + 2] << 8 | src[x + 3];
          *(volatile uint32_t *)((row + x) ^ IO_XOR) = w;
        }
      } else {
        uint32_t w = 0, n = 0, addr = row;
        for (uint32_t x = 0; x < DOOM_W; x++)
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

void DG_SleepMs(uint32_t ms) { plat_sleep_us(ms * 1000u); }
uint32_t DG_GetTicksMs(void) { return (uint32_t)(plat_micros() / 1000u); }
int DG_GetKey(int *pressed, unsigned char *key) { (void)pressed; (void)key; return 0; }
void DG_SetWindowTitle(const char *title) { (void)title; }

/* ---- results ---------------------------------------------------------------------- */
#ifdef DOOM_SMOKE_TICS
static uint32_t crc32(uint32_t crc, const uint8_t *p, size_t n)
{
  crc = ~crc;
  while (n--) {
    crc ^= *p++;
    for (int k = 0; k < 8; k++) crc = crc >> 1 ^ (0xedb88320u & -(crc & 1));
  }
  return ~crc;
}
#endif

static void halt(uint32_t code) __attribute__((noreturn));
static void halt(uint32_t code)
{
  REG(R_EXIT) = code;
  __asm__ volatile("sync");
  for (;;) ;
}

static int parse_uint(const char **s, uint32_t *v)
{
  const char *p = *s;
  *v = 0;
  while (*p >= '0' && *p <= '9') *v = *v * 10 + (uint32_t)(*p++ - '0');
  if (p == *s) return 0;
  *s = p;
  return 1;
}

/* The engine ends a timedemo with I_Error("timed %i gametics in %i realtics
 * ..."), which prints it to stderr and exits; this starts the next pass. */
void exit(int code)
{
  const char *s = err_line;
  uint32_t g, r;
  if (!strncmp(s, "timed ", 6) && (s += 6, parse_uint(&s, &g)) && !strncmp(s, " gametics in ", 13) &&
      (s += 13, parse_uint(&s, &r)) && r) {
    uint32_t i = results.passes % PASSES_SHOWN;
    uint32_t fps10 = (g * 350u + r / 2) / r;
    results.gametics[i] = g;
    results.realtics[i] = r;
    results.passes++;
    printf("doom: pass %lu gametics %lu realtics %lu fps %lu.%lu%s\n", (unsigned long)results.passes,
           (unsigned long)g, (unsigned long)r, (unsigned long)fps10 / 10, (unsigned long)fps10 % 10,
           g == DEMO3_GAMETICS ? "" : " desync");
    plat_restart();
  }
  printf("doom: exit %d\n", code);
  text_y = 0;
  text(0, 0, "Doom stopped:");
  text(0, 1, err_line);
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

  const uint8_t *wad = (const uint8_t *)PLAT_WAD_ADDR;
  if (memcmp(wad, "IWAD", 4)) {
    printf("doom: no IWAD at %08x (Load WAD%s)\n", PLAT_WAD_ADDR,
#ifdef __LITTLE_ENDIAN__
           " (little-endian)"
#else
           ""
#endif
    );
    text(0, 2, "No IWAD loaded: use Load WAD, then reload the program");
    halt(0xd0000001u);
  }
  /* The directory ends the file: offset 8, 16 bytes per lump from offset 4. */
  uint32_t lumps = wad[4] | wad[5] << 8 | wad[6] << 16 | (uint32_t)wad[7] << 24;
  uint32_t dir = wad[8] | wad[9] << 8 | wad[10] << 16 | (uint32_t)wad[11] << 24;
  plat_wad = wad;
  plat_wad_size = dir + 16u * lumps;
  if (plat_wad_size > PLAT_WAD_MAX) halt(0xd0000002u);

  static char *argv[] = {"doom", "-iwad", PLAT_WAD_NAME, "-timedemo", "demo3", "-nogui", NULL};
  doomgeneric_Create(6, argv);
#ifdef DOOM_SMOKE_TICS
  uint64_t start = 0;
  uint32_t start_tic = 0;
#endif
  for (;;) {
    doomgeneric_Tick();
#ifdef DOOM_SMOKE_TICS
    if (!start && gametic >= 3) {
      start = cycles();
      start_tic = (uint32_t)gametic;
    }
    if (gametic >= DOOM_SMOKE_TICS) {
      uint64_t span = cycles() - start;
      uint8_t pal[768];
      for (int i = 0; i < 256; i++) {
        pal[3 * i] = colors[i].r;
        pal[3 * i + 1] = colors[i].g;
        pal[3 * i + 2] = colors[i].b;
      }
      uint32_t crc = crc32(crc32(0, DG_ScreenBuffer, DOOM_W * DOOM_H), pal, sizeof pal);
      uint32_t tics = (uint32_t)gametic - start_tic;
      printf("doom: gametic %d frame crc %08lx\n", gametic, (unsigned long)crc);
      printf("doom: %lu cycles per gametic over gametics %lu-%d\n",
             (unsigned long)(span / (tics ? tics : 1)), (unsigned long)start_tic, gametic);
      halt(0);
    }
#endif
  }
}
