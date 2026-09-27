# Timer and live BAT FPGA measurement

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
