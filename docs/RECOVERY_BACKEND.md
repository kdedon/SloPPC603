# Sequential recovery backend

This is P06b1 work for the existing single-issue, single-GPR CPU foundation. This document describes P06b1 backend behavior. P06b2 now connects [full-core recovery](CORE_RECOVERY.md), including fetch drain, IQ clearing and diagnostic-stop cleanup. Branch decoding remains absent.

The completion queue classifies a redirect against its pre-edge ordered entries. It rejects inactive/stale pivots and any cut that kills a finished head, applies accepted cuts before finish qualification, permits a surviving old finished head to retire and preserves generation counters. Rejected requests permit ordinary progress. Result transport acceptance remains separate from a valid producer finish.

Two outputs serve different consumers. The kill mask and per-slot generations identify pre-edge producers for cancellation. The oldest-first survivor packets and identities exclude any head retiring on the edge and let rename rebuild the latest-writer map. A recovering rename preserves only matching live ownership, readiness and values, then retains any qualified same-edge wake. Survivor presence alone does not make an unfinished register ready.

Local cancellation is a scalar input to each execution holder, derived by its caller from the accepted kill identity. The station suppresses a killed issue and clears occupancy even when a matching operand wake arrives. It cannot capture a new dispatch on that cancellation edge. The IU suppresses its killed result and destroys the held token despite downstream stalls; it can accept a separately qualified surviving replacement. The replacement capability is tested at the unit level and is not presented as a legal younger-survivor prefix scenario in the current in-order execution path.

Cancellation must not depend on issue/result valid signals that cancellation itself masks. The core instead compares the exposed held identities against the accepted kill mask and generations. Stale packet contents in an empty holder are harmless. A future enabled redirect path must block dispatch for accepted recovery and qualify every incoming issue by survival.

The CQ has no independent issued-token directory. Its direct response port relies on the producer contract: only previously issued live work produces a final response, and local cancellation atomically destroys killed work. The registered IU enforces a separate issue edge before a result can finish. Before external or uncancellable result producers are connected, the collision/drain policy in [RECOVERY_CONTRACT.md](RECOVERY_CONTRACT.md) is mandatory.

## Verification

`make -C sim test-recovery-execution` passes 1,066 checks with strict Verilator warnings. It covers pending wake/cancel, ready-station cancellation, stalled-result cancellation, replacement capability, reset and 260 legal local cancellation cycles across eight-bit generation wrap. This is local-token evidence, not an arbitrary stale-replay guarantee after identity reuse.

`make -C sim test-recovery-state` passes 5,871 sequential CQ/rename checks after independent review, including same-edge events, pending/ready WAW survivors, full wrapped queues, irrevocable offers and generation reuse. Full no-redirect regressions also pass; see [VERIFICATION.md](VERIFICATION.md). The pure selector's 245,760 snapshot checks and Python policy model remain separate evidence. None alone establishes whole-core recovery.

P06b2 now implements a coordinated redirect path with held-request drain, newest-target replacement, IQ clearing, surviving diagnostic tracking and terminal-halt policy. Its compiled core bench compares against an independent surviving instruction stream and preserves the existing no-redirect stage timings.
