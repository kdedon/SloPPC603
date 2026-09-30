/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
#ifndef DEMO_STDLIB_H
#define DEMO_STDLIB_H
#include <stddef.h>
#define RAND_MAX 0x7fff
void *malloc(size_t size);
int abs(int v);
long labs(long v);
int rand(void);
void srand(unsigned seed);
void exit(int code) __attribute__((noreturn));
void abort(void) __attribute__((noreturn));
#endif
