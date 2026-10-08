<!-- SPDX-License-Identifier: GPL-2.0-or-later -->
<!-- Copyright (c) 2026 Kevin Dedon -->

# Performance target: 1:1 with a 603e

The goal is the same Dhrystones per MHz as a real MPC603e on the same binary.
1:1 means matching the manual's timing, not beating it: no change may make an
instruction sequence faster than the 603e would run it. This document defines
the target, measures the core against it and ranks the gaps. The CPI method and
counters are in [PERFORMANCE.md](PERFORMANCE.md).

## Target

| Definition | Cycles per Dhrystone run | Dhrystones/s per MHz | DMIPS/MHz | Firmness |
|---|---:|---:|---:|---|
| **Primary.** Our binary on a manual-accurate PID7v 603e, warm caches | **509** | **1965** | **1.118** | Model, about ±10% |
| Same, PID6 (37-cycle divide) | 526 | 1901 | 1.082 | Model |
| Published Motorola figure (other compiler and library) | (406) | 2460 | 1.40 | Vendor, compiler unstated |

CoreMark on the same model: CPI 0.918 over one full iteration (319,000
instructions), about **3.6 CoreMark/MHz** (3.4–3.7 for multiply costs of 2–5 cycles).
No published 603e CoreMark exists; CoreMark postdates the part.

### Primary definition

The binary is `toolchain/build/demo/dhrystone.hex` as the demo Makefile builds it:
pinned gcc, `-O2 -mcpu=603e -msoft-float`, `DHRY_RUNS=2000`, the demo runtime's
own `strcpy`/`strcmp` (byte loops, `-fno-builtin`). One run is 590.0 retired
instructions. The timed loop starts at `dhry_main+0x1d4`; `perf-diff` resolves it from the dump.

`sim/tools/perf_model_603e.py` schedules the retired instruction stream of that
loop against the MPC603e User's Manual (MPC603EUM/AD 11/97) and reports the
cycles a 603e needs. Each rule cites its source in the code:

| Rule | Source |
|---|---|
| Fetch: I-cache hit in the IQ one cycle after request, two instructions per cycle, six-entry IQ filled on any vacancy | UM 6.3.1, 6.3.2.1, 6.3.2.2; F6-3 |
| Branches leave the stream (folding); BPU executes the cycle after fetch; taken target in the IQ two cycles after the branch | UM 6.4.1.1; F6-3 (`br` 2F 3E, target 4F) |
| Static prediction (backward taken, `y` flips); one level; fetch stops for `bclr` after `mtlr`, `bcctr` after `mtctr`, CR branch behind a predicted one | UM 6.4.1.1, 6.4.1.2, 6.6.1.1 |
| Misprediction: correct path in the IQ the cycle after resolution, dispatch the next | F6-5 (`bc` 5E, target 6F 7D) |
| `cmp` CR forwarded to the BPU at end of execute | T6-4 `^` |
| Dispatch two per cycle in order; DQ1 needs a different free unit; five CQ entries, five GPR renames (update forms take two) | UM 6.3.3, 6.6, 6.6.1.2 |
| Reservation station per unit; operands from rename on the cycle they are written | UM 6.3.3, 6.3.3.1 |
| IU one execute stage; multiply 1 + multiplier bytes; divide 20 (PID7v) or 37 (PID6) | UM 6.4.2; T6-4; UM 1.1 |
| SRU adder runs `add`/`addo`/`addi`/`addis`/`cmp*` beside the IU; on a start-cycle tie it takes the one the next integer instruction does not need | UM 1.1.2.2.3, 6.4.5; T6-4 note 1; UM 6.3.3 |
| LSU two stages (EA/translate, cache), 2-cycle load-use, one access per cycle | UM 6.4.4; T6-6 `2:1` |
| Completion two per cycle in order; CQ1 only integer or load; ≤2 GPR, ≤1 CR writes; stores, SRU and FP only from CQ0; nothing completes behind an unresolved prediction | UM 6.3.3, 6.6.1.3 |
| Completion-serialized SRU work (`mfspr`, `mtspr`, CR logicals) starts after all older work completes, result forwarded after it completes; `mtspr` 2 cycles | UM 6.3.3.2, 1.1.4.4; T6-2 |

Assumptions (`perf_model_603e.py --assumptions` prints them):

- A1: caches always hit. Dhrystone and CoreMark fit in 16 KB.
- A2: a fetch pair is one aligned doubleword. Any pair instead: 500 cycles.
- A3: branches use no IQ entry, dispatch slot, CQ entry or rename.
- A4: a CR made by a non-compare instruction reaches the BPU in that
  instruction's completion cycle (F6-5).
- A5: a CTR branch behind a CTR branch waits one cycle after the first resolves.
- A6: no store-to-load or store-queue port conflicts (addresses are not traced).
- A7: work behind a correctly predicted branch may complete in its resolve cycle.
- A8: `mullw`/`mulhw` take 3 cycles without operand values (CoreMark only).
- A9: a station accepts the next instruction when the previous starts executing.
- A10: SRU adder present (603e only; UM C.2.3). The manual gives no unit-steering
  rule: an add or compare takes the unit that starts it first and, on a tie, the
  SRU when the next non-branch instruction needs the IU (UM 6.4.5 "in parallel
  with another integer instruction"; an IU station it held would stall that
  instruction, UM 6.3.3). IU on every tie: 521 cycles. Without the adder: 526.
- A11, A12: SRU serialization as above.
- A13: the single CR rename (UM 6.3.3.1) is not a dispatch condition (UM
  6.6.1.2 lists only GPR and FPR renames); a CR writer finishes, writing the
  rename, no earlier than the cycle after the previous CR writer completes.
- A14: a held branch stops fetch (UM 6.4.1.1 "Fetching is stopped"); the
  word fetched beside it stays, and the next fetch is the cycle after the
  branch executes. A CR branch behind an unresolved predicted branch is held
  even when its own CR is ready (UM 6.6.1.1).
- A15: an instruction after a branch dispatches no earlier than the branch
  executes; a held branch is not yet predicted, and the 603e executes through
  one level of prediction (UM 6.4.1.1, 6.4.1.2). No Dhrystone change.

Sensitivity of the primary figure: 502–526 cycles across A2, A10 and the divide.
A6 and A7 make the model optimistic (fewer cycles), so the target is, if anything,
slightly strict. The model has not been replayed against Figures 6-3 to 6-5
cycle by cycle; doing so is the first step that would firm it up.

### Published figures

