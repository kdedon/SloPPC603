/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* The C library the Doom engine needs: strings, a first-fit heap, the printf
 * family, and read-only files over memory (the IWAD). */
#include <ctype.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

#include "plat.h"

int errno;

/* ---- memory and strings ---------------------------------------------------- */
void *memcpy(void *d, const void *s, size_t n)
{
  uint8_t *dp = d;
  const uint8_t *sp = s;
  if ((((uintptr_t)dp | (uintptr_t)sp) & 3) == 0) {
    for (; n >= 16; n -= 16, dp += 16, sp += 16) {
      uint32_t a = ((const uint32_t *)sp)[0], b = ((const uint32_t *)sp)[1];
      uint32_t c = ((const uint32_t *)sp)[2], e = ((const uint32_t *)sp)[3];
      ((uint32_t *)dp)[0] = a;
      ((uint32_t *)dp)[1] = b;
      ((uint32_t *)dp)[2] = c;
      ((uint32_t *)dp)[3] = e;
    }
    for (; n >= 4; n -= 4, dp += 4, sp += 4) *(uint32_t *)dp = *(const uint32_t *)sp;
  }
  while (n--) *dp++ = *sp++;
  return d;
}

void *memmove(void *d, const void *s, size_t n)
{
  uint8_t *dp = d;
  const uint8_t *sp = s;
  if (dp <= sp || dp >= sp + n) return memcpy(d, s, n);
  while (n--) dp[n] = sp[n];
  return d;
}

void *memset(void *d, int c, size_t n)
{
  uint8_t *dp = d;
  uint32_t w = (uint8_t)c * 0x01010101u;
  while (n && ((uintptr_t)dp & 3)) { *dp++ = (uint8_t)c; n--; }
  for (; n >= 4; n -= 4, dp += 4) *(uint32_t *)dp = w;
  while (n--) *dp++ = (uint8_t)c;
  return d;
}

int memcmp(const void *a, const void *b, size_t n)
{
  const uint8_t *x = a, *y = b;
  for (; n; n--, x++, y++)
    if (*x != *y) return *x - *y;
  return 0;
}

void *memchr(const void *s, int c, size_t n)
{
  const uint8_t *p = s;
  for (; n; n--, p++)
    if (*p == (uint8_t)c) return (void *)p;
  return NULL;
}

size_t strlen(const char *s)
{
  size_t n = 0;
  while (s[n]) n++;
  return n;
}

char *strcpy(char *d, const char *s)
{
  char *r = d;
  while ((*d++ = *s++)) ;
  return r;
}

char *strncpy(char *d, const char *s, size_t n)
{
  size_t i = 0;
  for (; i < n && s[i]; i++) d[i] = s[i];
  for (; i < n; i++) d[i] = 0;
  return d;
}

char *strcat(char *d, const char *s)
{
  strcpy(d + strlen(d), s);
  return d;
}

char *strncat(char *d, const char *s, size_t n)
{
  char *e = d + strlen(d);
  while (n-- && *s) *e++ = *s++;
  *e = 0;
  return d;
}

int strcmp(const char *a, const char *b)
{
  while (*a && *a == *b) a++, b++;
  return (uint8_t)*a - (uint8_t)*b;
}

int strncmp(const char *a, const char *b, size_t n)
{
  for (; n; n--, a++, b++)
    if (*a != *b || !*a) return (uint8_t)*a - (uint8_t)*b;
  return 0;
}

int strcasecmp(const char *a, const char *b)
{
  while (*a && tolower(*a) == tolower(*b)) a++, b++;
  return tolower((uint8_t)*a) - tolower((uint8_t)*b);
}

int strncasecmp(const char *a, const char *b, size_t n)
{
  for (; n; n--, a++, b++)
    if (tolower(*a) != tolower(*b) || !*a) return tolower((uint8_t)*a) - tolower((uint8_t)*b);
  return 0;
}

