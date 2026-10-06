/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
#ifndef DOOM_ASSERT_H
#define DOOM_ASSERT_H
void doom_assert_fail(const char *expr, const char *file, int line) __attribute__((noreturn));
#define assert(e) ((e) ? (void)0 : doom_assert_fail(#e, __FILE__, __LINE__))
#endif
