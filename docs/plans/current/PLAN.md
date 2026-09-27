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
3. Fit the combined translated cached top with reviewed interface constraints
   (including reset arrival);
   fix setup and hold violations, then run broader integration and firmware gates
   on the final RTL. The existing fit archives measure earlier configurations.

Timing targets: 50 MHz is the provisional MVP constraint; 66 MHz, the original
603e's clock, is the aspirational target. Fit records report Fmax against both.

For the full 603e, dual issue, branch prediction, data cache/coherence, floating
point, endian/variant features and timing fidelity remain major workstreams.
Floating point has an investigation and phased plan in the
[FPU reuse assessment](../../FPU_REUSE_ASSESSMENT.md); its first steps are an FPU
contract and an isolated arithmetic-backend experiment.
Do not infer full CPU completion from the restricted MVP score.

After each accepted implementation round, update the scorecard's affected rows
and record fresh versus inherited checks. Refresh this plan when priorities or
acceptance gates change. Superseded progress snapshots, the agent work queue and
implemented slice proposals are retained under [stale plans](../stale/README.md)
as history, not as current instructions.