char *strchr(const char *s, int c)
{
  for (;; s++) {
    if (*s == (char)c) return (char *)s;
    if (!*s) return NULL;
  }
}

char *strrchr(const char *s, int c)
{
  const char *r = NULL;
  for (;; s++) {
    if (*s == (char)c) r = s;
    if (!*s) return (char *)r;
  }
}

char *strstr(const char *h, const char *n)
{
  size_t len = strlen(n);
  for (; *h; h++)
    if (!strncmp(h, n, len)) return (char *)h;
  return len ? NULL : (char *)h;
}

char *strdup(const char *s)
{
  size_t n = strlen(s) + 1;
  char *d = malloc(n);
  return d ? memcpy(d, s, n) : NULL;
}

char *strerror(int e)
{
  (void)e;
  return "error";
}

int isdigit(int c) { return c >= '0' && c <= '9'; }
int isupper(int c) { return c >= 'A' && c <= 'Z'; }
int islower(int c) { return c >= 'a' && c <= 'z'; }
int isalpha(int c) { return isupper(c) || islower(c); }
int isalnum(int c) { return isalpha(c) || isdigit(c); }
int isspace(int c) { return c == ' ' || (c >= '\t' && c <= '\r'); }
int isprint(int c) { return c >= 0x20 && c < 0x7f; }
int iscntrl(int c) { return (c >= 0 && c < 0x20) || c == 0x7f; }
int ispunct(int c) { return isprint(c) && !isalnum(c) && c != ' '; }
int isxdigit(int c) { return isdigit(c) || ((c | 0x20) >= 'a' && (c | 0x20) <= 'f'); }
int toupper(int c) { return islower(c) ? c - 0x20 : c; }
int tolower(int c) { return isupper(c) ? c + 0x20 : c; }
int abs(int v) { return v < 0 ? -v : v; }
long labs(long v) { return v < 0 ? -v : v; }

long strtol(const char *s, char **end, int base)
{
  while (isspace(*s)) s++;
  int neg = *s == '-';
  if (*s == '-' || *s == '+') s++;
  unsigned long v = strtoul(s, end, base);
  return neg ? -(long)v : (long)v;
}

unsigned long strtoul(const char *s, char **end, int base)
{
  unsigned long v = 0;
  while (isspace(*s)) s++;
  if ((base == 0 || base == 16) && s[0] == '0' && (s[1] | 0x20) == 'x') {
    s += 2;
    base = 16;
  } else if (base == 0) {
    base = s[0] == '0' ? 8 : 10;
  }
  for (;; s++) {
    int d = isdigit(*s) ? *s - '0' : isalpha(*s) ? (*s | 0x20) - 'a' + 10 : 99;
    if (d >= base) break;
    v = v * (unsigned)base + (unsigned)d;
  }
  if (end) *end = (char *)s;
  return v;
}

int atoi(const char *s) { return (int)strtol(s, NULL, 10); }
long atol(const char *s) { return strtol(s, NULL, 10); }
double atof(const char *s) { return (double)strtol(s, NULL, 10); }

static uint32_t rand_state = 1;
int rand(void)
{
  rand_state = rand_state * 1103515245u + 12345u;
  return (int)((rand_state >> 1) & RAND_MAX);
}
void srand(unsigned seed) { rand_state = seed; }

/* ---- heap -------------------------------------------------------------------- */
/* Blocks carry their size in a header; freed blocks join a first-fit list. */
struct block {
  size_t size;
  struct block *next;
};
static char *heap_next;
static struct block *free_list;

void *malloc(size_t n)
{
  n = (n + 15) & ~(size_t)15;
  for (struct block **pp = &free_list; *pp; pp = &(*pp)->next)
    if ((*pp)->size >= n) {
      struct block *b = *pp;
      *pp = b->next;
      return (char *)b + 16;
    }
  if (!heap_next) heap_next = plat_heap_start;
  if ((size_t)(plat_heap_end - heap_next) < n + 16) return NULL;
  struct block *b = (struct block *)heap_next;
  b->size = n;
  heap_next += n + 16;
  return (char *)b + 16;
}

