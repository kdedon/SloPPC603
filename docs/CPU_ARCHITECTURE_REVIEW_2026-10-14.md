# CPU architecture review — 2026-10-14

Recorded: source review (`git show bea975a:rtl/ppc_core.sv` and the named module paths), commit `bea975a`, 2026-10-14.

Read-only source audit against shared HDL/pipeline/decode/recovery skills and accepted execution, stage, CR/XER, LSU and FPU contracts. No simulation, synthesis, new snapshot or live edit. This is a focused control/ownership review, not complete manual conformance. No new architectural correctness defect is demonstrated. Existing measured timing and acceptance records retain their original scopes.

## 1. Source declarations are not yet a single hazard authority

**Concrete conservative false hazard; existing follow-up, not an architectural corruption finding.** `rtl/ppc_core.sv:2887–2889` tests both raw `uop.src_a/src_b` against an overlapped native load destination, without `zero_a` or `use_imm`. For example, `addi r3,0,1` need not read GPR0 but is blocked by a pending load to r0. Branches also retain raw instruction bit fields in those source slots: default assignment is `ppc_decode.sv:84–86`, while branch decode at `232–248` declares branch operands separately. A CTR-only branch can therefore acquire an unrelated GPR wait.

Other sites already use different declarations: DQ1 IU overlap at `ppc_core.sv:3126–3128` honors zero/immediate controls; SRU/update waits use `reads_reg/reads_base` at `2910–2926`; pair metadata in `ppc_pkg.sv:1026–1034` describes CR/XER/LR/CTR dependencies rather than GPR source use. This is genuine duplication of hazard policy, not merely long source text.

**Direction:** consolidate named GPR-read declarations for the *dispatched semantic uop*, retaining branch/MFSPR zero-GPR cases, RLWIMI's old destination as a real B source (`ppc_decode.sv:204–216`), update ownership, and cracked string/store source changes. Do not replace everything with today's `reads_reg`: its zero/immediate rule alone does not exempt branches. A shared declaration does not require a second scoreboard or a new cycle.

**Acceptance:** independent source-use truth table plus actual held native-load success/fault programs. Genuine A/B dependencies must remain blocked. Earlier branch dispatch must not commit younger CTR/LR/CR/FPSCR through an older load fault. This intentionally changes schedules, so use architectural equivalence plus explicit improved-dispatch observations, not a claim of identical cycles. Preserve the existing CTR-release matrix with an independent retained-stop fixture; that matrix currently uses this conservative wait in some cases.

## 2. Frontend classification controls older station routing and queue movement

**Observed structural timing problem; current direct-class experiment addresses part of it.** `ppc_core.sv:3025–3038` uses live fetched class behind queued branches to choose primary IU versus SRU. That drives station packet selection (`2335`, `2387`), and dispatch/queue movement (`2772–2796`, `ppc_iq.sv:76–102`). It places frontend decode before incoming station owner comparisons (`ppc_dispatch.sv:71–86`) and next GPR-address storage. The fetched instruction does not bypass IQ dispatch; its resource prediction controls an older instruction.

This is deliberate routing policy, not a second RAW mechanism. Removing lookahead or inserting FD/IU stages changes established schedules. The present direct projection shares the raw SRU predicate and keeps full decode authoritative. If its fit gain is insufficient, the coherent structural alternative is atomic cache-word classification with complete scalar/refill/error provenance, The necessary scope is summarized below. FD-only capture cannot fix the live FD_REG0 path. That proposal has a real unknown-selector equivalence boundary, not just interface plumbing. Prior rejected readiness/entry-selector experiments are not new recommendations.

## 3. FPU enable disables early recovery even for integer-only streams

**Documented integration/throughput limitation.** `ppc_core.sv:1776–1782` excludes ENABLE_FPU from BS_EARLY and therefore BS_ANCHOR. This can increase integer branch occupancy/misprediction cost without changing integer instruction semantics.

The restriction is justified by current ownership: `4009–4014` empties the entire FP tag queue on recovery and schedules delayed kill-all. An early branch cut can retain older FP CQ entries; discarding their FP owners would be incorrect. The FP head/result/sticky/replay machinery (`3957–3981`) depends on that queue remaining coherent.

