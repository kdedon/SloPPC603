/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Kevin Dedon */
#ifndef SELFTEST_H
#define SELFTEST_H

#include <stdint.h>

/* Register state, one word per field: r0-r31, then the fields below, then
 * the scratch buffer's words, the FPRs (high word first) and the FPSCR.
 * runner.S and gen.py use the same order. */
enum {
  F_CR = 32, F_XER, F_LR, F_CTR, F_VEC, F_SRR0, F_SRR1, F_MSR, F_DAR, F_DSISR, F_BUF,
  ST_BUF_WORDS = 64,
  F_FPR = F_BUF + ST_BUF_WORDS,
  F_FPSCR = F_FPR + 64,
  ST_NFIELDS = F_FPSCR + 1
};
#define ST_BUF ((volatile uint32_t *)0xfff3c000u)
/* A field value relative to the case's first instruction. */
#define ST_REL 0x100
#define ST_FIELD 0xff

struct st_kv {
  uint16_t field;
  uint32_t value, mask;
};

/* Inputs: the fields that differ from st_default (MSR always). Expected:
 * the fields that differ from the inputs, each under a mask. A case with
 * fpu set runs only on a processor with an FPU. */
struct st_case {
  const char *name, *text;
  void (*code)(void);
  uint8_t group, words, fpu;
  uint16_t in_first, in_n, ex_first, ex_n;
};

/* Nonzero when the processor has an FPU: the runner then loads and stores
 * the FPRs and FPSCR. */
extern uint32_t st_fp;
void st_enter(const uint32_t *in, uint32_t *out, void (*code)(void));
void st_done(void);

#endif
