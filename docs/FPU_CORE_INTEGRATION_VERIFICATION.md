# FPU core integration verification

Evidence for [FPU core integration](FPU_CORE_INTEGRATION.md).

## Package-top timing with the FPU

Recorded: `flock /tmp/ppc603e-quartus.lock quartus/chip/build.sh --docker --fpu`,
then `quartus/report-target-paths.sh chip 20 --docker` and
`quartus/report-target-paths.sh chip --docker` (15.152 ns), 2026-10-01.
The `ppc603e` package top with `ENABLE_FPU=1` (FULL, 64-bit data path),
Quartus 17.0.2, seed 1, slow-corner setup slack at the 20 ns gate:

| Sources | 100C | −40C | Failing at 66 MHz | ALMs |
| --- | --- | --- | --- | --- |
| `dc1dd13` (batch 8 head `290a73b` plus `--fpu`) | −5.388 | −5.352 | — | 22,651 |
| `7124e81` | −4.032 (worst corner; 9,466 endpoints) | | 23,257, −8.880 | — |
| `7b81560` | +0.338 | +0.209 | 21,732, −4.639 | 23,100 |
| `3b10c94` | +0.704 | +0.746 | 18,489, −4.144 | 23,309 |

Hold slack is positive at all corners on every row (worst +0.059 ns, fast
−40C, `3b10c94`). At `3b10c94` a 18 ns re-time fails 737 endpoints (−1.296
ns), so 50 MHz holds with about 0.7 ns margin and 55 MHz does not.

On `dc1dd13` the worst paths (about 30 LUT levels, 25 ns) ran from
completion retirement (`count_q`, `done_q`) and `checkstop_q` through
`fp_head`, the FPU commit tag match and rename credit into `issue_ready`,
through the core's `iq_ready` and dispatch back into the FPU, where the
issue handshake selected the work slot; from there into decode, FPR reads,
the divider and arithmetic inputs, the launch value in `pending_q`, and the
memory request into the lane's `state_q`, `ea_q` and `fpu_data_q`. The
issue loop through the work slot predates batch 7; batch 7's overlapped FP
accesses (`c6ce84e`) added the dispatch-cycle memory request and reply
paths into the lane and the replay cancel in the issue-packet select.
Fixes, all without cycle changes:

- `7124e81`: the work slot and FPR read indices present the issue packet
  whenever no pending entry is selected; only the valid bit follows
  `issue_valid_i`. Issue readiness is formed from state with and without a
  head retirement, and retirement selects last.
- `7b81560`: the lane's issue-packet select follows `S_FPU_ISSUE`, not the
  cancel-gated valid; the FPR inspect read no longer follows the issue
  valid; `ppc_fpu` `MEM_AT_ISSUE=0` in the lane offers memory requests only
  from pending entries, which the lane already required (it accepts them
  only in `S_FPU_WAIT`).
- `3b10c94`: that select is its own flop, loaded from `state_d`.

At `3b10c94` the 66 MHz worst groups are `pending_q` (−4.144, from the
completion queue and the issue-packet select through decode), the FPU adder
(`aligned_q` to `add_q`, −4.102), the lane's `result_select_q` and `state_q`
(−4.099, −3.425) and the divider inputs (−3.669).

Recorded: `make -C sim -j2 lint check-spec lint-fpu-production
lint-fpu-stream lint-fpu-dual lint-fpu-compact test-core-fpu
test-core-fpu-split test-core-fpu-compact test-core-fpu-602 test-chip-fpu
test-selftest-fpu demo-whetstone-hf mister-smoke-fpu` and
`flock /tmp/ppc603e-sim.lock make -C sim -j2 test-fpu-all`, sources of
`3b10c94` (lint and `lint-fpu-*` on `7b81560`), 2026-10-01. All passed;
`test-fpu-all` printed 51 PASS lines. Every cycle count matches `290a73b`:
`tb_core_fpu` 30,011 cycles (FULL, no stalls, 41 spacings), 32,189 (split
data path), 33,077 (COMPACT), 37,433 (602); `test-chip-fpu` 88,268 cycles;
`selftest-fpu` 73,241,611; Whetstone 5,285,692 cycles (20.321 MWIPS at 50
MHz) and 20.324 MWIPS on the MiSTer smoke bench. Not established: the
MiSTer FPU build's timing (the coordinator fits it), other seeds.

## 602 personality