**Direction:** either implement real suffix-preserving FP recovery with simultaneous older commit handling, or a narrower per-branch eligibility captured only when every older FP owner/lane/native load is quiescent. Eligibility must never be reevaluated after younger FP issue. No blind BS_EARLY toggle.

**Acceptance:** FULL/COMPACT and 602 boundary programs for older FP pending, paired older FP/FPLSU exclusion, released/native loads, younger kill, sticky and enabled exceptions, replay and tag reuse. These are independent throughput work, not a timing shortcut or a newly proven FPU numerical defect.

## 4. Completion/flags obey the right architectural boundary; preserve it

**Reviewed sound boundary, with existing bounded proofs rather than a new proof here.** Completion validates index, active ownership, generation, done and accepted recovery before finish/wake (`ppc_completion.sv:480–510`). Clean pending heads can retire on arrival (`580–604`); faults remain stored first. Stored CQ[1] is now independently kill-qualified (`615–621`), preserving the fixed mixed-arrival/recovery bug correction.

Core commit and commit1 remain ordered (`ppc_core.sv:3872–3875`), GPR/update writes are commit-qualified (`4092–4094`), and CR/XER writes use the same retirement packet/edge (`ppc_flags.sv:154–170`). The flag owner/waiter, CA/SO-only rules, FP unowned field commitment, and one-status-writing retire pair are explicit rather than arbitrary early writes. Special side effects use exact `commit_match` (`ppc_special.sv:762`, `1300`) and memory irrevocability guards are explicit (`ppc_lsu_pipe.sv:1123–1127`).

The donor PPC604 EX-status/MEM-data split relies on exclusions this design does not have: older faulting memory may remain, stwcx. writes CR, and updates own an additional GPR result. Moving CR/XER commit earlier would violate the accepted contract unless an entirely new manual-backed ordering proof were supplied. Keep the current unified retirement boundary.

**Remaining design risk:** flags still consume compact post-retirement recovery packets (`ppc_flags.sv:117–143`) while rename has a specialized unshifted view. If timing migrates there, precompute exact owner/waiter membership before late retirement masks, using one CQ-derived ownership authority. Do not build another recovery map or assume all result classes can use the clean-arrival bypass. This is conditional performance debt, not a demonstrated current failure.

## 5. Recovery is one backend transaction with several intentional phases

**Maintenance risk, not evidence that all clear signals should be merged.** The backend redirect arbitration is centralized (`ppc_core.sv:3882–3906`), CQ rejects stale/nonlive pivots and protects irrevocable settled offers (`ppc_completion.sv:378–420`), and accepted recovery supplies the shared exact kill generation vector. This satisfies the essential one-recovery authority.

Frontend early redirect is deliberately earlier than backend recovery (`ppc_core.sv:2152–2174`). `bs_fe_q` prevents the later accepted recovery from clearing the already redirected target stream again. Fetch keeps the old offered/accepted request obligation and drains it (`ppc_fetch.sv:69–85`). Treating frontend clear, backend kill, FPU delayed kill and bus cancellation as one simultaneous reset would lose ownership or change manual-visible branch cycles.

**Direction:** make a small typed internal recovery-intent record or clearer local grouping only if it replaces duplicated cause/target/phase selection without adding a phase or changing predicates. Preserve exact pivot/generation, retained-prefix age, committed stores and response obligations. Keep accepted/rejected redirects distinct at every consumer.

**Acceptance:** recovery-state/core-recovery/branch-recovery plus held-request drain, same-edge older retire/younger kill, stale pivot and irrevocable-store tests. A source refactor must retain current per-edge traces, not merely final GPR state.

## 6. Multicycle execution is already request/response based; special-lane coupling is the debt

**Reviewed sound arithmetic boundary.** `ppc_iu.sv:67–88,475–493` holds one captured request, waits for actual multiply/divide completion and the selected manual reservation interval, presents a tagged response, supports accepted-response replacement, and cancels the divider explicitly. Arithmetic result construction does not write architectural registers. `ppc_lsu_sequence.sv:32–76` cracks complex accesses into ordinary accepted uops, retains original EA progression and clears on recovery. These should not be replaced by instruction-specific stalls in the core.

**Maintenance risk:** `ppc_special.sv:280–287` owns memory, exception, context, MMU, timer and FPU-lane states. Its FP integration at `2205–2433` shares issue/commit/abort/memory ownership with the core FP queue. LSU adoption (`ppc_core.sv:3390–3397`) additionally arbitrates an older fault against a held SPR operation. This coupling makes a local ready/valid optimization capable of changing another service's lifetime.

