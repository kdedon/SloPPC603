# COMPACT FPU (`FPU_IMPL`)

`FPU_IMPL` (`ppc_fpu_pkg::fpu_impl_e`) selects the FPU implementation:

| Value | Module | Timing |
| --- | --- | --- |
| `FPU_IMPL_FULL` (default) | `ppc_fpu` | Table 6-5 latency and throughput |
| `FPU_IMPL_COMPACT` | `ppc_fpu_compact` | Longer latencies, one instruction in flight |

Both give the same architectural results: FPR bits, FPSCR, CR, exceptions,
602 SP/LT tags and emulation traps. COMPACT trades cycles for area. Its cycle
counts are a named deviation from 603e UM Table 6-5 (PDF 273) and 602 UM
Tables 6-2 and 6-5 (PDF 312, 315–316), selected only by `FPU_IMPL`; FULL is
unchanged.

The parameter passes through `ppc603e`, `ppc_core_bat_cached_bus60x`,
`ppc_core_bat_bus60x`, `ppc_core_bat`, `ppc_core` and `ppc_special`, and
through `ppc603e_demo_soc` and `ppc603e_mister`. The MiSTer build takes
`--fpu-compact`. Command-line tops take it as an integer (0 FULL,
1 COMPACT): `tb_demo_soc`, `tb_core_fpu`, `tb_fpu_impl_lint`. Both
personalities build standalone; the core attaches only the 603e
([integration](FPU_CORE_INTEGRATION.md)).

## Design

`ppc_fpu_compact` keeps the [interface](FPU_INTERFACE.md) with one
instruction in flight:

```
issue -> LAUNCH -> ARITH | MEMORY -> DONE -> commit
         (FPR reads, exceptions, local results)
```

- Issue is accepted only when empty; `issue_ready_o` is registered state.
- The launch cycle reads frA/frS, frB and frC from three MLAB copies with one
  write port, decides exceptions, and finishes moves, `fsel`, FPSCR and SPR
  instructions locally.
- The held result forms from one value word and a status record, as in FULL.
- The second issue lane, second retirement lane and forwarding buses stay
  idle. The FPR inspection port shares the frC read and is valid outside the
  launch cycle.

`ppc_fpu_arith_compact` keeps the arithmetic interface, including the
one-cycle finish prediction. It reuses classification, the multiplier, the
alignment plan and the rounding functions of `ppc_fpu_arith`, and replaces
the aligner, the three-way adder, the rounder's shifters and the radix-4
divider with one lane register pair (bits 159:48 on the 603e, 159:96 on the
602), one shifter, one adder and a radix-2 divide recurrence:

```
IN -> [MUL] -> ALIGN -> ADD -> [NEG] -> PREP -> NORM -> ROUND
IN -> ALIGN -> CONV                          (fctiw, fctiwz)
IN -> SPECIAL                (NaN, infinity, zero divide, compare, frsqrte)
IN -> DIVA -> DIVB -> DIVI x n -> PREP -> NORM -> ROUND   (fdiv, fdivs, fres)
```

ALIGN shifts y right with sticky jam; ADD forms x + y or x − y and NEG
negates a negative difference; PREP counts leading zeros and chooses the
normalizing or denormalizing shift; NORM shifts; ROUND increments and packs.
Right shifts with jam compose, so one pass equals the pipelined unit's
shifts. DIVA and DIVB normalize the dividend and divisor through one
normalizer; each DIVI cycle takes one restoring quotient bit, 26 for single
and 54 for double results, the same quotient and remainder as the pipelined
unit's radix-4 digits. On the 602 every operand is binary32-representable, so lane bits
below 96 are zero or sticky only.

## Cycle counts

Arithmetic unit, request accept to response valid (`tb_ppc_fpu_arith`
`latency_min`/`latency_max`, 603e raw vectors):

| Operation | Cycles |
| --- | --- |
| Special operands, compare, `frsqrte`, special divides | 2 |
| `fctiw`, `fctiwz` | 3 |
| add, subtract, `frsp`, single multiply | 6–7 |
| double multiply, multiply-add | 7–8 |
| `fdivs`, `fres` | 32 |
| `fdiv` | 60 |

The extra cycle is NEG, taken when x − y is negative.

Core dispatch to retirement of an isolated instruction (`test-core-fpu-compact`,
no retirement stalls), against FULL:

| Instruction | FULL | COMPACT |
| --- | --- | --- |
| `fadd(s)`, `fmuls`, `fmadds`, `frsp` | 4 | 9 |
| `fmul`, `fmadd` | 5 | 10 |
| `fctiw` | 4 | 6 |
| `fcmpu`, `frsqrte` | 4 | 5 |
| `fdivs`, `fres` | 19 | 35 |
| `fdiv` | 34 | 63 |
| `fmr`, `fsel`, `mffs`, `mtfsf`, `mtfsfi`, `mcrfs` | 3 | 2 |
| `lfs` / `lfd`, `stfs` / `stfd` | 8 / 10, 9 / 11 | same |

One instruction is in flight, so back-to-back FP instructions retire one
latency plus one cycle apart, dependent or not: four `fadd` retire 30 cycles
apart first to last (FULL: 3 independent, 9 dependent). The 602 SP/LT
`mfspr` and `mtspr` results arrive in two cycles, not one and two.

## Area and timing

Fitted FPU instance, standalone harness
([record](../quartus/fpu-production/README.md#compact-unit-fitted-603e-and-602)):

| Personality | FULL | COMPACT | Post-fit Fmax (COMPACT) |
| --- | ---: | ---: | --- |
| 603e | 15,465 ALMs | 3,551 ALMs | 55.06 MHz |
| 602 | 11,893 ALMs | 3,187 ALMs | 53.19 MHz |

COMPACT meets 50 MHz in both; 66 MHz is not met.

## Verification

The numerical and architectural benches run against COMPACT with
`+define+FPU_COMPACT`: raw, cluster, estimate and TestFloat vectors,
the shell, 602 and enabled-exception benches, the core program
(`test-core-fpu-compact`) and the SoC self-test
(`test-selftest-fpu-compact`). Checks that need overlapped instructions or
exact cycle counts stay FULL only: the dependent-distance test, the
operand-binding hazards, the 602 SPR latency check, and the timing, stream
and dual benches. Records are in
[production verification](../sim/fpu/PRODUCTION.md#compact-unit).
