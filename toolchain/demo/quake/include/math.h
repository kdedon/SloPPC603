/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Double-precision functions of the Quake port, from the fetched musl
 * sources; fabs is in the C library. */
#ifndef QUAKE_MATH_H
#define QUAKE_MATH_H
double fabs(double x);
double floor(double x);
double ceil(double x);
double sqrt(double x);
double sin(double x);
double cos(double x);
double atan(double x);
double tan(double x);
double atan2(double y, double x);
double pow(double x, double y);
#endif
