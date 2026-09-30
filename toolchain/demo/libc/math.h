/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* Double-precision functions from the fetched musl sources (libm), with
 * soft-float arithmetic from the fetched libgcc soft-fp sources. */
#ifndef DEMO_MATH_H
#define DEMO_MATH_H
typedef double double_t;
typedef float float_t;
#define INFINITY __builtin_inff()
#define NAN __builtin_nanf("")
#define HUGE_VAL __builtin_huge_val()
#define isnan(x) __builtin_isnan(x)
#define isinf(x) __builtin_isinf(x)
#define signbit(x) __builtin_signbit(x)
double fabs(double x);
double floor(double x);
float fabsf(float x);
double sqrt(double x);
double sin(double x);
double cos(double x);
double atan(double x);
double acos(double x);
double exp(double x);
double log(double x);
double pow(double x, double y);
double scalbn(double x, int n);
#endif
