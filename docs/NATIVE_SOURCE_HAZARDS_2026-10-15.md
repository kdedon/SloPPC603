# Native source-use overlap trial

Prepared against `d60f21d`, 2026-10-15. This is an unaccepted optimization
checkpoint. No frequency or aggregate acceptance claim follows from it.

Only `overlap_dispatch_ok` changes in the core: compare the native load's
destination against canonical dispatch sources only when the operation reads
them. Literal-zero A, immediate B and resolved branches do not consume the
corresponding GPR. Actual r0, old-destination RLWIMI and ADD sources retain
their hazards. All status, recovery, FP and native-lane permission gates remain.
No stage, execution latency, architectural port or storage change is proposed.

The new symbolic program checks complete GPR/CR/XER/LR/CTR and byte-memory
state at each retirement. New positive instructions are delivered after the
matching public load acceptance; mandatory observation still requires a real
pending read with delayed response and native destination ownership. The
two-word responder requests an upper-word positive separately to create that
window. Existing waiting-branch poison guards remain unchanged. An ordinary
new B instead skips an observable r8 write: its fallthrough can already be
prefetched before branch decode, but must never retire or alter state.

Recorded: `OBJCACHE= make -C sim -j1 lint check-spec`, commit `d60f21d`
plus this candidate, 2026-10-15. Pass: strict lint and spec checks, including
259 tool tests and 29 bus-checker tests. This precedes test-stimulus repairs;
the RTL expression is unchanged afterward.

Recorded: `OBJCACHE= make -C sim -j1 test-core-false-hazards`, same baseline
plus candidate and repaired stimulus, same date. One-word fetch passes:
66,719 checks, 847 retirements, 79 reads, 70 writes, 254 request stalls,
375 retirement stalls, 6,725 cycles. All three positive kinds have eight
actual pending-load dispatches each; all three real-dependency kinds have
192 pending cycles with dispatch blocked. Fourteen speculative branches,
eight mispredictions and eight early recoveries occur.

Two-word fetch fails the existing `ppc_fetch` stop-discard assertion at
edge1844 in the inherited program prefix. Compiling the exact same testbench
with the original `d60f21d` core reproduces the same edge/assertion, so this
failure predates the hazard change under the longer data-response latency.
The trace shows an early redirected request accepted at edge1842, followed
by its correct-path response at edge1843 while a wrong-path pending fault is
simultaneously killed. Fetch drops that response under the stale fault stop,
then resumes without another redirect. Keep the assertion enabled and resolve
the owner-lifetime issue before accepting this trial.

Fault/cancellation, LR/CTR/removal, retained CTR, original manual-relative
gates, fresh Quartus17 analysis and a matched fit remain pending. Optional
targets are in `sim/tools/false_hazards.mk`; default regression dependencies
are unchanged during this checkpoint. Full batch/reference acceptance remains
open. The accepted timing baseline remains 40.99MHz.
