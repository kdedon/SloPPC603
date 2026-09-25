# P05d: timing decisions and recovery readiness

**Decision: current-width-one recovery infrastructure can proceed with the existing registered execution edges.** No timing RTL change is required before a standalone CQ prefix selector, or before integrating recovery for the current seven legal IU forms once the cancellation, map and fetch interfaces below are implemented and tested. Full 603e timing conformance remains open. This document refines the prerequisites of those bounded slices; it does not mark P05, P06 or P12 complete.

Status: source-reviewed implementation decision for parent integration. File scope is this document only. The accepted execution contract, P05c observations and P06a policy model provide the baseline. No diagram cells, stage checker constants, canonical RTL or existing planning documents were changed by this decision.

## Source-backed bindings and explicit choices

The primary source is local `../../1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`, MPC603EUM/AD, 11/97. PDF numbers below are one-based physical pages. The accepted source transcriptions remain in [`TIMING_SPEC.md`](references/TIMING_SPEC.md) and `sim/spec/timing.json`.

Use rising-edge event numbers and sample eligibility before nonblocking updates. An interval `[k,k+1)` begins immediately after edge k and ends at edge k+1. A result visible combinationally within that interval is not an additional accepted event. No global offset is assigned between these edge numbers and the figures' numbered stage rectangles.

| Decision | Binding for the current implementation | Evidence and limit |
|---|---|---|
| TD-01: dispatch | D is accepted allocation of CQ/rename resources and RS capture. This is the current instruction's dispatch event. Preserve it through recovery and tracing. | §6.3.3/§6.3.3.1, PDF 258 / 6-12, allocates a completion buffer and rename register at dispatch. That identifies D by its resource effect; delaying the name to IU issue would conceal the allocation interval. |
| TD-02: execute and finish | E is IU input acceptance, E ≥ D+1. Execute occupies `[E,E+1)` for the seven legal forms. F=E+1 is ownership-valid finish acceptance, rename-result update and CQ done update. A surviving ready dependent can issue at F. | §6.1, PDF 247 / 6-1, defines latency and finish; §6.2, PDF 250 / 6-4, places execution-result/finish notification in execute; §6.4.2 and Table 6-4, PDF 264, 270–271 / 6-18, 6-24–6-25, give the single IU phase and one-cycle forms. §6.3.3, PDF 257–258 / 6-11–6-12, supports same-cycle dependent execution when data returns. The interval duration is source-compatible; the exact D→E admission is an implementation choice. |
| TD-03: completion | C is accepted legal head retirement: `retire_valid && retire_ready`. CQ removal and architectural commitment share C. C ≥ F+1; no new finish bypasses into retirement. | §6.1 and §6.3.3, PDF 247, 258 / 6-1, 6-12, identify completion with CQ removal and ordered commitment. §6.6.1.3, PDF 268 / 6-22, requires a finished head. §6.1 permits finish/completion overlap in some cases, so the strict F+1 floor is a conservative current policy, not a universal 603e requirement. |
| TD-04: writeback | W=C for the current one-GPR writer. There is no separate nonflushable writeback buffer. | §6.1, PDF 248 / 6-2, explicitly permits architectural writeback at completion; §6.2, PDF 251 / 6-5, and §6.3.3.1, PDF 259 / 6-13, connect retirement to architectural register updates. This binding is justified without resolving graphical W cells. |
| TD-05: release | Normal CQ and rename release occur at C. Capacity becomes visible after C and is available to an allocation accepted at C+1. A full resource cannot be reclaimed for allocation at C itself. | Five CQ/five GPR rename resources are documented at PDF 258 / 6-12. PDF 267 / 6-21 distinguishes execute-complete from execute-complete-deallocate lifetimes, but does not define the exact edge or same-edge admission rule. This release choice is retained for infrastructure and remains a fidelity question for P11/P12. |
| TD-06: recovery discard | At accepted redirect R, killed speculative state loses ownership at R. That discard is distinct from normal completion/writeback/release. Surviving C, F and E events may also occur at R subject to pre-edge eligibility and ownership checks. | §6.3.3.1, PDF 259 / 6-13, requires younger CQ and rename results to be flushed after misprediction; committed architectural state remains ordered. The source does not specify this implementation's kill-mask ports or combinational priority. P06a defines that internal policy. |

