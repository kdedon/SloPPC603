/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Kevin Dedon */
/* Hooks between the Quake port (qport.c) and its platform. */
#ifndef QUAKE_QPORT_H
#define QUAKE_QPORT_H
#include <stdint.h>

#define QPORT_W 320
#define QPORT_H 200

/* Runs the engine and the timedemo passes; does not return. */
void qport_run(void);

uint64_t plat_micros(void);
uint64_t plat_cycles(void);
/* A finished frame: 320 x 200 palette indices and the RGB palette. */
void plat_frame(const uint8_t *pix, const uint8_t *pal, int pal_changed);
/* A finished pass; ok is clear when the frame count shows lost sync. */
void plat_pass(uint32_t frames, uint32_t ms, uint32_t fps10, int ok);
/* The smoke run's last frame, for comparison with other builds. */
void plat_dump(const uint8_t *pix, const uint8_t *pal);
/* Ends the run, with an error message or NULL. */
void plat_stop(const char *error) __attribute__((noreturn));

#endif
