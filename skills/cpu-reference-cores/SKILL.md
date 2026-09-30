---
name: cpu-reference-cores
description: Load when you need precedent for a CPU microarchitecture decision (pipeline, forwarding, regfile, cache, TLB, exceptions, mul/div, FPU, bus, trace/savestate) and want to see how a shipping MiSTer/FPGA CPU did it. Indexes six mined cores — N64 VR4300, PSX R3000A, Saturn SH-2, SparcStation SPARC V8, Atari7800 ARM7TDMI, z486 with x87 FPU — with per-core reports carrying file:line evidence and ranked 603e lessons.
---

# Reference CPU cores — index and citation key

Six FPGA CPUs were read in depth. Each report in `references/` has one section per design
dimension with file:line evidence, then a ranked "Top transferable lessons for a 603e core" list.
Links are pinned to the reviewed commits; line numbers refer to those commits.

| Key | Core | Source | HDL | Clock | Report |
|---|---|---|---|---|---|
| **N64** | NEC VR4300 (MIPS III, 64-bit) | [MiSTer-devel/N64_MiSTer](https://github.com/MiSTer-devel/N64_MiSTer/tree/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl) | VHDL | 93.75 MHz native | `references/n64-vr4300.md` |
| **PSX** | LSI CW33300 (MIPS R3000A) + GTE | [MiSTer-devel/PSX_MiSTer](https://github.com/MiSTer-devel/PSX_MiSTer/tree/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl) | VHDL | 33.87 MHz native | `references/psx-r3000.md` |
| **SH2** | Hitachi SH7604 (SH-2) + SH7034 | [MiSTer-devel/Saturn_MiSTer](https://github.com/MiSTer-devel/Saturn_MiSTer/tree/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH) | SystemVerilog | 28.6 MHz (57 MHz, CE/2) | `references/saturn-sh2.md` |
| **SS** | SPARC V8 (MicroSPARC-II/SuperSPARC personality) | [Grabulosaure/ss](https://github.com/Grabulosaure/ss/tree/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu) | VHDL | 65 MHz target, 54 MHz achieved | `references/ss-sparc.md` |
| **ARM7** | ARM7TDMI | [MiSTer-devel/Atari7800_MiSTer](https://github.com/MiSTer-devel/Atari7800_MiSTer/tree/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi) | SystemVerilog | 71.58 MHz, fails by 0.8–2.5 ns | `references/a7800-arm7tdmi.md` |
| **Z486** | i486-class x86 + x87 FPU | [nand2mario/z486](https://github.com/nand2mario/z486/tree/53dc450e01302c174f75fc9280417a4dc5884863) | SystemVerilog | 57.95 MHz DE10-Nano fit; MiSTer release at 85 MHz | `references/z486-x87.md` |

Line numbers were spot-checked, not all re-verified; open the source before quoting a line as fact.

## What each core is good evidence for

- **N64** — best all-round template for a scalar in-order core at ~94 MHz on Cyclone V. Registered
  forwarding selects, MLAB regfile copies, µTLB + sequential main TLB, VIPT D-cache launched from
  EX, duplicated I-tags for parallel next-PC, cache fill straight from DDR3 into dual-port BRAM,
  unified in-order request FIFO, delta retirement trace, savestate-as-reset-value.
  *Weak:* every load bubbles; long ops freeze the whole pipe; silent timing shortcuts.
- **PSX** — non-blocking loads with 1-entry scoreboard and WAW squash, forwarding-enable-based
  visibility rules, per-source stall bits, per-word-valid I-cache with critical-word-first fill,
  write buffer FIFO, GTE micro-sequencing tables, table-seeded Newton–Raphson divide, sim-from-savestate.
  *Weak:* closes only because 34 MHz; same-cycle branch → async tag → fetch path.
- **SH2** — cleanest SystemVerilog: packed decoded-instruction record carried to WB, microcode as
  `decode(IR, STATE)`, exceptions as pseudo-instructions, R0/PR flop shadows for extra ports, flash
  invalidate bitmap, pairwise LRU, MAC as bus slave with latency counter, SoC register structs with masks.
  *Weak:* relies on CE/2; no address-error exceptions; stale duplicate RAM modules.
- **SS** — precise FPU via in-order FIFO + commit counter (no ROB), committed shadows of PSR/Y,
  faults as data on the bus, drain-before-redirect, epoch-tagged TLB flash invalidate, two-phase
  VIPT with AND-OR way select, LRU in tag word, dual-port tag for snoop, debug by instruction
  injection, FPU output skid (`SSTALL`). *Weak:* combinational ack→PC stall chain, CC→fetch branch
  path; ships with negative slack; SRT divider marked buggy; NaNs not PowerPC-correct.
- **ARM7** — best-documented timing campaign: rename-by-index banked regfile, "which vs whether"
  write-port funnel, forward-valid without handshake terms, operand-source codes + flat mux,
  predecoded read ports, condition vector, one-rotator shifter, iterative multiplier with hoisted
  corrections, replicated `dont_merge maxfan` retire flags, disciplined SDC with loud guards.
  *Weak:* still fails timing; raw memory response enters bypass; 140 loose signals instead of a
  struct; resets datapath arrays; no in-repo tests.
- **Z486** — the area reference for an FPU beside a CPU on Cyclone V: binary64-width x87 in ~5.6k ALMs.
  One work register, adder and rounder shared by all ops; 53×53 multiply as four 27×27 DSP limbs with
  carries over registered steps; shared div/sqrt recurrence; FP registers in M10K; horizontal microcode
  from a generator that rejects lane conflicts. Also valid-in-tag-word caches and `KEEP` address replicas.
  *Weak:* incomplete x87 (53-bit significand), no FMA, one op at a time, variable latency; released clock
  exceeds the reported Fmax.

## How to use a report

1. Find the dimension section in the report; follow the links and read the source lines yourself.
2. Check the core's clock: a technique that closes at 34 MHz (PSX) or CE/2 (SH2) may not at 603e rates.
3. Prefer lessons that two or more cores agree on; treat single-core tricks as options.
4. Every report ends with pitfalls; check your design against them before review.

## Checklist

- [ ] The cited technique was read at the linked source lines, not only in the report.
- [ ] The source core's clock and CE scheme were compared with the 603e target.
- [ ] At least two cores agree, or the lesson is labeled a single-core option.
- [ ] The report's pitfalls were checked against the design.
- [ ] Citations are GitHub permalinks at the reviewed commit.