TD-02 retains a measurable admission cost. With D anchored to allocation/RS capture, the current no-wait path holds the operation during `[D,D+1)`, then computes during `[D+1,D+2)`. The simplest adjacent-stage reading of §6.2, PDF 250 / 6-4, would latch ready execute operands at the end of dispatch and use the immediately following interval for execution. Under that reading the current separate RS→IU capture adds one post-dispatch interval. Record that as a deliberate scaffold timing difference; do not redefine D as E or call dispatch-to-finish two cycles the table's one-cycle latency. The source does not settle every stalled admission case, so this observation does not authorize a universal fast-path redesign.

The current no-wait legal sequence remains `D, E=D+1, F=D+2, C=W=release=D+3`. Recovery does not need a shorter sequence to preserve architectural order or producer ownership. Preserve these edge constants while implementing the bounded recovery slice; a later optimization must be a separate reviewed timing change with updated independent tests.

A newly completed instruction cannot be flushed through this interface. The existing retirement offer is also irrevocable before acceptance: killing a pre-edge finished head would retract a possibly stalled valid packet. Retain P06a's stronger rule rejecting such a cut regardless of ready. This is a public transport constraint of the scaffold, not a manual claim that every finished instruction is architecturally irrevocable.

## Graphical ambiguity remains open

Figures 6-3/6-4 show integer `D1 E2 W3 A4` (PDF 256/257, printed 6-10/6-11). They also show a younger integer black W before an older FP black W. Figure 6-5 repeats the ordering conflict (PDF 263 / 6-17). Ordered completion and architectural writeback prose at PDF 258–259 / 6-12–6-13 prevent treating those black cells as permission for younger architectural updates.

Keep `TIM-U17` and `ST-O01` open: the graphical W category is not bound to C or W merely because its legend says writeback. Keep `TIM-U14`/`ST-O02` open: A is not automatically one mandatory additional RTL cycle after C, nor evidence for same-edge rename reuse. `ST-O03` remains a full-timing question about source admission, overlap and width/SRU scheduling. The current infrastructure choices above are decided; their equivalence to all source schedules is not. No figure replay or full 603e cycle-conformance claim follows from this document.

## Standalone prefix selector: ready now

A combinational CQ prefix selector is independent of arithmetic latency, rename storage, producer cancellation and fetch response timing. It may be implemented and verified immediately against P06a's queue-age policy. Its input is a coherent **pre-edge** snapshot: head, count, active/done bits, per-slot generation, and a redirect request containing all/pivot/keep-pivot selection. This slice does not validate or change target PC, issue, finish, retire, fetch or architectural state.

Required selector behavior:

- Traverse `count` entries from `head` modulo five. A pivot is eligible only if it belongs to that traversal and its active bit and generation match. Slot number and generation magnitude do not express age.
- An all-cut selects zero survivors; a live pivot selects its older prefix, with the pivot included only when requested. Reject a selection that would remove a pre-edge finished head, regardless of retirement readiness.
- On acceptance, report the younger kill mask, surviving count and `new_tail=(head+surviving_count) mod 5`. An empty all-cut may accept, reporting zero kills and `new_tail=head`.
- On rejection or absent request, report zero kills and unchanged count/tail, with acceptance false. Rejection must not masquerade as a zero-survivor accepted flush.
- Treat the snapshot's ring/active/count consistency as an input invariant checked by assertions and the testbench. Guard encoded indices before array access. Invalid or inactive pivots must not become valid through truncating an index.

