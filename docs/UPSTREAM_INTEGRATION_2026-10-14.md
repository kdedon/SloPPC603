# Upstream integration, 2026-10-14

The validated local timing checkpoint is merge `9a68a26`, containing
`f2da169` (CPU/tests), `9c13500` (build/benchmarks), and `f7c2621` (skills).
Its CPU-only limiting-corner result is 40.66 MHz; full release gates remain
pending. Local work had incorrectly started before synchronizing remote main.

Integration branch: `codex/integrate-upstream-20261014`. Remote main was
freshly fetched at `e5cddb9`; nine previously missing commits are integrated.
They include response-payload pre-read, fixed-head kill, explicit GPR read-copy
instances and registered-address block-RAM inference, and demo reset changes.
No new clock, stage, manual cycle, architectural instruction or exception
policy is intended. Preserve all local owner-wrap and exception checks.

Conflict ownership: core frontend/dispatch, completion/recovery, I-cache and
router payload selection are reviewed independently. The router retains the
local separate reset-independent payload block, which already implements
upstream's intent and preserves refetch priority and procedural unknown-control
behavior. Data-page projection and held-OFFER snapshots remain unchanged.

The five eligible GPR read ports request block RAM; their existing registered
addresses must be absorbed without shifting externally visible latency.
Write-through behavior and actual fitted memory tiers must be checked rather
than inferred from source attributes.

Validation order: strict lint/specification, focused GPR/core fetch/recovery/
completion/cache/owner-wrap and verified-cycle gates; then one serial capped
matched CPU-only Quartus fit. Full CI, X-randomization and FPU/reference gates
remain required for release acceptance. No additional timing experiment is
stacked onto this integration. All physical results for the combined source
are pending; the saved checkpoint remains the comparison baseline.