Recorded: `make -C sim -j2 lint check-spec test-core-fpu test-core-fpu-split test-core-fpu-compact test-core-fpu-602 test-core-fpu-602-compact test-chip-fpu variant-special-lint-602 variant-icache-602 variant-watchdog-602 variant-exception-602-4 variant-decode-sweep-4 test-chip602-pins test-core-full-decode test-decode-sweep test-core-lsu-extensions test-core-alignment test-core-alignment-dependencies test-core-lsu-update test-core-dcache test-chip-pins` and `flock /tmp/ppc603e-sim.lock make -C sim -j2 test-fpu-all`, commits `9240cbf`–`aade0b5` (RTL final at `87d9786`; later commits change only benches and docs), 2026-09-30.

All passed. `test-fpu-all`: 51 PASS lines.

| Bench | Result |
| --- | --- |
| `test-core-fpu-602` (FULL), `+STALL=1` | 1111 checks, 1106 words; 8748 retirements, 3546 FP; 825 released loads; 15 sticky-bit stalls; 40323 cycles |
| `test-core-fpu-602`, `+STALL=0` | 1114 checks, 2 spacing probes; 37433 cycles |
| `test-core-fpu-602-compact`, `+STALL=0` | 1114 checks; spacings reported, not checked; 36814 cycles |
| `test-core-fpu` (603e), `+STALL=0` | 2668 checks, 27 latency and 41 spacing probes; 30011 cycles, unchanged |

`sim/tools/fpu_core_602_program.py` (seed `0x602`, 200 random cases from the
standalone 602 enabled-exception generator) checks: `fsqrt` illegal with
MSR[FP]=0; a double `fadd` taking FP unavailable, then the emulation trap
after the handler enables FP; SP/LT written and read by `mtspr`, `mfspr` and
the `mftb` form, with MSR[FP]=0 too; tags after `lfs`, `fctiwz` and `mffs`;
problem-state `mfspr`/`mtspr` of them taking the privileged program
exception; emulation traps for a source without SP, double arithmetic,
`fctiw`, `mtfsf` of an SP source, `stfiwx` of an SP source, `stfd` of an LT
source and `lfd` of 1/3, each leaving frD, FPSCR and tags; single arithmetic,
`fres` as a divide, `frsp`, moves, `fsel`, `fcmpu`; `lfd` narrowing and
`stfd` widening; `lfs` at offsets 1, 2, 3, 5, 6, 7 and `lfd`/`lfdx` at
offsets 1–7 (three words), `lfsu` updating rA; DSI on the second word, the
third word and the first (DAR = EA); alignment for unaligned `stfs`,
`stfdu`, `stfsx`; a pipelined trapping `fadds` cancelling the overlapped
store behind it; the FP enabled program exception of `mtfsb1` with FE set;
and the exact number of sticky-bit stalls (the bench counts them; a wrong
count fails). With `+STALL=0` two independent `fadds` retire two cycles
apart when the second newly sets XX, one cycle apart when XX was already set.