The selector result precedes any same-edge surviving head commitment. It must not decrement its survivor count for a commit it does not observe. Integration computes post-edge count/head after applying that separate event. A selector-only PASS proves this prefix computation, not recovery of the CPU.

## Current-width-one integration: ready for bounded implementation

The baseline is the existing five-entry CQ, five GPR renames, six-entry IQ, one RS and one registered IU producer. Keep the seven instruction forms, retirement packet and abstract fetch protocol. Use an explicit internal/test redirect control; do not imply that branch or architectural exception decode now exists.

The request must identify all/pivot/keep-pivot and an aligned 32-bit target PC, with an unambiguous accepted/rejected outcome. For a future valid/ready adapter, distinguish request transport consumption from redirect acceptance just as result transport differs from finish acceptance. A stale or forbidden request may be consumed and rejected; its caller must not assume it changed execution or fetch. If a rejected request is to be retried, the caller must submit another request explicitly. An invalid request cannot suppress ordinary dispatch, finish, issue or retirement.

The minimum implementation changes are concrete:

| Component | Required change before integrated acceptance |
|---|---|
| CQ/control | Apply accepted prefix cut to active/done state and tail, preserve generation counters, and block dispatch/allocation at R. Qualify finish against pre-edge surviving ownership. Allow only a surviving pre-edge finished head to commit. Keep retirement packet stable under consumer stall. |
| Rename | Preserve surviving entries, readiness and values; clear killed/retired ownership. Reconstruct each latest-writer mapping by scanning post-commit survivors oldest to youngest. Retain a producer finish accepted at R while rebuilding; do not overwrite it from a stale snapshot. No dispatch occurs at R, so there is no new destination-map conflict on that edge. |
| RS/IU | Compare held completion identities against the accepted surviving set. Cancel killed holders atomically at R. A killed RS must not issue, and a killed IU response must not finish or wake. Permit surviving old-result consumption and replacement issue only with surviving identities. Preserve pending operand identities and qualified same-edge forwarding for survivors. |
| IQ/fetch | Clear IQ only for an accepted redirect. Prevent a same-edge old fetch response from repopulating it. Preserve any already offered request address, accept/drain that obligation, discard its response, and issue only the most recent accepted target afterward. A rejected CQ request never redirects fetch. |
| Diagnostic state | Existing `fault_pending` must track surviving diagnostic entries if such entries are included in integration tests; killing a younger diagnostic entry must not leave fetch/dispatch permanently stopped. A committed diagnostic halt is not undone by speculative recovery. Either reject redirect after halt explicitly or exclude that terminal state from the test-control interface and assert the precondition. No P14 architectural exception semantics are added. |
| Wiring/observation | Connect the one accepted-redirect decision to every consumer. Expose the pre-edge classified surviving identities for cancellation at R and the post-commit survivor ordering for map reconstruction, or equivalent explicitly verified signals. Keep no-redirect behavior compatible with all existing core/wrapper benches; update explicit tie-offs if ports are added. Extend event traces with accepted/rejected redirects and killed identities before comparing recovery RTL to the model. |

No external result directory is required for this **local-producer-only** slice if the implementation proves that every held RS/IU token either remains attached to a live surviving CQ identity or is atomically destroyed on cancellation/reset. After each edge no killed local producer may remain capable of producing a response. With this invariant, a full generation wrap cannot encounter a still-live earlier local token for the reused slot. Preserve generations on redirect and verify wrap through legal cancellation sequences; never claim rejection of arbitrary replay after a cancelled/drained identity is reused.

Before attaching an external or uncancellable result producer, P06a's outstanding-token collision check or a reviewed whole-slot quarantine becomes mandatory. That producer-lifetime extension is a genuine dependency of that future producer. It is not a prerequisite for the present cancellable one-stage IU or for the standalone prefix selector. Untagged fetch drain remains mandatory even for this local-only execution slice because the current memory request cannot be cancelled by clearing IU state.

## Required acceptance evidence

