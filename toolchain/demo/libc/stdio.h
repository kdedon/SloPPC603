/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* Console output and read-only in-memory files (libc.c). nbench's output
 * goes through nb_printf, which keeps only its check lines. */
#ifndef DEMO_LIBC_STDIO_H
#define DEMO_LIBC_STDIO_H
#include <stdarg.h>
#include <stddef.h>

typedef struct demo_file FILE;
#define EOF (-1)

int printf(const char *fmt, ...);
int vprintf(const char *fmt, va_list ap);
int snprintf(char *buf, size_t size, const char *fmt, ...);
int puts(const char *s);
FILE *fopen(const char *path, const char *mode);
int fclose(FILE *f);
int fscanf(FILE *f, const char *fmt, ...);
int fprintf(FILE *f, const char *fmt, ...);

/* A read-only file for fopen: name and contents. */
struct demo_file_image {
  const char *name, *data;
};
extern const struct demo_file_image demo_files[];

#ifdef DEMO_NBENCH
int nb_printf(const char *fmt, ...);
#define printf nb_printf
#endif
#endif
