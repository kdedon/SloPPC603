/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* The toolchain's libgcc builds its float helpers for the hard-float ABI,
 * which this soft-float, FPU-less target cannot call. Dhrystone references
 * them only on its long-run reporting path, which simulation-sized runs
 * never take (the glue computes rates in integers). Reaching one fails. */
#include "soc.h"

#define NOFLOAT(name) \
  void name(void); \
  void name(void) { fail("floating point is not supported: " #name); }

NOFLOAT(__divdf3)
NOFLOAT(__divsf3)
NOFLOAT(__extendsfdf2)
NOFLOAT(__floatsisf)
NOFLOAT(__muldf3)
NOFLOAT(__mulsf3)
NOFLOAT(__truncdfsf2)