These gates attach to the implementation slice they exercise. Existing P05c constants remain expected for surviving legal IU work when no redirect kills it.

| Gate | Required tests and independent expectation |
|---|---|
| Selector | Enumerate each legal head/count arrangement, every live pivot and keep/exclude choice, all-cut, empty/full queues, wrap across slot four, stale generations, inactive/out-of-range pivots and finished-head rejection. Expected survivors come from list-prefix indices; do not compute the oracle with the selector's ring-mask algorithm. Verify rejected/absent requests return zero kills. |
| Simultaneous events | Accepted cut with older commit, surviving finish, killed finish, surviving RS issue and killed RS issue. New finish cannot commit at R. A result targeting newly issued work at R cannot finish at R. Verify rejected redirect permits the same progress as an otherwise identical no-redirect edge. |
| Rename/operands | Several writers to one GPR across the cut, including surviving older commit and younger surviving finish at R; recover the youngest remaining writer. Preserve RAW readiness and identities. A killed producer cannot wake any holder. Compare future architectural commits against an independently retained program-order prefix. |
| Retirement protocol | Keep a finished stalled head and kill younger entries without changing its offer. Reject all/exclude-head cuts that would retract that head with either ready value. Unfinished head may be killed with no architectural update. |
| Local lifetime | Kill a pending RS and occupied IU, then reuse slots; prove no killed issue/finish/wakeup. Repeatedly wrap slot and generation counters through legal cancellation/drain. Reset cancels internal producers under the existing external reset contract. |
| Fetch/integration | Redirect with an old request held, first offered or accepted at R; redirect with an old response and IQ readiness at R; arbitrary request/response stalls; repeated accepted targets while draining; rejected redirect; target alignment; IQ clearing; reset during drain. Only the latest accepted target may populate the IQ after drain. |
| Preservation | Strict Verilator lint and standalone/integrated benches; existing seven-form architectural trace, CQ and rename/IU regressions; P05c no-redirect timing probe and negative checker tests. Recovery-enabled tests need identity/epoch-aware traces; the existing reset-free/no-redirect stage checker cannot be relabeled a recovery checker. |

The accepted 15-test P06a model is the policy oracle for cuts, simultaneous ownership effects, map rebuilding and fetch drain. It is not an operand/RS implementation or proof of future wiring. Acceptance requires new compiled RTL observations and adversarial comparisons; a model PASS alone does not meet these gates.

## Dependency refinement and remaining work

For parent scheduling, split prerequisites by the property being implemented:

- **P06b selector preparation:** accepted P06a prefix/irrevocable-head policy plus package identity/resource definitions. Ready now, with the selector gate above.
- **P06b width-one local recovery integration:** accepted P05 current-subset execution/ownership tests, P05c observed edges, this decision, accepted P06a policy, and reviewed selector interface. Ready to implement with the integration gates above. Completion of that slice still requires new RTL evidence.
- **External producers and speculative memory:** require the explicit lifetime/drain protocol and memory-side recovery semantics before connection. Stores, load-update destinations, CR/XER/FPR state and architectural exceptions each require their own reviewed extension.
- **Full 603e timing/ISA acceptance:** retains P02/P03 coverage, P11 width/unit scheduling and P12 source/diagram reconciliation. The known dispatch holding interval, conservative finish/completion spacing and unbound deallocation timing prevent a full-conformance claim.

This refines the current planning phrase that all P05 source/timing gates precede any P06b work. The prefix and recovery-ownership properties depend on explicit D/F/C ownership boundaries, which are now stable and tested; they do not depend on interpreting FP graphical W cells, bus waveform transcription or completing unrelated ISA families. Parent may update the work queue to admit these bounded slices while leaving the full parent gates open. The ultimate processor fidelity objective is unchanged.

No new test execution or RTL acceptance is claimed by this document. Its evidence is primary-source review, the recorded P05c compiled probe/18 checker tests, the reviewed P06a policy/15 tests, and the explicit requirements for the next implementation slices.
