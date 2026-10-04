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
| 3 | Taken-branch refetch and empty IQ (`branch_refetch` + `fetch_empty` 258 per run) | UM 6.3.2.2: one-cycle hit, two instructions per fetch; IQ of six topped off every cycle; F6-3: target two cycles after the branch, hidden by the IQ | Done for pairs: the tops fetch two words (126 cycles at width 2). Open: the translation router and wrapper hold one fetch in flight, so fetch does not yet request every cycle | 120–200 |
| 4 | A `bc` waits for its uncommitted CR producer (`drain_branch` 187 per run) | T6-4 `^`: compare CR to the BPU at end of execute; UM 6.4.1.2: predict and dispatch down the predicted path, one level, no completion past it | Done: dispatch past one unresolved `bc`; a miss recovers when the branch retires, later than the 603e's R+1 | 150–190 (got 23 at width 2, 124 at width 1) |
| 5 | Dual dispatch rarely pairs (7.6% of instructions at width 2); dispatch alone is 0.92 CPI against a 0.86 CPI target | UM 6.6.1.2/6.6.1.3: DQ1 to a different unit, CQ1 integer or load; UM 6.4.5: SRU adder | Partly done: IU + LSU-unit access and unresolved `bc` + DQ1 pair (25 cycles). IU + SRU, LSU + IU and CQ1 rules existed | 80–150 (after 1–4) |
| 6 | Closed. Residual cost of plain accesses with old sources (5.0 cycles per load) | UM 6.4.4: one access per cycle | Found: a store hit held the data cache for four cycles. It now writes and answers in its lookup cycle. The rest of the charge is fetch and branch time | 5 measured |
| 7 | Closed for integer consumers (55 dependents, gap 0). A load or add producing the next access's base costs 3 cycles against T6-6's 2 | T6-6 `2:1` | The EA is formed at dispatch, a cycle ahead of the access. Forming it in P1 from operands snooped there would meet T6-6 but puts the result bus, adder and micro-TLB in one cycle ([LSU_PIPELINE.md](LSU_PIPELINE.md#remaining-work)) | Not measurable while fetch-bound |
| 8 | Branches take dispatch and completion slots (118 per run) | UM 6.4.1.1, 6.3.1: folded branches bypass the dispatch queue | Open. Retire folded branches from the BPU; LR/CTR updates through the BPU's own writeback; every retire-trace consumer must then expect missing branches | 40–100 |
| 9 | Integer waits not explained above (flags token, station full, `other` 50 per run) | UM 6.3.3 | Break the per-cause counters down further first | 50–100 |
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
