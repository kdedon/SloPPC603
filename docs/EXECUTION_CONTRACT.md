# Tagged execution foundation (P05)

Current extension: [DIVIDER_TIMING.md](DIVIDER_TIMING.md) adds 20/37-cycle DIVW/DIVWU reservation. The single-cycle relations below continue to apply to the original instruction subset and its stage probe; they do not describe divide finish timing.

Status: implemented foundation for the current 15 instruction forms (the original seven plus eight non-record register-logical forms). P02a provides the reviewed queue/resource and integer timing anchors; P03a checks the existing decode subset. Comprehensive ISA coverage and unresolved figure semantics remain separate gates. This implementation does not claim full chapter-6 conformance.

## Scope and event ordering

Keep the public core fetch/retirement interfaces, five rename slots, five completion entries, six IQ entries and width-one mode. Replace the combinational dispatch-to-completion path with:

1. Atomic dispatch allocates an **unfinished** completion entry and an unready GPR rename slot, and captures the operation plus source operands in a one-entry IU reservation station.
2. A ready reservation station issues to a registered IU input stage. Unready sources hold producer identities and can wake from an accepted result. Backpressure preserves both operation and operands.
3. The IU computes from held inputs during the following cycle. Its tagged result remains valid and stable until consumed. It can accept a replacement operation at the edge consuming the previous result.
4. Completion validates result ownership, stores the result and marks the entry finished. Only an accepted result updates rename storage or wakes operands.
5. Only a finished head entry can retire. Retirement updates architectural GPR state and releases its rename slot. A younger result finishing first cannot make architectural progress past an unfinished head.

Define dispatch acceptance at edge D and IU issue acceptance at edge E. Result transport (`result_fire = valid && ready`) consumes every response, including rejected identities. Only ownership-valid `finish_accept` changes CQ/rename/wakeup state. An unstalled valid single-cycle IU finish is accepted at E+1; a newly finished CQ entry becomes eligible for retirement after that edge, so its earliest commit is E+2. A ready instruction can issue at D+1. These are explicit first-stage interface choices, not full timing-schedule acceptance. P12 must reconcile completion/writeback/deallocation placement against the source.

## Identity and ownership

Use distinct types for rename slot indices and completion identities. A completion identity contains a bounded slot index plus a per-slot generation incremented on allocation. Invalid indices, inactive entries, mismatched generations, duplicate finishes, and finishes targeting an already-finished diagnostic fault do not change state.

A rename entry holds `valid`, `ready`, `value`, and its owning completion identity. A pending operand retains both its rename slot and producer identity. A result wakeup must match both. The completion queue selects the destination rename slot from its allocated metadata; an execution unit cannot choose an arbitrary architectural destination on finish.

Generations are a stale-result check, **not an unbounded uniqueness guarantee**. Legal producers generate one final result per issue and cancel/reset their state with the core. A finite counter cannot distinguish arbitrarily old illegally replayed data after wrap. P06 provides current local-producer cancellation and fetch drain; external/long-lived producers still require explicit lifetime tracking before connection; widening a counter alone is not that protocol. Reset clears all internal producers and consumers together; the existing external fetch reset-cancellation contract remains in force.

## Atomicity, forwarding and simultaneous events

- Dispatch requires IQ validity, CQ space, free rename slot and reservation-station space. Pop/allocate/capture all happen together or none happen. Unsupported instructions allocate only a finished diagnostic CQ entry and stop younger dispatch; older execution still drains.
- Read operands before the same edge's destination-map update, including `addi r3,r3,...`; a destination never becomes its own source. Reads use the pre-edge map and rename values, including a writer retiring at that edge; a future post-clear map implementation would require commit-to-GPR bypass. Literal-zero rA and immediate operands are explicitly ready.
- The latest-writer map points to an active rename slot. Old-writer retirement clears it only if it still names that writer. Younger allocation to the same GPR wins over that clear.
- A finish accepted in the same cycle as source capture or issue is eligible for bypass. This avoids missing a one-cycle wakeup and permits dependent issue without an extra register-read bubble.
- Full CQ/rename resources reclaim capacity on the next cycle after release. Do not allocate and release the same slot at one edge. This conservative capacity behavior is unchanged until the two-wide scheduling work.
- The reservation station may issue its old instruction and accept a new dispatch at the same edge. New capture wins over clearing/waking the old contents.
- Completion consumes and drops invalid result identities so a stale response cannot deadlock the transport; only its separate accepted-finish indication authorizes side effects.
- No combinational result-to-retirement bypass. A stalled retirement packet cannot be changed by younger finishes.

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
