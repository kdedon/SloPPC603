/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* times() reports processor cycles (the SoC cycle counter) as user time. */
#ifndef DEMO_SYS_TIMES_H
#define DEMO_SYS_TIMES_H
#include <sys/types.h>
struct tms {
  clock_t tms_utime, tms_stime, tms_cutime, tms_cstime;
};
int times(struct tms *buf);
#endif
