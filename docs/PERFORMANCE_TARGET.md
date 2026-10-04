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
| **Primary.** Our binary on a manual-accurate PID7v 603e, warm caches | **506** | **1976** | **1.125** | Model, about ±10% |
| Same, PID6 (37-cycle divide) | 523 | 1912 | 1.088 | Model |
| Published Motorola figure (other compiler and library) | (406) | 2460 | 1.40 | Vendor, compiler unstated |

CoreMark on the same model: CPI 0.918 over one full iteration (319,000
instructions), about **3.6 CoreMark/MHz** (3.4–3.7 for multiply costs of 2–5 cycles).
No published 603e CoreMark exists; CoreMark postdates the part.

### Primary definition

The binary is `toolchain/build/demo/dhrystone.hex` as the demo Makefile builds it:
pinned gcc, `-O2 -mcpu=603e -msoft-float`, `DHRY_RUNS=2000`, the demo runtime's
own `strcpy`/`strcmp` (byte loops, `-fno-builtin`). One run is 590.0 retired
instructions. The timed loop starts at `dhry_main+0x1d4` (`fff03808`).

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
| SRU adder runs `add`/`addi`/`addis`/`cmp*` beside the IU | UM 1.1.2.2.3, 6.4.5 |
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
- A10: SRU adder present. Without it: 512 cycles.
- A11, A12: SRU serialization as above.
- A13: the single CR rename (UM 6.3.3.1) is not modelled; UM 6.6.1.2 does
  not list it as a dispatch condition. Holding a CR writer's finish until the
  previous writer completes adds 1 cycle.

Sensitivity of the primary figure: 500–523 cycles across A2, A10 and the divide.
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

None changes the target. The single CR rename is now A13 (+1 cycle with
`--core cr-rename`). A6 stays the main optimistic assumption; the store
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
- An `mtlr` feeds the shadow LR with its source, two cycles after it
  dispatches, when the 603e's SRU result reaches the BPU (UM 6.4.1.1; the
  model's `lr_ready`). A `bclr` behind it resolves at dispatch or folds
  instead of waiting for the `mtlr` to retire.

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
at dispatch for its base. `LSU_BASE_SNOOP` removes it but is off until a fit
meets the clock target (LSU_PIPELINE.md, Base snooping). `CQ_FULL STORE`
(6) and `LSU_BUSY STORE` (3) in memcpy follow.

## Gaps

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
| 7 | Closed for integer consumers (55 dependents, gap 0). A load or add producing the next access's base costs 3 cycles against T6-6's 2 | T6-6 `2:1` | Done behind `LSU_BASE_SNOOP` (default off): a D-form load forms its EA in P1 from the result bus, 2 cycles; the path waits for a fit ([LSU_PIPELINE.md](LSU_PIPELINE.md#base-snooping)) | 1 measured while fetch-bound |
| 8 | Branches take dispatch and completion slots (118 per run) | UM 6.4.1.1, 6.3.1: folded branches bypass the dispatch queue | Open. Retire folded branches from the BPU; LR/CTR updates through the BPU's own writeback; every retire-trace consumer must then expect missing branches | 40–100 |
| 9 | Integer waits not explained above (flags token, station full, `other` 50 per run) | UM 6.3.3, 6.3.3.2 | Broken down with `+PROFILE` ([above](#dq1-rename-operands-and-base-snooping)): `mflr`/`mtlr` drains 20, CQ full 20, station full 20, flags 7. Moves no longer drain; XER-only writers take no flag token ([round](#serialization-flag-token-and-dq1-branches)) | 20 (SRU completion serialization): got 11.5 |
| 10 | `bclr` not folded (26 per run, 11 taken) | UM 6.6.1.1: `bclr` resolves when LR is available (shadow LR from `bl`); same timing as `b` | Done: folds and resolves from the shadow LR of an uncommitted linking branch | 30–50 (got 8–10) |

CoreMark points the same way with a different weight: loads (175,000 cycles of
gap per iteration), `bc` (178,000 at width 1, 66,000 at width 2), integer
(101,000). Its multiplies cost 4.7 cycles against the model's 3 (A8), worth
17,000 cycles per iteration.

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
