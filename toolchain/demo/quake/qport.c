/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Quake timedemo port: the engine's video and system layers over stdio and
 * the platform hooks in qport.h, and the benchmark loop. Each pass runs
 * "timedemo demo1"; a pass whose frame count differs from DEMO1_FRAMES has
 * lost sync. With QUAKE_SMOKE_FRAMES the clock advances a fixed step per
 * frame, so every build renders the same frames, and the run stops at that
 * many timedemo frames with a checksum of the picture and palette. */
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "quakedef.h"
#include "d_local.h"
#include "quakegeneric.h"
#include "qport.h"

/* demo1 of the v1.06 shareware pak0.pak, one demo message per frame. */
#define DEMO1_FRAMES 970u
#define SMOKE_STEP (1.0 / 20.0)

viddef_t vid;
static byte vid_buffer[QPORT_W * QPORT_H];
static short zbuffer[QPORT_W * QPORT_H];
static byte *surfcache;
static byte palette[768];
static int palette_changed;
static double clock_now;

/* ---- video ------------------------------------------------------------------ */
void VID_SetPalette(unsigned char *p)
{
  memcpy(palette, p, sizeof palette);
  palette_changed = 1;
}

void VID_ShiftPalette(unsigned char *p) { VID_SetPalette(p); }

void VID_Init(unsigned char *p)
{
  vid.maxwarpwidth = vid.width = vid.conwidth = QPORT_W;
  vid.maxwarpheight = vid.height = vid.conheight = QPORT_H;
  vid.aspect = 1.0;
  vid.numpages = 1;
  vid.colormap = host_colormap;
  vid.fullbright = 256 - LittleLong(*((int *)vid.colormap + 2048));
  vid.buffer = vid.conbuffer = vid_buffer;
  vid.rowbytes = vid.conrowbytes = QPORT_W;
  d_pzbuffer = zbuffer;
  int size = D_SurfaceCacheForRes(QPORT_W, QPORT_H);
  surfcache = malloc(size);
  if (!surfcache) Sys_Error("no memory for the surface cache");
  D_InitCaches(surfcache, size);
  VID_SetPalette(p);
}

void VID_Shutdown(void) {}

void VID_Update(vrect_t *rects)
{
  (void)rects;
  plat_frame(vid_buffer, palette, palette_changed);
  palette_changed = 0;
}

void D_BeginDirectRect(int x, int y, byte *pbitmap, int width, int height)
{
  (void)x, (void)y, (void)pbitmap, (void)width, (void)height;
}

void D_EndDirectRect(int x, int y, int width, int height) { (void)x, (void)y, (void)width, (void)height; }

/* ---- input: none ------------------------------------------------------------ */
int QG_GetKey(int *down, int *key)
{
  (void)down, (void)key;
  return 0;
}

void QG_GetMouseMove(int *x, int *y) { *x = *y = 0; }
void QG_GetJoyAxes(float *axes) { memset(axes, 0, QUAKEGENERIC_JOY_MAX_AXES * sizeof *axes); }

/* ---- system ----------------------------------------------------------------- */
#define MAX_HANDLES 10
static FILE *handles[MAX_HANDLES];

int Sys_FileOpenRead(char *path, int *hndl)
{
  FILE *f = fopen(path, "rb");
  *hndl = -1;
  if (!f) return -1;
  for (int i = 1; i < MAX_HANDLES; i++)
    if (!handles[i]) {
      handles[i] = f;
      *hndl = i;
      fseek(f, 0, SEEK_END);
      int len = (int)ftell(f);
      fseek(f, 0, SEEK_SET);
      return len;
    }
  Sys_Error("out of handles");
  return -1;
}

int Sys_FileOpenWrite(char *path)
{
  (void)path;
  return -1;
}

void Sys_FileClose(int h)
{
  fclose(handles[h]);
  handles[h] = NULL;
}

