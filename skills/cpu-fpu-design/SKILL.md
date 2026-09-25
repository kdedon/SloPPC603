---
name: cpu-fpu-design
description: Load when planning, implementing or reviewing a floating-point unit for an FPGA CPU — IU/FPU interlock and precise commit, FP register file and rename, datapath sharing (shifter, rounder, LZC, multiplier), iterative vs pipelined ops, divide/sqrt/reciprocal-estimate (fdiv, fres, frsqrte), IEEE corner cases, PowerPC FPSCR flag semantics and NaN propagation, and per-op verification against a softfloat reference. Lessons from SPARC, VR4300 and PSX GTE FPGA datapaths.
---

# FPU design for an FPGA CPU

Evidence links point at the reference cores on GitHub, pinned to the reviewed commits: N64 = VR4300 (N64_MiSTer), PSX = R3000A (PSX_MiSTer), SH2 = SH-2 (Saturn_MiSTer), SS = SPARC V8 (Grabulosaure/ss), ARM7 = ARM7TDMI (Atari7800_MiSTer).

PowerPC specifics: 64-bit FPRs (singles stored as doubles), fused
multiply-add, FPSCR with sticky exception bits, FX/FEX/VX summaries, FR/FI, FPRF result class.

## 1. Integration with the integer core

- **Precise without a ROB: in-order FIFO + commit counter.** Issue into a small FIFO; completion pulses
  one commit per retired FP op; a result writes the FPR/FPSCR only when "finished" meets a pending commit,
  else the FP pipe holds. On flush, drain committed ops, then clear. SS [`fpu_simple.vhd:120-133`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L120-L133), [`228-242`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L228-L242), [`560-569`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L560-L569).
- **Don't block integer work.** N64 stalls the whole core until `command_done` ([`cpu.vhd:2785-2787`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2785-L2787));
  the 603e overlaps FPU with IU/LSU.
- **FP loads/stores go through the LSU** into FPR rename slots (PSX routes LWC2 data to the coprocessor,
  [`cpu.vhd:2376-2379`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2376-L2379)); FP load results have write priority over FPU results on the FPR port (N64 [`cpu.vhd:905-915`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L905-L915)).
- **Scoreboard FP RAW against in-flight destinations** (SS `deps()` over FIFO entries, [`fpu_simple.vhd:176-183`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L176-L183)).
  Conservative is acceptable first; forwarding FPU→FPU is an optimization.
