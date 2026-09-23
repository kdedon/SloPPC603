# Bounded retirement/recovery timing changes

The latest committed-EA revision reports **-5.324 ns setup and -0.084 ns
hold** under the unchanged provisional 20 ns constraints. Both deficits
improve from the preceding revision, but timing closure remains unmet.
See the [current baseline](INTEGRATED_SYNTHESIS_BASELINE.md) for complete
results and measurement boundaries.

## Earlier payload/FIFO control-cut iteration

The first control-cut iteration targets the measured path from completion head selection through
retirement, recovery, instruction decode and dispatch into rename storage.
The earlier accepted fit and its constraints remain archived under
`quartus/integrated/accepted-20260921`; that build failed the provisional 20 ns
setup constraint. That source-stable full fit is archived separately under
`quartus/integrated/timing-20260921`. Worst setup improves from -12.576 ns to
-8.347 ns, while all-corner hold passed (minimum +0.097 ns). 50 MHz setup
closure remains outstanding; the concurrent typed fetch-fault addition means
this comparison cannot isolate each change's contribution.

## Structural changes

Rename payload registers now update only at reset or on an exact-owner wake.
Allocation and recovery continue to update valid, ready, owner and architectural
mapping metadata, but no longer clear or reconstruct payload bits. Surviving
owners retain their value naturally; a same-edge wake supplies their completed
value. Killed or released slots may retain stale physical bits, which cannot
be consumed through the invalid mapping. Allocation clears readiness, and the
operand interface explicitly returns zero while pending, preserving the old
observable pending value and the existing same-edge wake bypass.

The instruction FIFO no longer gates its data mux with clear. Reset and empty
still produce zero. During clear, valid and ready are withdrawn immediately,
so the old head is not an accepted transfer; the clear edge empties the queue.
This removes recovery-to-decode data selection from the path without changing
any accepted push/pop, cancellation, or dispatch event.

These edits add no pipeline stages and do not change retirement order, recovery
prefix selection, generation checking, or external reset/timing assumptions.
No false-path or multicycle exceptions were added.

## Verification and measurement

Existing completion (906 checks), recovery-state (5,871 checks) and execution
ownership/pressure suites passed after the rename change. The dedicated
recovery-storage test passed 18 checks covering surviving
exact-owner wake with recovery, killed wake and slot reuse, pending zero, stale
owner rejection, and FIFO clear during simultaneous push/pop. Fetch recovery
passed 288 checks including held fault causes and response/redirect/reset
coincidences. Joint-source integrated compilation and report checks completed
successfully,
with identical before/after source hashes. See
[the current baseline](INTEGRATED_SYNTHESIS_BASELINE.md) for all corners,
remaining critical-path endpoints, fitted resources and provisional-constraint
limitations. The concurrently added typed fetch-fault packet field is
preserved by completion's full allocation packet copy and held unchanged by
result completion and recovery survivor selection.

## Bounded ring arithmetic follow-up (measured)

The next revision replaces all four completion modulo expressions with a
widened sum and single conditional subtraction. With CQ_DEPTH=5, reachable
head indices are 0..4 and age/retained offsets are 0..5, so their sum is at
most 9. The retained count is explicitly count-width sized. Synthesis-off
assertions check head/tail indices and occupancy every active clock edge.
Retirement, kill acceptance, generation checks and held-head semantics are
unchanged; no new clock, constraint exception or pipeline stage is introduced.

The dedicated `tb_completion_ring` uses an independent modulo-based oracle.
It passes 16,480 checks across 600 recovery scenarios and all 30 reachable
head/offset combinations: every head, occupancy, pivot, keep/drop choice,
finished/unfinished head and retirement readiness, including full wrapped
rings and coincident finish/retirement. The subsequent frozen-source joint fit is preserved in
`quartus/integrated/ring-20260921`. It reports -6.098 ns worst setup and
-1.400 ns worst hold: setup deficit falls by 2.249 ns, while hold regresses.
The arithmetic change therefore does not establish closure or an unqualified
improvement. Compilation and read-only path query both succeeded, all source
hashes match, and no constraints changed. The remaining setup path runs from
completion count through retirement/redirect/wake/dispatch into rename
map-valid. The hold violation is external reset through decode into a special
unit register, requiring review of physical reset/clock arrival assumptions.
Live context remains disabled in this FPGA top; the compiled live BAT test
is separate simulation evidence.

