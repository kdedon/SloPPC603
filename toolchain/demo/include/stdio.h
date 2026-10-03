/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* The subset of stdio the benchmark sources use, bound to the demo runtime.
 * Dhrystone's output is checked as it is printed (dhry_glue.c). */
#ifndef DEMO_STDIO_H
#define DEMO_STDIO_H
int printf(const char *fmt, ...);
int dhry_printf(const char *fmt, ...);
int dhry_scanf(const char *fmt, ...);
#ifdef DEMO_DHRYSTONE
#define printf dhry_printf
#define scanf dhry_scanf
#endif
#endif
