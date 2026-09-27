# Timer and live BAT FPGA measurement



## 2026-09-27 refit after merging gate 2

Recorded: `./quartus/timer-bat/build.sh --docker`, merge of the gate-2 branch onto
`7609a14`, 2026-09-27. Setup meets 50 MHz at every corner (+1.594 / +1.393 ns
at slow 100 C / -40 C); Fmax 54.33 MHz; 4,945 ALMs. **Hold misses by 0.070 ns**
at slow -40 C on the zero-delay virtual input `pimem_rsp_insn_i[2]` →
`fetch.buf_insn[2]`; other corners pass.

## 2026-09-27 refit after merging AUD-21 and gate 1

Recorded: `./quartus/timer-bat/build.sh --docker`, merge of the gate-1 branch
onto `f6f9df5` (AUD-21 merged), 2026-09-27. Setup meets 50 MHz at every
corner (+1.447 / +1.612 ns at slow 100 C / -40 C); Fmax 53.90 MHz, 4,913 ALMs.
**Hold misses by 0.020 ns** at slow -40 C on the virtual input
`bat_write_data_i[30]` → `bat_service.write_data_q[30]`, with
`pimem_rsp_insn_i[6]` → `fetch.buf_insn[6]` at +0.001 ns. Both are
zero-delay same-clock virtual inputs, a measurement artifact rather than a
core path; the boundary model of the three measurement tops is being
revised. Other corners' hold passes (+0.251 / +0.137 / +0.121 ns).

## 2026-09-27 current refit (after AUD-50/AUD-33)

Recorded: `./quartus/timer-bat/build.sh --docker`, same merge, 2026-09-27.
Setup +0.695 / +0.648 ns, hold +0.249 / +0.052 ns at slow 100 C / -40 C; fast
corners pass. Fmax 51.67 MHz. 5,200 ALMs.

## 2026-09-27 micro-TLB refit with synchronized reset

Recorded: `./quartus/timer-bat/build.sh --docker`, commit `e8262df`,
2026-09-27. Quartus 17.0.2, derived clock uncertainty. As in the integrated
and translated tops, the measurement top registers `rst_ni` through two flops
and the SDC cuts only the asynchronous input to the first. Setup and hold
**meet 50 MHz at every corner**; 66 MHz is not met.

| Resource | Result |
| --- | ---: |
| ALMs | 5,215 / 41,910 (12%) |
| Registers | 5,094 |
| M10K blocks | 3 / 553 |
| Block-memory bits | 492 |
| DSP blocks | 3 / 112 |

| Corner | Setup slack (ns) | Hold slack (ns) |
| --- | ---: | ---: |
| Slow 1100 mV, 100 C | +0.775 | +0.249 |
| Slow 1100 mV, -40 C | +0.637 | +0.036 |
| Fast 1100 mV, 100 C | +9.278 | +0.136 |
| Fast 1100 mV, -40 C | +10.980 | +0.121 |

Fmax is 51.64 MHz at the worst corner (slow -40 C) and 52.02 MHz at slow
100 C. 66 MHz needs 15.15 ns; the core's worst path, the instruction-queue
RAM into `dispatch|entry.a.value`, would miss it by about 4.2 ns. The worst
paths into router, BAT service and micro-TLB registers keep 4.6 ns of slack
at slow 100 C (`state_q` into the BAT service response; micro-TLB fill,
4.9 ns), so at 66 MHz they would miss by at most 0.2 ns. The worst path
leaving the router is still `running_out_q` into the core, +1.790 ns. The
smallest hold slack is on the virtual `bat_write_data_i` input. Setup is
0.7 ns below the unsynchronized fit of `56824e5`; the reset is now an
internal high-fanout register net rather than a zero-delay input.

## 2026-09-27 micro-TLB refit

Recorded: `./quartus/timer-bat/build.sh --docker`, commit `56824e5`,
2026-09-27. Quartus 17.0.2, derived clock uncertainty. This adds the router's
per-side micro-TLBs and split instruction/data lanes
([MICRO_TLB.md](MICRO_TLB.md)). Setup **meets 50 MHz at every corner** with
1.5 ns to spare; hold **fails** on one measurement-boundary path.

| Resource | Without micro-TLB | This refit |
| --- | ---: | ---: |
| ALMs | 4,898 | 5,186 |
| Registers | 4,594 | 5,088 |
| M10K blocks | 3 | 3 |

