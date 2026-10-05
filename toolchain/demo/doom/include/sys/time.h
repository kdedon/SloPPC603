/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
#ifndef DOOM_SYS_TIME_H
#define DOOM_SYS_TIME_H
struct timeval { long tv_sec, tv_usec; };
int gettimeofday(struct timeval *tv, void *tz);
#endif