The 603e and FPU-less benches cover the shared lane changes (word beats,
decode). `variant-special-lint-602` and `variant-watchdog-602` failed on
the base commit (their benches lacked the lane's FP ports); both benches
now declare them.

Recorded: `flock /tmp/ppc603e-quartus.lock quartus/chip602/analyze.sh --fpu`, commit `87d9786`, 2026-09-30.
Quartus 17.0.2 analysis and elaboration of `ppc602_measure` with
`ENABLE_FPU=1` (FULL): successful, 0 errors, 36 warnings (unused-signal and
index-width notices). No synthesis or fit.

Not established: fitted area and timing of the 602 top with the FPU; the
COMPACT elaboration of that top (`analyze.sh --fpu-compact`); 602 Table 6-5
and 6-6 timing in the core beyond the sticky-bit spacing; the 602 self-test
image, which has no 602 SoC to run on.

## Overlapped FP accesses and 64-bit data path

Recorded: `make -C sim -j2 lint check-spec test-core-fpu test-core-fpu-split test-chip-fpu`, commit `bf6d0c2`, 2026-09-30.
Commit `a6d29b6` differs in RTL only by a comment.

All passed.

| Bench | Result |
| --- | --- |
| `test-core-fpu` (`DMEM_BITS=64`), `+STALL=1` | 2598 checks, 1503 words; 6945 retirements, 2502 FP; 855 released loads; 32412 cycles |
| `test-core-fpu`, `+STALL=0` | 2667 checks, 27 latency and 41 spacing probes; 30011 cycles (36085 on `4b71784`) |
| `test-core-fpu-split` (`DMEM_BITS=32`), `+STALL=0` | 1574 checks, same probes with split-doubleword values; 32087 cycles |
| `test-chip-fpu` | self-check passes; 1 eight-byte single-beat read and 1 write (`+MIN_DWORDS=1`); 88268 cycles |

The no-stall runs check exactly every row of the
[contract table](FPU_CORE_INTEGRATION.md#execution-model): `fmr`, `fsel` and
FPSCR instructions now retire at dispatch + 4 (Table 6-5 1-1-1, like `fadd`);
`lfs`/`lfd` 6, stores 7 (8 and 9 for split doublewords); four independent
loads 15 cycles first to last, stores 18; an `lfd` followed by three `addi`
dispatching on consecutive cycles; `stfd` of an `fadd` result retiring 6
cycles after it; `lwz`/`stw` references at 5. The 64-bit bench model checks
that every doubleword request is aligned with all eight strobes. A directed
case takes an FP enabled exception at an `fsub` with an overlapped `stfd`
behind it: the replay cancels the store (counted, required non-zero), which
then stores once. `test-chip-fpu` clears HID0[DCE] around an `lfd` and `stfd`
on lines the cache never holds; the target counts one TSIZ 000, TBST-negated
read and write. Cached FP accesses go through the data cache as eight-byte
requests.

Recorded: `make -C sim -j2 -k lint check-spec test-core test-core-recovery test-core-lsu-update test-core-lsu-extensions test-core-alignment test-core-alignment-dependencies test-core-page-data-exception test-core-tlb-miss test-core-dcache test-core-dcache-negative test-core-machine-check-trace test-core-bat-machine-check test-chip-dcache-coherence test-core-bus60x-update test-core-control-memory test-dcache test-completion test-biu-dcache-snoop test-core-full-decode test-chip-pins`, commit `bf6d0c2`, 2026-09-30.
All pass (exit 0), including the data-cache mutations (rejected). These cover
the FPU-less builds, whose logic the change leaves as it was.

Recorded: `make -C sim -j2 test-selftest-fpu demo-whetstone-hf`, commit `a6d29b6`, 2026-09-30.
Both pass. Whetstone hard-float: 492,105 cycles, 20.321 MWIPS at 50 MHz
(0.4064/MHz); on `04b5bad` the same image took 702,049 cycles, 14.244 MWIPS
(the 64-bit path and `fmr` fix alone, `f531149`: 16.394). The self-test
retires 19,088,576 instructions with no failed case.

Recorded: `flock /tmp/ppc603e-sim.lock make -C sim -j2 test-fpu-all`, commit `a6d29b6`, 2026-09-30.
36 PASS lines, including 910 shell checks and the 603e and 602 timing checks
(71 and 52 responses). The standalone benches do not time retirement of moves;
the core bench above does.

A Quartus 17 analysis and elaboration of the `ppc603e` pin top with
`ENABLE_FPU=1` (chip file list plus `rtl/fpu_files.f`) passed on `bf6d0c2`
with 0 errors; the warnings are unused-signal notices. No fit was run.

Not established: fitted area and timing; Table 6-6 latency and interval (see
the contract's limits); FP update forms in the overlapped path (serialized);
eight-byte scalar transfers without the data cache.

## Enabling FE with FEX set

Recorded: `make -C sim lint test-exception-state test-exception-tlb-miss variant-exception-602-4 test-crstate-execution variant-special-lint-602 test-core-fpu test-core-fpu-compact test-core-fpu-602 test-core-fpu-602-compact test-core-fpu-split test-chip-fpu`, and with the unit (`BUILD_DIR=build-lsu VERILATOR=$PWD/tools/verilate-lsu-pipe`) `test-core-lsu-timing test-core-fpu test-core-fpu-602 test-core-fpu-compact test-core-fpu-602-compact`, commit 3ac2fe2, 2026-10-04: pass.

The FP core programs set FEX with FE0 = FE1 = 0 (`mtfsb1` VE, then VXSOFT),
then `mtmsr` FE0|FE1: the log holds a program exception at `mtmsr` + 4 with
SRR1 = new MSR | bits 11 and 15, and the FPSCR is unchanged by it. FULL and
COMPACT, 603e and 602, unit off and on (`test-core-fpu` 2676 checks,
`test-core-fpu-602` 1120). The 0x700 handler clears FE in SRR1 when bit 15
is set, so it returns without re-enabling FE. Quartus 17.0.2
`quartus_map --analysis_and_elaboration` of the chip top with ENABLE_FPU and
`PPC_LSU_PIPE=1`: 0 errors.

Not established: the same rule for `rfi` (not implemented, see the
integration limits); interaction with a pending external interrupt.

## Pipelined FP issue

Recorded: `make -C sim -j2 lint check-spec test-core-fpu test-chip-fpu variant-special-lint-602 test-crstate-execution` and `flock /tmp/ppc603e-sim.lock make -C sim -j2 test-fpu-all`, commit `4b71784`, 2026-09-30.

All passed; `test-fpu-all` reports 36 PASS lines, including 910 shell checks,
the 603e and 602 timing checks (71 and 52 responses) and 3000 enabled-exception
cases per personality. The FPU source change is a split of one combinational
process into three, with unchanged function.

| Bench | Result |
| --- | --- |
| `test-core-fpu`, retirement stalls (`+STALL=1`) | 1496 checked words; 6889 retirements, 2481 FP; 38626 cycles |
| `test-core-fpu`, no stalls (`+STALL=0`) | 1496 words, 25 latency probes, 31 spacing probes; 36085 cycles |
| `test-chip-fpu` | self-check of the image, including two DTLB misses; 85905 cycles, 108 read bursts |

The no-stall run checks, exact to the cycle, every latency and spacing in the
[contract table](FPU_CORE_INTEGRATION.md#execution-model): isolated
dispatch-to-retirement per class; retirement spacing of four independent
instances per class (two for divides and estimates), including `fcmpu` into
distinct CR fields; dependent chains of four for `fadd(s)`, `fmul(s)`,
`fmadd(s)`, `frsp`, `fmr` and `fsel`; `mffs` and `mtfsfi` pairs; and a mixed
`fadd`/`addi`/`fmuls`/`addi`/`fmadd`/`addi` stream dispatching one per cycle.
Expectations derive from Table 6-5 and Figure 6-3 in the generator.

With FP work in flight (both runs), the bench establishes:

- FP enabled (VXISI, VE, FE0/FE1) at a pipelined `fsub` with an `addi` and an
  `fadd` dispatched behind it (a dispatch-spacing probe confirms they were in
  flight): SRR0 at the `fsub`, the `addi` and `fadd` each take effect once,
  and the `fadd` then takes its own FP enabled exception because FEX stays
  set.
- DSI on a plain `lwz` with an `fadd` and `addi` dispatched behind it: both
  are removed and run once after the handler.
- DSI on `lfd` and `stfd` behind an older pipelined `fadd`, which retires
  first.
- A branch on a CR field written by an `fcmpu` in flight takes the right
  path, and an `fadd` behind a taken branch never executes.
- The earlier directed and 200 random enabled-exception cases, now through
  the pipelined path and its replay.

`test-chip-fpu` adds the same FP enabled and branch cases on the `ppc603e`
pin top, and DTLB load and store misses on `lfd` and `stfd` under data
translation, with a pipelined `fadd` between them: the 0x1100 and 0x1200
handlers log SRR0 and DMISS, load the TLB entry and retry.

Unchanged behavior with `ENABLE_FPU=0` was checked on commit `9618ea5` plus
the uncommitted chip TLB miss test, with `make -C sim -j2 check-spec
test-completion test-recovery-state test-flags test-completion-flags
test-completion-cr-fields test-completion-cr-bits test-crstate-execution
test-completion-update test-completion-ring variant-watchdog-602 test-core
test-exception-state test-decode-sweep test-core-full-decode
variant-full-decode-0 variant-full-decode-1 variant-full-decode-2
variant-full-decode-4 test-core-alignment test-core-data-fault
test-core-control-memory test-core-lsu-update test-core-cache-control
variant-icache-602`: all passed. `variant-special-lint-602` failed on a bench
port list and passed after the fix, on `4b71784`.

A Quartus 17 analysis and elaboration of `quartus/chip` (FPU off) passed on
`4b71784` with 0 errors. No fit was run.

Not established: fitted area and timing with pipelined issue; the FPU-on
Quartus analysis; page-changed and machine-check faults on FP accesses;
Table 6-6 timing for FP loads and stores (still serialized).

The earlier records below cover the serialized lane, which FP loads and
stores still use; their latency figures for arithmetic rows are superseded.

## Serialized integration

Recorded: `make -C sim -j2 lint check-spec test-core-fpu test-chip-fpu`, commit `fe35249`, 2026-09-30.

All passed. Lint now also covers `ppc_core` with `ENABLE_FPU=1` and the
`ppc603e` pin top with `ENABLE_FPU=1`.

| Bench | Result |
| --- | --- |
| `test-core-fpu`, retirement stalls (`+STALL=1`) | 1455 checked words; 6583 retirements, 2359 FP; 69 exceptions; 41060 cycles |
| `test-core-fpu`, no stalls (`+STALL=0`) | 1455 words and 24 latency probes; 38543 cycles |
| `test-chip-fpu` | self-check of 397 words (every nonzero mask) with 18 exceptions; 76133 cycles, 102 read bursts |

`test-core-fpu` runs `ppc_core` (supervisor, live context, full decode, FPU)
on one word-addressed memory with a protected DSI window, one program from
`sim/tools/fpu_core_program.py` (seed `0x603e`, 200 random cases) and exception
handlers that log SRR0, SRR1, DAR, DSISR and the vector. It establishes:

- Illegal forms before FP unavailable with MSR[FP]=0 (`fadd` with a nonzero
  frC field, `fsqrt`); FP unavailable on `lfd`, whose handler sets MSR[FP] in
  SRR1 and retries it.
- Every load and store form: `lfs`, `lfsu`, `lfsx`, `lfsux`, `lfd`, `lfdu`,
  `lfdx`, `lfdux`, `stfs`, `stfsu`, `stfsx`, `stfsux`, `stfd`, `stfdu`,
  `stfdx`, `stfdux`, `stfiwx`, with update-form base values and a word-aligned
  doubleword.
- `fmr`, `fneg`, `fabs`, `fnabs` on an SNaN and −0 with Rc=1 (CR1); `fsel`
  for ±0, negative, NaN and +∞ selectors; `fcmpu`/`fcmpo` into four CR fields
  with FPCC, VXSNAN and VXVC; `mcrfs`; `mtfsfi.`, `mtfsf.` with a field mask,
  `mtfsb0.`, `mtfsb1`; `fres`/`frsqrte` special operands (FR/FI masked as
  undefined).
- Alignment on `lfd`, `stfdu` and `lfdx` with DAR, DSISR, unchanged FPR and
  base; DSI on a load, a store (store bit) and an `lfdu` whose second word
  faults (DAR = EA+4, base unchanged).
- FP enabled program exception from `mtfsb1` with FE0/FE1 set: SRR1 bit 11,
  FPSCR update committed.
- 200 random arithmetic cases from `sim/fpu/enabled_vectors.py` (`fadd` …
  `fnmadd` single and double, `frsp`, `fctiw`, `fctiwz`) with random
  VE/OE/UE/ZE/XE, NI, RN, FE0/FE1 and Rc: FPR result or preserved sentinel,
  FPSCR (FR masked after disabled overflow), CR, and the program exception
  whenever `(FE0∨FE1)∧FEX`. Expectations come from the Python reference
  model, not from the RTL.
- Random retirement backpressure (one cycle in four), which also delays store
  authorization at the queue head.
- The dispatch-to-retirement latencies in the contract table, exact to the
  cycle without stalls.

`test-chip-fpu` runs a self-checking build of the same generator (40 random
cases, no DSI section) on the `ppc603e` pin top from the hard reset vector
with HID0[DCE] set, against the coherent 60x target with random wait states,
ARTRY and DRTRY. It establishes that FP loads and stores through the data
cache and 60x bus produce the same results and exceptions; a program with one
corrupted expectation fails through the mailbox.

A second seed also passed on commit `1b21d14`:
`make -C sim test-core-fpu FPU_CORE_SEED=0x51ed FPU_CORE_RANDOM=500` checked
3240 words with 126 exceptions and 5659 FP retirements.

Unchanged behavior with `ENABLE_FPU=0` was checked on commit `80d9db9`, the
integration commit, with `make -C sim -j2 test-core test-crstate-execution
test-exception-state test-decode-sweep test-core-full-decode
variant-full-decode-0 variant-full-decode-1 variant-full-decode-2
variant-full-decode-4 variant-watchdog-602 variant-special-lint-602
test-core-alignment test-core-data-fault test-core-control-memory
test-core-lsu-update test-core-cache-control variant-icache-602`: all passed,
including FP unavailable in `tb_core_full_decode` (8669 checks, 70 events).

The standalone FPU sources are unchanged; `make -C sim -j2 test-fpu-shell`
passed on commit `ef993c5` (910 checks). `test-fpu-all` was not run for this
record; the batch gate runs it.

Not established: overlap or Table 6-5 throughput (the lane is serialized by
design); TLB miss, page-changed and machine-check faults on FP accesses;
recovery cancelling an FP instruction; compiled FP firmware (no PowerPC
cross-compiler or toolchain container on the build machine); fitted area and
timing with the FPU in the core.