void Sys_FileSeek(int h, int pos) { fseek(handles[h], pos, SEEK_SET); }
int Sys_FileRead(int h, void *dest, int count) { return (int)fread(dest, 1, count, handles[h]); }
int Sys_FileWrite(int h, void *data, int count)
{
  (void)h, (void)data, (void)count;
  return 0;
}

int Sys_FileTime(char *path)
{
  FILE *f = fopen(path, "rb");
  if (!f) return -1;
  fclose(f);
  return 1;
}

void Sys_mkdir(char *path) { (void)path; }
void Sys_MakeCodeWriteable(unsigned long start, unsigned long len) { (void)start, (void)len; }

void Sys_Error(char *error, ...)
{
  char text[256];
  va_list ap;
  va_start(ap, error);
  vsnprintf(text, sizeof text, error, ap);
  va_end(ap);
  printf("quake: error: %s\n", text);
  plat_stop(text);
}

void Sys_Printf(char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  vprintf(fmt, ap);
  va_end(ap);
}

void Sys_Quit(void) { plat_stop(NULL); }

double Sys_FloatTime(void)
{
#ifdef QUAKE_SMOKE_FRAMES
  return clock_now;
#else
  return (double)plat_micros() * 1e-6;
#endif
}

char *Sys_ConsoleInput(void) { return NULL; }
void Sys_Sleep(void) {}
void Sys_SendKeyEvents(void) {}
void Sys_HighFPPrecision(void) {}
void Sys_LowFPPrecision(void) {}

/* ---- benchmark -------------------------------------------------------------- */
static uint32_t crc32(uint32_t crc, const uint8_t *p, size_t n)
{
  crc = ~crc;
  while (n--) {
    crc ^= *p++;
    for (int k = 0; k < 8; k++) crc = crc >> 1 ^ (0xedb88320u & -(crc & 1));
  }
  return ~crc;
}

/* The frame count and time of a finished timedemo pass, as the engine
 * reports them. */
static void pass_done(uint32_t frames, double seconds)
{
  uint32_t ms = (uint32_t)(seconds * 1000.0 + 0.5);
  uint32_t fps10 = ms ? (uint32_t)(((uint64_t)frames * 10000u + ms / 2) / ms) : 0;
  plat_pass(frames, ms, fps10, frames == DEMO1_FRAMES);
}

void qport_run(void)
{
  static char *argv[] = {"quake", "-basedir", ".", "+timedemo", "demo1", NULL};
  QG_Create(5, argv);
  int was_timedemo = 0;
  float td_start = 0;
  double last = Sys_FloatTime();
#ifdef QUAKE_SMOKE_FRAMES
  uint64_t start_cycles = 0;
  int start_frame = -1;
#endif
  for (;;) {
#ifdef QUAKE_SMOKE_FRAMES
    clock_now += SMOKE_STEP;
#endif
    double now = Sys_FloatTime();
    QG_Tick(now - last);
    last = now;
    if (cls.timedemo) {
      was_timedemo = 1;
      td_start = cls.td_starttime;
#ifdef QUAKE_SMOKE_FRAMES
      int frame = host_framecount - cls.td_startframe;
      if (frame == 3) {
        start_cycles = plat_cycles();
        start_frame = frame;
      }
      if (frame >= QUAKE_SMOKE_FRAMES) {
        uint64_t span = plat_cycles() - start_cycles;
        uint32_t crc = crc32(crc32(0, vid_buffer, sizeof vid_buffer), palette, sizeof palette);
        printf("quake: timedemo frame %d crc %08lx\n", frame, (unsigned long)crc);
        if (start_frame > 0)
          printf("quake: %lu cycles per frame over frames %d-%d\n",
                 (unsigned long)(span / (uint64_t)(frame - start_frame)), start_frame, frame);
        plat_dump(vid_buffer, palette);
        plat_stop(NULL);
      }
#endif
    } else if (was_timedemo) {
      was_timedemo = 0;
      pass_done((uint32_t)(host_framecount - cls.td_startframe - 2), realtime - td_start);
      Cbuf_AddText("timedemo demo1\n");
    }
  }
}
