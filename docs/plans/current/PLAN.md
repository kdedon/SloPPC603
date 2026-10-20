# Current CPU plan

Updated: 2026-10-18. This is the active planning entry point. The target for
the next deliverable is a single-issue, big-endian integer CPU with supervisor
mode, resumable exceptions, interrupts and software-managed MMU. The full 603e
CPU remains the longer-term target.

The [system completion scorecard](../../SYSTEM_COMPLETION.md) is the authority
for current percentages, accepted behavior, gaps and the MVP effort range. The
[full CPU weighting audit](../../FULL_CPU_COMPLETION_AUDIT.md) tracks the wider
processor scope. [CPU references](../../references/README.md) collect the
distilled source contracts.

Companion plans in this directory:

- [MVP execution plan](MVP_EXECUTION_PLAN.md): MVP waves and the accepted-round ledger.
- [Full 603e task plan](TASK_PLAN.md): P00–P30 scope that the full CPU audit measures.
- [Original design brief](ORIGINAL_DESIGN_BRIEF.md): target machine for the full 603e.

Open correctness, efficiency and style findings are tracked in the
[repository audit](../../AUDIT.md).

## Working with this repository

Run `make -C sim regression` from the repository root for the simulation suite.
Reference comparison targets require a separate sibling `dingusppc` checkout.
Generated builds, logs and reports are excluded from version control.

## Next acceptance gates

CPU timing work retains the IU record-predicate factoring at 44.65/44.50 MHz (slow 100 C/-40 C) on the matched hints1/DW2/LSU1/FPU0 profile. Its focused proofs, exact manual-cycle/public-trace checks and physical source closure passed; see [IU evidence](../../IU_RECORD_FLAGS_PROOF.md). The implementation and benchmark records are on main. Recorded: `make -C sim ci` and `make -C sim test-fpu-all`, commit `aa89a0e`, 2026-10-20: both pass (FPU oracle 1,408,506 checked, 0 mismatches). The MiSTer configuration still fails `test-core-memory-edges` and `test-core-ctr-target-capture`, which `ci` does not run. Auto routability and Speed synthesis both regressed and are rejected; retain Balanced/Always settings. See [routability](../../CPU_ROUTABILITY_TRIAL_2026-10-18.md) and [Speed synthesis](../../CPU_SPEED_SYNTHESIS_TRIAL_2026-10-18.md).

The preceding integration checkpoint `7594131` completed its resumed 80-case initialization sweep (50 fresh, 30 preserved completed cases) and fresh full FPU suite, with independent source/input closure. Original interrupted runs remain recorded separately. The isolated SPECIAL result-owner cofactor passed fresh focused/manual checks and all six exact public traces, but regressed to 42.74/43.38 MHz and is rejected; see [the trial record](../../SPECIAL_OWNER_COFACTOR_REJECTED_2026-10-18.md). Next: run fresh full acceptance on the merged IU batch and validate the existing registered fetch/decode option as a distinct latency profile before its matched physical trial. Preserve existing manual cycle expectations, exception ownership and default FD0 behavior. The 66 MHz target remains open; a registered fetch/decode profile requires separate latency and physical acceptance.

1. Closed 2026-09-27: LRU page replacement, direct-store DSI/ISI and
   `tlbsync` are implemented, and seeded EXT/DEC/reset stress passes on the
   translated cached 60x top ([evidence](../../MMU_STRESS_FIRMWARE.md)).
   Machine check, trace and debug exceptions stay outside the MVP set; the
   stress has no ARTRY/TEA, which gate 2 owns.
2. Accepted 2026-09-27: cache maintenance, context changes, interrupts and data
   effects across held refills and bus retries, with CPU `icbi` and external
   maintenance as distinct contracts ([cache control](../../CACHE_CONTROL.md)).
   Page-table context changes under randomized retries remain with gate 1.
3. Closed 2026-09-28: the reviewed [interface timing contract](../../INTERFACE_TIMING_CONTRACT.md)
   is implemented by the measurement SDCs, and final fits on the complete MVP
   RTL meet 50 MHz setup and hold on all three tops. Open: 66 MHz on the cached
   tops (registered fetch-to-decode stage) and the remaining scorecard gaps.

