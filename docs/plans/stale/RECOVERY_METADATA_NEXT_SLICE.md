# Retained rename slot identities across recovery

The bounded implementation keeps each rename slot's `owners` completion
identity unchanged on recovery and release. It writes `owners[slot]` only on reset
(to zero) or an accepted allocation (to the newly allocated producer). It preserves
all existing valid/ready updates, survivor membership checks, wake handling and
oldest-to-youngest architectural map reconstruction. This change is implemented and functionally checked; no new FPGA fit or
timing-improvement claim accompanies it.

## Why identity retention is justified

In `ppc_rename`, a recovery survivor already must have a valid rename slot whose
owner exactly equals the CQ survivor index and generation. The previous loop
then wrote that same identity back after clearing every owner. Recovery does
not allocate or transfer a slot to a different producer: allocation is prohibited
and `alloc_ready_o` is withdrawn. Therefore surviving ownership bits need no
reconstruction. Killed slots can retain stale bits because their valid bit and
architectural mappings are cleared; wake and release match require validity
as well as exact identity. Reads consult ownership only through a valid GPR map.

Allocation overwrites a free slot's owner before its new validity is visible.
A simultaneous stale wake sees pre-edge validity, so it cannot wake a newly
allocated free slot. A later stale result must still fail the generation check.
This preserves the existing finite-generation/cancellation contract; it does
not make arbitrarily delayed tokens safe after complete identity wrap.

Completion supplies survivors in pre-edge age order **excluding a same-edge
retiring head**. On recovery, rename must still invalidate that retired slot,
even though its ordinary release branch is bypassed. A surviving same-edge
finish retains the same producer identity and sets readiness through the
existing exact-owner wake path; a killed finish is suppressed by completion.
Retaining owner bits changes none of these membership or readiness decisions.
Fault completion can remove write permission without releasing a rename slot
through normal GPR commit; do not assert an unconditional valid-slot/current
CQ-writer bijection that the existing diagnostic policy does not guarantee.

Update-form base writes use the separate committed GPR update port, not an
additional rename slot. Load-update destination ownership follows `gpr_write`;
store-update has no rename destination. Existing serialized memory dispatch
prevents a pending younger owner for the update base. Keep current decode
alias restrictions, old-base EA behavior and dual architectural writes intact.
The implementation does not interpret `update_write` as a second survivor owner or
skip map rebuilding when several surviving instructions target the same GPR.

## Implemented scope and verification obligations

- Split only the `owners` storage into reset/accepted-allocation updates; remove
  recovery owner clearing and identical survivor rewrites. Preserve reset zeros.
- Retain the existing assertion that recovery prohibits allocation and that
  every retained GPR-writing survivor has exact valid pre-edge ownership.
- Assert unique live rename-slot identities among supplied writer survivors,
  accepted allocation selects a pre-edge free slot, and a surviving slot's
  owner remains unchanged absent reset/allocation.
- Assert every valid architectural mapping points to a valid rename slot, with
  the youngest retained writer selected after recovery. Preserve current map
  and readiness logic; these cannot simply be held like ownership payload.
- Check release of a retiring head and restoration of another writer to the
  same GPR on the same recovery edge. Check update-base aliases using public
  architectural values and memory requests, not internal owner expectations.

Independent tests should cover wrapped/full CQ cuts, all keep/drop positions,
multiple same-GPR writers, pending and completed survivors, coincident survivor
wake/retirement, killed wake, stale release, free-slot reuse with an old token,
generation wrap under the established cancellation policy, and reset. Include
faulting completion/recovery and load/store-update predecessors. Existing
recovery-state, recovery-storage, completion-ring and memory/update suites are
useful foundations; retain their public expected streams and add cases only
where those combinations are missing.

## Timing boundary

The enabled timer/BAT fit's worst setup trace runs from completion `done_q[2]`
through branch commit, retained-prefix/survivor selection and rename rebuilding
to `owners[0].generation[7]`. This motivates removing redundant recovery writes,
but allocation enables still depend on dispatch and recovery gating. Other
reported endpoints include readiness. The change may move or preserve a timing
bottleneck and requires fresh frozen-source synthesis/fit after functional
verification. It does not address the external BAT-programming input hold
violation. All existing timing archives and constraints remain unchanged.

## Limited-round verification

The owner-write process now contains only reset and accepted allocation.
Simulation-only assertions check stability without allocation, free allocation
without recovery, valid maps targeting valid slots, and distinct writer-survivor
slots. The original exact-owner survivor assertion remains. Local recovery-state
(5,871 checks), recovery-storage (18 checks before the independent extension)
and execution ownership/pressure suites pass. Independent focused validation
passed the expanded storage test (23 checks), recovery state (5,871), execution
(1,066), completion ring (16,480), memory edges (799), LSU update (106,065),
alignment profiles (3,697/2,651) and dependencies (634), and fetch suites
(10,923/2,889), plus 24 strict lint targets and 241 Python tests. The 142-file
source manifest remained stable. See [RECOVERY_METADATA_VERIFICATION.md](../../RECOVERY_METADATA_VERIFICATION.md)
for commands, logs and coverage boundaries. All six compiled firmware profiles
were also rebuilt and passed by the integration owner.

The existing timer/BAT and cached physical timing archives precede this owner
change. They remain valid historical evidence of their recorded source hashes,
but do not establish area or timing for this revision. No new fit was run in
this bounded round, and no change to constraints or physical assumptions was
made.