| Corner | Setup slack (ns) | Hold slack (ns) |
| --- | ---: | ---: |
| Slow 1100 mV, 100 C | +1.492 | -0.356 |
| Slow 1100 mV, -40 C | +1.530 | -0.571 |
| Fast 1100 mV, 100 C | +8.676 | +0.134 |
| Fast 1100 mV, -40 C | +10.970 | -0.206 |

Fmax is 54.03 MHz at the worst corner. Worst setup stays in the core
(`fifo:iq` and `special:uop_q.spr` into `dispatch` and `special`). The
micro-TLBs synthesize to about 175 ALUTs and 184 registers per side. The
worst router paths have 4.66 ns of slack (slow 100 C): `request_ea_q` into
a micro-TLB fill, and `special|ea_q` into `request_ea_q` at acceptance, 5.0
ns. At 66 MHz (15.15 ns) the router paths would miss by about 0.2 ns and the
core by about 3.4 ns. Each failing hold path is the single path from the
virtual `rst_ni` input, with zero input delay, to `router|d_state_q`; the
refit above synchronizes that reset.

## 2026-09-27 refit without test redirect

Recorded: `./quartus/timer-bat/build.sh --docker`, commit `31bb82d`,
2026-09-27. Quartus 17.0.2, derived clock uncertainty. The measurement top now
sets `ENABLE_TEST_REDIRECT=0`, as the integrated top does, so the test-only
arbitrary-pivot recovery is not built. `running_o`, which gates the core's
reset, has its own `dont_merge` flop. Setup **meets 50 MHz at every corner**;
hold **fails** at slow -40 C on a measurement-boundary input.

| Resource | Combined refit | This refit |
| --- | ---: | ---: |
| ALMs | 5,628 | 4,898 |
| Registers | 4,478 | 4,594 |
| M10K blocks | 3 | 3 |

| Corner | Setup slack (ns) | Hold slack (ns) |
| --- | ---: | ---: |
| Slow 1100 mV, 100 C | +0.367 | +0.244 |
| Slow 1100 mV, -40 C | +0.532 | -0.121 (TNS -7.020) |
| Fast 1100 mV, 100 C | +8.327 | +0.131 |
| Fast 1100 mV, -40 C | +10.738 | +0.116 |

Fmax is 50.93 MHz at the worst corner (was 50.32), 51.37 MHz at slow -40 C;
66 MHz remains far off. Worst setup is in the core,
`special|uop_q.spr[3]` to `dispatch|entry.a.value`. The worst path leaving
the router is now `router|running_out_q` into the same dispatch endpoint at
+1.931 ns (slow -40 C), against -2.349 ns from `running_q` before. Every
failing hold path starts at the virtual `retire_ready_i` input, which has zero
input delay, and ends at a GPR MLAB address register; it is a property of this
measurement top's unconstrained I/O, like the earlier `bat_write_data_i` hold
failures, not a core register path.

## 2026-09-27 combined refit

Recorded: `./quartus/timer-bat/build.sh --docker`, merge of the MMU round (AUD-17,
AUD-42, AUD-48, AUD-74) onto `dea91c7`, 2026-09-27. Quartus 17.0.2, derived clock
uncertainty. Setup and hold **meet the provisional 50 MHz constraint at every
corner**, with little margin; 66 MHz (the aspirational target) is far off.

| Resource | Result |
| --- | --- |
| ALMs | 5,628 / 41,910 (13%) |
| Registers | 4,478 |
| M10K blocks | 3 / 553 |
| MLAB bits | 3,072 |

| Corner | Setup slack (ns) | Hold slack (ns) |
| --- | ---: | ---: |
| Slow 1100 mV, 100 C | +0.129 | +0.248 |
| Slow 1100 mV, -40 C | +0.264 | +0.067 |
| Fast 1100 mV, 100 C | +9.028 | +0.135 |
| Fast 1100 mV, -40 C | +11.040 | +0.118 |

Fmax is 50.32 MHz at the worst corner. The registered BAT write path (AUD-74)
removed the virtual BAT-input hold failures.

## 2026-09-27 MMU refit

Recorded: `./quartus/timer-bat/build.sh --docker`, commit `f3cc2f4`, 2026-09-27.
Quartus 17.0.2, `5CSEBA6U23I7`, seed 1. It **fits, meets hold and fails
setup**.

