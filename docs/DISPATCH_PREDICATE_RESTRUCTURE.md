<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
<!-- Copyright (c) 2026 Kevin Dedon -->
# Dispatch predicate restructure

`DISPATCH_PRED` (core parameter, default 0; `+define+PPC_DISPATCH_PRED=1'b1`,
or `DISPATCH_PRED=1` in `sim/Makefile`) makes dispatch read class, legality
and form predicates stored in each IQ entry at push, instead of decoding
them from the queued uop in the dispatch cycle. Dispatch rules and cycle
counts are unchanged.

## The path

Recent fits end the worst path at `rename.map_tag[r]`, starting at an IQ
entry flop (`entries[0][319]`). DQ0 and DQ1 are flops already; the cycle is

```
entry flops ─► iq_unpack / uop field compares ─► class terms
            ─► dispatch decision (iq_ready, dispatch1) ─► rename alloc_i/alloc_reg_i
            ─► map_tag[r] enable (alloc_fire && alloc_reg == r)
```

`map_tag` data (`alloc_tag_o`) is a priority encode of the rename `valid`
flops; the enable carries the whole decision.

## Cone

Instruction-only terms (functions of the entry: uop, fetch fault, word):

| Term | Feeds |
|---|---|
| `dispatch_pre.illegal`, `special_op == NONE / != NONE / FPU`, `gpr_write` (fault, no-FPU substitution) | `normal_uop`, `special_uop`, `fp_uop`, `fp_mem_pipe`, `iq_ready` rename terms, `alloc_i` |
| privileged-form list (`RFI`, `MTMSR`, …, `spr[4]`) | `dispatch_pre` program substitution |
| mfspr/mtspr LR/CTR | `sru_move` |
| flag-demand list, `xer_only` | `dispatch_needs_flags`, `flags_tok0/1`, `flags_ready`, `d1_needs_flags` |
| plain-access forms | `dispatch_mem_plain`, `dispatch_fp_mem_plain`, `lsu_route`, `d1_lsu`, `d1_mem` |
| fold form (`insn[31:26] == 18`, BO bits) | `d1_branch` |
| unit, serial, SRU form, reads/writes, `gpr_dsts`, `cq1_ok` | already stored: `iq_pair_t` |

Live state:

| Term | Source |
|---|---|
| MSR[PR], MSR[FP], MSR[SE/BE] (trace), `fp_replay_q` | flops |
| `rs_ready`, `sru_rs_ready`, `special_busy`, `special_ready`, `lsu_ready`, `fp_issue_ready` | unit/station flops plus small logic |
| `cq_ready`, `cq1_ready` | CQ count |
| `alloc_ready`, `alloc1/2_ready` | priority over rename `valid` flops, and `recovery_i` |
| `gpr_ready`, `src_*1.ready`, `special_mem_dst` compares | rename map read on DQ1 source fields, wake compares |
| `bu_branch`, `bu_ready`, `bu_remove`, `bs_*`, `c0_carry/c1_carry` | BPU: CR/CTR/LR state and prediction |
| `dispatch_align` | EA adder on renamed operand values |
| `flags_busy`, `ca/so_pending_q`, `cr_wait*` | flag ownership flops |
| `recovery_accepted`, `interrupt_qualified`, `fault_pending`, `bu_redirect_q`, `bs_miss_q` | recovery/exception control |

## Design

1. **Predecode at push.** `dispatch_predecode(uop, fetch_packet)` runs on
   the push lanes beside `pair_predecode` and `iq_pack`, from the uop the
   fetch-side decoder already produces. Its 15-bit result is the top field
   of the entry, so the bit positions the core reads from `dq2`/`dq3` and
   `FOLD_BIT` do not move. The fetch → slot bypass (empty IQ) writes the
   entry on the same edge as before: predecode adds logic to the push
   D-input, not a stage. UM 6.3.2.2's one-cycle request-to-IQ is kept.
2. **Live terms applied at dispatch.** The only live term the stored DQ0
   predicates need is MSR[PR] (privileged forms become a program
   exception): `pr_kill = MSR[PR] && priv`. MSR[FP], trace mode and
   `fp_replay_q` stay where they were.
3. **Rename demand.** `alloc_i` uses `pre.gpr_write && !dispatch_align &&
   !bu_branch` instead of the decoded `dispatch_uop.gpr_write`.

`dispatch_uop` keeps every other use (operand fields, station payload,
CQ record).

## Next steps

Not yet done; each needs its own fit evidence:

- **Registered rename free flags.** `alloc_ready`, `alloc1_ready` and
  `alloc2_ready` as flops updated from the next `valid` (popcount ≥1/≥2/≥3
  of `valid_d`), with `recovery_i` applied as today.
- **Alignment out of `alloc_i`.** `dispatch_align` (EA adder) gates the
  rename write. The fault already waits for a free slot (`iq_ready`), so
  allocating a slot it never commits, and dropping it at the fault's
  recovery, would remove the adder from the enable. This changes rename
  state on a faulting access and needs recovery-bench evidence.
- **Rename port select.** `alloc_reg_i` muxes three register fields by
  `rename0_dq1` (which depends on `dispatch1`). With the predicates, the
  select can be `{d0_gpr, d1_gpr, update}` from stored bits, leaving only
  the fire terms late.
- **Predecode at I-cache fill.** `ENABLE_FETCH_HINTS` carries per-word bits
  from fill through `ppc_fetch_hints`; moving `dispatch_predecode` there
  would take it off the I-cache RAM → IQ path as well, at the cost of
  widening `WORD_META_BITS`.

## Equivalence checks

Both forms are built in every configuration. Simulation asserts every
cycle that, for a valid DQ0, the stored-and-qualified predicates equal the
decoded ones (`illegal`, `normal`, `special`, `fpu`, `gpr_write`,
`sru_move`, flag demand, `xer_only` where flags are demanded), the rename
demand equals `dispatch_uop.gpr_write`, and both plain-access predicates
match; and for a valid DQ1, every stored form equals its decode.