## Committed-EA alignment cut (measured)

The remaining wake/operand-to-dispatch dependency includes alignment
classification. Under the current serialized LSU policy, its low EA bits now
use committed `arch_a`/`arch_b` rather than wake-bypassed rename
values. Both ordinary memory operations and transformed alignment events
require registered CQ count zero and idle execution before dispatch. A sole
head retiring on the current edge still has pre-edge count one, so it cannot
admit a memory operation on that edge. Previous-edge retirement has already
updated GPRs and cleared its rename mapping. Accepted recovery suppresses
allocation; a subsequent empty queue has no surviving rename owner.

The implementation preserves literal zero for nonupdate RA=0, immediate low
bits for D forms, the old committed base for update forms, and original decode
priority. Synthesis-off assertions at accepted original legal memory dispatch require
the CQ to be empty, no retirement/recovery to be simultaneous, and forwarded
and committed effective low bits to agree. Dedicated verification covers a
producer retiring immediately before D/X/update misalignment, an update
predecessor changing the base, recovery, nonzero GPR0 with zero-RA addressing,
and aliased base/index registers. `tb_core_alignment_dependencies` passes
634 checks across seven public-port scenarios, including a canceled fault
response coincident with an accepted external recovery. Existing alignment
profiles pass 3,697 enabled and 2,651 disabled checks; memory-edge recovery
passes 799 checks; the update program passes 106,065 checks/1,370 retirements.

This substitution ceases to be justified if the core later permits memory
dispatch alongside last-head retirement or introduces a nonserialized LSU
without explicit commit forwarding. The completed joint fit is archived in `quartus/integrated/alignment-20260921`
with stable production hashes, successful compilation/query and a verified
bundled-file manifest. Worst setup changes from -6.098 to -5.324 ns, and hold
from -1.400 to -0.084 ns; both still fail. The reported worst setup now ends
at special `ea_q[30]` through the full-width forwarded EA adder, without the
prior dispatch alignment/`iq_ready` chain. That remaining execution operand
path is the next bounded review candidate, not an implemented extension.
It requires its own proof of CQ-empty/idle execution, no simultaneous retirement
or accepted recovery, and full-width committed/forwarded operand equality at
accepted memory dispatch, including update and aliased source forms. This is
not permission to modify the frozen implementation or assume the low-bit
proof automatically covers full execution operands.
Live context and external interrupts remain disabled in the measured cached
physical top; their passing BAT/firmware tests are separate evidence. The
reset-input hold failure still requires its own timing-contract review.

## Reset/clock measurement boundary review

The current QSF marks both clock and reset virtual. Its SDC gives every
nonclock input zero min/max delay relative to the 20 ns clock. The Quartus
README describes active-low synchronous reset, while SOURCES.md D07/D104
leave the physical clock ratio and device AC/reset contract unresolved. No
board oscillator/pin mapping, reset source, or external reset arrival window
is specified by this measurement project. The observed reset-to-data hold
violation must remain reported under those assumptions.

A defensible follow-up is a separately named board or fixture top with an
explicit clock source and a registered synchronous reset launch/conditioner.
It must document reset assertion/release latency and timing at the fixture
boundary, and retain setup/hold coverage for that boundary. Its result would
measure that new integration contract, not retroactively close the existing
externally driven reset interface. A board-specific implementation needs the
actual clock/reset source and arrival constraints first. No reset behavior,
false path, min delay or clock constraint was changed in this wave.
