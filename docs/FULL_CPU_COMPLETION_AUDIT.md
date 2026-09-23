# Full CPU weighting audit

Date: 2026-09-23. Scope: the original CPU-only 603e project through P30 in
[TASK_PLAN.md](plans/stale/TASK_PLAN.md), including superscalar execution, floating point,
caches/coherence, modes, timing fidelity and FPGA delivery; board integration excluded.

**Revised estimate: about 46% complete (weighted 46.29%; judgment range 40–50%).**
This replaces the provisional 40–45% headline. It is completed project scope,
including documentation and tooling, not measured RTL coverage or a fraction of
remaining effort. The range is not a statistical confidence interval.

This is a bounded document/evidence audit of the current
[SYSTEM_COMPLETION.md](SYSTEM_COMPLETION.md), original task scope and historical
[PROGRESS.md](plans/stale/PROGRESS.md) weighting. No RTL review, tests or synthesis were rerun.
Evidence and limitations are inherited from the accepted feature contracts and
scorecard. A full independent implementation/conformance audit remains open.

## Weighting

The original eleven category weights remain unchanged: scope has not changed.
Three broad categories are decomposed below so absent hardware receives explicit
zero credit. These internal allocations are new engineering judgments, not
historically measured effort. Keep them fixed for subsequent updates.

| Workstream | Weight | Completion | Contribution |
| --- | ---: | ---: | ---: |
| Source contracts and ISA planning | 8% | 68% | 5.44% |
| Reproducible tools and scaffold | 4% | 90% | 3.60% |
| Scalar tagged execution, recovery and integer units | 8% | 85% | 6.80% |
| Dual dispatch/retirement and superscalar scheduling | 4% | 0% | 0.00% |
| Functional branches | 3% | 90% | 2.70% |
| Branch prediction and folding | 2% | 0% | 0.00% |
| Load/store architecture | 5% | 65% | 3.25% |
| Supervisor, system instructions and interrupts | 8% | 70% | 5.60% |
| MMU | 8% | 80% | 6.40% |
| 60x transport and protocol | 6% | 65% | 3.90% |
| Instruction cache and architectural maintenance | 4% | 80% | 3.20% |
| Data cache and writeback | 5% | 0% | 0.00% |
| Coherence and reservations | 3% | 0% | 0.00% |
| Floating point | 12% | 0% | 0.00% |
| Endian, variants and platform behavior | 6% | 0% | 0.00% |
| Full timing, reference and integration verification | 10% | 50% | 5.00% |
| Final FPGA closure and release | 4% | 10% | 0.40% |
| **Total** | **100%** | | **46.29%** |

## Reasons for the revised credit

- **Execution:** the old 12%-weight category combined integer/recovery and dual
  issue but scored 87%. Split it into 8% scalar machinery at 85% and 4% dual issue
  at zero. Its contribution falls from 10.44 to 6.80 points. This corrects prior
  over-credit; it does not represent a hardware regression. Scalar timing and
  finite recovery-token contracts still limit acceptance.
- **Branches/LSU:** preserve the combined 10% weight, allocating 3% to functional
  branches, 2% to prediction/folding and 5% to LSU. Branch semantics work, but
  prediction/folding do not. LSU credit is below the restricted MVP score because
  complete memory forms, split accesses and pipeline behavior remain open.
  Reservations are counted under coherence, not credited twice here.
- **Supervisor:** 70% recognizes live state, supported precise exceptions,
  interrupts and timers. Missing exception/debug coverage, full system operations
  and supported-state restrictions prevent using the higher restricted-MVP score.
- **MMU:** 80% recognizes CPU-owned BAT/SR/TLB state, real software table search,
  R/C updates and fault/retry on the combined cached bus path. Replacement policy,
  remaining attributes, edge cases and full conformance remain open.
- **Bus/cache/coherence:** preserve 18% as bus 6%, instruction cache 4%, data cache
  5%, coherence/reservations 3%. Bus receives 65% for the bounded scalar/burst
  implementation; full tenure, snoop, parity and error semantics are incomplete.
  Instruction cache receives 80% for translated physical operation, with
  architectural maintenance and remaining behavior open. Data cache and coherence
  receive zero. This category contributes 7.10 points, not an MVP cache percentage
  applied to the entire memory system.
- **Verification:** 50% recognizes the broad scalar regression, reference checks
  and compiled translated-cache firmware. Full-machine reference, timing/protocol
  fidelity, absent subsystems and broader integration stress are still open.
  Component tests support their feature credit; this row covers cross-system
  acceptance infrastructure and evidence, not another count of instructions.
- **FPGA/release:** 10% gives limited credit for representative fit archives.
  There is no combined final-top fit, passing setup/hold or release acceptance.
  Tool installation and early build setup belong to the separate tools row.
- **Source/tools:** retain 68%/90% without claiming a fresh source reconciliation.
  Their combined 9.04 points are project-delivery credit, not executable hardware.
  Floating point and the remaining mode/platform work stay at zero; existing
  bounded reset tests do not establish complete platform behavior.

## Reconciliation and next updates

Historical round-40 total: **39.40%**. Current audited total: **46.29%** (+6.89
points), combining real later capability with a downward correction to the old
execution estimate. The difference is not a clean development-velocity measure.
The MVP remains **80.81%** under its separate, unchanged scope and weighting.

The unimplemented dual-issue, prediction, data-cache, coherence, floating-point
and mode/platform rows collectively carry **32% of full project weight**.
Even finishing the restricted MVP will not finish those systems. Broader
conformance and final timing add further remaining work within nonzero rows.

No full-CPU delivery date is inferred from this percentage. Existing 6–10 / 8–14
engineer-week estimates apply only to restricted MVP simulation / timing-checked
FPGA acceptance. Update this table after accepted architectural milestones;
verification-only rounds need not move its score. Revisit internal allocations
only with an explicit rationale, preserving the historical table.
