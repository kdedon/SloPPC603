/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* C library for the Doom port (doom/libc.c). Files are read-only views of
 * memory; stdout and stderr go to the console. */
#ifndef DOOM_STDIO_H
#define DOOM_STDIO_H
#include <stdarg.h>
#include <stddef.h>

typedef struct doom_file FILE;
extern FILE *stdin, *stdout, *stderr;
#define EOF (-1)
#define SEEK_SET 0
#define SEEK_CUR 1
#define SEEK_END 2
#define BUFSIZ 512
#define FILENAME_MAX 256

FILE *fopen(const char *path, const char *mode);
int fclose(FILE *f);
size_t fread(void *p, size_t size, size_t n, FILE *f);
size_t fwrite(const void *p, size_t size, size_t n, FILE *f);
int fseek(FILE *f, long off, int whence);
long ftell(FILE *f);
int feof(FILE *f);
int ferror(FILE *f);
int fflush(FILE *f);
int fgetc(FILE *f);
char *fgets(char *s, int n, FILE *f);
int fputc(int c, FILE *f);
int fputs(const char *s, FILE *f);
int putchar(int c);
int puts(const char *s);
int printf(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
int fprintf(FILE *f, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
int sprintf(char *s, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
int snprintf(char *s, size_t n, const char *fmt, ...) __attribute__((format(printf, 3, 4)));
int vprintf(const char *fmt, va_list ap);
int vfprintf(FILE *f, const char *fmt, va_list ap);
int vsprintf(char *s, const char *fmt, va_list ap);
int vsnprintf(char *s, size_t n, const char *fmt, va_list ap);
int sscanf(const char *s, const char *fmt, ...);
int fscanf(FILE *f, const char *fmt, ...);
int remove(const char *path);
int rename(const char *from, const char *to);
#endif
