# Tagged execution foundation (P05)

Current extensions: [DIVIDER_TIMING.md](DIVIDER_TIMING.md) adds 20/37-cycle
DIVW/DIVWU reservation. The [writeback-cycle retirement
extension](DUAL_DISPATCH_DESIGN.md#completion-in-the-writeback-cycle) supersedes
P05's extra finish-to-retirement edge for eligible results at either dispatch
width. The current rules below preserve ordered, ownership-qualified commitment.

Historical scope: the P05 foundation covered 15 instruction forms (the original
seven plus eight non-record register-logical forms). Later contracts extend its
instruction set, producers and retirement timing. This foundation does not claim
full chapter-6 conformance.

## Current finish and retirement edges

Reconciled against `ppc_completion`, its `ppc_core` connections and
`sim/spec/stage_timing.json` on 2026-10-13. This is a source audit, with acceptance
evidence inherited from the writeback-cycle extension; no checks were rerun for
this documentation correction. Its manual anchors are UM §6.3.3 and Figures 6-3
and 6-5, as recorded in that extension.

Let F be the accepted finish edge. All events use pre-edge state plus the
ownership-qualified result inputs; processing order in a checker adds no clock
edge. A retirement offer commits only when the core's retirement gates and the
consumer's ready permit it.

| Case | Earliest retirement and edge ordering |
| --- | --- |
| Ordinary IU, SRU or pipelined LSU clean result | May offer and commit at F when it is the CQ head. CQ[1] may do so only with head commitment and the existing pair restrictions. The CQ merges result values and flag deltas into allocation-owned metadata. |
| Faulting result | Capture the fault and suppress destination effects at F. It becomes eligible from the stored packet at F+1; core exception/recovery gates determine the subsequent architectural action. No fault bypass. |
| Serialized special-lane result on either finish port | Capture at F; offer no earlier than F+1. `result_retire_i` / `result1_retire_i` exclude this source, and its commit control uses `retire_settled_o`. |
| FP instruction | Its CQ entry allocates finished, but that does not authorize commitment. The core gates retirement on the matching FPU head/result and replay/exception state; the FPU timing contract controls its finish/commit relation. |
| Accepted recovery and coincident result | Classify the retained prefix from pre-edge identities first. A killed result may drain but cannot finish, wake or bypass. A surviving eligible clean result may finish and commit at F if it reaches the head and retirement is allowed. Rename reconstruction excludes entries committed on that edge. |
| Retirement backpressure | A bypassed clean result is stored at F if it cannot commit. Its offered packet stays stable until accepted; younger finishes cannot replace it. |
| Allocation and release | Commitment releases CQ/rename ownership at the edge; capacity checks use pre-edge occupancy. A full resource cannot be reclaimed and reallocated on that same edge. |

For the seven-form single-cycle IU probe, E ≥ D+1 and F = E+1. An unstalled
head may therefore commit at D+2. The earlier P05 minimum D+3 is historical.
These edge rules do not shorten multiply/divide or FULL FPU execution latency.
COMPACT FPU latency remains a separate named implementation tradeoff.

## Scope and event ordering

Keep the public core fetch/retirement interfaces, five rename slots, five completion entries, six IQ entries and width-one mode. Replace the combinational dispatch-to-completion path with:

1. Atomic dispatch allocates an **unfinished** completion entry and an unready GPR rename slot, and captures the operation plus source operands in a one-entry IU reservation station.
2. A ready reservation station issues to a registered IU input stage. Unready sources hold producer identities and can wake from an accepted result. A source whose producer will occupy the IU is marked at capture and takes that IU result as it is accepted, so a dependent op issues in its producer's result cycle; any other wake is captured and issues one cycle later. Backpressure preserves both operation and operands.
3. The IU computes from held inputs during the following cycle. Its tagged result remains valid and stable until consumed. It can accept a replacement operation at the edge consuming the previous result.
4. Completion validates result ownership, stores the result and marks the entry finished. Only an accepted result updates rename storage or wakes operands.
5. Only a finished head entry, including an eligible clean result finishing on that edge, can retire. Retirement updates architectural GPR state and releases its rename slot. A younger result finishing first cannot make architectural progress past an unfinished head.

Define dispatch acceptance at edge D and IU issue acceptance at edge E. Result
transport (`result_fire = valid && ready`) consumes every response, including
rejected identities. Only ownership-valid `finish_accept` changes
CQ/rename/wakeup state. An unstalled single-cycle IU finish is accepted at E+1
and may retire on that edge under the table above. A ready instruction can issue
at D+1. P05 originally required earliest commitment at E+2; that extra edge was
superseded by the writeback-cycle extension. Full timing-schedule acceptance
remains separate.

## Identity and ownership

Use distinct types for rename slot indices and completion identities. A completion identity contains a bounded slot index plus a per-slot generation incremented on allocation. Invalid indices, inactive entries, mismatched generations, duplicate finishes, and finishes targeting an already-finished diagnostic fault do not change state.

A rename entry holds `valid`, `ready`, `value`, and its owning completion identity. A pending operand retains both its rename slot and producer identity. A result wakeup must match both. The completion queue selects the destination rename slot from its allocated metadata; an execution unit cannot choose an arbitrary architectural destination on finish.

Generations are a stale-result check, **not an unbounded uniqueness guarantee**. Legal producers generate one final result per issue and cancel/reset their state with the core. A finite counter cannot distinguish arbitrarily old illegally replayed data after wrap. P06 provides current local-producer cancellation and fetch drain; external/long-lived producers still require explicit lifetime tracking before connection; widening a counter alone is not that protocol. Reset clears all internal producers and consumers together; the existing external fetch reset-cancellation contract remains in force. The completion queue and special lane reset synchronously and do not gate their handshake outputs with `rst_ni`: from the first reset edge their valid outputs are low, ready outputs may be high, and any handshake offered while reset is held has no effect (`tb_completion` checks this). Recorded: `make -C sim test-completion test-completion-flags test-completion-cr-bits test-completion-cr-fields`, commit this branch, 2026-09-26. Pass: 907, 189, 4,016 and 3,244 checks.

## Atomicity, forwarding and simultaneous events

- Dispatch requires IQ validity, CQ space, free rename slot and reservation-station space. Pop/allocate/capture all happen together or none happen. Unsupported instructions allocate only a finished diagnostic CQ entry and stop younger dispatch; older execution still drains.
- Read operands before the same edge's destination-map update, including `addi r3,r3,...`; a destination never becomes its own source. Reads use the pre-edge map and rename values, including a writer retiring at that edge; a future post-clear map implementation would require commit-to-GPR bypass. Literal-zero rA and immediate operands are explicitly ready.
- The latest-writer map points to an active rename slot. Old-writer retirement clears it only if it still names that writer. Younger allocation to the same GPR wins over that clear.
- A finish accepted in the same cycle as source capture or issue is eligible for bypass. This avoids missing a one-cycle wakeup and permits dependent issue without an extra register-read bubble.
- Full CQ/rename resources reclaim capacity on the next cycle after release. Do not allocate and release the same slot at one edge. This conservative capacity behavior is unchanged until the two-wide scheduling work.
- The reservation station may issue its old instruction and accept a new dispatch at the same edge. New capture wins over clearing/waking the old contents.
- Completion consumes and drops invalid result identities so a stale response cannot deadlock the transport; only its separate accepted-finish indication authorizes side effects.
- Eligible clean results use the ownership-qualified finish-to-retirement bypass described above. A stalled retirement packet cannot be changed by younger finishes.

## Boundaries for following tasks

P06 owns age-aware redirect/flush, recovery of rename mappings, and long-lived result cancellation. The [CR/XER state foundation](FLAGS_STATE.md) extends the one-GPR result packet with allocation-controlled flag deltas and a shared commit event; record-logical forms use that path with captured SO and CR0-only write permission. Multi-destination load-update, FPR results and multiple execution producers still require explicit result-lane extensions. P11 widens resource allocation and retirement together. Unknown instructions retain diagnostic halt until P14 architectural exceptions.

A one-entry reservation station is a documented initial implementation choice. The manual's existence of reservation stations does not by itself establish every storage-depth/admission detail. The IU-only core cannot naturally demonstrate out-of-order finish; a direct completion-unit test must exercise this infrastructure before other units are integrated.

## Acceptance tests

1. Preserve the existing 768-result trace regression with stalls, reset and diagnostic faults.
2. Completion: fill five entries, finish younger entries first, stall the head and retirement consumer, then verify exact program order and value stability. Repeatedly wrap the ring allocation pointer and test old-generation, invalid-index and duplicate finishes without state mutation. Stale injections must differ from the active generation; full generation-counter wrap requires proof that no old producer token remains live, not a claim of unlimited replay rejection.
3. Rename/issue: capture a pending RAW source, prove it waits, then wake on the matching accepted producer. Wrong identity must not wake it. Exercise multiple writers, same-cycle finish/read, retirement plus younger allocation, and slot pressure.
4. IU: issue/result edge distance, stable result under backpressure, consecutive accepted operations, and reset during an outstanding operation.
5. Diagnostic fault behind unfinished work: older results commit, the fault has no GPR side effect, younger instructions never issue.
6. Strict lint on canonical RTL and all focused benches. Existing Quartus reports remain historical until a new measured build is requested; their source hashes must not be mistaken for the changed RTL.

## Operand mux review, 2026-10-13

Recorded: `make -C sim -j1 test-execution test-recovery-execution test-core-alignment-dependencies test-core-branch-recovery test-core-branch-fold lint check-spec`, commit b9f52ae8ef3b52159c341c7aa2ecaa565074da76 plus uncommitted changes, 2026-10-13.

The operand data mux uses parallel, disjoint masks with the existing IU, LSU,
forward, captured priority. Readiness, exact producer identity, completion
qualification and sequential capture are unchanged. An inactive LSU or forwarding
source can retain a matching old token, so tag equality alone cannot select it.
This structural change makes no issue-latency or frequency claim.

Fresh checks passed: 64 forwarding combinations (both operands, current/stale
generations, inactive sources and overlapping completions), IU bypass precedence,
1,066 recovery cancellation checks, 738 alignment-dependency checks across seven
variants, branch recovery/folding programs, strict lint and 281 Python checks.
The command ran with `OBJCACHE=` and under `/tmp/ppc603e-sim.lock`. These checks
do not establish full CPU conformance or FPGA timing closure.

Recorded: `make -C sim -j1 test-core-dual`, commit b9f52ae8ef3b52159c341c7aa2ecaa565074da76 plus uncommitted changes, 2026-10-13.

Pass at widths 1 and 2: 74 retirements in 239 and 224 cycles, respectively;
width 2 dispatches 21 pairs and retires 14 pairs. The two trace files compare
identically (65 packets). This checks the focused program, not full dual-issue
conformance.