| Source | Figure | DMIPS/MHz |
|---|---|---:|
| Motorola MPC603e fact sheet PPC603EFACT/D: "188 MIPS @ 133 MHz", "423 MIPS @ 300 MHz" ([PDF](http://oldcomputer.info/portables/tp850/603e_fs.pdf)) | MIPS, version unstated | 1.41 |
| MPC8260 Technical Summary, G2 (603e) core: "In Dhrystone 2.1 MIPS, the G2 is 280 MIPS at 200 MHz" ([PDF](https://www.nxp.com/docs/en/product-brief/MPC8260TS.pdf)) | Dhrystone 2.1 | 1.40 |
| Kontron VMP1, MPC8240 at 250 MHz: "375 Dhrystone (2.1) MIPS" ([datasheet](https://www.kontron.com/download/download?filename=%2Fdownloads%2Fdatasheets%2Fvmp1_datasheet.pdf&product=86837)) | Dhrystone 2.1 | 1.50 |
| Motorola Host and Integrated Processor Summary, 2003: "253MIPS @ 133 MHz" ([PDF](https://www.nxp.com/docs/en/supporting-information/PPCCPUSUMM.pdf)) | Marketing; rates the 750 below the 603e | 1.90 |
| MPC5200B brief, G2_LE core: "760 Dhrystone 2.1 MIPS" at 400 MHz ([PDF](https://www.nxp.com/docs/en/product-brief/MPC5200BPB.pdf)) | Dhrystone 2.1, later core | 1.90 |

All are vendor figures with no compiler stated. The 1.40 figures date from
the part's production years and agree across three documents; the 1.90 ones
come from later summaries that assign the same figure to every G2 part. A
period commercial compiler with tuned string routines runs fewer instructions
per Dhrystone than our build (590): matching 1.40 DMIPS/MHz with our binary
would need CPI 0.69, below what the model allows the 603e. The gap between 1.13
and 1.40 is the compiler and library, not the core, so the published figure
cross-checks the model's order of magnitude but is not the target.

## Today

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=build-lsu-w<1|2> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe demo-soc-model`, then `Vtb_demo_soc +IMAGE=toolchain/build/demo/<dhrystone|coremark>.hex`, commits 5d0d244 (before) and 60b0659 (after), 2026-10-04.
LSU unit and store queue on. All pass (Dhrystone checks match, CoreMark CRCs
match). Firmware built by the demo Makefile defaults (2000 runs, 10 iterations).
"Before" is the core this document was written against; "after" adds update
forms and rename-sourced operands in the unit and the one-cycle store hit
([gaps 1, 2, 6, 7](#gaps)).

| | Width 1 before | Width 2 before | Width 1 after | Width 2 after | 603e model | Core / 603e (width 2, after) |
|---|---:|---:|---:|---:|---:|---:|
| Dhrystone cycles per run | 2067.9 | 1950.4 | 1454.3 | 1454.3 | 506 | 2.87 |
| Dhrystones/s per MHz | 483.6 | 512.7 | 687.6 | 687.6 | 1976 | |
| DMIPS/MHz | 0.275 | 0.292 | 0.391 | 0.391 | 1.125 | |
| Dhrystone CPI | 3.504 | 3.305 | 2.464 | 2.464 | 0.858 | |
| CoreMark/MHz | 1.236 | 1.259 | 1.312 | 1.313 | about 3.6 | 2.74 |
| CoreMark CPI | 2.676 | 2.628 | 2.520 | 2.520 | 0.918 | |

After the change both widths run Dhrystone in the same cycles: fetch, one
instruction per cycle in this build, now sets the pace (`fetch_empty` 0.85
CPI, `drain_memory` and `lsu_busy` under 0.001), so the second dispatch slot
rarely finds a partner.

The CPI breakdown by stall cause is in
[PERFORMANCE.md](PERFORMANCE.md#cpi-with-the-lsu-unit-and-store-queue).

Recorded: `Vtb_demo_soc +IMAGE=toolchain/build/demo/dhrystone.hex +TRACE=1000000 +TRACE_TO=1012000` on both models, then `python3 sim/tools/perf_model_603e.py <log> --mark fff03808 --dump toolchain/build/demo/dhrystone.dump`, commit 5d0d244 plus the `+TRACE_TO` testbench change, 2026-10-04.
18 whole iterations of the timed loop. The core's cycles per iteration in the
trace (2067.5 and 1950.0) match the firmware's cycles per run. The same on
the width-2 model at commit 60b0659: 1454.0 cycles per iteration. CoreMark used
`+TRACE_TO=1320000` and no `--mark` (one window of 319,000 instructions, CPI
2.672 / 2.626 against the run's 2.676 / 2.628).

## Fetch and branch round

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=build-perf-w<1|2> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe demo-soc-model`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/<dhrystone|coremark>.hex`, commit 9dae6d9, 2026-10-04.
LSU unit and store queue on; prebuilt firmware (2000 runs, 10 iterations).
All four runs pass their checks. Each step is measured with the steps above
it; the step rows ran on scratch copies of the tree at that step, the last
row on 9dae6d9 itself.

| Step | Commit | Dhrystone cycles/run, w1 | w2 | CoreMark/MHz, w1 | w2 |
|---|---|---:|---:|---:|---:|
| Before | 5d0d244 | 2067.9 | 1950.4 | 1.236 | 1.259 |
| Two-word fetch through the wrappers (gap 3) | 800c8f4 | 1960.8 | 1824.3 | 1.328 | 1.376 |
| Speculative `bc` (gap 4) | 762e5c8, 9dae6d9 | 1836.8 | 1801.3 | 1.380 | 1.446 |
| `bclr` from the shadow LR (gap 10) | efdba96 | 1826.8 | 1793.8 | 1.380 | 1.446 |
| Unresolved `bc` + DQ1 pair, DQ1 access into the unit (gap 5) | 98e94dd | 1826.8 | 1768.8 | 1.380 | 1.449 |
| All, on the final commit | 9dae6d9 | 1826.8 | 1768.8 | 1.380 | 1.449 |

The width-1 speculative-`bc` row predates two fixes in 9dae6d9's parent
chain (no lane adoption behind the branch; the branch retires only from
CQ[0]); neither applies to a width-1 run without faulting accesses. At width 2
Dhrystone takes 9.3% fewer cycles (CPI 3.305 → 2.997) and CoreMark/MHz
rises 15.1%; the 603e model is still 3.5 times faster on Dhrystone.

Per Dhrystone run at width 2, `drain_branch` falls from 187 cycles to 0,
`branch_refetch` and `fetch_empty` together from 258 to 148. What remains is
memory: `drain_memory` (501 per run) and `lsu_busy` (502) now dominate, which
gaps 1 and 2 address. Branches still take a CQ entry (gap 8 is open).

## Both rounds together

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=build-d<1|2> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe demo-soc-model`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/<dhrystone|coremark>.hex`, commit 062da5e, 2026-10-04.
The LSU round ([Today](#today)) and the fetch and branch round on one
tree; unit and store queue on, prebuilt firmware (2000 runs, 10
iterations). All four runs pass their checks (Dhrystone values, CoreMark
CRC 0xfcaf).

| | LSU round, w1 | w2 | Fetch/branch round, w1 | w2 | Both, w1 | w2 |
|---|---:|---:|---:|---:|---:|---:|
| Dhrystone cycles per run | 1454.3 | 1454.3 | 1826.8 | 1768.8 | 998.8 | 992.3 |
| DMIPS/MHz | 0.391 | 0.391 | | | 0.569 | 0.573 |
| Dhrystone CPI (timed loop) | 2.464 | 2.464 | | | 1.692 | 1.681 |
| CoreMark/MHz | 1.312 | 1.313 | 1.380 | 1.449 | 1.748 | 1.786 |

The gains compound: with memory no longer draining the machine, fetch and
branch time is what is left, and the second round removes much of it. The
603e model is still 1.96 times faster on Dhrystone. Width 2 barely helps:
per Dhrystone run it dispatches in 0.87 CPI against 1.02 at width 1, but
`fetch_empty` and `branch_refetch` grow from 0.39 to 0.62, while station
and flag waits fall from 0.13 to 0.04. The DQ1 access still needs committed
sources, unlike DQ0's.

### With FP stores at one per cycle

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=build-d<1|2> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe demo-soc-model`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/<dhrystone|coremark>.hex`, commit ac9db33, 2026-10-04.
The tree above with the FPU store-data lookup merged; same prebuilt
firmware, all four runs pass their checks.

| | w1 | w2 |
|---|---:|---:|
| Dhrystone cycles per run | 998.8 | 992.3 |
| DMIPS/MHz | 0.569 | 0.573 |
| CoreMark/MHz | 1.748 | 1.786 |

Unchanged, as expected: both programs are integer-only, and the merge
touches only FP store data and the FP-enabled exception.

## Fetch and branch round 2

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=build-perf-w<1|2> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe demo-soc-model`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/<dhrystone|coremark>.hex`, commits 311a5be, a20c314 and b28e2ad, 2026-10-04.
LSU unit and store queue on; prebuilt firmware (2000 runs, 10 iterations).
All runs pass their checks. Step 1 ran on 311a5be itself; steps 2 and 3 ran
on scratch copies of the tree at those commits with a simulation-only
pairing counter added. Step 3 changes only dual dispatch, so width 1 was not
rerun.

| Step | Commit | Dhrystone cycles/run, w1 | w2 | CoreMark/MHz, w1 | w2 |
|---|---|---:|---:|---:|---:|
| Before | 9dae6d9 | 1826.8 | 1768.8 | 1.380 | 1.449 |
| A cache hit fetched every cycle (gap 3) | 311a5be | 1776.8 | 1716.3 | 1.451 | 1.545 |
| Misprediction recovered at resolution (gap 4) | a20c314 | 1766.8 | 1704.3 | 1.461 | 1.562 |
| A DQ0 branch that does not redirect pairs (gap 5) | b28e2ad | 1766.8 | 1699.3 | 1.461 | 1.563 |

At width 2 Dhrystone takes 3.9% fewer cycles than before the round (CPI
2.997 → 2.880) and CoreMark/MHz rises 7.9%. Dispatch alone falls from 0.803
to 0.794 CPI on Dhrystone.

Unpaired cycles at width 2 (Dhrystone, 2000 runs, from the counter) where
DQ0 dispatched and DQ1 held an instruction:

| DQ0 | DQ1 | Cycles | Why |
|---|---|---:|---|
| Integer | Conditional `bc` | 198,554 | DQ1 dispatches only folded `b` or branch-always |
| Serialized (update forms, SPR moves) | Any | 187,925 | Dispatches alone (gap 1) |
| Integer | Non-SRU integer | 90,317 | Same unit |
| Integer | Update form | 67,280 | Serialized (gap 1) |
| LSU-unit access | Access | 59,328 | Same unit |
| Integer | SRU form or access, pair allowed | 68,501 | CQ[1] full (75,523 of all blocked), DQ1 access sources uncommitted (30,603, gap 2) |

A `bc` dispatched speculatively from DQ1 beside the compare that sets its CR
(UM 6.6.1.2 allows it) was tried and dropped: Dhrystone 1704.3 cycles/run
(no gain), CoreMark/MHz 1.551 instead of 1.563.

## Batch 12 integration

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=build-d<1|2> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe demo-soc-model`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/<dhrystone|coremark>.hex`, commit 29d1376, 2026-10-04.

Both rounds, FP stores at one per cycle, fetch and branch round 2, real-mode
instruction caching and the bus fixes together. All runs pass their checks
(Dhrystone 23 values, CoreMark CRCs).

| | Width 1 | Width 2 |
|---|---:|---:|
| Dhrystone cycles/run | 863.8 | 775.8 |
| DMIPS/MHz | 0.658 | 0.733 |
| CoreMark/MHz | 1.991 | 2.136 |

Width 2 is 1.53× the target's 506 cycles/run (was 1.96× at 992.3).

## DQ1 rename operands and base snooping

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe demo-soc-model` (base snooping: a `VERILATOR` wrapper adding `+define+PPC_LSU_PIPE=1 +define+PPC_LSU_BASE_SNOOP=1`), then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/<dhrystone|coremark>.hex`, commits b48ef0c (before), be4c1f0 (DQ1 rename operands) and 6546dc5 (base snooping), 2026-10-04.
Unit and store queue on, prebuilt firmware as above. Every run passes its
checks (Dhrystone 23 values, CoreMark CRC 0xfcaf).

| | Before, w1 | w2 | DQ1 rename, w1 | w2 | + base snoop, w1 | w2 |
|---|---:|---:|---:|---:|---:|---:|
| Dhrystone cycles per run | 998.8 | 992.3 | 998.8 | 992.8 | 998.8 | 991.8 |
| DMIPS/MHz | 0.569 | 0.573 | 0.569 | 0.573 | 0.569 | 0.573 |
| CoreMark/MHz | 1.748 | 1.786 | 1.748 | 1.786 | 1.749 | 1.786 |

Both changes meet their Table 6-6 rows in the benches
([LSU_PIPELINE.md](LSU_PIPELINE.md#base-snooping)) but move neither
benchmark. DQ1 now pairs 5 more accesses per Dhrystone run, and base
snooping cuts `drain_memory` from 24 to 2 cycles per run; the cycles move
to `branch_refetch` and `fetch_empty`, which stay at 0.63 CPI. Width 1 is
unchanged.

What is left outside fetch, from `Vtb_demo_soc +PROFILE` (stall cycles by
cause and head instruction, and why DQ1 stayed behind DQ0, over the counted
region; width 2, base snooping):

| Dhrystone, per run | Cycles | |
|---|---:|---|
| `mflr`/`mtlr` waiting for the machine to drain | 20.5 | UM 6.3.3.2: SRU ops are completion-serialized; they wait in the unit, not at dispatch, so younger work dispatches behind them |
| CQ full | 19.6 | five entries, as the 603e |
| IU station full | 19.5 | one station per unit, as the 603e |
| unattributed (`other`), flag token | 10.0, 7.0 | |

| Dhrystone, slots per run where DQ1 stayed | Slots | |
|---|---:|---|
| IU + unfolded `bc` in DQ1 | 50.5 | only a folded `b` or branch-always pairs in DQ1 |
| access + IU, one CQ entry free | 39.0 | as the 603e |
| update form in DQ0 | 33.5 | update forms dispatch alone |
| branch + IU, station busy | 19.0 | |

CoreMark, the counted region (5.6 M cycles): the flag token holds dispatch
for 431,000 cycles (7.7%), the CQ is full for 147,000 and `mtspr` drains for
65,000; DQ1 stays behind an IU op for 320,000 slots with an unfolded `bc`
and 255,000 with a second integer op that is not SRU-capable.

The `mflr`/`mtlr` drain, the flag token and the unpaired `bc` are taken up
in the [next round](#serialization-flag-token-and-dq1-branches).

## Serialization, flag token and DQ1 branches

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe demo-soc-model`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/<dhrystone|coremark>.hex +PROFILE`, commits d49bfcf (before), a1dfaa1 (moves), 2df5715 (flag token) and 19726fc (DQ1 `bc`), 2026-10-04.
Unit and store queue on, base snooping off, prebuilt firmware (2000 runs,
10 iterations). Every run passes its checks (Dhrystone values, CoreMark
CRC 0xfcaf). Each step includes the ones above it.

| | Dhrystone cycles/run, w1 | w2 | CoreMark/MHz, w1 | w2 |
|---|---:|---:|---:|---:|
| Before (d49bfcf) | 998.8 | 992.8 | 1.748 | 1.786 |
| LR/CTR moves completion-serialized (a1dfaa1) | 987.8 | 981.3 | 1.768 | 1.800 |
| Flag token is the CR rename only (2df5715) | 987.8 | 981.3 | 1.784 | 1.821 |
| `bc` in DQ1 (19726fc) | 987.8 | 981.3 | 1.784 | 1.819 |

Dhrystone takes 1.1% fewer cycles at width 1 and 1.2% at width 2 (0.579
DMIPS/MHz, was 0.573); CoreMark is 1.8% faster
at width 2 and 2.1% at width 1.

- Moves (UM 6.3.3.2: SRU instructions other than add and compare are
  completion-serialized; only `mtspr(XER)` among SPR moves is dispatch
  serialized). `mflr`, `mfctr`, `mtlr` and `mtctr` dispatch into a holding
  slot and execute in the lane at the CQ head; younger work dispatches
  behind them, and a reader of the result waits for its retirement. The
  drain falls from 20.5 to 1.0 cycles per Dhrystone run (CoreMark: 73,254
  to 2,248 cycles). Other SPR moves still drain.
- Flag token (UM 6.3.3.1: one CR rename, no XER rename). The token stood
  for CR and XER together, so a compare waited behind `subfc` or `srawi`,
  and `subfc` behind a compare. Now an instruction that writes only CA, OV
  or SO takes no token; a CA or SO reader waits at dispatch until the
  youngest older writer retires (later than the 603e's in-order IU, never
  earlier). CoreMark flag waits fall from 402,676 to 341,120 cycles. The
  rest are CR writer behind CR writer (`cmpwi` behind `andi.`, 126,000;
  `cmpwi` behind `cmpwi`, 70,000), which the single CR rename also
  serializes; the token is reusable the cycle after the owner retires.
- `bc` in DQ1 (UM 6.4.1.2, F6-5: the BPU predicts a `bc` whose CR is
  pending while its producer dispatches). A `bc` on a CR bit alone pairs
  with DQ0 when its CR is final and agrees with the fetch path, or when
  DQ0 writes its CR; it is then predicted. IU + unfolded `bc` slots fall
  from 50.5 to 19.0 per Dhrystone run (CoreMark 262,994 to 70,096), but
  cycles do not move: 23.5 of them now wait for two CQ entries (branches
  still take one, gap 8), and in CoreMark the next compare waits for the
  CR token instead (flag waits 341,120 to 384,107). An earlier version
  that also predicted behind an older unfinished CR writer ran Dhrystone
  in 985.3 cycles at width 2: that writer often finished a cycle later,
  when DQ0 would have resolved the branch, and a miss here recovers at
  retirement, later than F6-5.

## Batch 13 start and CQ[1] retirement

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe demo-soc-model`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/<dhrystone|coremark>.hex +PROFILE`, commits c77ae69 plus the profiler change of 9906d74 (before) and 9906d74 (after), 2026-10-04.
Unit and store queue on, base snooping off, prebuilt firmware (2000 runs,
10 iterations). Every run passes its checks.

Profile at c77ae69, Dhrystone at width 2, cycles per run (entries of at
least 1.5):

| Cause | Cycles/run |
|---|---:|
| CQ full, `SPECIAL_NONE` at DQ0 | 50.6 |
| CQ full, `SPECIAL_STORE` | 16.5 |
| CQ full, `SPECIAL_LOAD` / `SPECIAL_MFSPR` | 3.0 / 2.5 |
| RS full | 32.5 |
| Flags wait | 28.0 |
| Drain for memory (load / store) | 20.5 / 2.0 |
| LSU busy (load / store / other) | 9.0 / 7.0 / 2.0 |
| Drain for `mtspr` | 3.0 |
| Special lane busy (store / other) | 3.0 / 2.0 |
| Other, store at DQ0 | 3.0 |
| Drain for branch | 2.0 |
| CQ[1] finished but held beside a retiring head (was "other") | 90.5 |

The profiler now names the held cases and the finished CQ[1] entries the
queue did not offer (UM 6.6.1.3 verdict in the last column):

| CQ[1] not retired | Dhrystone/run | CoreMark/iteration | Manual |
|---|---:|---:|---|
| Speculative `bc` in CQ[1], resolving as predicted this cycle | 79.0 | 33,524 | Allowed: it no longer follows an unresolved prediction. Relaxed. |
| Speculative `bc` in CQ[1], mispredicted (resolving, or resolved and not yet recovered) | 8.0 | 4,483 | Its next PC is not yet corrected; the younger work is flushed. Kept. |
| Head is a mispredicted `bc` awaiting recovery | 2.0 | 884 | CQ[1] follows a mispredicted branch. Kept. |
| Head is an SPR move finishing in the special lane (`mfspr`, `mtspr`) | 1.5 | 1,434 | Allowed (CQ[0] completes). Kept: the lane's commit-time redirect and exception outputs are not known early enough; small. |
| Store in CQ[1] (`stw`, `stwx`) | 7.0 | 395 | Forbidden: integer or load only. Kept. |
| Pair would write three GPRs | 0 | 692 | Forbidden. Kept. |
| Update load in CQ[1] beside a head that writes no GPR | 0 | 36 | Allowed (two GPR writes). Kept: the update base is written from the head only. |
| Two branches | 0 | 297 | Branches keep a CQ entry here; one LR/CTR write per cycle. Kept. |
| Same GPR in both | 0 | 0.2 | Allowed. Kept: the write ports never target one register. |

| | Dhrystone cycles/run, w1 | w2 | CoreMark/MHz, w1 | w2 |
|---|---:|---:|---:|---:|
| Batch 13 start (c77ae69) | 851.4 | 771.8 | 2.037 | 2.193 |
| Predicted `bc` retires as it resolves (9906d74) | 851.4 | 771.8 | 2.037 | 2.194 |

The 79 held cycles per run were not on the critical path: the branch now
retires a cycle earlier (whole program: 212 fewer cycles at width 2), but the CQ-full stall is unchanged (50.6 per run).
While dispatch waits for a CQ entry the head is busy 15.6 cycles per run
(store 7.5, load 6.1), one instruction retires 16.5 (CQ[1] unfinished 13.0)
and two retire 41.5: the queue drains at the full rate but an entry freed by
retirement reaches dispatch only the next cycle. Letting dispatch use the
entries retiring in the same cycle (9906d74 plus an uncommitted change to
the queue's allocation ready, which adds a retire-to-dispatch path) measured 755.9 cycles per Dhrystone run at width 2 (-2.1%), 840.9 at
width 1 and 2.201 CoreMark/MHz at width 2. The manual's DQ0 and DQ1 rules
say only that a completion buffer must be free, not whether one freed in
the same cycle counts.

## Where the cycles go (model vs RTL)

Recorded: `make -C sim DISPATCH_WIDTH=2 BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo perf-diff [PERF_DIFF_ARGS="--core <rule> ..."]`, commit 33bbb6a plus the `+STALL_TRACE` testbench change and `sim/tools/perf_diff.py` (this commit), 2026-10-04.
Unit and store queue on, base snooping off, prebuilt firmware, 18 iterations
of the timed loop: core 771.5 cycles per run, model 506.0, difference 265.5.

`perf_diff.py` runs the retired stream through the model and lines it up with
the core's `+DISPATCH_TRACE` and `+STALL_TRACE`. Each instruction is charged
the cycles since the previous instruction dispatched (model: dispatch, or BPU
execute for a folded branch), so the charges add up to the run. Each core
cycle carries its cause: the DQ0 stall slot, or, for the dispatch cycle
itself, why the instruction was not in DQ1 beside its predecessor. It prints
the difference per PC, basic block and function, the excess by cause,
dispatch to retirement per class and taken-branch redirect costs.
`--core <rule>` adds a restriction of this core to the model
(`perf_model_603e.py --core` takes the same), pricing each restriction in the
model's terms.

By function (cycles per run):

| Function | Instructions | Core | 603e | Difference |
|---|---:|---:|---:|---:|
| `strcmp` | 161 | 191.0 | 126.0 | 65.0 |
| `dhry_main` loop (Proc_2..5 inlined) | 66 | 115.5 | 73.0 | 42.5 |
| `strcpy` | 157 | 160.5 | 124.0 | 36.5 |
| `Proc_1` | 50 | 81.5 | 46.0 | 35.5 |
| `memcpy` | 77 | 92.0 | 59.0 | 33.0 |
| `Func_2` | 19 | 49.0 | 28.0 | 21.0 |
| `Proc_8` | 25 | 37.0 | 20.0 | 17.0 |
| `Proc_7`, `Proc_6`, `Func_1` | 35 | 45.0 | 30.0 | 15.0 |
| **Total** | **590** | **771.5** | **506.0** | **265.5** |

Dispatch to retirement (core) against dispatch to completion (model):

| Class | Per run | Core min / mean | 603e min / mean |
|---|---:|---:|---:|
| add, addi | 101 | 3 / 4.10 | 2 / 2.75 |
| compare | 86 | 3 / 3.99 | 2 / 3.66 |
| other integer | 87 | 3 / 3.76 | 2 / 3.07 |
| load | 115 | 4 / 4.33 | 3 / 3.34 |
| store | 75 | 4 / 4.77 | 3 / 3.73 |

Every class retires one cycle later than the 603e completes. F6-3 draws an
`add` as `1D 2E 3W 4A`: writeback the cycle after execute, deallocation the
cycle after that. Forwarding is unaffected (a load's integer consumer has no
gap); retirement is, and with it every entry's CQ occupancy, the CR token and
retirement-gated work.

### Ranked causes

Each rule is priced twice: added alone to the 603e model, and removed from
the model with all six rules (689.0 cycles). Leave-one-out estimates the gain
of fixing that one thing in the core. Figures overlap and do not add.

| Rank | Cause | `--core` rule | Alone | Leave-one-out | 603e rule | Verdict |
|---:|---|---|---:|---:|---|---|
| 1 | Retirement one cycle after the 603e's completion (above) | `late-retire` | +57 | 74 | F6-3, F6-5: `W` the cycle after the last `E` | Core slower; fixable |
| 2 | Branches take a dispatch slot, a CQ entry and a completion slot (118 per run) and execute at dispatch, not the cycle after fetch | `branch-slot` | +63 | 38 | UM 6.3.1, 6.4.1.1; T6-1 "may be folded for an effective cycle time of 0"; F6-3 `br 2F 3E` | Core slower; fixable (gap 8) |
| 3 | A CR writer dispatches only after the previous CR writer retires (flag token) | `cr-token` | +22 | 22 | UM 6.3.3.1: one CR rename; UM 6.6.1.2 does not make it a dispatch condition | Core slower; let the writer wait in its station (A13 prices the 603e's limit at 1) |
| 4 | A load or store dispatches only once its base is written (`drain_memory` 20.5 per run: `strcmp`'s `lbz` after `mr`) | `lsu-base` | +2 | 20 | UM 6.3.3, 6.3.3.1: the LSU station waits for the rename tag | Core slower; fixable |
| 5 | Misprediction: the correct path dispatches 4 cycles after the recovery (162 of 162); branch dispatch to correct-path dispatch 7.2 cycles, model 4.3 | `miss-late` | +18 | 18 | F6-5: `bc` resolves 5E, target 6F, dispatch 7D | Core slower; fixable |
| 6 | An add or compare in DQ0 goes only to the IU: `cmpwi` behind `divw` holds the IU station 19 cycles per run | `dq0-iu` | +4 | 7 | UM 6.3: the SRU adder "allows the dispatch and execution of multiple integer add and compare instructions on each cycle"; UM 6.4.5 | Core slower; fixable |
| | Residual: core 771.5 against 689.0 | | | 82.5 | | |

The residual by stall cause (all six rules): taken `b`/`bl` and `bclr`
redirects beyond two cycles (`branch_refetch` 27; `bclr` 3.1 cycles from
dispatch to target against 2), store traffic (`lsu_busy` 10.5, CQ full on a
store 10.5, other store 4: committed stores take the request port after
retirement, which A6 does not charge the 603e), SPR moves (`mtspr` drain 3,
`mfspr` CQ wait 2.5, lane pairing 4) and pairing rules. By function:
`Proc_1` 21.5, `dhry_main` 16.5, `Proc_8` 12, `Func_2` 10, `memcpy` 7,
`strcmp` 6.

### Model corrections

The single CR rename is now A13, applied by default (+1 cycle on
Dhrystone). A14 stops fetch at a held branch and holds a CR branch behind
an unresolved prediction (UM 6.4.1.1, 6.6.1.1; +12 cycles). Together they
raise the Dhrystone model from 506 to 519 cycles per run (width-2 core
trace at d798e7d). A6 stays the main optimistic assumption; the store
residual bounds it at about 25 cycles.

### CQ entry reuse

The manual does not say whether an entry freed by completion takes a dispatch
in the same cycle: UM 6.6.1.2 requires only that the completion buffer "is not
full". The figures draw deallocation (`A`) one cycle after writeback (`W`).
The model frees an entry for dispatch in the cycle after completion, the `A`
cycle: an `add` dispatched in cycle D frees its entry for D+3. The core
retires an `add` at D+3 at the earliest, so its retire cycle is the 603e's
`A` cycle. Letting dispatch use an entry in the core's retire cycle (the
reverted change, 755.9 cycles) gives the model's spacing, not a faster one.
The better fix is rank 1: retire at finish + 1, after which next-cycle reuse
matches. Reuse in the `W` cycle (`--core cq-same` on the 603e model, 498
cycles) is faster than the figures and not adopted. On the six-rule model
`cq-same` is worth 25 cycles; the core measured 16.

### Next steps

1. Retire at finish + 1 (74): done for IU, SRU and unit results, below
   (38.5 measured at width 2).
2. Fold branches out of dispatch and the CQ (38).
3. Check the CR token at execute, not dispatch (22). Done: 20 measured.
4. An LSU station that waits for the base, or base snooping from the IU (20).
   Done for D-form loads in DQ0; no gain until 1 and 2 land.
5. Misprediction recovery at F6-5 timing (18): partly done, below
   (two of three cycles).
6. Taken `b`/`bl`/`bclr` redirect at fetch (about 15 of the residual):
   done, below.
7. Store writes off the load port (up to 25 of the residual, part A6):
   done, below (22 measured at width 2, with the data micro-TLB).
8. DQ0 add/compare to the SRU when the IU station is taken (7). Done: 7.5 measured.

## Station waits for CR, base and the SRU

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo perf-diff`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/<dhrystone|coremark>.hex`, on f5305d4 (before), ca7afdf, c610eb4 and 6cef417, each with the `-fno-const-bit-op-tree` build fix of f7d561f, 2026-10-04.
Unit and store queue on, base snooping off, prebuilt firmware. Every run
passes its checks. Dhrystone is `perf-diff`'s timed loop (18 iterations).

| Step | Commit | Dhrystone cycles/run, w1 | w2 | CoreMark/MHz, w1 | w2 |
|---|---|---:|---:|---:|---:|
| Before | f5305d4 | 851.0 | 771.5 | 2.037 | 2.193 |
| CR writer waits for the token in its station (cause 3) | ca7afdf | 849.0 | 751.5 | 2.087 | 2.292 |
| Load waits for its base in the unit (cause 4) | c610eb4 | 849.0 | 751.5 | 2.096 | 2.298 |
| DQ0 add/compare to the SRU (cause 8) | 6cef417 | 849.0 | 744.0 | 2.096 | 2.301 |
| Causes 1, 3, 4, 8 together | 103325b | 814.0 | 714.5 | 2.187 | 2.406 |
| Causes 1, 3–6, 8 together | c736a1b | 783.0 | 685.5 | 2.290 | 2.603 |
| Causes 1, 3–8 together | a696e15 | 767.0 | 663.0 | 2.290 | 2.602 |
| IU result on the second finish port | 5f2d056 | 767.0 | 640.0 | 2.290 | 2.662 |

The build fix changes none of the figures.

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo perf-diff`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/coremark.hex`, commit 103325b, 2026-10-04 (last row; `perf-diff` exits 0, CoreMark CRCs match).
Together the four save 37.0 cycles at width 1 and 57.0 at width 2 against
f5305d4; completion in the writeback cycle alone saved 16.0 and 38.5, and
the station waits alone 2.0 and 27.5, so at width 2 the gains overlap by
9.0 cycles.

- Cause 3: one younger CR writer bound for the IU or SRU station dispatches
  while the token is held and becomes its owner on the edge the owner
  retires; its station holds it until then. At width 2 the `FLAGS_WAIT`
  excess (27.0 per run) is gone, and 20 of it is saved. At width 1 the
  waiter holds the only integer station, so the stall moves to `RS_FULL`.
- Cause 4: `DRAIN_MEMORY LOAD` (20.5 per run) is gone, but the run is no
  shorter: the load still offers when its base is written, and the work
  behind it fills the CQ instead (`own slot: DQ1 IU+IU cq` 3 to 22). As
  `--core lsu-base` alone predicted (+2), the gain waits on the
  retirement and branch causes.
- Cause 8: `RS_FULL` (33.5 per run) is gone; 7.5 cycles saved, the
  leave-one-out estimate.

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo perf-diff`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/coremark.hex`, commit c736a1b (merge of 310b01f and a91c265), 2026-10-04 (last row; `perf-diff` exits 0, CoreMark CRCs match).
With the redirect timing of causes 5 and 6 (678.0 at width 2 alone) the
station waits cost Dhrystone 7.5 cycles at width 2 and gain CoreMark 0.097.
The loss is `strcmp`'s loop, 9 cycles an iteration against 8: its `lbz`
now dispatches beside the `mr` that writes its base and waits in the unit,
the `cmpw` on the loaded byte waits in the IU station and finishes a cycle
later than when it dispatches after the load (`CQ_FULL` 28 to 60.5,
`DRAIN_BRANCH` 20). With the base wait off
(`+define+PPC_LSU_BASE_WAIT=1'b0`): 667.5 and 2.557 at width 2. The SRU
route off costs 10.5 (696.0).

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo perf-diff`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/coremark.hex`, commits a696e15 (merge of 2ac64dd, 29c64f9 and c83a389; width 2), 5f2d056 and fab7650 (both widths, same figures), 2026-10-04 (last two rows; `perf-diff` exits 0, CoreMark CRCs match).
With cause 7 merged, Dhrystone is 663.0 at width 2 and `strcmp` still
takes 9 cycles an iteration. The `cmpw` was not late to issue: the IU
station takes the load's result in the cycle it finishes, Table 6-6's load
latency 2. Its result then met the next iteration's `lbzu` result on the
completion queue's one IU and LSU finish port, and waited a cycle.

The 603e's units write their results on their own buses (UM 6.3.3). An IU
result that meets a load result now finishes on the second port, the SRU's,
when the SRU leaves it free. That port records value, CR0 and XER bits,
which is all an IU result carries; IU results never fault. `strcmp` takes
8 cycles an iteration. The SRU exists only at width 2, so width 1 is
unchanged. With the base wait off (`+define+PPC_LSU_BASE_WAIT=1'b0`) the
same build measures 640.0 and 2.662 (6 CoreMark cycles more): the base
wait no longer costs anything, and stays on.

## Completion in the writeback cycle

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo perf-diff`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/coremark.hex +PROFILE`, commits f5305d4 with the `-fno-const-bit-op-tree` build of 55adec6 (before) and b73b3d6 (after), 2026-10-04.
Unit and store queue on, prebuilt firmware. Every run passes its checks.

A fault-free result from the IU, the SRU or the load/store unit now retires
in the cycle it reaches the completion queue: `add 1D 2E 3W`, a load or
store `1D 2E 3E 4W` (F6-3, F6-5, UM 6.3.3). The entry frees for dispatch the
next cycle, the `A` cycle; same-cycle reuse stays off. Faulting results,
special-lane results and FP entries retire as before, a cycle after their
result or with the FPU's.

| | Dhrystone cycles/run, w1 | w2 | CoreMark/MHz, w1 | w2 |
|---|---:|---:|---:|---:|
| Before | 851.0 | 771.5 | 2.037 | 2.193 |
| After | 835.0 | 733.0 | 2.133 | 2.354 |

Dispatch to retirement at width 2 (minimum / mean, 603e model in brackets):
add 2 / 3.20 (2 / 2.75), compare 2 / 2.99 (2 / 3.66), other integer 2 / 3.06
(2 / 3.07), load 3 / 3.48 (3 / 3.34), store 3 / 4.11 (3 / 3.73). No class
retires before its manual cycle in isolation; means below the model's
reflect a different schedule. The model priced the rule at 74 cycles with
the other five rules removed; alone it measured 38.5 at width 2.

At width 1 the gain first measured 34 cycles worse: with one GPR write port
an update form's base takes the port the cycle after it retires, and that
cycle blocked all dispatch. It now blocks only an instruction that reads the
base (`strcpy` and `strcmp`, 30 and 19 cycles).

## Redirect timing

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo perf-diff`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/coremark.hex +PROFILE`, commits e4897b8 (before; CoreMark and width 1 from the record above) and 2380118 (after), 2026-10-04.
Unit and store queue on, prebuilt firmware. Every run passes its checks.

Three changes:

- Fetch offers the target request on the redirect edge itself, not the
  edge after, when the redirect comes from a register: a fold (`fold_q`),
  an unfolded taken branch (`bu_redirect_q`) or a misprediction
  (`bs_miss_q`). The core announces it a cycle early from those registers'
  D inputs (`early_q`, `early_target_q`); a redirect that does not arrive
  as announced takes the old path.
- A misprediction is detected in the cycle the CR owner's result arrives,
  the 603e's resolve cycle (F6-5: compare 4E, `bc` 5E), instead of the
  cycle after its capture. Recovery and the target request follow on the
  next edge, F6-5's `6F`. A correct prediction still resolves from the
  captured CR.
- An `mtlr` fed the shadow LR with its source two cycles after it
  dispatched, so a `bclr` behind it resolved before the `mtlr` retired.
  This was not the manual's timing: a move to LR is completion-serialized
  and its result is not forwarded before it retires (UM 6.3.3.2). The
  early feed was removed ([AUD-90](AUDIT.md); see
  [fetch-stop waits](#fetch-stop-waits-aud-90)); the table below includes it.

| | Dhrystone cycles/run, w1 | w2 | CoreMark/MHz, w1 | w2 |
|---|---:|---:|---:|---:|
| Before | 835.0 | 733.0 | 2.133 | 2.354 |
| After | 806.0 | 678.0 | 2.231 | 2.506 |

Width 2, branch dispatch to next dispatch (core min / mean, 603e model in
brackets): mispredicted `bc` 6 / 7.17 to 5 / 5.50 (3 / 4.33), `bclr`
3.15 to 2.55 (2.60), taken `b` 2.69 to 2.08 (2.54). `BRANCH_REFETCH`
stalls fall from 39.5 to 18.0 cycles per run. At width 1 a mispredicted
`bc` takes 4 / 4.83.

The target word still dispatches two cycles after the figures: the request
is now in the figure's fetch cycle, but the cache returns it the next cycle
and the fetch-to-decode register adds another before the IQ. Every
redirect pays these two cycles; removing them means fetching both paths or
decoding the cache output, which the 66 MHz top does not allow. Means of
`b` and `bclr` below the model's come from targets fetched while older
work drains; no single redirect reaches its target sooner than the figures.

On the redirect path: the fetch address gains one 2:1 mux, selected by
`early_q && !request_held` (registers) between `early_target_q` (a
register) and the old address; the late `recovery_accepted` reaches only
the request valid, which it already did. The misprediction compare (the
owner's CR nibble against `bs_bi_q`) ends in registers.

## Store traffic

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo perf-diff`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/coremark.hex +PROFILE`, commits a91c265 (before) and 97b28fc (after), 2026-10-04.
Unit and store queue on, prebuilt firmware. Every run passes its checks.

What the manual says about committed stores and loads at the data cache:

- One access per cycle. The data cache tags are single-ported, and a load
  or store deferred by a snoop executes "on the clock cycle following the
  snoop" (UM 1.1.5.2, Chapter 3 introduction); each cycle allows one read
  or one byte-wise read-modify-write (UM 1.1.5.2). A load and a store
  write never share a cycle.
- Stores wait in the store queue until completion and are then written
  (UM 1.1.4.3, Figure 6-2). Accesses are weakly ordered: loads may be
  performed ahead of stores (UM 1.1.4.3, 3.5.5.2; the BIU's "load ahead of
  store", UM 3.9). Loads and stores are 2:1 (UM 6.4.4, Table 6-6).
- No section orders a ready load against a completed store.

So the core keeps one access per cycle and lets a load ready for its first
offer go before a retired store while the queue has room. A full queue, a
standing store write, or a load the port refuses gives the store the
cycle.

The profile also showed the data micro-TLB missing every iteration:
Dhrystone touches the stack and four or more global pages. A store whose
page misses takes the slow path at the completion-queue head, and a load
waits for the translation sequence. The 603e translates every access in the
LSU's first stage (UM 6.4.4), so these misses have no 603e counterpart. The
data side now has eight entries (`DATA_MICRO_TLB_ENTRIES`); the instruction
side keeps four.

| | Dhrystone cycles/run, w1 | w2 | CoreMark/MHz, w1 | w2 |
|---|---:|---:|---:|---:|
| Before | 806.0 | 678.0 | 2.231 | 2.506 |
| Loads first only | | 667.5 | | |
| Eight data entries only | | 667.0 | | |
| After | 787.0 | 656.0 | 2.230 | 2.506 |

Width 2, dispatch to retirement (core mean, 603e model in brackets): load
3.67 to 3.42 (3.34), store 4.05 to 3.79 (3.73). Per run, `CQ_FULL STORE`
falls from 13 to 6 cycles and `LSU_BUSY` from 13 to 4. CoreMark keeps its
data in few pages and rarely has a load behind a store write.

The store write's select now also depends on the P1 load's overlap compare
(registered EA against four queue entries), and the data micro-TLB compares
eight entries instead of four. Both are on paths the 66 MHz fit flags; the
chip needs a fresh fit.

## Measurement reproducibility

A cycle count depends only on the RTL and the image: not on the X seed, the
initial-state mode, or bits that no logic reads. A count that moves with an
unrelated change is first a simulator-correctness question. Verilator 5.020
at `-O3` miscompiled `pair_ok` for one retire-packet layout, which made
Dhrystone 781.8 cycles/run instead of 775.8 ([BUG-03](BUGS.md)); builds now
disable that optimization.

Recorded: `make -C sim DISPATCH_WIDTH=2 VERILATOR=$PWD/sim/tools/verilate-lsu-pipe demo-soc-model`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/<dhrystone|coremark>.hex` with `+verilator+seed+<1..8> +verilator+rand+reset+2`, `+verilator+rand+reset+0` and `+verilator+rand+reset+1`, commit f7d561f, 2026-10-04.

All ten initial states give Dhrystone 775.8 cycles/run (1,551,710 cycles)
and CoreMark 4,681,079 ticks for 10 iterations; all pass. The same build
with three unused bits added to `retire_packet_t` gives the same two counts
(before the fix: 781.8 and, on f531cf2 itself, 775.8 for all ten states).
The counts match the batch 12 table, so the default layout was not
affected on these programs. `xrand-sweep` now checks the Dhrystone count
across its seeds.

## Stores behind stores

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo perf-diff`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/<dhrystone|coremark>.hex +PROFILE`, commits 29c64f9 (before), b58bd0c (micro-TLB only) and 20f17d3 (after), 2026-10-04.
Unit and store queue on, prebuilt firmware. Every run passes its checks.

What the manual says:

- The 603e translates each access in the LSU's first stage (UM 6.4.4), so a
  store to a page a load just used needs no second translation. A data
  micro-TLB entry filled by a load now records whether a store would pass
  (BAT PP, page PP and key, TLB C bit); see
  [MICRO_TLB.md](MICRO_TLB.md#entries).
- Loads and stores have one-cycle throughput (UM 6.4.4) and "a complete
  read-modify-write operation to the cache can occur in each cycle", on a
  byte basis (UM 1.1.5.2). Nothing restricts a store, or a load, to the
  double word written the cycle before.

The cache answered a store hit in its lookup cycle but accepted the next
request only for another double word, since the data RAM's early read could
not see the store's write. A store reads no data and now follows at once; a
load of that double word takes the written bytes from a one-cycle forward
merged per way and byte into the hit data.

| | Dhrystone cycles/run, w1 | w2 | CoreMark/MHz, w1 | w2 |
|---|---:|---:|---:|---:|
| Before | 787.0 | 656.0 | 2.230 | 2.506 |
| Micro-TLB store permission only | | 656.0 | | 2.506 |
| Stores behind stores, no forward | | 657.0 | | |
| Forward, stores still held | | 655.0 | | 2.517 |
| After | 786.0 | 655.0 | 2.240 | 2.518 |

The data micro-TLB already hit nearly always (one store miss over the
Dhrystone profile region), so its change moves nothing here. Per Dhrystone
run, about five stores now follow a store to the same double word and one
load follows one; strcpy's byte stores are the main source. Accepting the
stores alone costs a cycle in strcpy: the store takes a cycle in which a
held load would otherwise have been offered. The forward recovers it.

The forward adds a byte merge to the load hit data, which is on the
load-use path the 66 MHz fit flags; the chip needs a fresh fit.

The largest LSU-area gap left in the width 2 profile is `DRAIN_MEMORY LOAD`
(20 cycles/run, strcmp's `lbz r10,0(r4)` behind `mr r4,r8`): a load waiting
at dispatch for its base. `LSU_BASE_SNOOP` removes it and is the default
since 2026-10-06 (LSU_PIPELINE.md, Base snooping). `CQ_FULL STORE`
(6) and `LSU_BUSY STORE` (3) in memcpy follow.

## Branch removal (gap 8)

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BRANCH_REMOVAL=<0|1> BUILD_DIR=build-d VERILATOR=$PWD/sim/tools/verilate-lsu-pipe demo-soc-model`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/<dhrystone|coremark>.hex`, commit 3bb0024, 2026-10-04.
LSU unit and store queue on; prebuilt firmware (2000 runs, 10 iterations).
All eight runs pass their checks (Dhrystone 23 values, CoreMark CRC 0xfcaf).
`BRANCH_REMOVAL=1` removes a plain `b` before the IQ and other branches
without LR or CTR writes at dispatch
([CONTROL_MEMORY.md](CONTROL_MEMORY.md#branch-unit)).

| | Width 1, off | Width 1, on | Width 2, off | Width 2, on |
|---|---:|---:|---:|---:|
| Dhrystone cycles/run | 863.8 | 861.3 | 781.8 | 778.8 |
| CoreMark/MHz | 1.991 | 1.995 | 2.107 | 2.109 |

The gain is small: 3 cycles per run at width 2 against the 99 the branch row
of [Gaps](#gaps) charges. Branches folded at dispatch still take a dispatch
slot (only a plain `b` is removed before the IQ), and at width 2 a branch in
DQ0 already pairs, so the slot is rarely the limit; what removal saves is
mostly CQ entries (`cq_full` 0.098 CPI after, 0.102 before).

The "off" column is not batch 12 (775.8 at width 2): these builds predate
the [BUG-03](BUGS.md) fix ([measurement reproducibility](#measurement-reproducibility)),
which moved Dhrystone 6 cycles per run with no logic change.

## Fetch-stop waits (AUD-90)

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo perf-diff` (width 1 without `DISPATCH_WIDTH`), then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/coremark.hex`, commits 9c106ac (before) and 94c2815 (after), 2026-10-06.
LSU unit and store queue on, prebuilt firmware. Every run passes its checks
(CoreMark CRC 0xfcaf).

The core now waits where UM 6.4.1.1 stops fetching: a `bclr` behind an
`mtlr`, and a `bcctr` or CTR-testing `bc` behind an `mtctr`, resolve from
the register after the move retires; a CTR-testing branch or `bcctr`
behind a CTR-testing `bc`, and a linking branch other than `b` behind a
linking branch, wait for the older branch to complete. None of these
folds at fetch, and fetch stops at them (below).

| | Dhrystone cycles/run, w1 | w2 | CoreMark/MHz, w1 | w2 |
|---|---:|---:|---:|---:|
| Before | 766.0 | 639.0 | 2.300 | 2.675 |
| After | 769.0 | 641.0 | 2.276 | 2.641 |
| Fetch stop | 769.0 | 641.0 | 2.270 | 2.633 |

Recorded: the same commands, commit 4283ff7 (fetch stop), 2026-10-06.

Fetch now stops at a waiting branch: words fetched past its fetch pair are
dropped, and fetch restarts the cycle after the branch leaves the IQ, at
its target if taken, else after the pair. The manual gives no resume
cycle; in UM 6.4.1.2.1 (Figure 6-5, PDF 263) the new stream is requested
in the cycle the branch resolves, and the core requests it the cycle
after, as for every branch redirect. A linking `bc` or `bcctrl` behind an
`mtlr` folds again; it waits only behind a linking branch. Dhrystone does
not change; CoreMark loses 0.3% at both widths.

### One level of CR prediction

| | Dhrystone cycles/run, w1 | w2 | CoreMark/MHz, w1 | w2 |
|---|---:|---:|---:|---:|
| Fetch stop (4283ff7) | 769.0 | 641.0 | 2.270 | 2.633 |
| One level | 764.0 | 641.0 | 2.281 | 2.632 |

Recorded: the same commands, commit b9aca62, 2026-10-06.

UM 6.4.1.1 seventh case: a branch on CR behind an older one still waiting
on CR is not predicted. It stays in the fetch registers, and fetching
stops, until the older one resolves; it is then predicted in that cycle
(UM 6.4.1.2, Figure 6-5, PDF 263), as the CR result arrives. If its CTR
test already fails, the CR is ignored and it is not held. A branch whose
CR is final when it reaches the fetch registers, including in the cycle
the CR result arrives, is resolved there (UM 6.4.1) instead of predicted;
a branch predicted at dispatch takes its static prediction. The pair
fetched behind a held branch waits in the fetch buffer and enters the
fetch registers the cycle it is released, as the 603e fetches it then.

Dhrystone width 1 gains 5 cycles/run: a `bne` in `memcpy` (`fff0337c`)
whose `y` bit predicts it taken is resolved not taken from a final CR, and
no longer redirects at dispatch. Width 2 does not change: the held
second branches in `strcpy` and `strcmp` are released as the first
resolves, and the core's taken-branch refetch is no slower than before.
The pair behind a released branch is followed by a fetch the cycle after,
one cycle later than the 603e.

## Timing accuracy round 1

Recorded: `make -C sim DISPATCH_WIDTH=2 BRANCH_REMOVAL=<0|1> BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo perf-diff`, commit 382022b, 2026-10-06.
LSU unit and store queue on, prebuilt firmware. `perf-diff` now runs with
`BRANCH_REMOVAL=1`: the retire trace numbers each record after the branches
removed before it, and the model restores them from the disassembly.

| Dhrystone, width 2 | Core | 603e model | Gap |
|---|---:|---:|---:|
| Branch removal off | 641.0 | 506.0 | 135.0 (27%) |
| Branch removal on (UM 6.4.1.3) | 640.0 | 506.0 | 134.0 (26%) |

Excess cycles per run with removal on, ranked: DQ1 not supplied 74,
predicted `bc`/`beqlr` in DQ1 refused 36 (`units ... dq0-flags`), CQ full
27, update form in DQ0 blocks DQ1 17 (`LSU+IU update`), CQ1 not free for a
DQ1 integer op 19 (`LSU+IU cq`), taken-branch refetch 21, empty IQ 12.
`--core branch-slot` prices branches that take a dispatch slot and a CQ
entry at 63 cycles per run (model 569 against 506): with removal on, only
11 branches per run leave at dispatch; the 70 loop branches of `strcmp`
and `strcpy` are predicted and keep their entry.

Tried, not accepted (branch `timing-acc1-wip`):

- DQ1 predicted in the cycle the older prediction resolves correctly
  (UM 6.4.1.2, Figure 6-5). No change alone: the DQ1 branch then waits
  for a CQ entry.
- A conditional `bclr` with committed LR predicted from DQ1 like `bc`.
- A branch predicted from DQ1 takes no CQ entry (UM 6.3.1, A3): it is
  anchored on DQ0, its CR owner; nothing younger completes until it
  resolves, and a miss keeps the anchor (or removes everything once it has
  retired). Dhrystone stays at 640: the loops become fetch-bound
  (`BRANCH_REFETCH` 35) and the `lbzu` + `cmpwi` pair is refused by the
  update rule (35). `test-core-dual` fails at width 2 with removal on (a
  plain `b` is dispatched); the other width-2 benches run passed
  (`test-core`, `-recovery` with removal on; all nine focused benches,
  `test-dispatch-rules` and `test-reference-machine` with removal off).
- DQ1 beside an update form when DQ1 takes no GPR rename (UM 6.6.1.2
  counts renames, not ports). Deadlocks Dhrystone in `strcmp` with the
  anchored branch; not kept.

What remains is the front end: a held branch released as its older
branch resolves reaches dispatch with its target at R+3 or later against
Figure 6-5's R+2, because the fetch-to-decode register sits between the
cache and the IQ (UM 6.3.2.2: one cycle from request to IQ).

## Timing accuracy round 2a

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BRANCH_REMOVAL=<0|1> FETCH_DECODE_REG=<0|1> MISPREDICT_FETCH_NOW=<0|1> BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo perf-diff`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/coremark.hex`, commit 1b154ee, 2026-10-06.
"Before" is `FETCH_DECODE_REG=1 MISPREDICT_FETCH_NOW=0`, round 1's front end
(measured at 15e5182; later commits do not change that setting). The
second row is `FETCH_DECODE_REG=0 MISPREDICT_FETCH_NOW=0` at dfc9309.

| | Dhrystone cycles/run, w1 | w2 | w2, removal | CoreMark/MHz, w1 | w2 | w2, removal |
|---|---:|---:|---:|---:|---:|---:|
| Before | 764.0 | 641.0 | 640.0 | 2.281 | 2.632 | 2.635 |
| No fetch-to-decode register | | | 618.0 | | | |
| Both | 749.0 | 610.0 | 610.0 | 2.390 | 2.838 | 2.849 |

- `FETCH_DECODE_REG` (default 0): a word enters the IQ in the cycle the
  cache returns it (UM 6.3.2.2). The register holds only words the IQ
  refuses. A folded target now dispatches three cycles after its branch
  is fetched (UM Figure 6-3: branch 2F, target 4F 5D).
- `MISPREDICT_FETCH_NOW` (default 1): a misprediction redirects the front
  end and requests the correct path in the cycle it resolves; the path
  dispatches two cycles later (UM 6.4.1.2, Figure 6-5: resolve 5E, target
  6F 7D). The recovery on the next edge leaves the front end alone.

Neither can be faster than the manual: the cache answers a cycle after the
request at the earliest, the IQ is emptied on the resolve edge, and
dispatch is blocked until the recovery edge. `test-dispatch-rules` passes
at both widths with removal off and on, at both settings.

Still a cycle later than the manual: an unfolded branch resolved at
dispatch, or a folded one that falls through, requests its target on the
edge after dispatch (UM Figure 6-3: execute 3E, target 4F).

## Predicted branches without a CQ entry

Recorded: `make -C sim [DISPATCH_WIDTH=2] BRANCH_REMOVAL=<0|1> BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo perf-diff`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/coremark.hex`, commits 382022b (before) and f080b24 (after), 2026-10-06.
LSU unit and store queue on, prebuilt firmware. Every run passes its checks
(CoreMark CRC 0xfcaf).

UM 6.3.1 and 6.4.1.3: a branch predicted and resolved in the BPU takes no
CQ entry. With `BRANCH_REMOVAL=1` a predicted branch, from DQ0 or DQ1, is
now removed at dispatch and anchored on the youngest CQ entry before it
([CONTROL_MEMORY.md](CONTROL_MEMORY.md#branch-unit)). A DQ1 branch may be
predicted in the cycle the older prediction resolves correctly (UM
6.4.1.2, Figure 6-5), and a conditional `bclr` with a committed LR is
predicted from DQ1 like `bc`.

| | Dhrystone cycles/run, w1 | w2 | CoreMark/MHz, w1 | w2 |
|---|---:|---:|---:|---:|
| Removal off, before | 764.0 | 641.0 | 2.281 | 2.632 |
| Removal off, after | 764.0 | 641.0 | 2.281 | 2.632 |
| Removal on, before | 760.0 | 640.0 | 2.287 | 2.635 |
| Removal on, after | 711.0 | 639.0 | 2.331 | 2.638 |

Width 1 gains 49 cycles per run: the CQ entry was the limit. Width 2 gains
one: `CQ_FULL` falls from 27 to 11 cycles per run and the refused DQ1
`bc`/`beqlr` (36) are gone, but the `strcmp` and `strcpy` loops become
fetch-bound (`BRANCH_REFETCH` 14 → 35) and the `lbzu` + `cmpwi` pair is
refused by the update rule (17 → 35). Remaining excess at width 2, ranked:
DQ1 not supplied 74, update form in DQ0 blocks DQ1 35, taken-branch refetch
43, wrong-path dispatch 9, empty IQ 12, CQ full 11. A predicted branch
still takes the DQ0 dispatch slot; the 603e takes it out of the IQ at
fetch.

Recorded: `make -C sim BRANCH_REMOVAL=<0|1> test-core test-core-recovery test-core-dual test-core-fetch2 test-core-branch-fold test-core-branch-recovery test-core-machine-check-trace test-core-control-memory test-core-interrupt test-core-alignment test-dispatch-rules`, at width 1 and at width 2 with the LSU unit, commit f66a75c (`test-dispatch-rules` at f080b24), 2026-10-06; `make -C sim DISPATCH_WIDTH=2 BRANCH_REMOVAL=1 VERILATOR=... test-reference-machine MACHINE_PROGRAMS="dhrystone coremark selftest"`, commit f080b24.
All pass. The reference machine steps 266,595 removed branches in
Dhrystone at width 2. Two bench faults were found: `tb_core_dual` read
`dcycle[0x6c]` in a pair check, which inserted the key, so "a plain b was
dispatched" fired whenever removal was on, though the `b` never was; and
`tb_core_interrupt` expected the `b` at 0x28 to retire. The rule checker
now locates a removed mispredicted branch from the trace's `!<n>*<m>`.

## Timing accuracy round 4

Recorded: `make -C sim BUILD_DIR=<dir> BRANCH_REMOVAL=1 [DISPATCH_WIDTH=2] VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe REFERENCE_DIR=<dingusppc> DEMO_FW_DIR=<main checkout>/toolchain/build/demo MACHINE_PROGRAMS=dhrystone test-reference-machine perf-diff`, commits 3cdb974 (before), d798e7d, 103a0af and the branch-removal commit after it, 2026-10-06.
LSU unit and store queue on, removal on; every run passes the reference
machine and `test-dispatch-rules`.

| Dhrystone cycles/run | w1 | w2 | 603e model |
|---|---:|---:|---:|
| Before (3cdb974) | 692 | 593 | 506 |
| Rename and DQ1 rules (d798e7d) | 692 | 593 | 506 |
| Model A13, A14 (103a0af) | 692 | 593 | 519 |
| Resolved `bc`/`bclr` removed at IQ push | 687 | 592 | 519 |

- A DQ0 instruction without a GPR result needs no rename slot, and a DQ1
  IU instruction without one dispatches beside an update form (UM
  6.6.1.2). Load results reach the SRU station as they finish (UM 6.3).
  No change on Dhrystone.
- A `bc` or `bclr` without LR or CTR writes whose condition is final as it
  is queued is removed there (UM 6.4.1.1, 6.3.1), taken or not. A
  not-taken one in the first fetch lane is removed only without a second
  word. Predicted branches still take a DQ0 dispatch slot: removing them
  at push needs an IQ-side anchor for recovery, the remaining part of the
  63 cycles `--core branch-slot` prices.

## Timing accuracy round 14

Recorded: `make -C sim BUILD_DIR=<dir> BRANCH_REMOVAL=1 [DISPATCH_WIDTH=2] VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe REFERENCE_DIR=<dingusppc> DEMO_FW_DIR=<main checkout>/toolchain/build/demo MACHINE_PROGRAMS=dhrystone test-core test-core-recovery test-core-dual test-dispatch-rules test-reference-machine perf-diff`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/coremark.hex`, commits e6c5cb2 (before), 95a1efc, 95ec321 and 2032aef, 2026-10-06.
LSU unit and store queue on, removal on. Every run passes its benches, the
reference machine and `test-dispatch-rules`; CoreMark CRCs match.

| | Dhrystone cycles/run, w1 | w2 | CoreMark demo cycles, w1 | w2 |
|---|---:|---:|---:|---:|
| Before (e6c5cb2) | 649 | 554 | 4,971,885 | 4,315,278 |
| Base snoop by default (95a1efc) | 649 | 553 | 4,827,248 | 4,238,258 |
| Held branch predicted from FD (95ec321) | 631 | 553 | 4,764,675 | 4,235,978 |
| Target requested on release (2032aef) | 629 | 543 | 4,765,478 | 4,234,377 |

The 603e model gives 521 cycles per Dhrystone run.

- `LSU_BASE_SNOOP` is on: a load whose base a load or add produces waits
  Table 6-6's 2 cycles. `LSU_BASE_SNOOP=0` keeps the base wait, the named
  timing trade ([LSU_PIPELINE.md](LSU_PIPELINE.md#base-snooping)).
- A held CR branch released from FD with no IQ entry left to carry its
  prediction no longer enters the IQ (UM 6.3.1): it is predicted from FD,
  anchored on the youngest entry dispatching that cycle or the youngest CQ
  entry, and may replace an anchored prediction whose CR arrives matching
  it that cycle. In `strcmp` the slot becomes fetch wait.
- A held branch predicted taken as it is released requests its target on
  that edge rather than through `fold_q` a cycle later (UM Figure 6-5).
  `strcmp` and `strcpy` now match the model.

## Timing accuracy rounds 15 and 16

Recorded: `make -C sim BUILD_DIR=<dir> BRANCH_REMOVAL=1 [DISPATCH_WIDTH=2] VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe REFERENCE_DIR=<dingusppc> DEMO_FW_DIR=<main checkout>/toolchain/build/demo MACHINE_PROGRAMS=dhrystone test-core test-core-recovery test-core-dual test-dispatch-rules test-reference-machine perf-diff`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/coremark.hex`, commits 2032aef (before), 36c7e3c and 383e017, 2026-10-06.
LSU unit and store queue on, removal on. At 383e017 both widths pass
their benches, the LSU benches, the reference machine and
`test-dispatch-rules`; CoreMark CRCs match. `test-core` and
`test-core-full-decode` pass at the default configuration.

| | Dhrystone cycles/run, w1 | w2 | CoreMark demo cycles, w1 | w2 |
|---|---:|---:|---:|---:|
| Before (2032aef) | 629 | 543 | 4,765,478 | 4,234,377 |
| IU, load and SRU results forwarded as they finish (36c7e3c) | 629 | 542 | 4,765,478 | 4,195,696 |
| Store data from an LR or CTR move (383e017) | 627 | 539 | 4,764,252 | 4,194,493 |

The 603e model gives 521 cycles per Dhrystone run.

- A second forward port carries IU or load results to the SRU station and
  SRU results to the IU station in their finish cycle (UM 6.3.1).
  Mispredicted `bc` mean at width 2: 4.67 → 4.50 (model 4.33).
- A store whose data an `mflr` or `mfctr` writes dispatches to the LSU
  and takes its data from the wake bus (UM 6.3.3, 6.4.5); only a base
  read waits for the move. In `Func_2`, `stw r0,20(r1)` dispatched four
  cycles after `mflr`; it now dispatches with the model. Mispredicted `bc`
  mean at width 2: 4.50 → 4.33, the model's.
- Linking branches still take a CQ entry. Removing them needs the shadow
  LR (UM 6.3.1, 6.6.1.1) written when every older instruction has
  completed, with interrupts and the retirement trace treating the branch
  as done at that point; not yet built.

## Timing accuracy round 17

Recorded: `make -C sim BUILD_DIR=<dir> BRANCH_REMOVAL=1 DISPATCH_WIDTH=<1|2> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo perf-diff test-dispatch-rules` and `make -C sim check-spec`, commit e9c2a0a plus the checker and report changes below, 2026-10-06.

perf-diff reported the core faster than the model on mispredicted
branches (width 1: `bc` 4.17 against 4.33, `bclr` 4 against 6; width 2:
`bclr` 5 against 6). The same report showed it at 36c7e3c and at
3cdb974 (`bc` 3.17 at width 1). It was the metric, not the core: the
core side ran from the dispatch of the instruction before a removed
branch, the model side from the branch's BPU execute, which the model
places at fetch + 1, often before older instructions dispatch.
Measured from a common older instruction, every Dhrystone misprediction
reaches the correct path no earlier than the model. Example, `memcpy`
`andi.` then `beq` at fff03318, width 2: `andi.` dispatches in cycle 3,
executes in 4 and writes back in 5, which resolves the branch; the
target is fetched in 6 and dispatches in 7, as in Figure 6-5 (UM
6.4.1.2.1: resolved in 5, fetched in 6, dispatched in 7). A `cmpwi`
producer in `fb_palette_default` dispatches in 13262, its CR is
available in 13264 (T6-4 '^'), and the correct path dispatches in 13266.

- perf-diff now measures a taken branch from the dispatch of the last
  older non-branch (for a misprediction, the CR producer) to the next
  dispatch, on both sides. Mispredicted `bc` reads 4.67 against 5.00 at
  both widths, `bclr` 5 against 5. The residue is a model producer that
  dispatches early and waits in its station for a load result; the core
  dispatches it later and executes it in the same cycle.
- `test-dispatch-rules` checks TIM-BPU-MISPREDICT: the first dispatch
  after a recovery is at least four cycles after the dispatch of the
  branch's CR producer (execute, resolve, fetch, dispatch; Figure 6-5).
  Dhrystone meets the bound exactly in 30,532 of 34,052 recoveries at
  width 1 and 31,919 of 32,065 at width 2, and fails none, here or at
  3cdb974.

## Timing accuracy round 18

A `bl` now leaves at dispatch like a branch without LR or CTR writes
(UM 6.3.1: only branches that update LR or CTR need a completion
entry). It holds PC + 4 in a shadow LR, written to LR when the next
allocated instruction reaches the CQ head or retires second of a pair,
so LR is written in order. An interrupt taken before then sees LR
unwritten and resumes at the `bl`. A `bl` is removed only when the
shadow is free, no prediction is outstanding and no recovery is in
flight; a recovery keeps the shadow while the `bl` survives. Removed
`bcl`, `bclrl` and `bcctrl` stay excluded: they are conditional or read
a register (UM 6.4.1.1, 6.6.1.1).

| | Dhrystone cycles/run, w1 | w2 | CoreMark demo cycles, w1 | w2 |
|---|---:|---:|---:|---:|
| Round 16 (383e017) | 627 | 539 | 4,764,252 | 4,194,493 |
| Removed `bl` (99c3e2e) | 621 | 536 | 4,760,510 | 4,194,442 |

The 603e model gives 521 cycles per Dhrystone run; both widths stay
slower than it. CoreMark CRCs match at both widths (w1 361,101, w2
313,643 cycles per iteration).

Rules:

- `test-dispatch-rules` (TIM-BPU-FOLD) accepts a removed branch that
  writes no CTR and LR only as a `bl`; a younger LR-writing branch other
  than `bl` may not dispatch until everything older than a removed `bl`
  has completed (UM 6.4.1.1, 6.6.1.1).
- The reference runner steps a removed `bl` and compares LR at the next
  record against DingusPPC's LR after the `bl`. It fetches each removed
  word through the reference's instruction translation, so a branch in
  translated space is checked; a fetch fault, a removed non-branch or a
  removed `bcl`/`bclrl`/`bcctrl` fails. When an interrupt is taken with
  removed branches not yet counted on a record (empty CQ), the runner
  steps removed branches, at most three, until its PC equals the RTL's
  SRR0; each must pass the same rule. The runner holds DingusPPC's clock,
  so its decrementer never expires on its own: the RTL decides when DEC
  is taken, and the runner checks where.
- A new negative control flips LR in the first record after a removed
  `bl`; it must fail.

Recorded: `make -C sim -j2 lint check-spec`; and at `DISPATCH_WIDTH=1`
and `2` with `BRANCH_REMOVAL=1 VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo`:
`test-core test-core-recovery test-core-dual test-dispatch-rules perf-diff`,
CoreMark on the demo model (`+IMAGE=coremark.hex`), and
`test-core-lsu-update test-core-lsu-extensions test-core-lsu-timing test-core-lsu-timing-snoop test-core-lsu-timing-602`;
`test-core test-core-full-decode` at the default configuration; commit
99c3e2e, 2026-10-06. All pass. Dispatch rules: Dhrystone 61,496
removed branches at w1, 59,494 at w2, no failures; CoreMark and
Whetstone pass at both widths.

Recorded: `test-core-branch-fold test-core-branch-recovery test-core-interrupt test-core-interrupt-disabled perf-diff`,
`test-reference-machine REFERENCE_DIR=<dingusppc> MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`
and `test-reference-machine-mmu MACHINE_MMU_ELF=<main checkout>/toolchain/build/chip-mmu-stress/smoke.elf`
at both widths with the flags above, commit 4d979d9 (`lint check-spec` also
rerun there: 250 and 29 checker tests), 2026-10-06. All pass, except that
`test-core-branch-fold` at w1 stops at its built-in w2 build on
REDEFMACRO (`PPC_DISPATCH_WIDTH` redefined), a harness quirk; its w1
program passes (checks=102,522, removed=284) and both programs pass at
w2. Interrupt benches: 382 checks. Reference, w2: 5 programs and 7
negative controls pass; Dhrystone 1,009,270 records, 288,579 removed
branches of which 21,980 `bl`; MMU stress 42,364 records, 233
interrupts, 122 TLB misses, 10,379 removed branches (665 `bl`). w1:
MMU stress 49,363 records, 250 interrupts, 10,395 removed branches
(681 `bl`); 5 programs and 7 negative controls pass, Dhrystone
1,313,360 records, 290,548 removed branches of which 23,982 `bl`.

## Timing accuracy round 19

A held `mflr`, `mtlr`, `mfctr` or `mtctr` now enters the special lane in
the cycle the entry ahead of it retires, so it executes the cycle after
every older instruction has completed (UM 6.3.3.2) instead of one cycle
later. It is not started beside the retirement of the lane's own last
instruction. The lane reads LR and CTR in its execute cycle, after a
retiring branch or the shadow LR has written them. An IU instruction in
DQ1 now dispatches beside such a move in DQ0 unless it reads the move's
result: the move is completion-serialized, and UM 6.6.1.2 stops DQ1 only
behind a dispatch-serialized instruction.

| | Dhrystone cycles/run, w2 |
|---|---:|
| Round 18 (64e707f) | 536 |
| Moves (b1e85e5) | 533 |

Proc_1's gap to the model drops from 4 to 2 cycles; the `mflr r0` at its
entry completed two cycles after `stwu` instead of the model's one.

The model has no width-1 mode: it always dispatches two (UM 6.6.1.2), so
the w1 gap (621 against 521) is mostly DQ1 slots w1 cannot use. Only w2
is compared against it.

Open, w2 (gap per run against the model): `memcpy` 6, `dhry_main` 5,
`Proc_8` 2, `Proc_1` 2. The `memcpy` loop runs 7.5 cycles per pass
against the model's 7, filling the five-entry CQ (CQ_FULL STORE). The
core keeps a CQ entry for `bdnz` (it decrements CTR at retirement); the
model's A3 gives no branch a CQ entry. With nine entries per pass, each
held three to five cycles, five entries cannot sustain seven cycles per
pass. The manual says a branch that needs a write back does it "sometime
after the decode/execute phase" (UM 6.3.1) and lists only CTR
availability as a resource for `bc` on CTR (UM 6.6.1.1); T6-1 marks `bc`
as foldable to an effective zero cycles. Neither fixes whether a counting
branch takes a CQ entry. Closing it means a CTR shadow written in order,
as round 18 did for LR, or a model change with a citation.

The early entry is withheld while a predicted branch is unresolved
(0178fe9). In Whetstone at w1, `mflr r0` in `cos` entered the lane as the
`cmplw` ahead of it retired; that CR resolved the removed `bgt` between
them as mispredicted, and the recovery killed the lane, tripping the
special-lane kill assertion. The dispatch-rules failure (`retired
0000fff0 was not dispatched`) was the checker reading the trace cut off
by that abort. Dhrystone and CoreMark cycles are unchanged by the fix.

At w1 Dhrystone is 622, one above round 18's 621. In `Func_2` the move
now executes in the cycle the following `li r9,0` offers its result. At
w1 the IU shares the one result port and yields while the lane holds it,
then to the two `lbz` and the `stw` behind, so `li` completes four
cycles late and the CQ fills (CQ_FULL, 3 cycles). This is the w1 result
port, not a manual rule: the IU and SRU have their own result buses (UM
6.3.3), as w2's second port shows. CoreMark w1 improves (4,760,510 to
4,740,364).

| | w1 | w2 |
|---|---:|---:|
| Dhrystone cycles/run | 622 | 533 |
| CoreMark cycles (demo run) | 4,740,364 | 4,174,575 |
| CoreMark cycles/iteration | 359,202 | 311,896 |

Recorded: `make -C sim -j2 lint check-spec` and `make -C sim test-core test-core-full-decode` at the default configuration;
at `DISPATCH_WIDTH=1` and `2` with `BRANCH_REMOVAL=1 VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo REFERENCE_DIR=<dingusppc>`:
`test-core test-core-recovery test-core-dual test-dispatch-rules test-core-interrupt test-core-interrupt-disabled test-core-branch-fold test-core-branch-recovery perf-diff`,
`test-reference-machine MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`,
`test-reference-machine-mmu MACHINE_MMU_ELF=<main checkout>/toolchain/build/chip-mmu-stress/smoke.elf`
and CoreMark on the demo model (`+IMAGE=coremark.hex`); `quartus_map --analysis_and_elaboration`
of `quartus/chip` with `PPC_LSU_PIPE=1 PPC_DISPATCH_WIDTH=2 PPC_BRANCH_REMOVAL=1`;
commit 0178fe9, 2026-10-07. All pass (Quartus: 0 errors), except the known
`test-core-branch-fold` REDEFMACRO stop at its built-in w2 build at w1; its w1
program passes (checks=102,527). Dispatch rules pass Dhrystone, CoreMark and
Whetstone at both widths (w1 Whetstone 3,939,931 retirements; w2 837,058 pairs
dispatched). CoreMark CRCs match at both widths. Interrupt benches: 13,953 and
382 checks. Reference: 5 programs and 7 negative controls at both widths; MMU
stress 48,921 records and 210 interrupts at w1, 42,238 and 220 at w2.

## Timing accuracy round 20

A `bc` that counts CTR without LK (`bdnz`, `bdz`, and their CR forms
when CR is final) now leaves at dispatch like round 18's `bl`. Only CTR
availability is listed as a resource for a `bc` on CTR (UM 6.6.1.1), and
T6-1 folds `bc` to an effective zero cycles. A shadow CTR holds CTR - 1,
written to CTR as the next allocated instruction reaches the CQ head or
retires second of a pair, so CTR is written in order. An interrupt taken
before then sees CTR unwritten and resumes at the `bc`. The `bc` is
removed only when no older CTR writer (`mtctr` or a counting branch) is
uncommitted, the shadow is free, no prediction is outstanding and no
recovery is in flight; otherwise it takes a CQ entry as before. A
younger `bc` on CTR or `bcctr` waits until the removed `bc` completes,
that is until everything older has (UM 6.4.1.1). Once the CQ has drained
behind it with nothing allocated since, the `bc` has completed and a
`bcctr` uses the shadow's value. A held `mfctr`/`mtctr` (or
`mflr`/`mtlr`) that is a shadow's tagged entry enters the special lane
only at the CQ head, after the shadow has written.

| | Dhrystone cycles/run, w1 | w2 | CoreMark demo cycles, w1 | w2 |
|---|---:|---:|---:|---:|
| Round 19 (efc1a82) | 622 | 533 | 4,740,364 | 4,174,575 |
| Removed `bdnz` (7a2a472) | 622 | 531 | 4,674,089 | 4,170,333 |

CoreMark per iteration: w1 352,524, w2 311,603; CRCs match at both
widths. The `memcpy` loop now runs at the model's 7 cycles per pass in
steady state. Its first pass still takes 9: that `bdnz` is fetched
behind the `mtctr`, is not folded, and sits in DQ1 behind a store. A
trial that removed counting `bc` from DQ1 too left `memcpy` unchanged
and cost 3 cycles in `Proc_1` (534), so it was dropped. Open, w2:
`dhry_main` 5, `memcpy` 4, `Proc_8` 2, `Proc_1` 2.

Rules:

- `test-dispatch-rules` (TIM-BPU-FOLD) accepts a removed branch that
  writes CTR only as a `bc` without LK, and LR only as a `bl`. A younger
  `bc` on CTR or `bcctr` may not dispatch until everything older than a
  removed counting `bc` has completed (TIM-BPU-FETCH-STOP). The invalid
  counting `bcctr` form counts as a CTR write.
- The reference runner steps a removed counting `bc` and compares CTR at
  the next record. New negative controls flip CTR in the first record
  after a removed `bdnz`, and offer `bdnzl`, `bdnzlr` and a counting
  `bcctr` as removable words; each must fail (11 controls in all).
- `tb_core_interrupt` phase 12 raises an IRQ as a `bdnz` is removed; the
  IRQ must see CTR unwritten and resume at the `bdnz`, which then counts
  once (`mfctr` reads 0x54 from 0x55).

Recorded: `make -C sim -j2 lint check-spec` and `make -C sim test-core test-core-full-decode` at the default configuration;
at `DISPATCH_WIDTH=1` and `2` with `BRANCH_REMOVAL=1 VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo REFERENCE_DIR=<dingusppc>`:
`test-core test-core-recovery test-core-dual test-dispatch-rules test-core-interrupt test-core-interrupt-disabled test-core-branch-fold test-core-branch-recovery perf-diff`,
`test-reference-machine MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`,
`test-reference-machine-mmu MACHINE_MMU_ELF=<main checkout>/toolchain/build/chip-mmu-stress/smoke.elf`
and CoreMark on the demo model (`+IMAGE=coremark.hex`); `quartus_map --analysis_and_elaboration`
of `quartus/chip` with `PPC_LSU_PIPE=1 PPC_DISPATCH_WIDTH=2 PPC_BRANCH_REMOVAL=1`;
commit 7a2a472, 2026-10-07. All pass (Quartus: 0 errors), except the known
`test-core-branch-fold` REDEFMACRO stop at its built-in w2 build at w1; its w1
program passes (checks=101,519). Dispatch rules pass Dhrystone, CoreMark and
Whetstone at both widths. Interrupt benches: 15,044 and 382 checks.
Reference: 5 programs and 11 negative controls at both widths; Dhrystone
28,967 removed `bdnz` and selftest about 1.07 million; MMU stress 46,088
records, 220 interrupts and 2,944 removed `bdnz` at w1, 41,061 records and
236 interrupts at w2.

## Timing accuracy round 21

An `mtlr`/`mtctr` now dispatches into its holding slot before its
operand is written and takes it from the result buses there, as a
reservation station would (UM 6.3.3); it still enters the special lane
only at the CQ head. Before, it waited at dispatch for a ready source,
so in `memcpy` the `mtctr` behind `srwi` dispatched a cycle late.

| | Dhrystone cycles/run, w1 | w2 | CoreMark demo cycles, w1 | w2 |
|---|---:|---:|---:|---:|
| Round 20 (7a2a472) | 622 | 531 | 4,674,089 | 4,170,333 |
| Held-move snoop (5b26f0e) | 623 | 531 | 4,671,880 | 4,170,343 |

CRCs match at both widths. Whole Dhrystone run at w2: 2,014,111 to
2,013,520 cycles; Whetstone 6,481,816 to 6,481,565.

Diagnosis of the open w2 gaps (one iteration, core dispatch against the
model's front end):

- `dhry_main`: after `Proc_7` the core fetches `fff03e70` alone and its
  `blr` a cycle later, because a pair is fetched only with two free IQ
  entries. The model fetches the pair, since a branch goes to the BPU and
  takes no IQ entry (UM 6.3.1). The core is slow; every later fetch in
  the block is a cycle behind. Fix: let a fetched pair in when only one
  entry is free and the second word is removed.
- `memcpy`: with the `mtctr` fixed, `lwz` at `fff0333c` still dispatches
  a cycle after it, as DQ1 pairs beside a move only with an IU op. A
  trial that also paired an access beside `mtspr` matched the model's
  dispatch but then lost three cycles to `LSU_BUSY` before `fff0334c`
  (Dhrystone 532), so it was dropped; that stall is undiagnosed.
- `Proc_8`: `lwz r6,76(r1)` at `fff03850` reads the word `Proc_7` just
  stored and completes one cycle later than the model (A6), which fills
  the CQ and delays `fff03e7c` (+1). `stwx` at `fff03e88` then misses
  pairing in DQ1 (`IU+LSU lsu`, +1). Not yet traced into the LSU.
- `Proc_1`: not diagnosed this round.

Recorded: `make -C sim -j2 lint check-spec` and `make -C sim test-core test-core-full-decode` at the default configuration;
at `DISPATCH_WIDTH=1` and `2` with `BRANCH_REMOVAL=1 VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo REFERENCE_DIR=<dingusppc>`:
`test-core test-core-recovery test-core-dual test-dispatch-rules test-core-interrupt test-core-interrupt-disabled test-core-branch-fold test-core-branch-recovery perf-diff`,
`test-reference-machine MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`,
`test-reference-machine-mmu MACHINE_MMU_ELF=<main checkout>/toolchain/build/chip-mmu-stress/smoke.elf`
and CoreMark on the demo model (`+IMAGE=coremark.hex`); `quartus_map --analysis_and_elaboration`
of `quartus/chip` with `PPC_LSU_PIPE=1 PPC_DISPATCH_WIDTH=2 PPC_BRANCH_REMOVAL=1`;
commit 5b26f0e, 2026-10-07. All pass (Quartus: 0 errors), except the known
`test-core-branch-fold` REDEFMACRO stop at its built-in w2 build at w1; its w1
program passes (checks=101,519). Dispatch rules pass Dhrystone, CoreMark and
Whetstone at both widths. Interrupt benches: 15,044 and 382 checks.
Reference: 5 programs and 11 negative controls at both widths; MMU stress
46,319 records and 241 interrupts at w1, 41,058 records and 236 interrupts at w2.

## Timing accuracy round 22

A fetched pair whose second word is a `b`, or a `bclr` on an available
LR with BO "branch always", now enters with one free IQ entry: the word
goes to the BPU and takes none (UM 6.3.1). The decision reads only the
fetched word and LR state; if the word is not removed after all (a
waiting first word, trace mode), the pair waits in the FD registers for
two entries, as before. The FD registers' own pair also enters with one
entry when its second word is removed, folded or held back.

| | Dhrystone cycles/run, w1 | w2 | CoreMark demo cycles, w1 | w2 |
|---|---:|---:|---:|---:|
| Round 21 (bec1db2) | 623 | 531 | 4,671,880 | 4,170,343 |
| Removed pair word (230bb7a) | 623 | 530 | 4,671,878 | 4,170,242 |

CRCs match at both widths. Whole Dhrystone run at w2: 2,013,520 to
2,011,451 cycles; Whetstone 6,481,565 to 6,481,470.

Diagnosis of the other w2 gaps:

- An access in DQ1 beside an `mtctr` or `mtlr` in DQ0 is allowed by UM
  6.6.1.2 (different units, neither dispatch-serialized). A retrial of
  the pairing (`c0_move && d1_lsu && !dispatch_uop.gpr_write`) still
  costs a cycle (Dhrystone 531). In `memcpy` it never pairs: after the
  mispredicted `beq` at `fff03318`, the `mtctr` waits two to three
  cycles at the DQ0 head with `LSU_BUSY`, because the special lane is
  still busy with a non-overlapped memory operation (the
  `!special_busy || ... || (sru_move && (special_mem_overlap ||
  sru_in_lane))` dispatch term, `perf_special_mem_q` set). Which access
  holds the lane, and why it is not overlapped, is not yet traced; the
  pairing stays off.
- `Proc_8`: the model's A6 text and code agree once read as "the store
  writes the cache the cycle after it completes, and the load reads it
  the cycle after that": the code starts the load's EA cycle at store
  C + 1, so its cache read is at C + 2. The core's `lwz r6,76(r1)` reads
  a cycle later; the LSU side is not yet traced.

Recorded: `make -C sim -j2 lint check-spec` and `make -C sim test-core test-core-full-decode` at the default configuration;
at `DISPATCH_WIDTH=1` and `2` with `BRANCH_REMOVAL=1 VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo REFERENCE_DIR=<dingusppc>`:
`test-core test-core-recovery test-core-dual test-dispatch-rules test-core-interrupt test-core-interrupt-disabled test-core-branch-fold test-core-branch-recovery perf-diff`,
`test-reference-machine MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`,
`test-reference-machine-mmu MACHINE_MMU_ELF=<main checkout>/toolchain/build/chip-mmu-stress/smoke.elf`,
`test-core-lsu-update test-core-lsu-extensions test-core-lsu-timing test-core-lsu-timing-snoop test-core-lsu-timing-602`
and CoreMark on the demo model (`+IMAGE=coremark.hex`); `quartus_map --analysis_and_elaboration`
of `quartus/chip` with `PPC_LSU_PIPE=1 PPC_DISPATCH_WIDTH=2 PPC_BRANCH_REMOVAL=1`;
commit 230bb7a, 2026-10-07. All pass (Quartus: 0 errors), except the known
`test-core-branch-fold` REDEFMACRO stop at its built-in w2 build at w1; its w1
program passes (checks=101,519). Dispatch rules pass Dhrystone, CoreMark and
Whetstone at both widths. Interrupt benches: 15,044 and 382 checks.
Reference: 5 programs and 11 negative controls at both widths; MMU stress
46,319 records and 241 interrupts at w1, 41,058 records and 236 interrupts at w2.

## Timing accuracy round 23

A retired store in the LSU pipe's store queue now offers its write in its
retire cycle instead of the cycle after. The cache takes the write the
cycle after the store completes, and an overlapping load offers the cycle
after that and reads the cache then (A6, UM 1.1.4.3). A load's offer
cycle is the model's EA cycle and its response the cache cycle, as for a
load with no older store. In `Proc_8`, `lwz r6,76(r1)` behind the `stw`
in `Proc_7` now retires three cycles after the store, as in the model,
not four. The `test-core-lsu-timing` store-then-load retirement spacing
expectation moves from 4 to 3 to match.

| | Dhrystone cycles/run, w1 | w2 | CoreMark demo cycles, w1 | w2 |
|---|---:|---:|---:|---:|
| Round 22 (230bb7a) | 623 | 530 | 4,671,878 | 4,170,242 |
| Store offers at retirement (120f35f) | 623 | 529 | 4,645,044 | 4,148,984 |

CRCs match at both widths. Whole Dhrystone run at w2: 2,011,451 to
2,008,517 cycles; Whetstone 6,481,470 to 6,467,554.

Diagnosis of the other w2 gaps:

- `memcpy`: the round 22 note was wrong. The `LSU_BUSY` cycles at the
  `mtctr` are a stale `perf_special_mem_q` label: the special lane is
  busy with the `mtctr` itself (state EXEC, then HOLD, after it reaches
  the CQ head), and the younger `addi` waits on a full CQ and IU station,
  not on a memory access. No wrong-path access holds the lane. The
  `mtctr` itself retires on the model's cycle (D + 4). The loss is the
  first `bdnz`: fetch stops behind it (UM 6.4.1.1) and the core resolves
  it only at DQ0, four cycles after the model's BPU resolves it (the
  cycle after the `mtctr` executes). The target dispatches two cycles
  later than the model's, which is bounded by the CQ. Resolving a waiting
  CTR branch in the IQ when CTR becomes ready would recover those two
  cycles. Pairing the `lwz` beside the `mtctr` in DQ1 gains nothing:
  the CQ fills behind the serialized `mtctr` either way.
- Memcpy exit: `cmpwi` (an adder op) in DQ0 beside `slwi` in DQ1 does
  not pair. The model sends the `cmpwi` to the SRU and the `slwi` to the
  IU; the core only sends DQ1 to the SRU. The cycle is recovered a few
  instructions later.
- `stwx` at `fff03e88` in DQ1 waits for its index registers to be ready
  (`d1_lsu_ready` needs ready sources except a D-form base). The model
  dispatches it beside the `mulli` with unready sources into the LSU
  reservation station (UM 6.6.1.2).

Recorded: `make -C sim -j2 lint check-spec` and `make -C sim test-core test-core-full-decode` at the default configuration;
at `DISPATCH_WIDTH=1` and `2` with `BRANCH_REMOVAL=1 VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo REFERENCE_DIR=<dingusppc>`:
`test-core test-core-recovery test-core-dual test-dispatch-rules test-core-interrupt test-core-interrupt-disabled test-core-branch-fold test-core-branch-recovery perf-diff`,
`test-reference-machine MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`,
`test-reference-machine-mmu MACHINE_MMU_ELF=<main checkout>/toolchain/build/chip-mmu-stress/smoke.elf`
and CoreMark on the demo model (`+IMAGE=coremark.hex`); `quartus_map --analysis_and_elaboration`
of `quartus/chip` with `PPC_LSU_PIPE=1 PPC_DISPATCH_WIDTH=2 PPC_BRANCH_REMOVAL=1`;
commit 120f35f, 2026-10-07. All pass (Quartus: 0 errors), except the known
`test-core-branch-fold` REDEFMACRO stop at its built-in w2 build at w1; its w1
program passes (checks=101,519). Dispatch rules pass Dhrystone, CoreMark and
Whetstone at both widths. Interrupt benches: 15,044 and 382 checks.
Reference: 5 programs and 11 negative controls at both widths; MMU stress
46,418 records and 250 interrupts at w1, 41,049 records and 235 interrupts at w2.

Recorded: `make -C sim -j2 check-spec` and, at both widths with the same LSU-pipe settings,
`test-core-lsu-update test-core-lsu-extensions test-core-lsu-timing test-core-lsu-timing-snoop test-core-lsu-timing-602`;
commit 120f35f plus the spacing-expectation change committed with this record, 2026-10-07. All pass
(timing benches: 3,209 checks, 55 spacings).

## Timing accuracy round 24

A load or store with one address source not yet written now dispatches
from either slot into the LSU and waits there for it, with the other
source or the displacement as its offset (UM 6.3.3, 6.6.1.2). Before, only
a D-form load could wait on its base; an indexed access, or a store, waited
at dispatch for both sources. Update forms still wait at dispatch. In
`Proc_8`, `stwx` at `fff03e88` now dispatches beside the `mulli`, as in the
model.

An add or compare in DQ0 now takes the SRU when DQ1 holds an IU-only
operation, and the pair dispatches together (UM 6.4.5: the SRU executes
add and compare "in parallel with another integer instruction"). The
`memcpy` exit `cmpwi` and `slwi` now pair. The `test-core-dual`
`add + mullw` case now expects a pair when the SRU is built, for the
same reason.

| | Dhrystone cycles/run, w1 | w2 | CoreMark demo cycles, w1 | w2 |
|---|---:|---:|---:|---:|
| Round 23 (93b4201) | 623 | 529 | 4,645,044 | 4,148,984 |
| Waiting accesses, SRU pairing (23298cb) | 622 | 528 | 4,639,686 | 4,144,826 |

CRCs match at both widths. Whole Dhrystone run at w2: 2,008,517 to
2,003,717 cycles; Whetstone 6,467,554 to 6,443,526.

Not done: the first `bdnz` behind `mtctr` in `memcpy` still resolves at
DQ0, four cycles after the model's BPU (about two cycles per call). Fetch
stops behind it (UM 6.4.1.1) and `ctr_pending_q` clears only when the
`mtctr` retires. Resolving the youngest waiting CTR-only branch in the IQ
in the cycle after `ctr_pending_q` clears, and redirecting fetch from
there, would recover the cycles.

Recorded: `make -C sim -j2 lint check-spec` and `make -C sim test-core test-core-full-decode` at the default configuration;
at `DISPATCH_WIDTH=1` and `2` with `BRANCH_REMOVAL=1 VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo REFERENCE_DIR=<dingusppc>`:
`test-core test-core-recovery test-core-dual test-dispatch-rules test-core-interrupt test-core-interrupt-disabled test-core-branch-fold test-core-branch-recovery perf-diff`,
`test-reference-machine MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`,
`test-reference-machine-mmu MACHINE_MMU_ELF=<main checkout>/toolchain/build/chip-mmu-stress/smoke.elf`,
`test-core-lsu-update test-core-lsu-extensions test-core-lsu-timing test-core-lsu-timing-snoop test-core-lsu-timing-602`
and CoreMark on the demo model (`+IMAGE=coremark.hex`); `quartus_map --analysis_and_elaboration`
of `quartus/chip` with `PPC_LSU_PIPE=1 PPC_DISPATCH_WIDTH=2 PPC_BRANCH_REMOVAL=1`;
commit 23298cb, 2026-10-07 (the w1 `test-core-dual` run was repeated after the bench change). All pass
(Quartus: 0 errors), except the known `test-core-branch-fold` REDEFMACRO stop at its built-in w2 build
at w1; its w1 program passes (checks=101,519). Dispatch rules pass Dhrystone, CoreMark and Whetstone
at both widths. Interrupt benches: 15,044 and 382 checks. Reference: 5 programs and 11 negative
controls at both widths; MMU stress 46,319 records and 241 interrupts at w1, 41,094 records and
252 interrupts at w2. LSU timing benches: 3,209 checks, 55 spacings.

## Timing accuracy round 25

A `bc` on the CTR alone (BO[0] set, no LK) that stops fetching behind an
`mtctr` (UM 6.4.1.1) now executes in the IQ: in the cycle after the
`mtctr` retires, with no other CTR writer queued or uncommitted, the
youngest IQ entry, if it is that branch, resolves from CTR. Taken, fetch
redirects to its target and the entry is marked folded, so DQ0 does not
redirect again; not taken, fetch restarts after it. The branch still
dispatches and decrements CTR. Before, it resolved only at DQ0.

When CTR is ready: the manual says the branch "waits for the mtspr to
execute" (UM 6.4.1.1), and the BPU holds a CTR rename register for
`mtspr(CTR)` (UM 6.3). `mtspr` is completion-serialized (UM 6.3.3.2) and
takes 2 cycles (Table 6-2), so it finishes executing as it becomes able to
complete. The model's `ctr_ready = fin + 1` is therefore the earliest the
manual allows and is unchanged. The core resolves one cycle later (the
cycle after retirement, from the committed CTR), so it is never faster.

In `memcpy`, the first loop `lwz` now retires 8 cycles after the `mtctr`,
as in the model (10 before).

| | Dhrystone cycles/run, w1 | w2 | CoreMark demo cycles, w1 | w2 |
|---|---:|---:|---:|---:|
| Round 24 (23298cb) | 622 | 528 | 4,639,686 | 4,144,826 |
| CTR release in the IQ (dd7afe6) | 620 | 525 | 4,629,935 | 4,135,770 |

CRCs match at both widths. Whole Dhrystone run at w2: 2,003,717 to
1,997,520 cycles; Whetstone unchanged (6,443,526).

Remaining w2 Dhrystone gap (perf-diff, per iteration): `dhry_main` +6
front end, `Proc_1` +2, `strcpy` and `memcpy` +1 each.

Recorded: `make -C sim -j2 lint check-spec` and `make -C sim test-core test-core-full-decode` at the default configuration;
at `DISPATCH_WIDTH=1` and `2` with `BRANCH_REMOVAL=1 VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo REFERENCE_DIR=<dingusppc>`:
`test-core test-core-recovery test-core-dual test-dispatch-rules test-core-interrupt test-core-interrupt-disabled test-core-branch-fold test-core-branch-recovery perf-diff`,
`test-reference-machine MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`,
`test-reference-machine-mmu MACHINE_MMU_ELF=<main checkout>/toolchain/build/chip-mmu-stress/smoke.elf`,
`test-core-lsu-update test-core-lsu-extensions test-core-lsu-timing test-core-lsu-timing-snoop test-core-lsu-timing-602`
and CoreMark on the demo model (`+IMAGE=coremark.hex`); `quartus_map --analysis_and_elaboration`
of `quartus/chip` with `PPC_LSU_PIPE=1 PPC_DISPATCH_WIDTH=2 PPC_BRANCH_REMOVAL=1`;
commit dd7afe6, 2026-10-07. All pass (Quartus: 0 errors), except the known `test-core-branch-fold`
REDEFMACRO stop at its built-in w2 build at w1; its w1 program passes (checks=101,519). Dispatch
rules pass Dhrystone, CoreMark and Whetstone at both widths. Interrupt benches: 15,044 and 382
checks. Reference: 5 programs and 11 negative controls at both widths; MMU stress 46,141 records
and 225 interrupts at w1, 41,006 records and 243 interrupts at w2. LSU timing benches: 3,209
checks, 55 spacings. No bench expectation changed.

## Timing accuracy round 26

A store in LSU P1 no longer waits while a load that passed queued stores
is still in P2. In `Proc_8` the `lwzx` at `fff03ecc` passes the queued
`stw`s; the two `stw`s behind it then held P1 a cycle each, P1 filled,
and the `lwz` at `fff03864` dispatched a cycle late (`LSU_BUSY`). In
`Proc_1` the `stwu` behind that `lwz` waited the same way and the CQ
filled. The manual has no such ordering wait: stores leave the LSU for
the store queue and loads bypass them (UM 1.1.4.3, A6). The store now
queues and is marked young: the passing load's fault (`redo` or FP
fault) removes it with the rest of P1, and no later load passes it while
that load is in P2, so every store a passing load bypasses is older
than it.

| | Dhrystone cycles/run, w1 | w2 | CoreMark demo cycles, w1 | w2 |
|---|---:|---:|---:|---:|
| Round 25 (dd7afe6) | 620 | 525 | 4,629,935 | 4,135,770 |
| Young stores queue (63247f3) | 619 | 521 | 4,629,966 | 4,134,249 |

CRCs match at both widths. Whole Dhrystone run at w2: 1,997,520 to
1,986,169 cycles; Whetstone 6,443,526 to 6,442,041.

The w2 iteration now equals the model (521). Per function the core is
still +5 in `dhry_main` and +1 in `strcpy`, offset by `Proc_7` -2 and
`Func_1` -3. One of the offsets is the core being faster than the
manual: the `mtlr r0` at `fff03614` retires two cycles after the
instruction ahead of it, where completion serialization (UM 6.3.3.2) and
the 2-cycle `mtspr` (Table 6-2) give three. It enters the special lane
through `sru_head_next`, in the cycle the entry ahead retires, and
executes for one cycle. The `mtctr` at `fff03338` and `mtlr` at
`fff03f60` take three. Open; the fix is to let only `mfspr` enter on
`sru_head_next`.

Recorded: `make -C sim -j2 lint check-spec` and `make -C sim test-core test-core-full-decode` at the default configuration;
at `DISPATCH_WIDTH=1` and `2` with `BRANCH_REMOVAL=1 VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo REFERENCE_DIR=<dingusppc>`:
`test-core test-core-recovery test-core-dual test-dispatch-rules test-core-interrupt test-core-interrupt-disabled test-core-branch-fold test-core-branch-recovery perf-diff`,
`test-reference-machine MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`,
`test-reference-machine-mmu MACHINE_MMU_ELF=<main checkout>/toolchain/build/chip-mmu-stress/smoke.elf`,
`test-core-lsu-update test-core-lsu-extensions test-core-lsu-timing test-core-lsu-timing-snoop test-core-lsu-timing-602`
and CoreMark on the demo model (`+IMAGE=coremark.hex`); `quartus_map --analysis_and_elaboration`
of `quartus/chip` with `PPC_LSU_PIPE=1 PPC_DISPATCH_WIDTH=2 PPC_BRANCH_REMOVAL=1`;
commit 63247f3, 2026-10-07. All pass (Quartus: 0 errors), except the known `test-core-branch-fold`
REDEFMACRO stop at its built-in w2 build at w1; its w1 program passes (checks=101,519). Dispatch
rules pass Dhrystone, CoreMark and Whetstone at both widths. Interrupt benches: 15,044 and 382
checks. Reference: 5 programs and 11 negative controls at both widths; MMU stress 46,141 records
and 225 interrupts at w1, 41,006 records and 243 interrupts at w2. LSU timing benches: 3,209
checks, 55 spacings. No bench expectation changed.

## Timing accuracy round 27

An `mtspr` to LR or CTR no longer enters the special lane in the cycle
the entry ahead retires. It executes after every older instruction
retires (UM 6.3.3.2) and takes two cycles (Table 6-2), so it retires
three cycles after the instruction ahead; only `mfspr` (one cycle) may
enter as its older work completes. The `mtlr r0` at `fff03614` now takes
three cycles, like the `mtctr` at `fff03338` and the `mtlr` at
`fff03f60`; `mflr` keeps two.

The dispatch-trace checker enforces this as `TIM-SER-SRU-LATENCY`: an
`mtspr` or `mfspr` retires at least its Table 6-2 latency plus one cycle
after the retirement ahead (`mtspr` 2, `mfspr` 1, `mfspr` of a BAT 3).
The round 26 Dhrystone trace fails it; the new traces pass.

| | Dhrystone cycles/run, w1 | w2 | CoreMark demo cycles, w1 | w2 |
|---|---:|---:|---:|---:|
| Round 26 (c6c3133) | 619 | 521 | 4,629,966 | 4,134,249 |
| `mtspr` at the head (41e0a1f) | 621 | 523 | 4,642,833 | 4,143,790 |

CRCs match at both widths. The model is unchanged at 521, so the w2
core is now 2 cycles over it: the manual's cost of the `mtlr`, which
the round 26 total hid.

`Proc_7` and `Func_1` show the core ahead of the model only in the
front-end (dispatch) column. By retirement the core equals the model
through both functions: the per-instruction difference is the same on
entry and exit. The negative front-end figures are attribution: a
removed `blr` or `beq` takes no completion slot, so its offset drops and
the next instruction's rises in the caller. On the third `Proc_7` call
the core also dispatches its first `mr` beside the `addi` at `fff0362c`
by sending the `addi` to the SRU; the model gives the `addi` the IU and
dispatches the `mr` a cycle later. UM 6.4.5 lets the SRU add in parallel
with another integer instruction, so the model's greedy unit choice is
pessimistic. Making it choose the SRU when the next instruction needs
the IU drops the model to 509 cycles; that change needs its own review
and is not taken here.

`dhry_main` +5: by retirement, the first gap is the `li r31,65` at
`fff03878` behind the removed `ble` at `fff03874`. The model completes
it with the `cmplwi` in the branch's resolve cycle; the core retires it
a cycle later. Open: check against Figure 6-5 whether an instruction
behind a predicted branch may complete in the resolve cycle.

Recorded: `make -C sim -j2 lint check-spec` and `make -C sim test-core test-core-full-decode` at the default configuration;
at `DISPATCH_WIDTH=1` and `2` with `BRANCH_REMOVAL=1 VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo REFERENCE_DIR=<dingusppc>`:
`test-core test-core-recovery test-core-dual test-dispatch-rules test-core-interrupt test-core-interrupt-disabled test-core-branch-fold test-core-branch-recovery perf-diff`,
`test-reference-machine MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`,
`test-reference-machine-mmu MACHINE_MMU_ELF=<main checkout>/toolchain/build/chip-mmu-stress/smoke.elf`,
`test-core-lsu-update test-core-lsu-extensions test-core-lsu-timing test-core-lsu-timing-snoop test-core-lsu-timing-602`
and CoreMark on the demo model (`+IMAGE=coremark.hex`); `quartus_map --analysis_and_elaboration`
of `quartus/chip` with `PPC_LSU_PIPE=1 PPC_DISPATCH_WIDTH=2 PPC_BRANCH_REMOVAL=1`;
commit 41e0a1f with the checker of 2400ce6, 2026-10-07. All pass (Quartus: 0 errors), except the known
`test-core-branch-fold` REDEFMACRO stop at its built-in w2 build at w1; its w1 program passes
(checks=101,519). Dispatch rules, now with `TIM-SER-SRU-LATENCY`, pass Dhrystone, CoreMark and
Whetstone at both widths. Reference: 5 programs and 11 negative controls at both widths; MMU stress
46,362 records and 245 interrupts at w1, 40,792 records and 223 interrupts at w2. LSU timing benches:
3,209 checks, 55 spacings. Bench expectation changed: the synthetic `mtctr` in
`test_dispatch_trace.py` `test_fetch_stops` now retires three cycles after the `add` ahead
(UM 6.3.3.2, Table 6-2), not one.

## Timing accuracy round 28

The model's unit choice for an add or compare was pessimistic. It gave
the IU on every start-cycle tie, so a compare waiting in the IU station
for a load held the station and the next IU instruction could not
dispatch (UM 6.3.3: "dispatch of that instruction will stall until the
first instruction completes execution"). UM 6.4.5 lets the SRU execute
`addi`, `addis`, `add`, `addo`, `cmpi`, `cmp`, `cmpli` and `cmpl` "in
parallel with another integer instruction"; Table 6-4 note 1 limits the
`add` row to `add` and `addo` (no record form), and UM C.2.3 removes the
adder on the 602 (`--no-sru-add`). The manual names no steering rule,
so the model now picks the earlier start and, on a tie, the SRU when the
next non-branch instruction needs the IU (A10). It also admits `addo`,
which the core already sent to the SRU. The core's own rule (an add or
compare in DQ0 takes the SRU when DQ1 holds an IU-only instruction,
round 24) is the same choice.

| | Model, Dhrystone cycles/run | Core w2 | Gap |
|---|---:|---:|---:|
| Round 27 (1c76de0) | 521 | 523 | 2 |
| SRU steering (d6e8347) | 509 | 523 | 14 |

Other model figures: IU on every tie 521, no SRU adder 526, any fetch
pair (A2) 502, 37-cycle divide 526. The core is unchanged.

Per function by retirement spacing (core minus model, cycles per run,
round 27 trace): `strcmp` +11, `Proc_7` +2, `dhry_main` +2, `strcpy`
+1, `Func_2` -2, the rest 0. `strcmp`'s inner loop (`lbzu`, `cmpwi`,
`beq`, `mr`, `lbz`, `addi`, `cmpw`, `beq`) takes 6 cycles in the model
(the `cmpwi` waits for the `lbzu` in the SRU and the `mr` dispatches
the next cycle) and alternates 6 and 7 in the core: the `lbz r10,0(r4)`
behind `mr r4,r8` retires two cycles after the `mr` against one in the
model, and the core's `cmpw` retires four cycles after its dispatch.

Completion in a predicted branch's resolve cycle (A7). UM 6.6.1.3 bars
completion of an instruction that follows "an unresolved predicted
branch"; Figure 6-5 acts on a resolution in its own cycle: branch 1
resolves in cycle 3 and the BPU predicts branch 5 in cycle 3, and branch
5 resolves in cycle 5 and the correct-path fetch request goes out in
cycle 5. A7 stands: work behind a correctly predicted branch may
complete in the resolve cycle. The core breaks it for a removed branch:
`bs_young_hold` releases only from the captured CR (`bs_hit`), a cycle
after the owner's CR arrives, so the `li r31,65` at `fff03878` retires
a cycle after the `cmplwi` ahead of the removed `ble` instead of beside
it. Adding the arrival-cycle match (`bs_cap_hit`) to the release fixes
that instance and passes the width-2 dispatch rules for Dhrystone,
CoreMark and Whetstone, but saves nothing on Dhrystone (1,991,076 against
1,991,074 cycles) and 26 cycles on CoreMark (4,143,764). It also puts the
IU compare result on the CQ1 retire gate, the path the existing comment
keeps it off. Not taken; it needs a timing review before it lands.

Recorded: `make -C sim check-spec` (251 and 29 tests pass) and
`perf_model_603e.py` on the round 27 width-2 Dhrystone trace
(`--mark fff03808`, default and `--fetch any`, `--div 37`,
`--no-sru-add`), commit d6e8347, 2026-10-07. The `bs_cap_hit`
experiment: `make -C sim test-dispatch-rules perf-diff DISPATCH_WIDTH=2
BRANCH_REMOVAL=1 VERILATOR=$PWD/sim/tools/verilate-lsu-pipe
VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe` on d6e8347 plus that
uncommitted one-line change, 2026-10-07: pass, figures above.

## Timing accuracy round 29

Two core changes; the model is unchanged (509 cycles per run).

Completion in a predicted branch's resolve cycle (A7, UM 6.6.1.3, Figure
6-5) now lands. `bs_young_hold` releases on the owner's CR result as it
is offered and matches the prediction (`bs_cap_offer`). The offer ignores
recovery, which retirement already gates; built from the cancel-masked
capture, the hold closed a combinational loop through recovery
acceptance. Timing-phase item: the IU and SRU compare results and the CR
bit select now reach the CQ1 retire gate (`bs_cap_offer` to
`bs_young_hold` to the retire gate).

SRU steering in the core now follows the model's tie rule (A10). `strcmp`'s
`cmpwi` (DQ1, beside the `lbzu` in DQ0) waited in the IU station for the
load, so the `mr` behind the predicted `beq` could not dispatch until the
`cmpwi` started (UM 6.3.3). The core only sent a DQ1 add or compare to the
SRU while the IU station was taken. With both stations free, an add or
compare in DQ0, or in DQ1 beside another unit's instruction, now takes the
SRU when the next non-branch instruction needs the IU. The lookahead reads
the IQ entry behind DQ1 (a new `dq2_o` port) and the fetched words.
Timing-phase item: the fetched words' decode and pair predecode, from the
fetch response when the fetch/decode register is empty, now feed dispatch
through `fd_next_iu`, `c0_sru` and `d1_alt_sru`.

The round 28 note that `lbz` retires two cycles after `mr` against one
in the model was attribution: the load starts the cycle after the `mr`
executes and completes two cycles later in both. The model's `mr`
completes late because it waits on the `cmpwi` ahead of it in order.

| | Model | Core w2 | Core w1 | CoreMark w2 demo | CoreMark w1 demo |
|---|---:|---:|---:|---:|---:|
| Round 28 (5c9e854) | 509 | 523 | 621 | 4,143,790 | 4,642,833 |
| A7 and SRU steering (a180a4b) | 509 | 513 | 621 | 4,138,918 | 4,642,833 |

Per function by retirement spacing (core minus model, w2): `strcmp` +11
to +1; `dhry_main` +3, `strcpy` +1 and `Proc_7` +2 unchanged; `Func_2`
-2. `Func_2`'s is a real difference, not attribution: `stw r0,20(r1)`
after `mflr r0` completes two cycles after the `mflr` in the core and
three in the model, which starts the store only once its data is
forwarded (A11). Whether a store whose EA is ready may complete in the
cycle after its data is forwarded needs a manual ruling (UM 6.3.3,
Table 6-6) before either side changes. In `Proc_7` the removed `blr`'s
retirement stamp adds 1 to 3 cycles that the next instruction gives
back; the gap that stays is the `addi r9,r9,2` after `mr r9,r3`, which
the core retires a cycle after the `mr` in two of the three calls while
the model completes both together. Not yet diagnosed.

Recorded: `make -C sim -j2 lint check-spec`, `make -C sim test-core
test-core-full-decode`, and at widths 1 and 2 with
`VERILATOR=$PWD/sim/tools/verilate-lsu-pipe
VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe BRANCH_REMOVAL=1`:
`test-core test-core-recovery test-core-dual test-dispatch-rules
test-core-interrupt test-core-interrupt-disabled test-core-branch-fold
test-core-branch-recovery test-reference-machine perf-diff`
(`MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`),
`test-reference-machine-mmu` (chip-mmu-stress `smoke.elf`), the
CoreMark demo, and `test-core-lsu-update test-core-lsu-extensions
test-core-lsu-timing test-core-lsu-timing-snoop
test-core-lsu-timing-602`; commit a180a4b, 2026-10-07. All pass; CoreMark
CRCs match at both widths. At width 1, `test-core-branch-fold` does not
build: its width-2 variant redefines `PPC_DISPATCH_WIDTH` (REDEFMACRO),
as on round 28; the bench, not the RTL. Dispatch rules, width 2: Dhrystone
1,969,972 cycles, CoreMark 4,138,893, Whetstone 6,443,944. Quartus
`quartus_map --analysis_and_elaboration` of `quartus/chip` with
`PPC_LSU_PIPE=1`, `PPC_DISPATCH_WIDTH=2` and `PPC_BRANCH_REMOVAL=1`:
0 errors. No fit was run, so this round makes no timing claim.

Per instruction, the core's retirement spacing minus the model's completion
spacing, summed per iteration (Dhrystone, width 2, cycles per run), before
and after closing gaps 1, 2, 6 and 7:

| Retiring instruction | Per run | Core before | Core after | 603e | Gap before | Gap after |
|---|---:|---:|---:|---:|---:|---:|
| Update-form load/store (`lbzu`, `stbu`, `stwu`) | 83 | 574 | 410 | 115 | 459 | 294 |
| Integer instruction using the previous load | 55 | 255 | 55 | 55 | 200 | 0 |
| Plain load, base written ≤6 instructions back | 35 | 190 | 126 | 54 | 136 | 72 |
| Compare | 60 | 161 | 88 | 28 | 133 | 60 |
| Other integer | 149 | 228 | 298 | 107 | 122 | 192 |
| Plain store, a source written ≤6 instructions back | 34 | 156 | 90 | 51 | 106 | 40 |
| Plain load, base older | 30 | 152 | 139 | 48 | 104 | 91 |
| First instruction after a taken branch | 18 | 108 | 130 | 37 | 71 | 93 |
| Branches (folded on the 603e) | 118 | 107 | 99 | 0 | 107 | 99 |
| Plain store, sources older | 8 | 18 | 18 | 11 | 8 | 7 |
| **Total** | **590** | **1950** | **1454** | **506** | **1444** | **948** |

Recorded: the traces above (commits 5d0d244 and 60b0659), classified by
retiring instruction in that order of precedence: branch, update form, plain
load, plain store, first after a taken branch, integer reading the previous
load's destination, compare, other. 2026-10-04.

After the change no instruction waits for memory to drain. What the update
forms and loads are still charged is fetch and branch time: `strcpy` and
`strcmp` are byte loops whose loop-top `lbzu` follows a taken `bc` that waited
for its compare, then a refetch, one instruction per cycle (gaps 3 and 4).

A row is charged where the stall shows up, not where it starts: a branch that
waits for a compare shows up on the compare or the instruction after it.
`strcpy` and `strcmp` (byte loops on update forms) hold 67% of the gap (968 cycles per run).

Ranked by estimated cycles recovered per run at width 2. Estimates overlap;
they are not additive. None needs timing faster than the manual's.

| Rank | Gap | 603e rule | Change | Est. gain |
|---:|---|---|---|---:|
| 1 | Closed. Update forms took the serialized lane (5–8 cycles each, 83 per run) | T6-6: `lbzu`/`stbu`/`stwu`/`lwzu` are `2:1` like plain forms; the update uses a second GPR rename (UM 6.6) | Done: update forms run in the unit, the base in a second rename slot written with the EA ([LSU_PIPELINE.md](LSU_PIPELINE.md#update-forms-and-rename-operands)) | 491 measured with 2 |
| 2 | Closed. A load or store whose base or data had an uncommitted producer drained the machine (`drain_memory` 367 per run) | UM 6.3.3, 6.3.3.1: the instruction waits in the LSU station for the rename tag, executes the cycle the result is written; stores wait for data in the store queue (UM 1.1.4.3) | Done: the base comes from rename, including a value written that cycle; store data waits in P1 for the result bus. `drain_memory` is 0 per run at width 2 (19 at width 1: an update load's base takes the single write port a cycle later) | (with 1) |
| 3 | Taken-branch refetch and empty IQ (`branch_refetch` + `fetch_empty` 258 per run) | UM 6.3.2.2: one-cycle hit, two instructions per fetch; IQ of six topped off every cycle; F6-3: target two cycles after the branch, hidden by the IQ | Done: the tops fetch two words (126 cycles at width 2), and a micro-TLB and cache hit is requested every cycle (52 more) | 120–200 (got 178) |
| 4 | A `bc` waits for its uncommitted CR producer (`drain_branch` 187 per run) | T6-4 `^`: compare CR to the BPU at end of execute; UM 6.4.1.2: predict and dispatch down the predicted path, one level, no completion past it | Done: dispatch past one unresolved `bc`; a miss removes the younger work and redirects fetch on the edge after resolution | 150–190 (got 35 at width 2, 134 at width 1) |
| 5 | Dual dispatch rarely pairs (7.6% of instructions at width 2); dispatch alone is 0.92 CPI against a 0.86 CPI target | UM 6.6.1.2/6.6.1.3: DQ1 to a different unit, CQ1 integer or load; UM 6.4.5: SRU adder | Partly done: IU + LSU-unit access, unresolved `bc` + DQ1 (25 cycles), a DQ0 branch that does not redirect + DQ1 (5). IU + SRU, LSU + IU and CQ1 rules existed. Open: an SRU-form DQ0 beside a non-SRU integer DQ1 (the SRU takes DQ0); the rest waits on gaps 1 and 2 | 80–150 (after 1–4) |
| 6 | Closed. Residual cost of plain accesses with old sources (5.0 cycles per load) | UM 6.4.4: one access per cycle | Found: a store hit held the data cache for four cycles. It now writes and answers in its lookup cycle. The rest of the charge is fetch and branch time | 5 measured |
| 7 | Closed for integer consumers (55 dependents, gap 0). A load or add producing the next access's base costs 3 cycles against T6-6's 2 | T6-6 `2:1` | Done: `LSU_BASE_SNOOP` (default on since 2026-10-06) forms a D-form load's EA in P1 from the result bus, 2 cycles; `LSU_BASE_SNOOP=0` is the named base-wait timing trade, 3 cycles ([LSU_PIPELINE.md](LSU_PIPELINE.md#base-snooping)) | 1 measured while fetch-bound |
| 8 | Branches take dispatch and completion slots (118 per run) | UM 6.4.1.1, 6.3.1: folded branches bypass the dispatch queue; a branch with no SPR write back is retired by the BPU | Partly done behind `ENABLE_BRANCH_REMOVAL`: a plain `b` never enters the IQ; other branches without LR/CTR writes take no CQ entry but still a dispatch slot ([branch removal](#branch-removal-gap-8)). Linking and counting branches keep their entry | 40–100 (got 3 at width 2) |
| 9 | Integer waits not explained above (flags token, station full, `other` 50 per run) | UM 6.3.3, 6.3.3.2 | Broken down with `+PROFILE` ([above](#dq1-rename-operands-and-base-snooping)): `mflr`/`mtlr` drains 20, CQ full 20, station full 20, flags 7. Moves no longer drain; XER-only writers take no flag token ([round](#serialization-flag-token-and-dq1-branches)) | 20 (SRU completion serialization): got 11.5 |
| 10 | `bclr` not folded (26 per run, 11 taken) | UM 6.6.1.1: `bclr` resolves when LR is available (shadow LR from `bl`); same timing as `b` | Done: folds and resolves from the shadow LR of an uncommitted linking branch | 30–50 (got 8–10) |

CoreMark points the same way with a different weight: loads (175,000 cycles of
gap per iteration), `bc` (178,000 at width 1, 66,000 at width 2), integer
(101,000). Its multiplies cost 4.7 cycles against the model's 3 (A8), worth
17,000 cycles per iteration.

## Timing accuracy round 30

One core change and a new checker rule; the model is unchanged (509
cycles per run).

`Func_2`'s `stw r0,20(r1)` after `mflr r0` completed 2 cycles after the
`mflr` in the core and 3 in the model. The core was too fast. UM 6.3.3.2
and 6.4.5: results of completion-serialized SRU instructions "will not be
available or forwarded for subsequent instructions until the serializing
instruction is retired"; UM 6.3.3.1: an instruction waiting on a rename
tag begins execution once the data is in the rename register; T6-6 and
UM 6.4.4: a store takes two cycles. A reader therefore executes no
earlier than the cycle after the retirement, and a store completes no
earlier than 3 cycles after it, as the model has it (A11). The special
unit's result woke its readers in its finish cycle, a cycle before it
retires, so the store in P1 had its data a cycle early.

The wake packet now carries a `late` bit for a special-unit result other
than a memory access's. Rename does not forward it at dispatch; the IU
and SRU stations and the LSU's P1 (data and base) take the value and use
it a cycle later. Timing-phase item: the late bit adds a register per
station operand and per P1 entry; the P1 data and base snoops and the
station's same-cycle resolve gain a `!late` term.

The checker gains TIM-SER-RESULT (`sim/spec/timing.json`): a reader of an
`mfspr`, `mftb`, `mfmsr`, `mfcr`, `mfsr` or `mfsrin` result retires at
least 2 cycles after it, a load or store using it as base or data at
least 3. It counts only forms whose operand fields are unambiguous, and
stops tracking a register at any later instruction that may write it.

| | Model | Core w2 | Core w1 | CoreMark w2 demo | CoreMark w1 demo |
|---|---:|---:|---:|---:|---:|
| Round 29 (18dab36) | 509 | 513 | 621 | 4,138,918 | 4,642,833 |
| Serialized result forwarding (446452f) | 509 | 515 | 619 | 4,139,002 | 4,642,787 |

Per function (core minus model, w2): `Func_2` -2 to 0. Width 1 gains 2
cycles per run: the store now meets its data later, which moves later
work off a conflict.

`Proc_7` +2 is not in completion. In calls 2 and 3 (from `Proc_1`, behind
a `bl` the core removes at dispatch) the `bl` takes a dispatch cycle of
its own, so the `mr r9,r3`/`addi r9,r9,2` pair dispatches a cycle later
than in the model, where the folded `bl` takes no slot (UM 6.4.1.1) and
its target reaches dispatch two cycles after its fetch (F6-3). The core
then completes both at their execution time; the model's `mr` completes
late beside the `addi` because the two instructions ahead hold both
completion slots. Whether the `bl` slot or the target fetch sets the core's
cycle is not yet traced.

Recorded: `make -C sim -j2 lint check-spec`, `make -C sim test-core
test-core-full-decode`, and at widths 1 and 2 with
`VERILATOR=$PWD/sim/tools/verilate-lsu-pipe
VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe BRANCH_REMOVAL=1`:
`test-core test-core-recovery test-core-dual test-dispatch-rules
test-core-interrupt test-core-interrupt-disabled test-core-branch-fold
test-core-branch-recovery test-reference-machine perf-diff`
(`MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`),
`test-reference-machine-mmu` (chip-mmu-stress `smoke.elf`), the
CoreMark demo, and `test-core-lsu-update test-core-lsu-extensions
test-core-lsu-timing test-core-lsu-timing-snoop
test-core-lsu-timing-602`; commit 446452f, 2026-10-07. All pass; CoreMark
CRCs match at both widths. At width 1, `test-core-branch-fold` does not
build (REDEFMACRO of `PPC_DISPATCH_WIDTH` in its width-2 variant), as on
rounds 28 and 29. Dispatch rules, width 2: Dhrystone 1,974,063 cycles,
CoreMark 4,138,977, Whetstone 6,444,552; width 1: 2,265,283, 4,642,762,
7,259,287. Quartus `quartus_map --analysis_and_elaboration` of
`quartus/chip` with `PPC_LSU_PIPE=1`, `PPC_DISPATCH_WIDTH=2` and
`PPC_BRANCH_REMOVAL=1`: 0 errors. No fit was run, so this round makes no
timing claim.

## Timing accuracy round 31

One core change, no cycle change; the model is unchanged (509 cycles per
run). Two causes of the remaining width-2 gap are traced.

The add/compare steering takes the SRU on a tie when the next
instruction needs the IU, so an IU station held by the add does not
stall that instruction's dispatch (UM 6.3.3, 6.4.5; model A10). The core's
lookahead stopped at a branch two entries behind DQ0 unless the queue held
exactly three. A branch takes no station, so it now reads the entry behind
the branch, as the model's next non-branch instruction does. In a
steady-state `Proc_1` call to `Proc_7`, the `addi r5,r5,12` before
`bl Proc_7` now takes the SRU and the target's `mr r9,r3` dispatches
beside the `bl`, matching the model's dispatch cycles. Timing-phase item:
the IU-need term gains a mux over IQ entry 3's unit bits.

`Proc_7` +2 (calls 2 and 3): dispatch now matches the model; the cycle is
in finish. In the traced iteration the `stw` before the `bl` (LSU), the
`addi` (SRU) and the `mr` (IU) finish in the same cycle. The CQ has two
finish ports; the store's result takes port 0 and the SRU's port 1, so the
`mr` holds the IU a cycle and the dependent `addi r9,r9,2` issues a cycle
late. The manual gives each unit its own result path into the rename
registers (UM 6.3), with no limit on finishes per cycle, and the model has
none. A store writes no rename register, so the fix is a finish path for a
store (or a third port).

`dhry_main` +3: two cycles are `Func_2`'s return, `mtlr r0` then `blr`.
UM 6.4.1.1: "An mtspr(LK) followed by a bclr—Fetching is stopped, and the
branch waits for the mtspr to execute." The model resolves the `blr` the
cycle after the `mtlr` finishes; the core clears `lr_pending_q` only when
the `mtlr` retires, so the `blr` resolves a cycle after retirement, and its
target dispatches 3 cycles after it rather than 2. The fix is to give the
BPU the `mtlr` value at finish.

Not done: `strcpy` +1, `strcmp` +1, and why round 30 made width 1 two
cycles faster (both dispatch-rule runs pass at width 1, but the rule that
covers the change is not yet identified).

The checker's rule coverage count is raised to 41 for round 30's
TIM-SER-RESULT; `check-spec` failed without it.

| | Model | Core w2 | Core w1 | CoreMark w2 demo | CoreMark w1 demo |
|---|---:|---:|---:|---:|---:|
| Round 30 (446452f) | 509 | 515 | 619 | 4,139,002 | 4,642,787 |
| Station lookahead past a branch (b5e542f) | 509 | 515 | 619 | 4,139,002 | 4,642,787 |

Recorded: `make -C sim -j2 lint check-spec`, `make -C sim test-core
test-core-full-decode`, and at widths 1 and 2 with
`VERILATOR=$PWD/sim/tools/verilate-lsu-pipe
VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe BRANCH_REMOVAL=1`:
`test-core test-core-recovery test-core-dual test-dispatch-rules
test-core-interrupt test-core-interrupt-disabled test-core-branch-fold
test-core-branch-recovery test-reference-machine perf-diff`
(`MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`),
`test-reference-machine-mmu` (chip-mmu-stress `smoke.elf`), the
CoreMark demo, and `test-core-lsu-update test-core-lsu-extensions
test-core-lsu-timing test-core-lsu-timing-snoop
test-core-lsu-timing-602`; commit b5e542f, 2026-10-07 (`check-spec` rerun
after the coverage fix). All pass; CoreMark CRCs match at both widths. At
width 1, `test-core-branch-fold` does not build (REDEFMACRO of
`PPC_DISPATCH_WIDTH` in its width-2 variant), as on rounds 28 to 30.
Dispatch rules, width 2: Dhrystone 1,974,063 cycles, CoreMark 4,138,977,
Whetstone 6,444,552; width 1: 2,265,283, 4,642,762, 7,259,287. Quartus
`quartus_map --analysis_and_elaboration` of `quartus/chip` with
`PPC_LSU_PIPE=1`, `PPC_DISPATCH_WIDTH=2` and `PPC_BRANCH_REMOVAL=1`: 0
errors. No fit was run, so this round makes no timing claim.

## Timing accuracy round 32

One core change: `mtlr` feeds the BPU's LR rename register as it finishes
(4f2f753). Dhrystone width 2 515 → 513, width 1 619 → 617; the model is
unchanged (509).

UM 6.4.1.1: "An mtspr(LK) followed by a bclr—Fetching is stopped, and the
branch waits for the mtspr to execute." The BPU holds its own LR rename
register for this (UM 6.2). The core cleared `lr_pending_q` only when the
`mtlr` retired, so the `blr` resolved a cycle after retirement. The lane's
`mtlr` result now carries the value; a `bclr` waiting on it leaves the IQ
in the `mtlr` finish cycle and redirects fetch the next (the BPU execute
cycle). Its target dispatches at `mtlr` finish + 3, the model's F6-3
timing. This removes two of round 31's three `dhry_main` cycles
(`Func_2`'s `mtlr r0; blr`).

Timing-phase path, taken for accuracy: the lane's result-port handshake
(`special_result_ready`) and the producer compare now reach `bu_ready` and
the dispatch decision, and the lane's result value reaches `bu_target`.

Checker: the `mtlr`/`bclr` case moves from TIM-BPU-FETCH-STOP to
TIM-BPU-LR-DEPENDENCY, now an execute-kind rule: a `bclr` behind an
`mtspr(LR)` resolves no earlier than the move's finish (a cycle before it
retires), and a taken target dispatches no earlier than the move's
retirement + 2. The test case "bclr removed behind mtlr" is replaced by a
passing trace (resolve the cycle after finish, target at retirement + 2)
and three failing ones: `bclr` before the `mtlr` executes, target early,
and target early after retirement.

| | Model | Core w2 | Core w1 | CoreMark w2 demo | CoreMark w1 demo |
|---|---:|---:|---:|---:|---:|
| Round 31 (b5e542f) | 509 | 515 | 619 | 4,139,002 | 4,642,787 |
| `mtlr` feeds the BPU LR rename (4f2f753) | 509 | 513 | 617 | 4,136,530 | 4,640,461 |

Recorded: `make -C sim -j2 lint check-spec`, `make -C sim test-core
test-core-full-decode`, and at widths 1 and 2 with
`VERILATOR=$PWD/sim/tools/verilate-lsu-pipe
VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe BRANCH_REMOVAL=1`:
`test-core test-core-recovery test-core-dual test-dispatch-rules
test-core-interrupt test-core-interrupt-disabled test-core-branch-fold
test-core-branch-recovery test-reference-machine perf-diff`
(`MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`),
`test-reference-machine-mmu` (chip-mmu-stress `smoke.elf`), the
CoreMark demo, and `test-core-lsu-update test-core-lsu-extensions
test-core-lsu-timing test-core-lsu-timing-snoop
test-core-lsu-timing-602`; commit 4f2f753, 2026-10-07. All pass; CoreMark
CRCs match at both widths. At width 1, `test-core-branch-fold` does not
build (REDEFMACRO of `PPC_DISPATCH_WIDTH` in its width-2 variant), as on
rounds 28 to 31. Dispatch rules, width 2: Dhrystone 1,969,140 cycles,
CoreMark 4,136,505, Whetstone 6,443,917; width 1: 2,260,333, 4,640,436,
7,258,594. Quartus `quartus_map --analysis_and_elaboration` of
`quartus/chip` with `PPC_LSU_PIPE=1`, `PPC_DISPATCH_WIDTH=2` and
`PPC_BRANCH_REMOVAL=1`: 0 errors. No fit was run, so this round makes no
timing claim.

## Timing accuracy round 33

One core change and a bench fix; the model is unchanged (509 cycles per
run). Dhrystone width 2 513 → 512, width 1 617 → 612.

`test-core-branch-fold` builds its width-2 variant with its own
`PPC_DISPATCH_WIDTH`; it now drops the outer `DISPATCH_WIDTH` define for
that build, so the bench builds and passes at width 1 (REDEFMACRO since
round 28).

The completion queue gains a third finish port for stores without
update. UM 6.3 gives each execution unit its own result path and sets no
limit on finishes per cycle; the core had two ports, port 0 shared by the
LSU, the IU and the special unit with the LSU first. A plain store writes
no register, so the LSU's result for it now finishes on the new port: no
wake, no value, but it carries the fault fields (`fault`, `data_fault`,
`page_miss`), and a clean finish retires in its arrival cycle as on port
0. Port 0 is then free for the IU. In round 31's `Proc_7` trace (calls 2
and 3, `stw` + `addi` + `mr` finishing together) the `mr` no longer holds
the IU, and the core's offset from the model is now constant through
`Proc_7`. `tb_completion` adds a store finishing on the third port beside
a register result on port 0 (no wake, retires that cycle) and a faulting
one (retires a cycle later with its cause). Four completion benches
(`test-completion`, `-cr-bits`, `-cr-fields`, `-flags`) had not built
since the wake packet's `late` bit (round 30, UNUSEDSIGNAL); they now
consume it.

Timing-phase item: the store flag selects port 0's source
(`lsu_port0`) and reaches the IU's and special unit's port-0 grant; the
CQ's head retire and pair retire gain a third finish term.

Why round 30 made width 1 two cycles faster: no manual rule was
involved; the gain was this port conflict. Width 1 has no SRU, so the IU
never takes port 1. In `Func_2`, before round 30 the `stw r0,20(r1)` took
the `mflr` value at finish, and the LSU's results on port 0 kept the
`li r9,0` result off the port: it retired 7 cycles after dispatch, and
the CQ filled for 3 cycles (PERF_CQ_FULL). Round 30 (UM 6.3.3.2, 6.4.5)
delayed the store's data a cycle, which moved the LSU results off the
`li`'s cycle; the `li` retired 3 cycles earlier and `Func_2` went 33 → 31
per run. With the third port, width 1 gains 5 more cycles, and CoreMark's
width-1 dispatch-rules run drops 66,276 cycles.

| | Model | Core w2 | Core w1 | CoreMark w2 demo | CoreMark w1 demo |
|---|---:|---:|---:|---:|---:|
| Round 32 (4f2f753) | 509 | 513 | 617 | 4,136,530 | 4,640,461 |
| Store finish port (faa2568) | 509 | 512 | 612 | 4,136,487 | 4,574,185 |

Not done: `strcpy` +1 and `strcmp` +1 at width 2, and the third
`dhry_main` cycle.

Recorded: `make -C sim -j2 lint check-spec`, `make -C sim test-core
test-core-full-decode`, `make -C sim test-completion
test-completion-cr-bits test-completion-cr-fields test-completion-flags
test-completion-ring test-completion-update test-recovery-state`, and at
widths 1 and 2 with `VERILATOR=$PWD/sim/tools/verilate-lsu-pipe
VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe BRANCH_REMOVAL=1`:
`test-core test-core-recovery test-core-dual test-dispatch-rules
test-core-interrupt test-core-interrupt-disabled test-core-branch-fold
test-core-branch-recovery test-reference-machine perf-diff`
(`MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`),
`test-reference-machine-mmu` (chip-mmu-stress `smoke.elf`), the
CoreMark demo, and `test-core-lsu-update test-core-lsu-extensions
test-core-lsu-timing test-core-lsu-timing-snoop
test-core-lsu-timing-602`; `test-fpu-all` at width 2 with the LSU pipe;
commit faa2568 plus the record, 2026-10-07. All pass, including
`test-core-branch-fold` at width 1; CoreMark CRCs match at both widths.
Dispatch rules, width 2: Dhrystone 1,967,636 cycles, CoreMark 4,136,462,
Whetstone 6,443,806; width 1: 2,245,885, 4,574,160, 7,223,475. Quartus
`quartus_map --analysis_and_elaboration` of `quartus/chip` with
`PPC_LSU_PIPE=1`, `PPC_DISPATCH_WIDTH=2` and `PPC_BRANCH_REMOVAL=1`: 0
errors. No fit was run, so this round makes no timing claim.

## Timing accuracy round 34

One core change; the model is unchanged (509 cycles per run). Dhrystone
width 2 stays at 512, width 1 612 → 607.

Width 1 has no SRU, and the IU took the second finish port only beside
an SRU, so an IU result meeting a load's on port 0 waited a cycle. UM 6.3
gives each unit its own result path and sets no limit on finishes per
cycle; the IU now takes port 1 whenever a load holds port 0 and no SRU
result is offered there, with or without an SRU. Width 2 on the 603e is
unchanged (the SRU was already present); the 602 variant, which has no
SRU, gains the same port. Timing-phase item: `iu_port1` and
`iu_offer_ready` no longer depend on the variant, so the IU's port-1
grant is live at width 1 and on the 602.

Width-2 residue, diagnosed but not fixed (each is a core cycle beyond
the model, which the manual supports):

- `strcpy` entry (`bl` at fff0381c). The fetcher took `stb` fff03818
  alone into its buffer while the IQ was full, then fetched the `bl`
  alone a cycle later. UM 6.3.1: a vacancy of one takes one instruction,
  but a branch goes to the BPU and takes no IQ entry, so the model fetches
  the doubleword `stb`+`bl` together. Keeping a buffered pair whole (and
  taking a `bl` second word with one IQ entry free) moves the fold a cycle
  earlier, but the `bl` still occupies an IQ entry and the DQ1 slot
  (removed at dispatch), so `addi` fff03484 still dispatches a cycle
  after the `stb`; the cycle needs the `bl` to leave the IQ at fetch
  (UM 6.3.1, model A3), which the core does not do for linking branches.
- `strcmp` exit (`beq` fff034e4 mispredicted, refetch at fff034e8). In
  each loop pass the forward `beq` fff034d0 waits on CR behind the
  predicted `beq` fff034e4 (UM 6.4.1.1, one level of prediction). The
  core holds the `mr` fff034d4 fetched beside it in the fetch registers
  too, so the `lbz` fff034d8 dispatches a cycle late; on the last pass the
  `cmpw` result, and so the mispredict, is a cycle late. UM 6.4.1.1 stops
  fetching only; the word already fetched beside the held branch enters
  the IQ (the model's `stop_f` rule).
- `dhry_main` fff03870: after `Proc_7`'s `blr` to fff0386c the core
  fetches fff03870 two cycles after fff0386c; the model one. Not yet
  traced.

No function is faster than the model in a way the manual forbids:
`Func_1` (−2 front end, −1 retirement) and `Proc_7` (−2) come from the
core dispatching ahead after earlier stalls, and `check_dispatch_trace.py`
passes at both widths.

| | Model | Core w2 | Core w1 | CoreMark w2 demo | CoreMark w1 demo |
|---|---:|---:|---:|---:|---:|
| Round 33 (b223ca6) | 509 | 512 | 612 | 4,136,487 | 4,574,185 |
| IU port 1 without SRU (d8bfec5) | 509 | 512 | 607 | 4,136,487 | 4,503,469 |

Recorded: `make -C sim -j2 lint check-spec`, `make -C sim test-core
test-core-full-decode`, and at width 1 with
`VERILATOR=$PWD/sim/tools/verilate-lsu-pipe
VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe BRANCH_REMOVAL=1`:
`test-core test-core-recovery test-core-dual test-dispatch-rules
test-core-interrupt test-core-interrupt-disabled test-core-branch-fold
test-core-branch-recovery test-reference-machine perf-diff`
(`MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`),
`test-reference-machine-mmu` (chip-mmu-stress `smoke.elf`), the
CoreMark demo, `test-core-lsu-update test-core-lsu-extensions
test-core-lsu-timing test-core-lsu-timing-snoop
test-core-lsu-timing-602` and `test-fpu-all`; at width 2 the same set
without the reference-machine targets and the CoreMark demo (the
width-2 603e logic is unchanged); commit d8bfec5 plus the record,
2026-10-07. All pass; CoreMark CRCs match. The width-2 CoreMark demo
figure in the table was inherited from round 33; rerun fresh in round 35
(`perf-diff` and the CoreMark demo at width 2, commit 2c61050, whose RTL
is d8bfec5's, 2026-10-07): 4,136,487 cycles, CRCs match. Dispatch rules, width 1: Dhrystone 2,228,118
cycles (was 2,245,885), CoreMark 4,503,444 (4,574,160), Whetstone
7,152,086 (7,223,475); width 2 unchanged at 1,967,636, 4,136,462,
6,443,806. Quartus `quartus_map --analysis_and_elaboration` of
`quartus/chip` with `PPC_LSU_PIPE=1` and `PPC_BRANCH_REMOVAL=1` (width
1): 0 errors. No fit was run, so this round makes no timing claim.

## Timing accuracy round 35

One core change; the model is unchanged (509). Dhrystone width 2
512 → 511, width 1 stays at 607.

`dhry_main` fff03870, traced: `Proc_7`'s `mr` fff03e70 and `blr`
fff03e74 arrived as one doubleword while the IQ was full (the core
trails the model by a cycle there, inherited from earlier code). The
fetcher handed out the `mr` alone and refetched the `blr` a cycle later,
so the `blr` folded, and fff0386c was fetched, a cycle late. The round 34
note had the symptom wrong: fff03870 follows fff0386c by one cycle; the
pair was late. UM 6.3.1: a branch takes no IQ entry, so the model fetches
it with the word before it as that word enters the IQ (A2, A3). Empty
fetch registers now take such a pair (second word a `b` or unconditional
`bclr`, as `rm1_early` already selects) while the IQ is full; the branch
folds as the first word enters. Path: `fetch_room2` gains an OR of
`rm1_early` and `!fd_valid_q`. The remaining cycle at fff03870 is a
completion-queue stall (`LSU+IU cq`) that follows from the same inherited
lag.

Not attempted this round (diagnosis as in round 34): the `strcmp` exit
(the `mr` held beside a CR-held `beq`) and the `strcpy` entry (`bl`
leaving the IQ at fetch).

| | Model | Core w2 | Core w1 | CoreMark w2 demo | CoreMark w1 demo |
|---|---:|---:|---:|---:|---:|
| Round 34 (2c61050) | 509 | 512 | 607 | 4,136,487 | 4,503,469 |
| Removable-branch pair held whole (fda2a79) | 509 | 511 | 607 | 4,136,487 | 4,503,469 |

Recorded: `make -C sim -j2 lint check-spec`, `make -C sim test-core
test-core-full-decode`, and at widths 1 and 2 (`DISPATCH_WIDTH=2` for
width 2) with `VERILATOR=$PWD/sim/tools/verilate-lsu-pipe
VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe BRANCH_REMOVAL=1`:
`test-core test-core-recovery test-core-dual test-dispatch-rules
test-core-interrupt test-core-interrupt-disabled test-core-branch-fold
test-core-branch-recovery test-reference-machine perf-diff`
(`MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`),
`test-reference-machine-mmu` (chip-mmu-stress `smoke.elf`), the
CoreMark demo and `test-core-lsu-update test-core-lsu-extensions
test-core-lsu-timing test-core-lsu-timing-snoop
test-core-lsu-timing-602`; commit fda2a79, 2026-10-07. All fresh, all
pass; CoreMark CRCs match. Dispatch rules, width 2: Dhrystone 1,965,563
cycles (was 1,967,636), CoreMark 4,136,462 (unchanged), Whetstone
6,443,805 (6,443,806); width 1: Dhrystone 2,228,113 (2,228,118), CoreMark
4,503,444, Whetstone 7,152,086 (unchanged). `test-fpu-all` not rerun (no
LSU or finish change). Quartus `quartus_map
--analysis_and_elaboration` of `quartus/chip` with `PPC_LSU_PIPE=1`,
`PPC_DISPATCH_WIDTH=2` and `PPC_BRANCH_REMOVAL=1`: 0 errors. No fit was
run, so this round makes no timing claim.

## Timing accuracy round 36

Design only; no RTL change. Neither width-2 residue could be made exact
and verified in the round's time box, so both are written up here
instead of landing partially. Figures are round 35's (56d77ef): model
509, Dhrystone w2 511, w1 607; CoreMark demo w2 4,136,487, w1 4,503,469.

### `strcmp` exit: word beside a CR-held branch

Today the lane-0 `beq` fff034d0 waits on CR behind the predicted `beq`
fff034e4 (`cr_hold0`), and `fd_push` is low, so the `mr` fff034d4 in
lane 1 stays in the fetch registers too. UM 6.4.1.1 (seventh case) stops
fetching only; the model enters the word at fetch (A14) and dispatches
it no earlier than the branch executes (A15).

Design:

1. Record. When `cr_hold0` is set, `fd1_valid` and the IQ has an entry,
   push lane 1 and move the branch to a pending record `hb_*`: valid,
   PC, BO/BI, target, and the anchor (the youngest IQ entry before it,
   or `fd_anchor` when the IQ empties this cycle, as `rem0_fd` picks).
   The record is not a prediction: it does not take the single BS
   record, and `bs_busy` stays the older predicted branch's.
2. Gate (A15). The entry pushed from lane 1 carries a `behind_hb` bit;
   it does not dispatch while the record is valid. Nothing else enters:
   fetch stays stopped (`fetch_hold_q`), as for `fetch_stop`.
3. Release. When `cr_final` (the cycle `cr_hold0` would drop today), the
   record resolves with `folds`' condition test. Not taken: clear the
   record; the entry dispatches the next cycle and fetch resumes at
   PC + 8. Taken: drop the youngest IQ entry (the lane-1 word; it cannot
   have dispatched) and request the target on that edge as `rel_fold`
   does, so the refetch keeps today's timing (UM Figure 6-5). The IQ
   needs a tail pop for this; it has none today.
4. Recovery and interrupts. A redirect or recovery older than the record
   (the predicted `beq` mispredicting, an exception on an older entry)
   clears the IQ and the record together; the branch refetches from the
   resume PC. An interrupt resumes at `committed_next_pc_q`, which is the
   branch's PC once the anchor has retired, so the branch re-executes;
   the `behind_hb` entry never dispatched. The branch's retirement count
   goes on the anchor's rb field only when it resolves.

Checks: `check_dispatch_trace.py` A15 already rejects a dispatch of the
`mr` before the branch executes; `test-core-branch-fold` and
`test-core-branch-recovery` need a case with the held branch taken and
an older mispredict in the same cycle. Path: the release adds a compare
on `hb_*` beside `rel_fold`, and the tail pop adds a decrement to the IQ
write pointer.

### `strcpy` entry: `bl` leaving the IQ at fetch

The core removes a `bl` at dispatch (`bu_remove`/`d1_remove` with the LR
shadow, `shadow_set`), so it takes an IQ entry and a dispatch slot. UM
6.3.1 and 6.4.1.1 remove branches at fetch; model A3 gives a branch no IQ
entry or dispatch slot. `blsplit.patch` (fetch keeps a buffered pair
whole; `lk_hold1` holds the `bl` alone in FD) moves the fold a cycle
earlier but not the `addi` fff03484 dispatch.

Design: remove a `bl` as it is queued, like `plain_b`, and move
`shadow_set` from dispatch to the carrier:

1. IQ empty after this cycle's dispatch: set the LR shadow at push
   (unarmed, `shadow_val_q` = PC + 4); it arms on the next allocation, as
   now.
2. Otherwise the youngest IQ entry carries an `lk_after` bit, with the
   value in one pending register; the carrier sets the shadow when it
   dispatches. One pending `bl` at a time: push removal requires
   `!shadow_valid_q`, no pending carrier, `!bs_busy` and
   `!recovery_accepted`, the conditions `bu_remove` uses now.
3. `lk_iq_q` does not count the removed `bl`; `lk_busy` also covers a
   pending carrier, so a younger `bcl`/`bclrl` still waits for the `bl`
   to complete (UM 6.4.1.1 sixth case). `lr_front_q` already takes the
   `bl`'s PC + 4 at push.
4. The rb count on the carrier includes the `bl` for retirement and the
   trace; the reference runner's `lr after removed bl` case and
   `test-core-interrupt` phase 11 (interrupt between the carrier and the
   `bl`'s completion) cover LR. An interrupt or exception before the
   carrier dispatches flushes the bit, and the `bl` refetches from the
   resume PC; after it, the shadow behaves as today.

Path: `push_remove0/1` gain the `bl` term (an opcode and LK compare);
`shadow_set` gains the carrier's dispatch.

Recorded: no RTL change; figures inherited from round 35 (commit
56d77ef, 2026-10-07). This record is commit-only documentation on
`timing-acc36`, 2026-10-07.

## Timing accuracy round 37

The `strcpy` entry design of round 36, implemented (af57641). The model
is unchanged (509). Dhrystone width 1 607 → 600; width 2 stays at 511.

A `bl` is removed as it is queued, like a plain `b` (UM 6.3.1, model
A3): it takes no IQ entry or dispatch slot, and its retirement is
counted on the next entry pushed. If no IQ entry is left after this
cycle's dispatch, it sets the LR shadow at push (unarmed, as a
dispatched `bl` does). Otherwise the youngest IQ entry is its carrier:
`lkp_q` holds the `bl`, `lkp_pos_q` the carrier's position, and the
shadow, `lr_disp_q` and the LR/LK pending state are set as the carrier
dispatches; beside a DQ0 carrier the shadow arms on the DQ1 allocation.
Conditions: one `bl` at a time (no shadow, no pending `bl`), no LR
writer queued before it (`lr_iq_q`, and not lane 0 of its pair), no
branch or prediction record queued before it (`marked_o`, a new IQ
output), and no misprediction or fix-up pending. A prediction may be
unresolved: the `bl` is then on its path (`lk_spec_q`), and a
misprediction recovery drops its shadow instead of keeping it. An
interrupt or exception before the carrier dispatches clears the IQ and
the pending `bl`, which refetches; after it, the shadow behaves as
before. `lk_iq_q` and `lr_iq_q` no longer count the `bl`; `lk_busy` and
`lr_free` cover the pending one, so a younger `bcl`/`bclrl` still waits
for it (UM 6.4.1.1 sixth case).

Width 2: the `bl` fff0381c now leaves at fetch, but `addi` fff03484
still dispatches a cycle after the `stb` fff03818: the CQ has one free
entry that cycle (`cq1_ready` low), from the inherited lag of the stores
before it (the model dispatches fff03808 and fff0380c a cycle apart).

Path: `push_remove0/1` gain the `bl` term (opcode and LK, `lr_iq_q`, the
six-entry `marked_o` OR); `shadow_set`, the shadow value mux and the LR
dispatch state gain the carrier's pop.

| | Model | Core w2 | Core w1 | CoreMark w2 demo | CoreMark w1 demo |
|---|---:|---:|---:|---:|---:|
| Round 35 (56d77ef) | 509 | 511 | 607 | 4,136,487 | 4,503,469 |
| `bl` removed at fetch (af57641) | 509 | 511 | 600 | 4,136,434 | 4,500,094 |

Recorded: `make -C sim -j2 lint check-spec`, `make -C sim test-core
test-core-full-decode`, and at widths 1 and 2 (`DISPATCH_WIDTH=2` for
width 2) with `VERILATOR=tools/verilate-lsu-pipe
VERILATOR_TOOL=tools/verilate-lsu-pipe BRANCH_REMOVAL=1`: `test-core
test-core-recovery test-core-dual test-dispatch-rules
test-core-interrupt test-core-interrupt-disabled test-core-branch-fold
test-core-branch-recovery test-reference-machine perf-diff`
(`MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`),
`test-reference-machine-mmu` (chip-mmu-stress `smoke.elf`), the
CoreMark demo and `test-core-lsu-update test-core-lsu-extensions
test-core-lsu-timing test-core-lsu-timing-snoop
test-core-lsu-timing-602`; commit af57641, 2026-10-07. All fresh, all
pass; CoreMark CRCs match; the reference runner's negative controls
(including `lr after removed bl`) pass. Dispatch rules, width 2:
Dhrystone 1,965,521 cycles (was 1,965,563), CoreMark 4,136,403
(4,136,462), Whetstone 6,443,608 (6,443,805); width 1: Dhrystone
2,213,186 (2,228,113), CoreMark 4,500,069 (4,503,444), Whetstone
7,124,977 (7,152,086). `test-fpu-all` not rerun (no FPU change). Quartus
`quartus_map --analysis_and_elaboration` of `quartus/chip` with
`PPC_LSU_PIPE=1`, `PPC_DISPATCH_WIDTH=2` and `PPC_BRANCH_REMOVAL=1`: 0
errors. No fit was run, so this round makes no timing claim.

## Timing accuracy round 38

A directed test of round 37's speculative `bl` found an LR bug, fixed in
1966674. No cycle-accuracy change was intended.

Bug: a `bl` removed at fetch on the predicted path of an anchored
branch still waiting on CR armed its LR shadow on the next entry. LR was
written as that entry reached the CQ head, although the entry's own
retirement was held by `bs_hold`. When the branch then mispredicted, the
recovery dropped the shadow, but LR already held the wrong-path PC + 4.
The write now also waits for `!bs_hold`. A `bl` completes only after the
branches before it resolve (UM 6.3.1, 6.6.1.3).

Tests:

- `test-core-branch-fold` program: the bc on a divide, mispredicted
  both ways, with the wrong path holding a `bl` alone, behind a carrier
  `addi`, or behind an `mtlr` (that one is not removed at fetch). The
  correct path reads LR and calls its own `bl`. Without the fix the
  width-1 run fails with GPR24 0x22b0 (the wrong-path `bl`'s PC + 4)
  where 0x44 is expected.
- `test-core-interrupt` phases 13-16: `divw`, `cmpi`, `beq+` (not
  taken), and the wrong path `bl` at 0x300 (alone) or 0x304 (behind a
  nop). The IRQ is raised as the shadow is set (13, 14) or once it is
  armed (15, 16). It must see the committed LR and resume on the correct
  path, where `mflr` reads it. Phase 15 fails without the fix. The
  oracle accepts the IRQ at 0x34, after the resolved removed `bc`, which
  no later retirement counts.

Path: `bs_hold` (CR capture and resolve) now feeds the LR shadow write
enable.

Width 2: Dhrystone stays at 511, and CoreMark's demo cycles fall by 6.
Width 1: unchanged.

Not done in the time box: the `strcmp` exit design (round 36) and the
width-2 `strcpy` entry lag. In the lag, `lwz` fff03808 reports "own
slot: DQ1 IU+LSU other" for one cycle, then pairs with fff0380c a cycle
after the model. Its cause is not yet traced.

| | Model | Core w2 | Core w1 | CoreMark w2 demo | CoreMark w1 demo |
|---|---:|---:|---:|---:|---:|
| Round 37 (af57641) | 509 | 511 | 600 | 4,136,434 | 4,500,094 |
| LR shadow behind `bs_hold` (1966674) | 509 | 511 | 600 | 4,136,428 | 4,500,094 |

Recorded: `make -C sim -j2 lint check-spec`, `make -C sim test-core
test-core-full-decode`, and at widths 1 and 2 (`DISPATCH_WIDTH=2` for
width 2) with `VERILATOR=tools/verilate-lsu-pipe
VERILATOR_TOOL=tools/verilate-lsu-pipe BRANCH_REMOVAL=1`: `test-core
test-core-recovery test-core-dual test-dispatch-rules
test-core-interrupt test-core-interrupt-disabled test-core-branch-fold
test-core-branch-recovery test-reference-machine perf-diff`
(`MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`),
`test-reference-machine-mmu` (chip-mmu-stress `smoke.elf`), the
CoreMark demo and `test-core-lsu-update test-core-lsu-extensions
test-core-lsu-timing test-core-lsu-timing-snoop
test-core-lsu-timing-602`; commit 1966674, 2026-10-07. All fresh, all
pass; CoreMark CRCs match. Dispatch rules, width 2: Dhrystone 1,965,521,
CoreMark 4,136,403, Whetstone 6,443,608; width 1: Dhrystone 2,213,186,
CoreMark 4,500,069, Whetstone 7,124,977 (all as round 37).
`test-fpu-all` was not rerun (no FPU change). Quartus `quartus_map
--analysis_and_elaboration` of `quartus/chip` with `PPC_LSU_PIPE=1`,
`PPC_DISPATCH_WIDTH=2` and `PPC_BRANCH_REMOVAL=1`: 0 errors. No fit was
run, so this round makes no timing claim.

## Timing accuracy round 39

The width-2 lag at the `strcpy` call in the Dhrystone loop is fixed.
At the loop tail, `cmpw` fff03910 in DQ0 carries the removed `bge`
fff03914, and `lwz` fff03808, the branch target, sits in DQ1. Beside a
carrier only an IU op could dispatch, so the `lwz` waited a cycle
("DQ1 IU+LSU other"). UM 6.6.1.2 has no such rule, and a folded branch
does not hold dispatch (UM 6.4.1.1). A DQ1 access to the LSU now
dispatches beside a carrier. The carrier's branch starts on that edge,
so the access enters the unit marked as behind an unresolved branch,
as it would a cycle later.

Path: `carry_start` (CR finality and the prediction test) now feeds the
LSU's speculation input, which is registered in the unit.

The pair now dispatches with the model, but the next cycle's `addi`
fff0380c waits on a full CQ, so retirement does not move: Dhrystone
w2 stays at 511 and its dispatch-rules run falls by 17 cycles.

Not done: the `strcmp` exit design (round 36) needs an IQ tail pop and
a held-branch record with its recovery cases; it was not attempted in
the time box.

| | Model | Core w2 | Core w1 | CoreMark w2 demo | CoreMark w1 demo |
|---|---:|---:|---:|---:|---:|
| Round 38 (1966674) | 509 | 511 | 600 | 4,136,428 | 4,500,094 |
| DQ1 access beside a carrier (4e10507) | 509 | 511 | 600 | 4,136,428 | 4,500,094 |

Recorded: `make -C sim -j2 lint check-spec`, `make -C sim test-core
test-core-full-decode`, and at widths 1 and 2 (`DISPATCH_WIDTH=2` for
width 2) with `VERILATOR=tools/verilate-lsu-pipe
VERILATOR_TOOL=tools/verilate-lsu-pipe BRANCH_REMOVAL=1`: `test-core
test-core-recovery test-core-dual test-dispatch-rules
test-core-interrupt test-core-interrupt-disabled test-core-branch-fold
test-core-branch-recovery test-reference-machine perf-diff`
(`MACHINE_PROGRAMS="hello dhrystone coremark whetstone selftest"`),
`test-reference-machine-mmu` (chip-mmu-stress `smoke.elf`), the
CoreMark demo and `test-core-lsu-update test-core-lsu-extensions
test-core-lsu-timing test-core-lsu-timing-snoop
test-core-lsu-timing-602`; commit 4e10507, 2026-10-07. All fresh, all
pass; CoreMark CRCs match. Dispatch rules, width 2: Dhrystone 1,965,504
(was 1,965,521), CoreMark 4,136,403, Whetstone 6,443,608; width 1:
Dhrystone 2,213,186, CoreMark 4,500,069, Whetstone 7,124,977
(unchanged). `test-core-branch-fold` at width 2 covers stores and loads
on both paths of a predicted `bc` at four code offsets, which should put
some in DQ1 beside a carrier (not instrumented); no bench expectation
changed. `test-fpu-all` was
not rerun (no FPU change). Quartus `quartus_map
--analysis_and_elaboration` of `quartus/chip` with `PPC_LSU_PIPE=1`,
`PPC_DISPATCH_WIDTH=2` and `PPC_BRANCH_REMOVAL=1`: 0 errors. No fit was
run, so this round makes no timing claim.

## Memory system

The demo SoC differs from a 603e board in ways that do not affect these numbers
but would on a real board:

- Its 60x target is on-chip RAM at the processor clock: AACK two cycles after TS,
  data beats on consecutive cycles, no address pipelining
  ([DEMO_SOC.md](DEMO_SOC.md#60x-target)). A 603e runs the bus at 1/2 to 1/6 of
  the core clock (UM 1.1; PID7v has no 1:1) with DRAM latency, so a miss costs
  many more processor cycles.
- Both benchmarks fit in the caches: misses are under 0.001 CPI in both, so warm
  caches (A1) hold and the bus does not set the result.
- Console and framebuffer writes outside the timed window are uncached tenures;
  they do not enter the measured figures.

## Timing rules not yet contracts

The manual sections below set the 603e's throughput but have no timing contract
in `docs/`. [TIMING_SPEC.md](references/TIMING_SPEC.md) transcribes Tables 6-1 to 6-6,
the rules and the figure cells, but marks them unbound and unreplayed.

| Section | Rule to capture |
|---|---|
| UM 6.3.1, 6.3.2.1–6.3.2.2 | Fetch: two per cycle, one-cycle hit, IQ of six filled on any vacancy, branch identification at fetch |
| UM 6.3.2.3, F6-4; ch. 3.1.2, 3.2.2 | I- and D-miss timing: critical doubleword forwarded, cache busy until the reload ends (PID6) or hit-under-reload (PID7v) |
| UM 6.4.1.1–6.4.1.2, F6-3, F6-5 | BPU cycle costs: taken target at F+2, misprediction redirect at R+1, one-level prediction, the seven fetch-stop cases, LR shadow |
| T6-4 `^`, UM 6.4.3 | CR forwarding to the BPU before completion |
| UM 6.3.3, 6.3.3.1 | Reservation-station issue on the rename write cycle |
| UM 6.6.1.2–6.6.1.3 | DQ1 and CQ1 pairing rules as cycle checks |
| UM 6.3.3.2, 1.1.4.4 | SRU completion serialization cost and result visibility |
| UM 6.4.4, 1.1.4.3 | LSU: 2:1 for update forms, single-cycle store, three-cycle store latency, miss blocking |
| UM 6.5.1–6.5.3 | Copy-back, write-through and inhibited access costs |
| UM 8.3.2.3, 8.4 | Burst ordering and data-tenure timing per bus ratio |
| UM 6.6 | Rename and CQ limits as dispatch stalls |

Each contract should come with a bench that checks the cycle count, the way
`test-core-lsu-timing` checks the LSU rows.
