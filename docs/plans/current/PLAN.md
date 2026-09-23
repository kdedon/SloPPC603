# Current CPU plan

Updated: 2026-09-23. This is the active planning entry point. The target for
the next deliverable is a single-issue, big-endian integer CPU with supervisor
mode, resumable exceptions, interrupts and software-managed MMU. The full 603e
CPU remains the longer-term target.

The [system completion scorecard](../../SYSTEM_COMPLETION.md) is the authority
for current percentages, accepted behavior, gaps and the MVP effort range. The
[full CPU weighting audit](../../FULL_CPU_COMPLETION_AUDIT.md) tracks the wider
processor scope. [CPU references](../../references/README.md) collect the
distilled source contracts.

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
Do not infer full CPU completion from the restricted MVP score.

After each accepted implementation round, update the scorecard's affected rows
and record fresh versus inherited checks. Refresh this plan when priorities or
acceptance gates change. The old wave plans and work queue are retained under
[stale plans](../stale/README.md) as history, not as current instructions.