**Direction:** typed service descriptors and explicit lifecycle contracts for adoption/MMU/FPU ports are a safer first step than splitting the FSM or introducing new sequencers. Keep old EA/PC/producer ownership in adoption; do not recompute from a later uop or commit a response merely because transport accepts it. Test simultaneous adoption, same-edge replacement, cancel and response backpressure before a module extraction. No current cycle change is warranted by source size alone.

## 7. Finite producer identity is safe only with lifetime discipline

**Existing tracked boundary; no new wrap defect found.** CQ generation checking alone cannot reject an arbitrarily delayed response after exact token reuse. Current LSU P2/Q/redo holders latch killed state (`ppc_lsu_pipe.sv:948–951,1031–1048`) and suppress live response/result adoption (`683–714`) independently of later generation reuse. That is the needed protection for current draining memory traffic. The real-core cancelled-response wrap regression exists at `sim/Makefile:2901–2905`; the former invalid-wake alias is separately recorded as fixed AUD-91.

Do not remove latched killed state as redundant with `killed_now`, widen generation counters as a substitute, or connect an uncancellable external execution producer using only CQ tags. The older producer-directory discussion in RECOVERY_CONTRACT describes such an extension; it is not evidence that existing internal drained responses must stall every exact-token reuse. Reset still requires its documented environment cancellation boundary.

## 8. Model selection is mostly at appropriate static boundaries

**Deliberate choices and remaining configuration debt.** `cpu_cfg` and scalar capability helpers in `ppc_pkg.sv:635–728` centralize model properties. Core's width/SRU/branch-removal choices (`434–448`) and IU multiply parameter preserve model differences. FULL versus COMPACT is a whole-module choice (`ppc_special.sv:2378–2420`), not a runtime hidden mode. COMPACT arithmetic explicitly says its latency is not Table 6-5 (`rtl/fpu/ppc_fpu_arith_compact.sv:8`); FULL manual latency remains the target. A COMPACT fit cannot certify FULL timing fidelity.

The repeated static decode bindings at core `746–764`, `953–971`, and `3601–3619` are a drift risk as more projections are added; no mismatch is established here. Prefer a checked common configuration binding and the actual canonical decoder, not another raw ISA table. A future cache classifier must match all static parameters exactly. Preserve Quartus 17 restrictions when considering a configuration struct.

## Priority

The isolated direct-class measurement is now recorded in [the control-path review](CPU_CONTROL_PATH_REVIEW_2026-10-13.md): 40.99 MHz, with fetched-word classification absent from all 80 reported setup paths. The measured next timing work is fixed-slot rename readiness and the independent CR/branch qualifier. Cache-class provenance/four-state work is deferred unless a later fit returns that cone to the limiting set. Pursue false GPR hazards and quiescent-FP branch eligibility as separate throughput changes with their own fault/ownership acceptance. Keep the current precise completion, typed multicycle execution and phased drain contracts intact. Broad extraction or more aggressive issue policy is not a justified substitute for a measured critical-path cut.

## Cache-class acceptance boundary

An atomic class stored beside each instruction can remove canonical decode from
cache-hit lookahead without an added stage, provided both refill halves, immediate
refill response, direct/managed scalar bypass, router error/refetch normalization,
fetch buffer promotion and live/held/split FD ownership transport it coherently.
All 18 static decoder parameters must match actual core bindings. Dynamic IABR
and fetch faults remain evaluated at the existing point; full IQ decode remains
authoritative.

This cannot be claimed equivalent for arbitrary malformed cache-way masks or
unknown source/index/valid controls. The original cache ORs way words; decoding
their OR can differ from selecting or ORing their two-bit classes. Unknown word
muxes likewise need not commute with classification. A literal binary multiway
fallback keeps the old decoder on the hot path. A reachable-state refinement
therefore needs independent initialization/tag-uniqueness and response-time
ownership proofs, coherent transport under stalls and flushes, and every-cycle
lookahead/readiness comparisons including poisoned invalid companions. Existing
assertions, tests, architectural traces and manual cycles must stay intact. Such a
complete refinement proof and implementation remain pending; this review does
not establish them.