4. MVP completion (scope set 2026-09-28): a snooping MEI data cache built and
   integrated behind the LSU and BIU; a top whose ports are exactly the 603e pins,
   with internal blocks grouped as on the chip; a 603e-timed multiplier; the
   remaining diagnostic halts replaced by manual behavior; the compiled corpus
   compared against DingusPPC; a registered fetch-to-decode stage toward 66 MHz;
   then release packaging and final signoff fits.

Timing targets: 50 MHz is the provisional MVP constraint; 66 MHz, the original
603e's clock, is the aspirational target. Fit records report Fmax against both.

For the full 603e, dual issue, branch prediction, data cache/coherence, floating
point, endian/variant features and timing fidelity remain major workstreams.
Floating point has manual-backed [603e](../../FPU_CONTRACT.md) and
[602](../../FPU_602_CONTRACT.md) contracts and a completed isolated donor
experiment. The donor failed qualification and was removed. The replacement standalone module
selects 603e or 602 at compile time and must match original instruction latency
and throughput. The coherent baseline passes both personalities’ numerical, exact-cycle,
public-shell, paired dispatch/retirement and strict lint gates in
[verification](../../../sim/fpu/PRODUCTION.md), including full-queue admission
and 602 SPR timing. Frequency closure and the documented silicon-semantics
gaps remain open. On `0ff3a45`
the FULL FPU fits at 51.57 MHz (603e) and 50.58 MHz (602), COMPACT at 53.43
and 60.07 MHz (`quartus/fpu-production/synthesize.sh --docker fullfit`,
`full602fit`, `compactfit`, `compact602fit`); all miss 66 MHz. Timing work keeps the Table 6-5 cycle counts exact; any change to
them goes behind a named parameter such as `FPU_IMPL`. See the
[FPU assessment](../../FPU_REUSE_ASSESSMENT.md) for the remaining semantic and
implementation gaps. The FPU is in the core behind `ENABLE_FPU`, which
leaves FPU-less builds unchanged.
Do not infer full CPU completion from the restricted MVP score.

## Work queue

