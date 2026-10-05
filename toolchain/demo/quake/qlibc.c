/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* C library calls of the Quake engine beyond the Doom port's, and those the
 * compiler forms (sincos from a sin and cos of one angle). */
#include <math.h>
#include <stdio.h>

void sincos(double x, double *s, double *c);

int getc(FILE *f) { return fgetc(f); }

void sincos(double x, double *s, double *c)
{
  *s = sin(x);
  *c = cos(x);
}