void free(void *p)
{
  if (!p) return;
  struct block *b = (struct block *)((char *)p - 16);
  b->next = free_list;
  free_list = b;
}

void *calloc(size_t n, size_t size)
{
  void *p = malloc(n * size);
  return p ? memset(p, 0, n * size) : NULL;
}

void *realloc(void *p, size_t n)
{
  if (!p) return malloc(n);
  struct block *b = (struct block *)((char *)p - 16);
  if (b->size >= n) return p;
  void *q = malloc(n);
  if (q) {
    memcpy(q, p, b->size);
    free(p);
  }
  return q;
}

/* ---- printf ------------------------------------------------------------------ */
struct out {
  char *buf;
  size_t size, len;
  FILE *file;
};

static void out_c(struct out *o, char c)
{
  if (o->file) fputc(c, o->file);
  else if (o->len + 1 < o->size) o->buf[o->len] = c;
  o->len++;
}

static void out_num(struct out *o, unsigned long long v, int base, int upper, int neg,
                    int width, int prec, int left, char pad, char sign)
{
  char tmp[24];
  int n = 0;
  const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";
  do {
    tmp[n++] = digits[v % (unsigned)base];
    v /= (unsigned)base;
  } while (v);
  while (n < prec) tmp[n++] = '0';
  char s = neg ? '-' : sign;
  int len = n + (s != 0);
  if (!left && pad == ' ')
    for (; len < width; width--) out_c(o, ' ');
  if (s) out_c(o, s);
  if (!left && pad == '0')
    for (; len < width; width--) out_c(o, '0');
  while (n) out_c(o, tmp[--n]);
  if (left)
    for (; len < width; width--) out_c(o, ' ');
}

static int format(struct out *o, const char *fmt, va_list ap)
{
  for (; *fmt; fmt++) {
    if (*fmt != '%') {
      out_c(o, *fmt);
      continue;
    }
    int left = 0, width = 0, prec = -1, lng = 0;
    char pad = ' ', sign = 0;
    for (;; fmt++) {
      if (fmt[1] == '-') left = 1;
      else if (fmt[1] == '0') pad = '0';
      else if (fmt[1] == '+') sign = '+';
      else if (fmt[1] == ' ') sign = sign ? sign : ' ';
      else if (fmt[1] != '#') break;
    }
    fmt++;
    if (*fmt == '*') {
      width = va_arg(ap, int);
      fmt++;
    }
    while (isdigit(*fmt)) width = width * 10 + *fmt++ - '0';
    if (*fmt == '.') {
      prec = 0;
      fmt++;
      if (*fmt == '*') {
        prec = va_arg(ap, int);
        fmt++;
      }
      while (isdigit(*fmt)) prec = prec * 10 + *fmt++ - '0';
    }
    while (*fmt == 'l' || *fmt == 'h' || *fmt == 'z') {
      if (*fmt == 'l') lng++;
      fmt++;
    }
    switch (*fmt) {
    case 'd':
    case 'i': {
      long long v = lng > 1 ? va_arg(ap, long long) : lng ? va_arg(ap, long) : va_arg(ap, int);
      out_num(o, v < 0 ? -(unsigned long long)v : (unsigned long long)v, 10, 0, v < 0, width,
              prec, left, pad, sign);
      break;
    }
    case 'u':
    case 'x':
    case 'X':
    case 'o': {
      unsigned long long v = lng > 1 ? va_arg(ap, unsigned long long)
                           : lng ? va_arg(ap, unsigned long) : va_arg(ap, unsigned);
      out_num(o, v, *fmt == 'u' ? 10 : *fmt == 'o' ? 8 : 16, *fmt == 'X', 0, width, prec, left,
              pad, 0);
      break;
    }
    case 'p':
      out_num(o, (uintptr_t)va_arg(ap, void *), 16, 0, 0, 8, 0, 0, '0', 0);
      break;
    case 'c':
      out_c(o, (char)va_arg(ap, int));
      break;
    case 's': {
      const char *s = va_arg(ap, const char *);
      if (!s) s = "(null)";
      int n = 0;
      while (s[n] && (prec < 0 || n < prec)) n++;
      if (!left)
        for (int i = n; i < width; i++) out_c(o, ' ');
      for (int i = 0; i < n; i++) out_c(o, s[i]);
      if (left)
        for (int i = n; i < width; i++) out_c(o, ' ');
      break;
    }
    case 'f':
    case 'g': {
      /* Fixed point, to the precision (6 by default). */
      double v = va_arg(ap, double);
      int neg = v < 0;
      if (neg) v = -v;
      if (prec < 0) prec = 6;
      unsigned long long scale = 1;
      for (int i = 0; i < prec; i++) scale *= 10;
      unsigned long long n = (unsigned long long)(v * (double)scale + 0.5);
      out_num(o, n / scale, 10, 0, neg, 0, 0, 0, ' ', sign);
      if (prec) {
        out_c(o, '.');
        out_num(o, n % scale, 10, 0, 0, 0, prec, 0, ' ', 0);
      }
      break;
    }
    case '%':
      out_c(o, '%');
      break;
    default:
      out_c(o, '%');
      out_c(o, *fmt);
      if (!*fmt) return (int)o->len;
    }
  }
  return (int)o->len;
}