Done (batches 5–6, 2026-09-30): FPU in the core behind `ENABLE_FPU`, with FP
arithmetic pipelined to Table 6-5 ([integration](../../FPU_CORE_INTEGRATION.md));
603e power modes (V14); the opcode self-test ([SELFTEST.md](../../SELFTEST.md));
Whetstone ([BENCHMARKS.md](../../BENCHMARKS.md#whetstone)); the SoC and MiSTer
FPU option; CI preparation ([CI.md](../../CI.md)).

Done (batches 7–9, 2026-10-01): FP loads and stores as single 64-bit accesses,
overlapped with younger work; the 602 FPU in the core (V12) and its timing to
50 MHz; COMPACT FPU ([FPU_COMPACT.md](../../FPU_COMPACT.md)); the 603 with XATS
(V5); the pipelined LSU with one-cycle cached hits (P3, `ENABLE_LSU_PIPE`,
`--lsu-pipe`, off by default; [LSU](../../LSU_PIPELINE.md)); dual dispatch
behind `DISPATCH_WIDTH=2` (slices 0–6, `--dual`, default 1;
[design](../../DUAL_DISPATCH_DESIGN.md)); FPU issue-path timing (package top
with the FPU at 50 MHz); MiSTer `--fpu-compact --dual --lsu-pipe` core
timing-clean.

Priority since 2026-10-03: completion of the 603e before speed. 50 MHz stays
the gate; 66 MHz work follows the completion items.

Done (batch 10, 2026-10-03): loadable program images on MiSTer (OSD "Load
program", [MISTER_CORE.md](../../MISTER_CORE.md#loading-programs)); little-endian
mode with the misaligned-LE split (V13; [LE](../../LITTLE_ENDIAN.md)); inbound
data parity, BR negation after a foreign ARTRY, push pipelining, the two-CPU
bench `test-chip-mp` and HID0 ILOCK
([chip verification](../../CHIP_PACKAGE_VERIFICATION.md)); CI enabled
([CI.md](../../CI.md)); relicense to GPL-2.0-or-later.

Done (batch 11, 2026-10-04): dual dispatch slice 7, a folded branch in DQ1
beside DQ0 work, with `bclr`/`bcctr` folding
([design](../../DUAL_DISPATCH_DESIGN.md#slice-7)); FP loads and stores
through the LSU unit, loads at Table 6-6 2:1
([LSU](../../LSU_PIPELINE.md#fp-accesses)). Branches without a CQ entry are
deferred.

Done (batch 13, 2026-10-05): the batch 12–13 performance line (retire in
the writeback cycle, early redirect, load priority, 8-entry data micro-TLB,
second IU finish port and others; Dhrystone 0.89 DMIPS/MHz at width 2 with
the LSU unit, [target](../../PERFORMANCE_TARGET.md)); the LSU store queue
([LSU](../../LSU_PIPELINE.md#store-queue)); branch removal behind
`ENABLE_BRANCH_REMOVAL` (off); FP loads through the LSU; the 602/rename
timing fix; whole-machine reference lockstep at width 2 with the LSU unit,
MMU stress included; the [source reconciliation](../../references/SOURCE_RECONCILIATION.md)
and [manual inventory](../../references/MANUAL_INVENTORY.md) (AUD-75 to
AUD-86). 66 MHz regressed: every top misses by −3.3 to −5.5 ns on
`0ff3a45` (−0.45 ns on `6cb15bb`). The MiSTer test core does not route.

Done (batch 14, 2026-10-06): manual-mismatch fixes AUD-75 (SMI with TGPR),
AUD-77 (burst-read snoop flush), AUD-79 (IBATs have no G bit), AUD-81 (IFEM on
cached fetches) and AUD-83 (soft reset clears ICE).

Done (batch 15–16, 2026-10-06): PVR 0x00070200 (AUD-76); HID0[IFEM] on
single-beat fetches (AUD-81); MCP and SRESET preempt a faulting instruction
(AUD-84); DBDIS and CSE checks (AUD-85); 603 checkstop sources and the
fetch-TEA refetch (AUD-86); 602 injected snoops (AUD-82); 32-bit data bus and
reduced pinout (AUD-80); EC603e `fsqrt` takes FP unavailable (AUD-87); an FPU
semantics review (AUD-88/89 recorded); metadata and five-variant legality for
all 226 Appendix A rows; the MiSTer test core at 45 MHz (`--sys-mhz`; 45 MHz
is the floor, 66 MHz the target). All five tops meet 50 MHz; 66 MHz misses by
−3.3 to −4.6 ns on `6b073fc`.

In progress on branches: Doom and Quake timedemos (`doom-timedemo`,
`quake-timedemo`, `quake-le-asm`).

Timing priority, 2026-10-13: the requested full MiSTer 66 MHz fit passed
synthesis but failed routing at 96% ALM utilization, before TimeQuest.
[The review](../../FMAX_66_REVIEW.md) identifies instruction-queue storage,
completion/rename metadata and hold-delay routing as the next targets. The
focused checks pass; no higher-clock release or frequency gain is accepted.
The [architecture audit](../../DESIGN_REVIEW_2026-10-13.md) adds LSU payload,
dispatch lookahead and repeated FP classification concerns. The [IQ/rename
candidate review](../../IQ_RENAME_REVIEW_2026-10-13.md) records passing checks
but increased synthesis logic; both RTL candidates were reverted, with their
stronger tests retained.
The following [payload/metadata pass](../../PAYLOAD_WIDTH_REVIEW_2026-10-13.md)
reduced whole-board synthesis logic by 595 ALUTs and 294 registers, with
passing decode, exact-cycle, LSU/FP/cache and 602 checks.
The CQ pass saves another 332 synthesis ALUTs (927 combined). The following
normal-effort full-board fit still failed routing at an estimated 38,853 ALMs
(93%), before timing analysis. Retain the smaller, verified implementation;
continue matched [CPU/FPU isolation](../../FIT_ISOLATION_2026-10-13.md). The fresh
CPU-only fit routes but misses 66 MHz by 15.205 ns: SRU result/CR forwarding
through branch folding, instruction translation and I-cache response enable.
Address that CPU/frontend cone without restoring the extra fetch/decode cycle
removed for manual accuracy. The [CPU control-path pass](../../CPU_CONTROL_PATH_REVIEW_2026-10-13.md)
specializes the SRU statically, computes targets before late selection, and
projects the requested CR bit. Strict lint, unchanged exact-cycle/branch/recovery
checks and four translated held-CR request cases pass. The matched CPU-only fit
improves restricted Fmax from 32.94 to 36.07 MHz and saves 213 fitted ALMs,
with all hold corners passing. Setup still misses 66 MHz by 12.572 ns. The new
path runs from the primary IU shift result through CR, speculative-branch
resolution, translation and the I-cache response enable; continue there. Backend BI-bit projection now passes the same
lint, spec, exact-cycle and branch/recovery checks. Cache metadata/response
captures pass old/new equivalence at all supported geometries and the retained
cache/bus/managed tests. Derived shift/rotate record masks pass full/restricted
unit equivalence and all four retained oracle profiles, exact-cycle/branch and
translated-cache integration gates. These changes preserve the existing
issue/fetch cycles. The matched CPU-only fit improves 36.07 to 38.31 MHz,
with positive holds and 347 additional ALMs; setup still misses 66 MHz by
10.952 ns. The completed detailed report now places exception redirect,
cancellation, immediate completion/retirement and rename reconstruction on the
worst path. The recovery pass preserves precise faults, generation checks and
same-edge retirement, fixes a killed CQ1 fresh/stored-pair retirement corner,
and improves the matched CPU-only fit to 39.23 MHz (23,183 ALMs), with all
hold corners passing and zero unconstrained paths. Setup still misses 66 MHz
by 10.342 ns. The new worst path is IU forwarding → LSU address → data
translation → cache acceptance → tag/state lookup. Shorten late acceptance
before the metadata read, and the secondary instruction-decode → dispatch
late-wake capture path, without changing any verified cycle boundary.
The next station/cache/writer batch preserves focused accuracy gates but
fits at 38.95 MHz (23,333 ALMs), below the 39.23 MHz best. All holds and
constraint coverage pass; worst setup is -10.522 ns. Its detailed report now prioritizes recovery→special-result ownership→rename
forwarding→alignment→incoming LSU base wake/trap capture. Separate identity and
trap calculation from late qualification, preserving exact accepted ownership;
evaluate component retention before claiming any new timing gain.
The raw incoming-base selection and CNTLZW record-only MSB predicate now pass
focused independent/core gates, including required renamed-base DQ1 coverage,
all count/control values and unchanged stage/branch/cache edges. A matched
66 MHz CPU-only fit completed at 36.54 MHz, below the 39.23 MHz best. Holds and
constraint coverage pass, but the combined timing candidate was rejected.
Both functional changes are now reverted (50 RTL source hashes match the
station/cache/writer predecessor), and the independent tests remain. The next
experiment targets the measured checkstop→router payload→dispatch→late PC
increment path. Paired-router reset/response checks and fresh chip/core gates
pass for reset-independent payload, parallel stop-resume sums and captured
CTR-release targets. A new mandatory AA/outcome/stopped-lane matrix covers all
eight width-two bins; public traces and existing manual-backed cycles match
baseline exactly. The serialized CPU-only 66 MHz fit completes at 39.13 MHz
(23,303 ALMs), gaining 0.18 MHz over its 38.95 MHz predecessor but remaining
0.10 MHz below the 39.23 MHz best. All holds pass and unconstrained paths are
zero. The reset/CTR-target route is absent from the top 20; the new worst
path is special-result/CQ wake identity→rename readiness→incoming LSU
EA/trap capture (24.993 ns, 19 levels, 71% wire delay). Validate parallel
incoming trap predicates and earlier owner-identity projection next, retaining
exact fault qualification, full EA, queued wake behavior and verified cycles.
The frontend batch was provisional at this point. The subsequent batch also
fixes a pre-existing generation-wrap bug: an invalid wake0 alias could override
valid wake1 and offer the wrong queued-load address. Valid-qualified selection
passes `test-core-lsu-wake-wrap` with the required alias and six controls,
without adding a cycle. Fresh manual-backed LSU, 602/FP, cache, dual-dispatch,
branch/reset/chip and recovery/coherence gates pass. Its fit reaches a new best
of 39.82 MHz at the limiting slow -40 C corner (40.11 MHz at slow 100 C), with
all holds passing and zero unconstrained paths. The 66 MHz target remains unmet.

That fit's 24-level worst path runs through CQ recovery/pivot, LSU address and
translation, then store-queue movement/classification. The next live trial
compares pivot generations at fixed slots and classifies existing/incoming SQ
entries before movement, preserving same-edge kill/commit/error and every
physical slot. Private SQ comparison and its canonical independent oracle pass;
the CQ four-state semantic proof passes. Broad integration now passes with unchanged manual-backed cycles and wrap
coverage; its matched fit completes at 39.70 MHz, below the 39.82 MHz corrected-source
best, with all holds passing and no unconstrained paths. It remains provisional.
Detailed paths now end in LSU P1 capture: frontend/CR eligibility into EA at
slow 100 C, and recovery/address/translation readiness into data at slow -40 C.
SQ and SRU endpoints are absent from both slow-corner top twenties. The private
SRU lane-capture comparison passes but is deferred. An isolated preservation
attribute on the existing two head-address sums yields exactly the same 39.70 MHz
timing/resources and is removed. P1 classification before movement now passes
both private temporal profiles and 263,680 four-state composition cases,
preserving simultaneous advance/base-wake priority. Its permanent public oracle
passes split EA wrap, incoming alignment/cancellation and late operands. It is
provisionally adopted with primary-word CR eligibility (five-profile semantic
proof, independent decoded-predicate assertion). Broad core integration passes
with unchanged manual timing, wrap, recovery, cache, FP-memory and held-CR
counts; its matched fit reaches 39.55 MHz, not a gain. New worst endpoints are
IQ payload movement and I-cache response-way capture. The core CR helper is
removed byte-exactly; P1 alone reaches 39.75 MHz (39.85 MHz at the other slow
corner), still below the corrected-source best and using more logic. P1,
SQ classification and fixed CQ pivot are removed, restoring all applicable
archived CPU RTL files byte-exactly to the 39.82 MHz source. Their focused
regression coverage is retained. Astra finds no correctness blocker, but the core CR
projection's decode-once maintenance exception is not retained without a gain.
A package-owned alternative is prepared privately, unbuilt. The next live
experiment removed redundant fetch-lookahead dependence from IU/SRU station
readiness, sharing one eligibility predicate and preserving unknown-state
behavior. Optional `test-iu-station-readiness` passes 256 binary and 65,536
four-state source-extracted expression comparisons. Focused core integration
passed with unchanged branch, CTR, dual dispatch, LSU timing, owner-wrap,
FP-memory and recovery counts. Its fit reaches only 38.64 MHz (38.74 MHz at
the other slow corner), so it is removed back to the exact 39.82 MHz CPU
source. Its candidate-specific optional proof target is also removed.
The next provisional live batch cuts router miss arbitration and main-IU
input selection. The router's strict old/new comparison passes both data
pipeline settings with all public outputs matching each edge; canonical
four-state expression targets also pass. Strict lint/specification and
production router/core gates pass with unchanged verified cycles, owner-wrap
and exception counts. Its matched CPU-only fit reaches 39.33 MHz (39.38 MHz at the other slow
corner), below the 39.82 MHz best, so router/core hardware changes and their
optional expression targets are removed. The truthful dispatch comment is
retained. The next candidate projects D-uTLB page matches before late address
selection: private four/eight-entry leaf temporal and four-state checks pass;
Astra layout review finds no source-level blocker. The typed interface is
provisionally integrated with coherent assembly enable and lower defaults off.
Fresh typed-leaf and 131,072 source-composition cases pass, as do strict lint
and specification checks. Full-core enabled/disabled gates pass with the same 105,303 checks and
12,112 cycles; manual/wrap counts remain unchanged. The private held-OFFER
comparison also passes both pipeline settings with exact public-output and
independent payload checks. The matched CPU-only fit completes at **40.66 MHz**
at the limiting slow -40 C corner (40.69 MHz at slow 100 C), improving the
39.82 MHz predecessor. Hold checks pass and all unconstrained categories are
zero; 23,725 ALMs, 18,515 registers, 42 M10Ks and two DSPs are fitted.
Projection is retained provisionally; this is not 66 MHz or board closure.
All 80 reported detailed setup paths traverse `fd_next_iu` and `c0_sru`.
Prepared SQ overlap and isolated IQ fixed-pop fits are deferred: IQ alone
leaves a station path with an approximately 40.82 MHz unchanged-delay ceiling.
The next private proposal stores instruction classification atomically in
I-cache rows and carries it through existing fetch/FD boundaries, preserving
all scalar/refill/fault provenance, four-state behavior and manual cycles.
Implementation and physical measurement of that proposal remain pending.
The 39.82 MHz result measures the SQ/pivot trial's predecessor. The separate rename
readiness proposal passes private RTL differential and four-state semantic
checks but remains unadopted and unfitted. Full CI, X-randomization and reference
release acceptance remain pending for the final batch. A separate false GPR overlap-hazard proposal is private and
requires older-load fault/branch-shadow acceptance before adoption.
Parallel read-only fetch/translation/
tag probes remain a prepared candidate for the former branch path; they have
not passed integrated simulation or a fit. Further FPU optimization is deferred at the user's request. A controlled board fit with aggressive routability
optimization remains a physical experiment after the critical-path work. The architecture
audit found CPU-domain hold insertion and local congestion, without establishing
a missing-clock cause. Preserve 66 MHz, seed 2, normal router effort and the
existing setup/hold constraints for that experiment. No higher-clock release or
manual timing relaxation is accepted.

Before further timing changes, upstream synchronization is integrated on
`codex/integrate-upstream-20261014` at `22eb2b0`, including nine remote commits
through `e5cddb9`. The 40.66 MHz checkpoint is preserved at `9a68a26`.
Combined lint/spec, fetch/cache/recovery/owner-wrap and verified-cycle gates
pass, including the production mixed GPR RAM-copy profile. Its fresh capped
CPU-only fit completes at 40.12 MHz limiting (40.74 MHz at the other slow
corner), saving 1,768 ALMs and 2,567 registers but giving no clock gain over
the saved predecessor. Holds pass; unconstrained categories are zero.
The subsequent isolated direct branch/needs-IU projection at `bea975a`
passes source-extracted four-state and focused core/manual-cycle gates. Its
fresh matched CPU-only fit measures 40.99 MHz limiting, with 281 fewer ALMs
and 155 fewer registers than the integrated baseline, passing holds and zero
unconstrained categories. No fetched-word classification, predecode or
`fd_next_iu` appears on its 80 reported detailed setup paths. The new hot
limit is selected-producer/rename value-forwarding membership into LSU P1;
the cold limit is CR/branch validity into station capture. The early output
consumes value only, so fixed-slot readiness is secondary. Raw-producer owner
comparison before selection is the next hot-path experiment, preserving tag,
offer, late, payload priority and four-state fallback. CNTLZW record
qualification is a separate cold-path candidate. SQ overlap and cache metadata transport
are deferred; neither appears on the new measured path set. Full CI,
initialization-randomized, FPU and reference release acceptance remain
pending on the merged batch; 66 MHz remains open. See
[the integration record](../../UPSTREAM_INTEGRATION_2026-10-14.md),
[measured control-path evidence](../../CPU_CONTROL_PATH_REVIEW_2026-10-13.md)
and [the source-only architecture review](../../CPU_ARCHITECTURE_REVIEW_2026-10-14.md).

Queued, in order:

1. Land the pending branches: `aud90c` (fetch stops, P12 checks),
   `fpu-timing`, `le-reference` (DingusPPC little-endian comparison),
   `bus-followups`.
2. Defaults: width 2, the LSU unit and branch removal on, two-word fetch
   through the wrappers ([LSU remaining work](../../LSU_PIPELINE.md#remaining-work)).
3. Speed: recover 66 MHz (translated −4.342 ns, integrated −3.291,
   timer-bat −4.591, chip −4.361, chip602 −4.040 on `6b073fc`), then width
   2, the LSU unit and the FPU at 66 MHz; Dhrystone 1:1 with the 603e
   (641 cycles/run against the model's 506); a single-precision Mandelbrot.
4. FPU silicon-semantics gaps (AUD-88/89, [assessment](../../FPU_REUSE_ASSESSMENT.md)),
   FULL FPU in the MiSTer core (reduce area or keep COMPACT).
5. Verification: P12 per-row latencies and the chapter 6 worked-schedule
   replays (the trace-visible dispatch rules are checked) and the
   open manual inventory rows ([audit](../../AUDIT.md)).

After each accepted implementation round, update the scorecard's affected rows
and record fresh versus inherited checks. Refresh this plan when priorities or
acceptance gates change. Superseded progress snapshots, the agent work queue and
implemented slice proposals are retained under [stale plans](../stale/README.md)
as history, not as current instructions.
