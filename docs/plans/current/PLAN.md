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

1. Close remaining page replacement and data/exception behavior, then stress
   event and reset interactions on the translated cached 60x path.
2. Verify cache maintenance, context changes, interrupts and data effects across
   held refills and bus retries. Keep explicit CPU synchronization and external
   maintenance contracts distinct.
3. Fit the combined translated cached top with reviewed interface constraints;
   fix setup and hold violations, then run broader integration and firmware gates
   on the final RTL. The existing fit archives measure earlier configurations.

For the full 603e, dual issue, branch prediction, data cache/coherence, floating
point, endian/variant features and timing fidelity remain major workstreams.
Floating point now has a manual-backed [FPU contract](../../FPU_CONTRACT.md),
including explicit source conflicts, and a completed isolated arithmetic
experiment under the [FPU reuse assessment](../../FPU_REUSE_ASSESSMENT.md).
The SS candidate fails numerical qualification and the pre-fit frequency
target. The standalone 603e shell and replacement arithmetic pass
independent numeric and architectural tests: 200,000 raw packets, 11,958
estimate packets, 851 shell checks and 76 cancellation offsets. It is
serialized, with no core integration or four-entry rename throughput. The
full-unit post-map estimate is 50.5 MHz, meeting the synthesis-only 50 MHz
check; 66 MHz remains unmet. No fitted timing closure is claimed. See the
assessment for resources, selected semantics and remaining silicon questions. A separate process will integrate the FPU
into the CPU. Existing core RTL and file lists remain outside this workstream.
The requested complete 603e/602 module remains open. The
[602 contract](../../FPU_602_CONTRACT.md) now has a pinned primary manual;
the [replacement pipeline](../../FPU_PIPELINE_DESIGN.md) must meet original
instruction latency and throughput in each compile-time build. The
latest arithmetic pipeline map reached 18.2 MHz; rounding/classification
still needs redesign within the fixed cycle count. The earlier serialized suite and
50.5 MHz measurement do not close the new implementation's acceptance gates.
Do not infer full CPU completion from the restricted MVP score.

After each accepted implementation round, update the scorecard's affected rows
and record fresh versus inherited checks. Refresh this plan when priorities or
acceptance gates change. Superseded progress snapshots, the agent work queue and
implemented slice proposals are retained under [stale plans](../stale/README.md)
as history, not as current instructions.
