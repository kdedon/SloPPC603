/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* setjmp and longjmp of the Quake port (setjmp.S): r1, r2, r13-r31, LR and
 * CR, and with hard float f14-f31. */
#ifndef QUAKE_SETJMP_H
#define QUAKE_SETJMP_H
typedef double jmp_buf[32];
int setjmp(jmp_buf env) __attribute__((returns_twice));
void longjmp(jmp_buf env, int val) __attribute__((noreturn));
#endif