int vsnprintf(char *s, size_t n, const char *fmt, va_list ap)
{
  struct out o = {s, n, 0, NULL};
  format(&o, fmt, ap);
  if (n) s[o.len < n ? o.len : n - 1] = 0;
  return (int)o.len;
}

int vsprintf(char *s, const char *fmt, va_list ap) { return vsnprintf(s, 1u << 30, fmt, ap); }

int vfprintf(FILE *f, const char *fmt, va_list ap)
{
  struct out o = {NULL, 0, 0, f};
  return format(&o, fmt, ap);
}

int vprintf(const char *fmt, va_list ap) { return vfprintf(stdout, fmt, ap); }

int snprintf(char *s, size_t n, const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  int r = vsnprintf(s, n, fmt, ap);
  va_end(ap);
  return r;
}

int sprintf(char *s, const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  int r = vsprintf(s, fmt, ap);
  va_end(ap);
  return r;
}

int printf(const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  int r = vfprintf(stdout, fmt, ap);
  va_end(ap);
  return r;
}

int fprintf(FILE *f, const char *fmt, ...)
{
  va_list ap;
  va_start(ap, fmt);
  int r = vfprintf(f, fmt, ap);
  va_end(ap);
  return r;
}

/* Integers and strings only, as the engine's configuration parser uses. */
int sscanf(const char *s, const char *fmt, ...)
{
  va_list ap;
  int n = 0;
  va_start(ap, fmt);
  for (; *fmt; fmt++) {
    if (isspace(*fmt)) {
      while (isspace(*s)) s++;
      continue;
    }
    if (*fmt != '%') {
      if (*s++ != *fmt) break;
      continue;
    }
    fmt++;
    while (isspace(*s)) s++;
    if (!*s) break;
    if (*fmt == 'd' || *fmt == 'i' || *fmt == 'x') {
      char *end;
      long v = *fmt == 'x' ? (long)strtoul(s, &end, 16) : strtol(s, &end, *fmt == 'i' ? 0 : 10);
      if (end == s) break;
      *va_arg(ap, int *) = (int)v;
      s = end;
    } else if (*fmt == 's') {
      char *d = va_arg(ap, char *);
      while (*s && !isspace(*s)) *d++ = *s++;
      *d = 0;
    } else {
      break;
    }
    n++;
  }
  va_end(ap);
  return n;
}

/* ---- files ------------------------------------------------------------------- */
struct doom_file {
  const uint8_t *data;
  long size, pos;
  int console;
};
static struct doom_file files[8] = {{NULL, 0, 0, 1}, {NULL, 0, 0, 1}, {NULL, 0, 0, 1}};
FILE *stdin = &files[0], *stdout = &files[1], *stderr = &files[2];