- **Output skid register** so the downstream stall has no combinational path into the FP pipe's ready chain.
  SS `SSTALL` ([`fpu_calc.vhd:83`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_calc.vhd#L83), [`776-803`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_calc.vhd#L776-L803)).

## 2. Datapath structure

- **First implementation: one copy each of shifter-with-sticky, rounder (all four modes), LZC, and a
  zero/inf/NaN shortcut path, time-shared across ops.** N64 [`cpu_FPU.vhd:1017-1114`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_FPU.vhd#L1017-L1114), [`883-900`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_FPU.vhd#L883-L900).
  SS: one add/convert datapath and one mul/div/sqrt datapath, singles mapped into the double layout
  ([`fpu_pack.vhd:476-503`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_pack.vhd#L476-L503)).
- **Classify once at unpack** (5-bit class vector: zero, denormal, normal, inf, QNaN/SNaN) and drive all
  special-case logic from it. SS `class()` ([`fpu_pack.vhd:516-560`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_pack.vhd#L516-L560)).
- **Tree LZC**, log-depth (SS `clz64`).
- **Multiplier**: a 53×53 in one cycle is a DSP-cascade critical path (SS [`fpu_mul.vhd:208-231`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_mul.vhd#L208-L231)). Use a
  pipelined split (e.g. 53×27 two-pass for double, matching the 603e's two-pass double multiply), optionally
  shared with integer `mullw` (N64 [`cpu.vhd:2721-2735`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2721-L2735)).
- **Separate arithmetic from flag/saturation formation**: compute flags from the registered result the next
  stage (PSX [`gte_mac123.vhd:43-44`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/gte_mac123.vhd#L43-L44), [`106-143`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/gte_mac123.vhd#L106-L143)).
- **Micro-sequence complex ops with a readable per-step control table** (record/struct rows with column
  comments). PSX GTE [`gte.vhd:619-760`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/gte.vhd#L619-L760), [`pGTE.vhd:7-33`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/pGTE.vhd#L7-L33). Good for fdiv/fsqrt sequences and denormal steps.

## 3. Divide, sqrt, estimates

- **Table seed + fixed Newton–Raphson iterations, one DSP multiply per stage**, bit-exact by copying the
  reference table and rounding constants. PSX UNR divide: 257-entry table, 7 stages ([`gte_UNRDivide.vhd:21-40`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/gte_UNRDivide.vhd#L21-L40), [`102-173`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/gte_UNRDivide.vhd#L102-L173)).
- PowerPC `fres`/`frsqrte` are architecturally *estimates*; matching a specific implementation's bits
  (for software that depends on them) requires that implementation's table. Decide the target (603e vs
  generic) and record it.
- Digit-recurrence fallback: combined non-restoring div/sqrt loop (SS [`fpu_div.vhd:233-305`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_div.vhd#L233-L305), radix-2).
  Avoid the SS SRT variants (marked buggy).

## 4. IEEE and PowerPC semantics — where reference cores are wrong for PPC

- **NaN propagation**: PowerPC returns the first NaN operand in architected order (frA, then frB, then frC),
  quieting an SNaN; invalid operations with no NaN input produce the default QNaN. SS does not preserve NaN
  payload/sign ([`fpu_pack.vhd:13-14`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_pack.vhd#L13-L14)); MIPS writes its own default NaN (N64 [`cpu_FPU.vhd:902-921`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_FPU.vhd#L902-L921)). Neither is PPC.
- **Denormals are handled in hardware** on PowerPC (no unimplemented-operation trap); N64's trap-to-software
  ([`cpu_FPU.vhd:503-511`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_FPU.vhd#L503-L511)) is not an option. FPSCR[NI] non-IEEE mode may flush.
- **FPSCR**: sticky exception bits OR in at completion; FX set on any new sticky bit; VX = OR of VX* bits;
  FEX from enabled exceptions; FR/FI from rounding; FPRF from the result class. Cause bits are per-instruction,
  sticky bits accumulate (N64 clears cause at op start, `causeReset`). Commit FPSCR with the FPR result.
- **Fused multiply-add**: single rounding at the end; do not implement as mul-round-add.
- Single-precision ops round to single and store as double; `frsp` handles the conversion and its flags.
- Enabled FP exceptions: precise vs imprecise modes (MSR[FE0/FE1]); SPARC's deferred-trap queue does not apply.

## 5. Verification

- **Per-op sim trace**: op, rounding mode, operands, result, FPSCR before/after, written to a file and
  diffed against a softfloat-based reference. N64 [`cpu_FPU.vhd:1770-1853`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_FPU.vhd#L1770-L1853).
- Directed corners: ±0, ±inf, QNaN/SNaN in each operand position, denormal in/out, overflow/underflow at
  each rounding mode, exact vs inexact, fmadd cancellation, int conversions at bounds.
- Randomized differential against the reference for every op and rounding mode, deterministic seeds.

## 6. Checklist

- [ ] FPR/FPSCR writes happen only on completion commit; flush drains committed ops first.
- [ ] Integer work proceeds while the FPU is busy.
- [ ] Classification computed once; expensive units shared or pipelined deliberately.
- [ ] NaN selection order, SNaN quieting and default NaN match PowerPC.
- [ ] Denormals handled in hardware; NI mode defined.
- [ ] FPSCR sticky/summary/FPRF semantics tested per op.
- [ ] Softfloat differential with recorded seeds passes before integration.
