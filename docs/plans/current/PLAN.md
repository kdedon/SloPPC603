# Current CPU plan

Updated: 2026-09-27. This is the active planning entry point. The target for
the next deliverable is a single-issue, big-endian integer CPU with supervisor
mode, resumable exceptions, interrupts and software-managed MMU. The full 603e
CPU remains the longer-term target.

The [system completion scorecard](../../SYSTEM_COMPLETION.md) is the authority
for current percentages, accepted behavior, gaps and the MVP effort range. The
[full CPU weighting audit](../../FULL_CPU_COMPLETION_AUDIT.md) tracks the wider
processor scope. [CPU references](../../references/README.md) collect the
distilled source contracts.

Companion plans in this directory:

- [MVP execution plan](MVP_EXECUTION_PLAN.md): MVP waves and the accepted-round ledger.
- [Full 603e task plan](TASK_PLAN.md): P00–P30 scope that the full CPU audit measures.
- [Original design brief](ORIGINAL_DESIGN_BRIEF.md): target machine for the full 603e.

Open correctness, efficiency and style findings are tracked in the
[repository audit](../../AUDIT.md).

## Working with this repository

Run `make -C sim regression` from the repository root for the simulation suite.
Reference comparison targets require a separate sibling `dingusppc` checkout.
Generated builds, logs and reports are excluded from version control.

## Next acceptance gates

1. Closed 2026-09-27: LRU page replacement, direct-store DSI/ISI and
   `tlbsync` are implemented, and seeded EXT/DEC/reset stress passes on the
   translated cached 60x top ([evidence](../../MMU_STRESS_FIRMWARE.md)).
   Machine check, trace and debug exceptions stay outside the MVP set; the
   stress has no ARTRY/TEA, which gate 2 owns.
2. Accepted 2026-09-27: cache maintenance, context changes, interrupts and data
   effects across held refills and bus retries, with CPU `icbi` and external
   maintenance as distinct contracts ([cache control](../../CACHE_CONTROL.md)).
   Page-table context changes under randomized retries remain with gate 1.
3. Closed 2026-09-28: the reviewed [interface timing contract](../../INTERFACE_TIMING_CONTRACT.md)
   is implemented by the measurement SDCs, and final fits on the complete MVP
   RTL meet 50 MHz setup and hold on all three tops. Open: 66 MHz on the cached
   tops (registered fetch-to-decode stage) and the remaining scorecard gaps.

4. MVP completion (scope set 2026-09-28): a snooping MEI data cache built and
   integrated behind the LSU and BIU; a top whose ports are exactly the 603e pins,
   with internal blocks grouped as on the chip; a 603e-timed multiplier; the
   remaining diagnostic halts replaced by manual behavior; the compiled corpus
   compared against DingusPPC; a registered fetch-to-decode stage toward 66 MHz;
   then release packaging and final signoff fits.

Timing targets: 50 MHz is the provisional MVP constraint; 66 MHz, the original
603e's clock, is the aspirational target. Fit records report Fmax against both.

For the full 603e, dual issue, branch prediction, data cache/coherence, floating
point, endian/variant features and timing fidelity remain major workstreams.
Floating point has manual-backed [603e](../../FPU_CONTRACT.md) and
[602](../../FPU_602_CONTRACT.md) contracts and a completed isolated donor
experiment. The donor failed qualification and was removed. The replacement standalone module
selects 603e or 602 at compile time and must match original instruction latency
and throughput. The coherent baseline passes both personalities’ numerical, exact-cycle,
public-shell, paired dispatch/retirement and strict lint gates in
[verification](../../../sim/fpu/PRODUCTION.md), including full-queue admission
and 602 SPR timing. Frequency closure and the documented silicon-semantics
gaps remain open. The latest
603e FPU fit is 15,465 ALMs at 43.17 MHz and the 602 fit 11,893 ALMs at
31.81 MHz ([production record](../../../sim/fpu/PRODUCTION.md)); both miss 50
and 66 MHz. Timing work keeps the Table 6-5 cycle counts exact; any change to
them goes behind a named parameter such as `FPU_IMPL`. See the
[FPU assessment](../../FPU_REUSE_ASSESSMENT.md) for the remaining semantic and
implementation gaps. Integration into the core is in progress behind a
parameter that leaves FPU-less builds unchanged.
Do not infer full CPU completion from the restricted MVP score.

## Work queue

Done (batches 5–6, 2026-09-30): FPU in the core behind `ENABLE_FPU`, with FP
arithmetic pipelined to Table 6-5 ([integration](../../FPU_CORE_INTEGRATION.md));
FPU retiming (603e 51.55 MHz post-fit, exact cycle counts); 603e power modes
(V14); the opcode self-test app ([SELFTEST.md](../../SELFTEST.md)); Whetstone,
soft- and hard-float ([BENCHMARKS.md](../../BENCHMARKS.md#whetstone)); the SoC
and MiSTer FPU option (`mister/build.sh --fpu`, awaiting its first fit); CI
preparation ([CI.md](../../CI.md); workflows drafted, not enabled).

Queued, in order:

1. FP loads and stores at Table 6-6: pipelined, with single 64-bit accesses
   through the LSU, D-cache, BIU and 60x (today they serialize and split
   doublewords into two words). Check the FPU's `fmr`/`fsel`/FPSCR finish
   cycle against Table 6-5 (it finishes one cycle early).
2. 602 FPU timing toward 50 MHz (35.69 MHz post-fit), then the 602 FPU in the
   core (V12).
3. COMPACT FPU (`FPU_IMPL`) for both personalities.
4. 603 with XATS (V5); two-stage LSU (P3); dual dispatch.
5. FPU at 66 MHz: retiming alone is estimated 2–3 ns short per stage; the
   choice between an FPU at 50 MHz and a parameter-gated extra stage is open.
6. Enable CI and measure one MiSTer build on a hosted runner.

After each accepted implementation round, update the scorecard's affected rows
and record fresh versus inherited checks. Refresh this plan when priorities or
acceptance gates change. Superseded progress snapshots, the agent work queue and
implemented slice proposals are retained under [stale plans](../stale/README.md)
as history, not as current instructions.
