/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* Helpers shared by the nbench and Embench ports (bench.c). */
#ifndef DEMO_BENCH_H
#define DEMO_BENCH_H
#include <stdint.h>

/* Processor clock from the MODE register. */
uint32_t bench_clock_hz(void);
/* Prints v rounded to the given number of decimals, right-aligned in width. */
void bench_print_fixed(double v, int decimals, int width);
/* Starts the screen console with a title line. */
void bench_screen(const char *title);
/* Fills the free stack with a pattern; the check prints the deepest use
 * since and fails if the pattern is gone at the stack limit. */
void bench_stack_paint(void);
void bench_stack_check(void);

#endif
