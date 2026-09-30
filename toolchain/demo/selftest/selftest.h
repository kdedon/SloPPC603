/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
#ifndef SELFTEST_H
#define SELFTEST_H

#include <stdint.h>

/* Register state, one word per field: r0-r31, then the fields below, then
 * the scratch buffer's words. runner.S and gen.py use the same order. */
enum {
  F_CR = 32, F_XER, F_LR, F_CTR, F_VEC, F_SRR0, F_SRR1, F_MSR, F_DAR, F_DSISR, F_BUF,
  ST_BUF_WORDS = 64,
  ST_NFIELDS = F_BUF + ST_BUF_WORDS
};
#define ST_BUF ((volatile uint32_t *)0xfff3c000u)
/* A field value relative to the case's first instruction. */
#define ST_REL 0x80

struct st_kv {
  uint8_t field;
  uint32_t value, mask;
};

/* Inputs: the fields that differ from st_default (MSR always). Expected:
 * the fields that differ from the inputs, each under a mask. */
struct st_case {
  const char *name, *text;
  void (*code)(void);
  uint8_t group, words;
  uint16_t in_first, in_n, ex_first, ex_n;
};

void st_enter(const uint32_t *in, uint32_t *out, void (*code)(void));
void st_done(void);

#endif