| Result | 2026-09-26 refit | This refit |
| --- | ---: | ---: |
| ALMs | 6,860 | 6,840 |
| Registers | 5,264 | 5,334 |
| Block-memory bits / M10K | 402 / 2 | 402 / 2 |
| Setup slack, slow 100 C / -40 C (ns) | -5.952 / -5.353 | -4.432 / -4.653 |
| Hold slack, slow 100 C / -40 C (ns) | -3.867 / -3.851 | +0.291 / +0.013 |
| Setup slack, fast 100 C / -40 C (ns) | — | +6.956 / +9.055 |

AUD-74 moved BAT write validation behind a captured request and registered
its result, and gave the router's BAT request select a private copy of
`!running_q`. The former worst path (`router|running_q` through the BAT
request mux and validation into `bat|upper_q`) is gone, and so is the
virtual-input hold failure into `bat|upper_q`. Every path ending in a router
or BAT-service register now has positive setup slack (worst +0.923 ns at
slow 100 C, into `router|request_wdata_q` from `completion|head_q`).

Worst setup is again the core cone, `core|completion|done_q[3]` to
`core|special|ea_q[30]` (AUD-01). The worst path leaving the MMU is
`router|running_q` into the same `special|ea_q` endpoint (-2.349 ns), a core
consumer of `running_o`.

This profile leaves page translation disabled, so synthesis prunes the TLB.
The AUD-17 entry RAMs were checked separately with map-only synthesis of
`ppc_tlb_service` (both runtime features enabled): two 64 x 62
simple-dual-port M10K blocks, 7,936 bits, 386 registers and 722 ALUTs,
against 8,226 registers, 3,510 ALUTs and no RAM for the previous flop array.
The paths were named with `quartus_sta` `report_timing` in the pinned image.

## 2026-09-26 refit

Recorded: `./quartus/timer-bat/build.sh --docker`, commit `95422a6` plus the
router struct-literal fix in the same commit as this record, 2026-09-26.
Quartus 17.0.2, `5CSEBA6U23I7`, seed 1, with derived clock uncertainty (AUD-09).
The previous source list omitted the segment and TLB services and no longer
elaborated (AUD-03); this run compiles the full `files.f` list. It **fits but
fails setup and hold**.

| Resource | Result | Archived |
| --- | --- | --- |
| ALMs | 6,856 / 41,910 (16%) | 7,093 |
| Registers | 5,275 | 5,132 |
| Block-memory data bits | 402 | 402 |
| M10K blocks | 2 / 553 | 2 |
| DSP blocks | 3 / 112 | 6 |
| Virtual / physical I/O pins | 721 / 0 | 647 / 0 |

| Corner | Setup slack (ns) | Hold slack (ns) |
| --- | ---: | ---: |
| Slow 1100 mV, 100 C | -4.494 | -3.700 |
| Slow 1100 mV, -40 C | -4.765 | -3.861 |
| Fast 1100 mV, 100 C | +5.646 | -1.621 |
| Fast 1100 mV, -40 C | +8.210 | -1.668 |

Worst setup is the AUD-01 cone, `core|completion|count_q[0]` to
`core|special|ea_q[30]`. Every worst hold path starts at the virtual
`bat_write_data_i` measurement input and ends in `bat|upper_q` storage with a
zero input delay: a property of this measurement top, which exposes the startup
BAT write port as unconstrained virtual pins, not of a core register path.

After the remaining audit merges (AUD-25/26/27/32/51/53/54/60), a refit on
2026-09-26 (`./quartus/timer-bat/build.sh --docker`) gives slow-corner setup
slack -5.952 / -5.353 ns (100 C / -40 C), hold -3.867 / -3.851 ns, 6,860 ALMs and 5,264 registers. The worst setup path moved to the BAT write/validate path (AUD-74).

## Archived result


The enabled timer/BAT profile **fits Cyclone V but fails provisional 50 MHz
setup and hold**. Quartus completed synthesis, fitting, assembly and timing
analysis in 13m11s; compilation and evidence checks returned zero, and source
hashes remained stable.

This separate project measures `ppc_core_bat` with supervisor exceptions,
live committed context, external interrupts and timers all enabled. It exposes
all 70 wrapper port declarations, including tick/TBEN, BAT programming,
physical instruction/data requests and responses, complete retirement packets,
and distinct external/DEC acceptance traces. No data path is tied to a fixed
instruction responder, and no trace is folded into a digest.

