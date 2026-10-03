/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* C library functions the fetched benchmarks need beyond the demo runtime:
 * strings, character classes, rand, exit, and read-only in-memory files. */
#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "soc.h"

void *memmove(void *dst, const void *src, size_t n)
{
  uint8_t *d = dst;
  const uint8_t *s = src;
  if (d <= s || d >= s + n) return memcpy(dst, src, n);
  while (n--) d[n] = s[n];
  return dst;
}

void bzero(void *p, size_t n) { memset(p, 0, n); }

char *strcat(char *dst, const char *src)
{
  strcpy(dst + strlen(dst), src);
  return dst;
}

int strncmp(const char *a, const char *b, size_t n)
{
  for (; n; n--, a++, b++) {
    if (*a != *b) return (unsigned char)*a - (unsigned char)*b;
    if (!*a) break;
  }
  return 0;
}

char *strchr(const char *s, int c)
{
  for (;; s++) {
    if (*s == (char)c) return (char *)s;
    if (!*s) return 0;
  }
}

int abs(int v) { return v < 0 ? -v : v; }
long labs(long v) { return v < 0 ? -v : v; }

int isdigit(int c) { return c >= '0' && c <= '9'; }
int isupper(int c) { return c >= 'A' && c <= 'Z'; }
int islower(int c) { return c >= 'a' && c <= 'z'; }
int isalpha(int c) { return isupper(c) || islower(c); }
int isxdigit(int c) { return isdigit(c) || ((c | 0x20) >= 'a' && (c | 0x20) <= 'f'); }
int isspace(int c) { return c == ' ' || (c >= '\t' && c <= '\r'); }
int toupper(int c) { return islower(c) ? c - 0x20 : c; }
int tolower(int c) { return isupper(c) ? c + 0x20 : c; }

/* The C standard's example generator. */
static uint32_t rand_state = 1;
int rand(void)
{
  rand_state = rand_state * 1103515245u + 12345u;
  return (int)((rand_state >> 16) & RAND_MAX);
}
void srand(unsigned seed) { rand_state = seed; }

void exit(int code)
{
  if (code) printf("FAIL: exit %d\n", code);
  SOC_EXIT = (uint32_t)code;
  for (;;) {}
}

void abort(void)
{
  fail("abort");
  for (;;) {}
}

int puts(const char *s)
{
  con_puts(s);
  con_putc('\n');
  return 0;
}

float fabsf(float x)
{
  union { float f; uint32_t u; } v = {x};
  v.u &= 0x7fffffffu;
  return v.f;
}

/* ---- read-only files -------------------------------------------------- */

__attribute__((weak)) const struct demo_file_image demo_files[] = {{0, 0}};

struct demo_file {
  const char *pos;
  int open;
};
static struct demo_file files[2];

FILE *fopen(const char *path, const char *mode)
{
  if (mode[0] != 'r') return 0;
  for (const struct demo_file_image *f = demo_files; f->name; f++) {
    if (strcmp(f->name, path) != 0) continue;
    for (unsigned i = 0; i < sizeof files / sizeof files[0]; i++)
      if (!files[i].open) {
        files[i] = (struct demo_file){f->data, 1};
        return &files[i];
      }
  }
  return 0;
}

int fclose(FILE *f)
{
  if (f) f->open = 0;
  return 0;
}

/* Writing to a file is not supported: output is dropped. */
int fprintf(FILE *f, const char *fmt, ...)
{
  (void)f;
  (void)fmt;
  return 0;
}

/* Conversions: %d and %ld, with whitespace in the format matching any run
 * of whitespace. Returns the number of values stored, or EOF. */
int fscanf(FILE *f, const char *fmt, ...)
{
  va_list ap;
  int stored = 0;
  va_start(ap, fmt);
  for (; *fmt; fmt++) {
    if (isspace(*fmt)) {
      while (isspace(*f->pos)) f->pos++;
      continue;
    }
    if (*fmt != '%') {
      if (*f->pos != *fmt) break;
      f->pos++;
      continue;
    }
    int lng = fmt[1] == 'l';
    fmt += 1 + lng;
    if (*fmt != 'd') fail("fscanf: unsupported conversion");
    while (isspace(*f->pos)) f->pos++;
    if (!*f->pos) {
      if (!stored) stored = EOF;
      break;
    }
    int neg = *f->pos == '-';
    if (neg || *f->pos == '+') f->pos++;
    if (!isdigit(*f->pos)) break;
    long v = 0;
    while (isdigit(*f->pos)) v = v * 10 + (*f->pos++ - '0');
    if (neg) v = -v;
    if (lng) *va_arg(ap, long *) = v;
    else *va_arg(ap, int *) = (int)v;
    stored++;
  }
  va_end(ap);
  return stored;
}
