/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
#ifndef DEMO_ASSERT_H
#define DEMO_ASSERT_H
void fail(const char *what);
#define assert(e) ((e) ? (void)0 : fail("assertion " #e))
#endif
