---
name: cpu-execution-units
description: Load when implementing or reviewing integer execution hardware — ALU/adder structure, carry-in/XER[CA] handling, rotate/shift/mask units (rlwinm, rlwnm, rlwimi, slw, srw, sraw), compare, count-leading-zeros, multipliers on Cyclone V DSPs, iterative dividers, sticky/summary flags (XER[SO/OV], CR0), and latency/cycle-accuracy modeling for multi-cycle ops. Covers FPGA-proven area and timing patterns plus multiplier multicycle pitfalls.
---

# Integer execution units

Evidence links point at the reference cores on GitHub, pinned to the reviewed commits: N64 = VR4300 (N64_MiSTer), PSX = R3000A (PSX_MiSTer), SH2 = SH-2 (Saturn_MiSTer), SS = SPARC V8 (Grabulosaure/ss), ARM7 = ARM7TDMI (Atari7800_MiSTer).

## 1. Adder / ALU

- **One adder, decoded operand inversion and carry-in select.** `sum = (inv_a ? ~a : a) + (inv_b ? ~b : b) + cin`,
  with `inv_a/inv_b/cin_sel` decoded in the previous stage. Covers add, subf, neg, cmp, adde, subfe,
  addme, addze, subfic. SH2 `Adder()` ([`SH_pkg.sv:1421-1498`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_pkg.sv#L1421-L1498)): `b ^ {32{code[0]}}` plus a selected carry-in.
- **Anti-pattern:** a separate `arith = …` expression per opcode arm (ARM7 [`core:1133-1194`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L1133-L1194)) → several
  adders + wide mux on the critical loop.
- **Fuse carry-in into the chain**: `({1'b0,a,1'b1} + {1'b0,b,cin}) >> 1` gives one carry chain for three
  inputs. ARM7 [`core:1095-1105`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L1095-L1105).
- Derive signed/unsigned compare results from the same adder (SH2 [`SH_core.sv:545-548`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_core.sv#L545-L548)); CR0 LT/GT/EQ from
  the result and SO copy.
- **Flags merged by a decoded mask**: `new = (old & ~mask) | (flags & mask)` computed with mask from decode.
  ARM7 [`core:1196-1209`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L1196-L1209). Applies to CR field writes, XER[CA/OV/SO], `mtcrf` field masks.
- Z-detect (`== 0`) on the result is on the loop; if CR0 is critical, compute EQ one stage later and
  forward CR separately from the GPR result.

## 2. Rotate / shift / mask

- **One rotator + per-bit mask + sign fill covers every shift.** ARM7 [`pkg:123-185`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_pkg.sv#L123-L185) (a third of the area of
  four shifters); SS shared 64-bit rotate for SLL/SRL/SRA ([`iu_pack.vhd:1517-1560`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L1517-L1560)); N64/PSX reuse one
  arithmetic shifter for logical by forcing the fill bit.
- PowerPC is literally this model: `rlwinm/rlwnm/rlwimi` = rotl32 + MASK(MB,ME) (+ insert with rA);
  `slw/srw` = rotate + mask with the 6th count bit zeroing; `sraw/srawi` = rotate + mask + sign fill,
  CA = sign ∧ (any 1 shifted out). Mask via two thermometer compares; wrapped masks (MB > ME) are the OR form.
- `rlwimi` reads rA as a third operand — count it as a regfile read port and forwarding consumer
  (PSX notes the same trap for LWL/LWR old-data, [`cpu.vhd:2364-2369`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2364-L2369)).
- `cntlzw`: tree LZC (log-depth encode/combine, SS `clz64`, [`fpu_pack.vhd:364-377`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_pack.vhd#L364-L377)), not a priority for-loop
  on a critical path.

## 3. Multiplier

- **Pipeline the DSP explicitly (input and output registers) and put the result on the result bus from a
  register.** ARM7 measured −3.84 ns when the multiplier sat on the forwarding loop ([`arm7tdmi.sdc:44-46`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi.sdc#L44-L46));
  its retire reads only `mul_acc` ([`core:947-952`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L947-L952)).
- **Multicycle without a constraint is a pitfall**: N64 samples a 64×64 product 4–7 cycles later with no
  `set_multicycle_path` ([`cpu_mul.vhd`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_mul.vhd), [`N64.sdc`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/N64.sdc)). Either pipeline it or constrain it with a matching
  enable — and never constrain a path that has a one-cycle degenerate case (ARM7 SDC note, [`arm7tdmi.sdc:31-71`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi.sdc#L31-L71)).
- **One signed 33×33 serves signed and unsigned** (sign/zero-extend inputs); PSX's separate signed and unsigned
  32×32 wastes DSPs ([`cpu.vhd:1836-1837`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L1836-L1837)). N64 uses one multiplier with dynamic sign ports.
- **Iterative option**: 32×8 per cycle with fixed corrections (signed-long terms, early-termination tail) hoisted
  into the seed accumulator so the loop body is one small product + add. ARM7 [`core:1256-1293`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L1256-L1293). SS uses four 17×17
  partial products over 4 cycles ([`iu_muldiv.vhd:144-207`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_muldiv.vhd#L144-L207)).
- **Data-dependent latency** matching silicon: PSX early-out by rs magnitude ([`cpu.vhd:1954-1970`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L1954-L1970)); ARM7 by
  significant bytes ([`core:1228-1254`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L1228-L1254)). 603e `mullw/mulhw` latency depends on operand width — model with a counter.
- **Share the wide multiplier with the FPU mantissa multiply** if latency budgets allow (N64 loads FP mantissas
  into the same `mul1/mul2`, [`cpu.vhd:2721-2735`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2721-L2735)).

## 4. Divider

- Radix-2 restoring/non-restoring, 1 bit/cycle, on magnitudes with sign fix-up at the end is enough for
  `divw/divwu` (603e: 37 cycles). N64 [`divider.vhd`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/divider.vhd) (`is32` shortens), PSX [`divider.vhd`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/divider.vhd), SH2 [`DIVU.sv`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/DIVU.sv).
- **Handle architected special cases outside the iterative core** (divide by zero, 0x80000000 / −1 → OV,
  undefined result) selected by a mode enum. PSX `HILOCALC_DIV0` ([`cpu.vhd:1974-2009`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L1974-L2009)); SS early-out on
  divide-by-zero ([`iu_muldiv.vhd:331-336`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_muldiv.vhd#L331-L336)).
- Don't trust SRT code without exhaustive tests (SS SRT variants are marked buggy, [`fpu_div.vhd:10`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_div.vhd#L10)).
- If the core runs at CE/2, split mux and adder across phases (SH2 [`DIVU.sv:60-93`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/DIVU.sv#L60-L93)); otherwise keep the
  iteration body to one add/sub + shift.

## 5. Latency, completion and flags

- **Compute fast, model latency with a counter, expose a "fast" switch.** SH2 MULT computes in one clock and
  counts real latency separately ([`MULT.sv:81-125`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/MULT.sv#L81-L125)); N64 `hiloWait` counters; PSX `TURBO`. Keep accuracy
  stalls additive and removable; functional behavior must not depend on them.
- **Pre-register and replicate the "done" decision** feeding issue, forwarding and flag paths:
  compute `count <= 2` one edge early and replicate per consumer with `dont_merge maxfan`. ARM7 [`core:243-253`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L243-L253).
- **Interlock only dependents** of a busy unit; independent work overlaps (SH2 [`MULT.sv:168`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/MULT.sv#L168)).
- **Separate the arithmetic stage from saturation/flag formation**: flags computed from the registered result
  next cycle (PSX GTE [`gte_mac123.vhd:43-44`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/gte_mac123.vhd#L43-L44), [`106-143`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/gte_mac123.vhd#L106-L143)). Sticky flags OR into a summary bit — same shape as
  XER[SO] and FPSCR[FX/VX].
- Unit result joins through the normal result mux/bus; no extra write port (SS [`iu_pack.vhd:1684-1703`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L1684-L1703)).

## 6. Checklist

- [ ] One adder in the IU; inversion/carry selects registered from decode.
- [ ] One rotator+mask datapath for all rotate/shift ops; `rlwimi` third operand counted.
- [ ] Multiplier pipelined with DSP registers, or constrained multicycle with an enable and no 1-cycle case.
- [ ] Divider special cases handled outside the loop; OV/SO per architecture; exhaustive corner tests.
- [ ] Busy/done signals registered and replicated; only true dependents stall.
- [ ] Latency-modeling counters separable from functional timing.
