/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
/* Names the fetched libm sources expect from their own library. */
#ifndef DEMO_FEATURES_H
#define DEMO_FEATURES_H
#define hidden __attribute__((__visibility__("hidden")))
#define weak_alias(old, new) \
  extern __typeof(old) new __attribute__((__weak__, __alias__(#old)))
#endif
