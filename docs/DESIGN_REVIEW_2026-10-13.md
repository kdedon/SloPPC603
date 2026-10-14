# Architecture and timing review, 2026-10-13

Source audit of commit `b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus
uncommitted changes. The review covers dispatch, completion/recovery contracts,
LSU payload/control and execution-unit boundaries. It found no new proven
correctness bug. No RTL, simulation build or Quartus run belongs to this review;
proposed area/timing benefits remain hypotheses. Acceptance percentages do not
change.

The [66 MHz fit review](FMAX_66_REVIEW.md) records routing failure at 96% ALMs,
with no fresh TimeQuest result. IQ and completion/rename storage remain the
first area targets; the findings below supplement that work. Source inspection
cannot establish routing savings, Fmax or full manual conformance.

## Findings

### CPU throughput follow-up

Benchmark startup enables both caches: `toolchain/demo/crt0.S` maps Dhrystone
RAM with WIMG=0000, enables translation and sets HID0 ICE/DCE. Doom and Quake
share `toolchain/demo/doom/stub.S`, which maps their image/data regions and
enables caches before entering the program. Source inspection therefore does
not support an accidental startup cache-disable explanation. The installed
board build profile is still unknown; `mister/build.sh` defaults to single
issue with the pipelined LSU disabled, while the explicit dual/LSU profile
enables them.

The external-memory bridge buffers a complete DDR3 line before releasing the
CPU response, then replays critical-first 60x beats (`rtl/soc/soc_xmem_bridge.sv`).
This delays even the data cache's critical-beat forwarding. The instruction
cache also waits for a completed line; early restart remains a documented gap.
These are source-level throughput limits, not measured CPI attribution. Any
bridge change needs independent retry/error/coherence checks before acceptance.
Streaming requires a corresponding change in `soc_bus60x_target.sv`: after
data grant, its read state currently acknowledges and advances every beat.
DDR3 returns may contain gaps, so releasing the grant after only the critical
word would expose unfilled words. A candidate must track received words and
gate read requests, TA and beat advancement on the requested word's readiness,
preserving the registered memory-read edge. DDR3 still returns the aligned
line in order; no earlier arrival of a late critical word is implied.
The stale real-mode instruction-cache prohibition in the startup comment and
current scorecard was corrected: eligibility checks WIMG.I and ICE, and
real-mode WIMG=0001 permits caching. Percentages and historical records stay
unchanged.

### FPU integration disables an integer branch fast path

`BS_EARLY` excludes `ENABLE_FPU` in `rtl/ppc_core.sv`; `BS_ANCHOR` depends on
that parameter. Thus enabling the FPU also disables early branch recovery and
anchor-based removal of unresolved predicted branches in integer-only code.
Ordinary resolved branch removal remains available. This is a source-level
throughput limit, not a measured CPI attribution.

The restriction protects a real integration boundary: every accepted recovery
clears the core FP tag queue and schedules `kill_all`. An early branch cut can
retain older FP CQ entries, which would then lose their FP work. Late branch
recovery waits until older work has committed. The standalone FULL FPU has
tagged inclusive suffix abort, and COMPACT can abort its sole matching tag,
but the core currently uses that port only for serialized-lane cancellation.
FULL also suppresses result validity on matching abort and assumes no
concurrent retirement in its abort count update. Wiring the existing abort
port alone could add a completion bubble or desynchronize retirement.

A general solution must preserve the same FP prefix as CQ, abort at the first
killed FP tag, and define simultaneous older commit/younger abort behavior.
It must preserve sticky/CR/replay and lane-load release metadata. A narrower
integer fast path could latch per-branch eligibility only when no older FP
work exists, including paired dispatch and unreleased lane work, then use that
eligibility consistently for anchor selection, recovery and late resolution.
Neither proposal is implemented or accepted. Required checks include older
long-latency FP surviving a miss, same-edge commit/recovery, killed delayed
loads/stores, enabled exceptions, replay and tag reuse across FULL, COMPACT and
602. Do not simply enable the parameter.

### P1 Contract descriptions lag accepted retirement timing

The foundation execution, recovery, CR/XER and stage-observation documents still
forbade finish-to-retirement bypass. The later [writeback-cycle
extension](DUAL_DISPATCH_DESIGN.md#completion-in-the-writeback-cycle) accepts it
for eligible clean results, citing UM §6.3.3 and Figures 6-3/6-5. Current RTL
agrees: `ppc_completion.sv:489–532` qualifies and merges those results;
`ppc_core.sv:3663–3678` excludes special-lane results on both ports. The stage
checker and numeric contract already use `finish_to_retire_min=0`.

Corrected in this documentation batch: the [current edge
table](EXECUTION_CONTRACT.md#current-finish-and-retirement-edges), scoped
supersession notes in [recovery](RECOVERY_CONTRACT.md),
[CR/XER](CR_XER_CONTRACT.md) and [stage timing](STAGE_TIMING.md), and two stale
descriptions in `sim/spec/stage_timing.json`. Historical measurements, numeric
constants and the independent test oracle are preserved. This resolves a
documentation conflict; it does not authorize reverting manual-backed timing
or demonstrate all finish/recovery/backpressure collisions.

### P1 LSU payload and request lookahead consume broad muxes

[`ppc_lsu_pipe.sv`](../rtl/ppc_lsu_pipe.sv), lines 148–175, carries a full `uop_t`
with EA/data, PC/instruction, offset and dependency identities in one `entry_t`.
P1, P2, queued completion and replay use that type. Lines 613–728 form both
request-ready outcomes for both queues before the final selection; lines
739–741 shift complete store-queue entries. The failed fit attributes about
2,738 direct ALMs to this unit.

This is a performance hypothesis, including an intentional area-for-late-ready
tradeoff. Review stage-specific descriptors, immutable payload separated from
ordering metadata, and factoring common work out of the handshake alternatives.
Preserve the data needed for fault adoption and replay, and the existing request
offer and LSU cycle counts. Synthesis may already prune unused fields; no saving
is established. Verify simultaneous push/pop, wakeup, split FP accesses, fault
adoption, recovery and committed-store drain with the existing LSU timing,
update, FP, fault and recovery benches, then compare area and fitted timing.

### P2 Dispatch lookahead reaches fetched-word predecode

[`ppc_core.sv`](../rtl/ppc_core.sv), lines 2903–2919, computes SRU assignment
through DQ1/DQ2/DQ3, skipped branches and fetched-word predecode before controlling
`c0_sru`. This couples dispatch admission to frontend decode and multiple queue
positions. It is a timing hypothesis, not a measured critical path.

Investigate compact maintained lookahead metadata or parallel eligibility
selection. Keep the same unit assignment and dispatch acceptance edge;
registering the decision or dropping the lookahead can change accepted timing.
Compare dispatch traces using `test-dispatch-rules` and `test-core-dual`, covering
empty/partial queues, branch chains, simultaneous fetch/dispatch, recovery and
station occupancy, before making an FPGA timing claim.

### P2 FP memory admission repeats instruction classification

[`ppc_pkg.sv`](../rtl/ppc_pkg.sv), `pair_predecode` at line 973, already classifies
FP arithmetic, memory and store forms. `ppc_core.sv:2637–2648,2699–2709,2747–2749,2765`
repeats instruction-bit classification for routing, width, source dependencies
and direction. This conflicts with the canonical decode-once and source-use
metadata guidance; no functional disagreement was demonstrated.

Derive compact semantic controls once and retain dynamic mode/resource checks
at admission. Preserve 602 exclusions, actual GPR source use and exception
behavior without bloating IQ storage. Compare classification across all variant
decode profiles, then run FP-memory, little-endian, update-form and paired
dependency tests independently of the new metadata.

### P2 Canonical hardware budget overstated ALMs

The HDL skill's target paragraph used approximately 110K ALMs instead of the
fit's 41,910-ALM capacity. The current batch corrects that guidance and separates
logic elements from ALMs. Architecture choices must use the actual device's
resource units; the failed fit already demonstrates that area is a constraint.

## Boundaries to preserve

- Keep in-order CQ-gated architectural updates. The donor's early EX status
  commit relies on excluding older faults and memory status writes; it does not
  prove safety for this core's faulting `stwcx.` or update forms.
- Preserve exact producer identities and accepted-result qualification while
  consolidating hazard metadata. Keep CR/XER and variant-specific source rules.
- `ppc_lsu_sequence.sv:65–76` already advances only on accepted dispatch and
  clears sequence ownership on recovery. The IU and FPU arithmetic interfaces
  already separate arithmetic requests/results from architectural commitment.
- `ppc_core.sv:2053–2083` deliberately redirects the frontend before backend
  recovery for early misprediction handling. A common recovery representation
  must preserve these phases, retained ages, committed stores and response drain.
- FULL FPU manual latency/throughput remains the accuracy target. COMPACT's
  [arithmetic module](../rtl/fpu/ppc_fpu_arith_compact.sv), line 8, explicitly
  departs from Table 6-5 latency. A COMPACT fit cannot establish FULL timing
  fidelity. Model differences belong in named parameters or module choices;
  frequency work must preserve the selected contract.

Independent verification remains necessary for proposed RTL changes: exact-cycle
and architectural/protocol tests first, Quartus elaboration and a fresh fit
afterward. This source audit supplies neither those proofs nor release signoff.

## Physical follow-up after the smaller board fit

The completed normal-router-effort fit still failed routing before TimeQuest at
an estimated 38,853 ALMs (93%). The report records automatic aggressive
routability optimization; the next controlled experiment explicitly selects
`ALWAYS`, retaining 66 MHz, seed 2 and all setup/hold constraints. This measures
routability and does not imply a timing gain.

The failed report places `normal_idle~0_OTERM94686`, a physical retimed register,
at `FF_X29_Y40_N32` with 2,083 fanout. Its clock-enable/synchronous-control loads
lie inside the reported congestion hotspot. The RTL expression has three
functional consumers; the physical fanout arises after optimization. CPU-domain
hold-delay insertion remains dominant. No missing-clock cause was established.

An unapplied candidate exposes combinational drain-idle from dispatch occupancy
and IU occupancy/cancellation, removing readiness and completion terms from the
source expression. An independent exhaustive Boolean proof passes 1,024 cases,
including reset, cancellation, CR holds and result backpressure. It adds no
register or cycle. This is only a logical proof: physical retiming may already
perform the simplification, so synthesis and routing must measure any benefit.
Current-source CPU/FPU isolation uses frozen RTL before this candidate is tried.

Recorded: `python3 /tmp/ppc-drain-idle-proof.py`, commit
`b9f52ae8ef3b52159c341c7aa2ecaa565074da76` plus uncommitted changes,
2026-10-13. The temporary proposed patch is not part of accepted RTL.
