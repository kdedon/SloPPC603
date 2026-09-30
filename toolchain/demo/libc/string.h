/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* The subset of the C library the fetched benchmarks and libm use, from
 * libc.c and the demo runtime. */
#ifndef DEMO_STRING_H
#define DEMO_STRING_H
#include <stddef.h>
void *memcpy(void *dst, const void *src, size_t n);
void *memmove(void *dst, const void *src, size_t n);
void *memset(void *dst, int c, size_t n);
int memcmp(const void *a, const void *b, size_t n);
char *strcpy(char *dst, const char *src);
char *strcat(char *dst, const char *src);
int strcmp(const char *a, const char *b);
int strncmp(const char *a, const char *b, size_t n);
char *strchr(const char *s, int c);
size_t strlen(const char *s);
#endif