FILE *fopen(const char *path, const char *mode)
{
  const char *base = strrchr(path, '/');
  base = base ? base + 1 : path;
  if (mode[0] != 'r' || strcasecmp(base, PLAT_WAD_NAME) || !plat_wad_size) {
    errno = ENOENT;
    return NULL;
  }
  for (int i = 3; i < 8; i++)
    if (!files[i].data) {
      files[i] = (struct doom_file){plat_wad, (long)plat_wad_size, 0, 0};
      return &files[i];
    }
  return NULL;
}

int fclose(FILE *f)
{
  if (!f->console) f->data = NULL;
  return 0;
}

size_t fread(void *p, size_t size, size_t n, FILE *f)
{
  if (f->console || !size) return 0;
  size_t avail = (size_t)(f->size - f->pos) / size;
  if (n > avail) n = avail;
  memcpy(p, f->data + f->pos, n * size);
  f->pos += (long)(n * size);
  return n;
}

size_t fwrite(const void *p, size_t size, size_t n, FILE *f)
{
  const char *c = p;
  if (!f->console) return 0;
  for (size_t i = 0; i < size * n; i++) fputc(c[i], f);
  return n;
}

int fseek(FILE *f, long off, int whence)
{
  long base = whence == SEEK_SET ? 0 : whence == SEEK_CUR ? f->pos : f->size;
  if (f->console || base + off < 0 || base + off > f->size) return -1;
  f->pos = base + off;
  return 0;
}

long ftell(FILE *f) { return f->pos; }
int feof(FILE *f) { return !f->console && f->pos >= f->size; }
int ferror(FILE *f) { (void)f; return 0; }
int fflush(FILE *f) { (void)f; return 0; }

int fgetc(FILE *f)
{
  if (f->console || f->pos >= f->size) return EOF;
  return f->data[f->pos++];
}

char *fgets(char *s, int n, FILE *f)
{
  int i = 0, c = 0;
  while (i < n - 1 && (c = fgetc(f)) != EOF) {
    s[i++] = (char)c;
    if (c == '\n') break;
  }
  s[i] = 0;
  return i ? s : NULL;
}

int fputc(int c, FILE *f)
{
  if (f->console) plat_putc(c, f == stderr);
  return c;
}

int fputs(const char *s, FILE *f)
{
  while (*s) fputc(*s++, f);
  return 0;
}

int putchar(int c) { return fputc(c, stdout); }

int puts(const char *s)
{
  fputs(s, stdout);
  fputc('\n', stdout);
  return 0;
}

int fscanf(FILE *f, const char *fmt, ...) { (void)f; (void)fmt; return EOF; }
int remove(const char *path) { (void)path; return -1; }
int rename(const char *from, const char *to) { (void)from; (void)to; return -1; }
int mkdir(const char *path, mode_t mode) { (void)path; (void)mode; return -1; }
int access(const char *path, int mode) { (void)path; (void)mode; return -1; }
int unlink(const char *path) { (void)path; return -1; }
int isatty(int fd) { (void)fd; return 1; }
char *getenv(const char *name) { (void)name; return NULL; }
int system(const char *cmd) { (void)cmd; return -1; }

int usleep(unsigned usec)
{
  plat_sleep_us(usec);
  return 0;
}

int gettimeofday(struct timeval *tv, void *tz)
{
  (void)tz;
  uint64_t us = plat_micros();
  tv->tv_sec = (long)(us / 1000000u);
  tv->tv_usec = (long)(us % 1000000u);
  return 0;
}

void abort(void) { exit(-2); }

void doom_assert_fail(const char *expr, const char *file, int line)
{
  fprintf(stderr, "assert %s at %s:%d\n", expr, file, line);
  exit(-3);
}

double fabs(double x) { return x < 0 ? -x : x; }
