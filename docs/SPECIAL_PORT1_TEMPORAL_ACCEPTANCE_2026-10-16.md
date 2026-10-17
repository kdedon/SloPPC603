<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

Composition note (2026-10-16): this draft adds the D1 admission cofactor to the exact accepted-bfd plus special-port1 source. The historical standalone results below do not validate the new combination. Fresh accepted-bfd temporal tracing, combined proofs, strict RTL/core gates, Quartus and matched timing remain pending.
<!-- Copyright (c) 2026 Kevin Dedon -->
# Special second-port temporal acceptance

Recorded: `make -C sim -j1 test-core-special-port1-temporal`, baseline RTL commit `bfd023cf702e653a74a9989856f935bcf971045b` plus the test extension, 2026-10-16. Strict compilation and baseline simulation pass. The special-offer candidate at `35dc07c` also passes strict compilation and simulation.

The optional complete-packet trace hook also passed a fresh baseline run with seed 1 and randomized reset. All 1,099 cycle/slot/packed-packet observations were recorded; SHA256 `7266c3f32b44ed84e345428b5c78226dd0ba8395ca49192d0d40c76977b3f780`. Baseline counters and manual assertions remain unchanged with logging enabled. The candidate trace is byte-identical: all 1,099 complete packets, cycles and slots match. Both runs take 5,096 cycles, with 215 dispatch pairs, 180 retirement pairs and one DQ1 access using a renamed base. The EXEC grant, SRU-priority collision, timer and suffix coverage counters are identical. Candidate RTL was supplied through a two-file source overlay against frozen `bfd023c`; the consumed core, special unit and bench match `35dc07c` exactly.

The extended existing `tb_core_dual` keeps `PORT1_STRESS=0` by default, with
its original program, configuration and expectations. The optional target enables
width 2, pipelined LSU, supervisor/live context, external interrupts and timers.
Timer ticks remain zero; it uses the default PID7v 603e division latency.
No default regression dependency is added.

## Baseline result

| Check | Observed result |
| --- | ---: |
| Eligible special EXEC grant beside LSU port 0 | 1 |
| Eligible special blocked by simultaneous SRU offer beside LSU port 0 | 1 |
| Standalone accepted timer result | 128 |
| Timer result beside LSU port 0 | 0 (reported, not required) |
| Independently checked suffix retirements | 1,024 |
| Total retirements | 1,099 |
| Cycles | 5,096 |
| Dispatch pairs / retirement pairs | 215 / 180 |
| DQ1 accesses with a renamed base | 1 |

All original dispatch/retirement pair and relative-cycle checks passed. The
original prefix's register/memory checks remain, with final register expectations
adjusted only for the suffix's explicit writes. No halt or illegal retirement
occurred. These are acceptance counts, not throughput improvements.

The 128 eight-word groups begin with sync and a long divide. The move and load
swap order in adjacent groups. A younger real load may issue while an older
divide holds the completion-serialized LR move. The first 64 groups make both
adds consume the divide result; the latter 64 make them independent, allowing
SRU completion before the move release. Each half tests both orders with public
load-response delays 0 through 31. Delay depends only on accepted public read
ordinal, with no forced DUT state or ready.

The independent suffix oracle requires every PC and instruction word in order,
known fault-free retirement, expected GPR destination and fixed architectural
value. It checks all 1,024 suffix instructions. The event monitor uses the
original leaf `result_port1_o`, actual special validity and LSU/SRU offers; it
never treats the proposed new complete-offer output as its oracle. It requires
nonzero EXEC grant, SRU contention and standalone timer bins, and checks complete
selected result packets against their actual source packet at those boundaries.

## Reproduction

Run the canonical optional target serially from the repository root:

```sh
make -C sim test-core-special-port1-temporal \
  BUILD_DIR=build/special-port1-temporal XRAND=1 XRAND_SEED=1
```

It uses the actual `sim/tools/verilate` wrapper, strict assertions and warnings,
one compiler worker, O0 C flags, unique X initialization and runtime seed 1 /
random-reset mode 2. The executed baseline used the identical recipe with only
the test-source path redirected to the prepared extension. Its test source SHA
is `0c60e68f64ebea3e2a61c52874fe7cc7308c938e4c4dfb3573281232eac2a2ea`;
full baseline core SHA is
`8a717edfb0feea9cb3985613ea7e6ec79f8c7d0576e84b55bec3894ed979b8e4`.
The target's canonical source is `tb/tb_core_dual.sv`; no scratch generator or
snapshot is required to run it.

To print bounded diagnostics for the first two groups and later actual move-
release/overlap events, explicitly append the optional plusarg:

```sh
make -C sim test-core-special-port1-temporal \
  BUILD_DIR=build/special-port1-temporal XRAND=1 XRAND_SEED=1 \
  SIM_ARGS='+verilator+seed+1 +verilator+rand+reset+2 +PORT1_DEBUG'
```

The new optional `+PORT1_TRACE=path` writes one row for **every** accepted
retirement, including branches: cycle, slot, and complete packed
`retire_packet_t` in hexadecimal. It preserves the existing `RETIRE_LOG` output
and its historical branch filtering. It adds no DUT input or control dependency.
For a matched old/new run, append `+PORT1_TRACE=path` to the same runtime arguments,
use distinct owned paths, and compare both complete files byte for byte. Exactly
1,099 packet rows and the same cycles are expected for this fixed profile; that
stronger baseline/candidate comparison remains unexecuted at this recording.

## Scope and remaining candidate acceptance

This establishes real baseline EXEC/LSU and SRU-contention reachability, not
candidate equivalence. Re-run the same canonical target on the proposed cofactor
and retain its exact architectural/manual expectations and nonzero bins before
claiming candidate temporal acceptance. The separate source-connected four-state
control-product proof covers unknown states, timer/MMU classes and exclusions;
it does not replace this temporal test or full-core precision/recovery checks.

Timer-plus-LSU overlap was zero. Ordinary timer dispatch drains LSU and blocks
new LSU issue while busy, unlike the LR/CTR move's special `sru_in_lane` case.
This workload does not claim integrated timer/LSU collision coverage or prove
that combination globally unreachable. Standalone timer acceptance is mandatory.
No FPU, MMU-fault recovery, ownership-wrap or full-state equivalence claim follows
from this finite workload. Existing timer-register, TLB-load, dual-LSU and
wake-wrap regressions remain relevant. No Fmax or area result is implied.

The finite source-connected four-state proof and this public temporal corpus pass. Other focused special/MMU/timer/owner gates, Quartus elaboration and physical timing for the new offer remain pending. This result makes no Fmax claim.