This is not the cached 60x composition. It includes the BAT translation service
and physical word-memory interfaces, not instruction/data cache, 60x transport,
segment/TLB/page-miss routing or the complete MMU MVP. The earlier cached
physical measurements remain unchanged and are not an A/B baseline for this
configuration.

## Configuration and checks

The target is Cyclone V `5CSEBA6U23I7`, Quartus 17.0.2, seed 1, one compilation
worker. The image is pinned by the same digest as the existing measurement
project. All ports, including the clock, are virtual. The provisional SDC uses
a 20 ns clock with zero min/max input/output delays. These constraints define
an experiment, not board reset/clock arrival or physical CPU timing signoff.
No constraint exception or reset behavior change is introduced.

Strict Verilator lint, shell syntax and the fail-closed 70-port virtual
assignment check pass. The project source list has 20 entries. The completed
result is recorded below.

Run from `quartus/timer-bat`:

```sh
verilator --lint-only -Wall --top-module ppc_timer_bat_measure -f files.f
./build.sh --docker
./report-critical-paths.sh --docker
```

The build records source/project/script hashes before and after execution and
rejects drift. It collects only fresh map/fit/flow/STA reports and requires zero
physical I/O. Compact evidence distinguishes complete-report hashes from its own
bundled-file manifest and retains critical-path query provenance.

## Fitted resources and timing

| Resource | Result |
| --- | --- |
| ALMs | 7,093 / 41,910 (17%) |
| Registers | 5,132 |
| Block-memory data bits | 402 |
| M10K blocks | 2 / 553 |
| DSP blocks | 6 / 112 |
| Virtual / physical I/O pins | 647 / 0 |

The instruction queue supplies the 402 RAM bits. Synthesis explicitly retains
`ppc_timer:timers_enabled.timer` with 97 registers for TB64, DEC32 and pending;
the fitter also records duplicated timer registers for routing. BAT service,
router and live exception state remain in the retained hierarchy. These are
actual measurements of this enabled configuration, not estimates from the
cached physical design.

| Corner | Setup slack (ns) | Hold slack (ns) |
| --- | ---: | ---: |
| Slow 1100 mV, 100 C | -4.939 | -2.998 |
| Slow 1100 mV, -40 C | -4.800 | -3.112 |
| Fast 1100 mV, 100 C | +6.576 | -1.264 |
| Fast 1100 mV, -40 C | +8.622 | -1.343 |

All illegal/unconstrained clock, input-port, input-path, output-port and
output-path counts are zero for setup and hold. Complete provisional coverage
is not board signoff. No operating frequency is inferred from these slacks.

## Measured paths and next review

The read-only path query succeeded and reproduced the reports. Worst setup
is a full-cycle internal register path at slow 100 C:
`core|completion|done_q[2]~DUPLICATE` to
`core|rename|owners[0].generation[7]`. It crosses special commit/branch redirect,
completion retained-prefix/survivor selection, then rename ownership
reconstruction. At slow -40 C the endpoint is rename `ready[0]~DUPLICATE`.
The next bounded setup review is whether survivor ownership metadata can be
retained instead of rewritten through the recovery-selection network, while
preserving ready/wake, generation identity and youngest-writer mapping. This
is a review proposal, not a change or proof of timing closure.

Worst hold is an external-input path at slow -40 C:
`bat_write_data_i[2]` through router request selection into
`router|bat|upper_q[1][3][2]`. Data arrives at 2.836 ns against a 5.948 ns
latch requirement. It is an external BAT programming boundary under zero
input delay, not a timer-counter or reset hold path. A physical clock and
programming-interface arrival contract is required before choosing a remedy.
No broad false path, reset change, or input-delay relaxation was applied.

## Accepted evidence

Compact evidence in the local `quartus/timer-bat/timer-20260921` archive (not in the repository) retains
resource excerpts, original flow/STA reports, full path query, tool/image
identity, statuses and source hashes. `archive.sha256` checks every bundled
file; `original-full-reports.sha256` is explicitly provenance for full reports
in ignored `evidence/20260921T142321Z-351712`. The source hashes were checked
again after the read-only query. Full databases and bitstreams remain ignored.
