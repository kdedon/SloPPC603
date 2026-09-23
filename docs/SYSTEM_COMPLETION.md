# System completion scorecard

Updated: 2026-09-23. Scope: single-issue, big-endian integer CPU with supervisor
mode, resumable exceptions, external/decrementer interrupts, CPU-managed BAT
and page translation, and an integrated cache/60x path. FPGA acceptance also
requires reviewed constraints and passing setup/hold. Board bring-up is excluded.

This is the current status index. Feature contracts linked below control exact
behavior; [MVP_EXECUTION_PLAN.md](plans/stale/MVP_EXECUTION_PLAN.md) preserves implementation
history. Earlier inventory and round-40 percentages are historical snapshots.

## How to read the estimates

Percentages are engineering judgments about accepted scope, not measured code
coverage, elapsed effort, a probability of success, or a time-remaining ratio.
Weights represent the chosen MVP delivery scope and total 100. A working
standalone component earns partial credit; integration, adverse cases and
acceptance evidence are still required. The aggregate is `sum(weight × completion)
/ 100`, rounded to a whole percent. Keep weights fixed between rounds unless the
user changes scope. Treat small score changes as bookkeeping, not velocity.

**MVP estimate: about 81% complete (weighted 80.8%; planning range 60–85%).** The
remaining work is concentrated in MMU replacement and exception completeness,
broader combined-system stress, architectural maintenance and timing closure. These are
hard acceptance blockers regardless of the weighted score. Final FPGA acceptance
is currently unmet.

## MVP systems

| System | Weight | Complete | Accepted capability | Gaps and deliberate shortcuts |
| --- | ---: | ---: | --- | --- |
| Fetch and dispatch | 4% | 90% | Buffered fetch, precise supported fetch faults, drain/refetch on live context and events | One outstanding instruction request with reserved queue capacity; single dispatch; additional reset/interleaving stress open. |
| Integer execution, multiply/divide, GPR/CR/XER | 9% | 85% | Broad scalar arithmetic/Boolean/rotate/shift/compare corpus, tagged flags, iterative divide, compiled integer firmware | Explicit XER access now supports state saving; compiler/ISA subset remains explicit; multiply latency counter does not establish a pipelined product datapath. |
| Rename, completion and recovery | 7% | 85% | Tagged dependencies, ordered retirement, retained-prefix recovery, precise supported events | Five rename slots/CQ entries; finite generation-token lifetime contract; recovery timing and unsupported diagnostic ownership remain bounded policies. |
| Branches and control flow | 4% | 90% | Direct/conditional/LR/CTR branches, handler entry and RFI | Serialized companion lane; prediction, folding and dual issue excluded; Broader event/control-flow collisions on the combined path remain open. |
| Load/store and memory ordering | 7% | 75% | BE scalar D/indexed/update operations, ordered stores, load cancellation/drain, alignment faults and resumable BAT and page protection DSI; denied accesses suppress destination/base/memory effects | Serialized aligned subset; supported page misses now enter refill handlers; transport errors remain diagnostic; no atomics/string/multiple forms. |
| Supervisor state and synchronous exceptions | 8% | 75% | SC/RFI, live MTMSR/MFMSR, selected SPRs, program/alignment/supported ISI and BAT/page protection DSI; DAR/DSISR capture and handler repair/retry | Supported MSR mask only; remaining DSI causes or complete platform/debug exception set. |
| External interrupts and TB/DEC | 7% | 85% | EE masks, precise resume PC, admitted EXT latching, TB64/DEC32, priority and retirement-only writes; translated cached IRQ/refill drain, DEC-to-EXT promotion and RFI hits | Synchronous pins/tick; no CDC or bus-clock divider; local bounded event-recognition policy; eight direct-core entry-reset scenarios pass, while collision/physical reset coverage remains open. |
| BAT translation and live context | 10% | 85% | CPU-owned privileged BAT SPR reads/writes, retirement-only mapping changes, cancellation/drain, live IR/DR/PR, supported instruction/data-protection faults; compiled mapping replacement with pending EXT/DEC | Abstract, scalar 60x and bounded cached 60x paths accepted; final timing and broader context/cache collisions remain open. Malformed/overlapping candidates terminate diagnostically by local policy; deterministic zero reset differs from silicon. |
| Segment registers, page TLB and software refill | 14% | 90% | CPU-owned SR/SDR1/compare/RPA; TLBLD/TLBLI and TLBIE against sole I/D banks; precise PP/N/G exceptions; architectural I/load/store miss and C=0 entry with full-EA/HASH capture, TGPR, primary/secondary PTEG search, R/C writeback, PP/key checks, ordinary failed-search ISI/DSI and refill/RFI retry | LRU remains open (true misses use WAY=0); changed-bit hits retain the matched way. Software fixture is single-writer, using a halfword R/C update for stores; concurrent PTE writers and nested misses are outside its contract. Bounded SDR1/provenance checks and read-only real-mode miss SPR policy; loads require V=1/H=0 and supported RPA shape. T=1, external-management frontend coherence, broader event/reset interleavings and final timing remain open. |
| 60x physical transport | 7% | 78% | Scalar master and separate four-beat line reads; translated scalar wrapper runs real search/fault ELFs, with physical PA/byte lanes, ARTRY/DRTRY, TEA/reset checks | Scalar path fixes CI=1/WT=0/GBL=0; cached wrapper permits WIMG=0 instruction fills only. Full WIMG/coherence behavior remains open. Data errors are diagnostics, instruction errors are reset-only terminal stops; one active-address reset point covered. No full snoop/parity/timing conformance. |
| Instruction cache and maintenance | 5% | 85% | 16-KiB four-way physical cache, block-RAM data array, translated WIMG=0 fills/hits, scalar bypass, remap and explicit stale-code invalidate/restart, denied warm-line suppression and partial-fill TEA/reset | Conservative WIMG policy; no automatic code coherence or architectural cache instructions. External maintenance is not a CPU/store barrier; broader event/interleaving acceptance remains open. |
| Toolchain and reproducible builds | 4% | 90% | Pinned compiler, BE ELF loader, twenty compiled workloads plus scalar-bus and cached-bus runs of the same search/fault ELFs (TLBIE, TLB-load and page-miss profiles each have three modes), parallel-safe regression and source-hashed fit archives | Small bare-metal memory/ABI profile; no arbitrary OS/binary compatibility or release packaging claim. |
| Integration and verification | 7% | 85% | Independent directed/reference tests, 243 Python checks, CPU-owned translation over scalar 60x, runtime BAT suites and firmware negatives | Search/fault firmware now covers the combined supervisor/page-MMU/cache/bus path; no formal/collected HDL coverage/continuous CI gate; long reference acceptance remains open. |
| FPGA fit, timing and release | 7% | 35% | Current cached physical and separately timer-enabled BAT designs fit Cyclone V with archived evidence | Neither representative fit closes timing; no combined final MVP top, board I/O timing contract or release signoff. New RTL changes require fresh fit before timing claims. |

Evidence: [core recovery](CORE_RECOVERY.md), [integer ISA inventory](references/ISA_MATRIX.md),
[alignment](ALIGNMENT_VERIFICATION.md), [live context](LIVE_CONTEXT_VERIFICATION.md),
[interrupts](EXTERNAL_INTERRUPT_VERIFICATION.md), [timers](TIMER_VERIFICATION.md),
[runtime BAT acceptance](RUNTIME_BAT_VERIFICATION.md), [TLB service](TLB_SERVICE.md),
[segment bank](SEGMENT_REGISTERS.md), [CPU segment verification](CPU_SEGMENT_VERIFICATION.md), [page-hit protocol](PAGE_PATH_PROTOCOL.md),
[page verification](PAGE_PATH_VERIFICATION.md), [page firmware](PAGE_FIRMWARE.md), [CPU TLBIE](CPU_TLBIE.md),
[TLBIE verification](TLBIE_VERIFICATION.md), [compiled firmware](COMPILED_FIRMWARE_VERIFICATION.md),
[cached FPGA fit](INTEGRATED_SYNTHESIS_BASELINE.md),
[timer/BAT FPGA fit](TIMER_SYNTHESIS_BASELINE.md).
The generated ISA matrix describes its metadata profile; later live-context/timer
extensions have their own decode tests and contracts. Its form count is not the
completion denominator.

## Full-603e estimate and systems outside this MVP

**Approximately 46% of full-603e project scope (weighted 46.29%; judgment range
40–50%)** follows the [2026-09-23 weighting audit](FULL_CPU_COMPLETION_AUDIT.md).
Original category weights are preserved; broad execution, branch/LSU and memory
categories now explicitly allocate weight to unimplemented systems. This corrects
historical dual-issue over-credit while recognizing later supervisor/MMU work.
The historical round-40 score remains 39.40% in [PROGRESS.md](plans/stale/PROGRESS.md).
This is a document/evidence audit, not fresh conformance testing, and includes
source/tooling credit. It is not derived by rescaling the MVP score.


These remain part of the original full-603e ambition. Exclusion from the MVP
means no credit is silently assigned for them.

| System | Implementation estimate | Boundary |
| --- | ---: | --- |
| Dual dispatch/retirement and superscalar scheduling | 0% | Scalar tagged machinery is a foundation, not working dual issue. |
| Branch prediction and folding | 0% | Serialized branches execute without either feature. |
| Data cache, writeback and coherence | 0% | Data accesses use uncached transport; no MEI/snoop/castout system. |
| Floating point, FPR and FPSCR | 0% | Integer/soft-float software restriction; no canonical FPU. |
| Little endian, additional variants and power modes | 0% | Toolchain artifacts/source preparation do not establish executable hardware. |
| Full 603e cycle/throughput fidelity | Not separately scored | Unit latency checks exist; complete machine fidelity is unimplemented. |
| Board integration | Excluded | No pinout, clocks/CDC, external-memory controller or board demonstration acceptance. |

## Quality and delivery risks

The strongest evidence is in explicit ownership, held-request stability,
retirement-only side effects, independent expected-state oracles and negative
firmware checks. Serialization trades throughput for a tractable precise-state
contract. The largest remaining integration risk is breadth: the combined software-managed
MMU/cache/bus path runs bounded firmware, but broader event collisions, software
maintenance and hardware timing acceptance remain open.

The special lane and its optional profiles concentrate control complexity.
[CORE_STATUS_REVIEW.md](CORE_STATUS_REVIEW.md) records the independent core assessment.
Further additions need disjoint ownership, a frozen handshake contract and tests
for cancellation before commitment and irrevocability afterward. Documentation
contains historical passages; use this index and feature contracts for current
capability. No percentage here constitutes exhaustive correctness proof.

Latest fitted timer/BAT revision: 7,093 ALMs (17%), worst setup −4.939 ns,
worst hold −3.112 ns under provisional 20 ns virtual-I/O constraints. The cached
physical revision is a different configuration: 13,661 ALMs (33%), setup
−5.324 ns, hold −0.084 ns. Neither result describes a final unified MVP or a
board timing contract. Preserve those archives when newer RTL is tested.

## Remaining effort and next acceptance gates

Planning range from this baseline: **6–10 focused engineer-weeks to integrated
simulation acceptance; 8–14 to FPGA timing-checked acceptance**, assuming one
experienced RTL engineer with agent assistance, the fixed restricted scope,
available tools and no major timing redesign. Confidence is low-to-moderate;
these are effort-based planning ranges, not promises of agent wall-clock time.
The original 10–16 / 12–20 week audit forecasts remain historical.

1. Replacement policy, remaining page/data exception causes, and broader event/reset
   interleavings (roughly 1–3 weeks). Real primary/secondary software search, R/C
   writeback and failed-search conversion are now accepted in simulation.
2. Broaden the now-integrated cache/MMU/bus acceptance: interrupts and context
   changes around cache hits/refills, external-maintenance sequencing, and
   remaining instruction attributes (roughly 1–3 weeks). Keep data uncached
   and distinguish the external control contract from architectural `icbi`.
3. Fit the combined translated cached top under reviewed interface constraints,
   then close setup/hold and run broader integration stress (roughly 2–4 weeks,
   overlapping the above; redesign could extend the range). Preserve the old
   fit archives as historical configurations.

The 6–10 / 8–14 engineer-week ranges remain conservative because the combined
translated cache/bus topology has no current FPGA fit or timing result. The
software-managed MMU now runs through both scalar and cached 60x paths in
simulation. This removes a major composition uncertainty; it does not establish
final integration or shorten the timing critical path. Packages overlap and
must not simply be added or divided by agent count. Re-estimate after the first
combined fit and the broader cached event/maintenance gates.

## Update after every round

Update the date, affected rows, evidence and remaining gaps. Record old/new
scores and explain any change; accepted hardening may leave percentages unchanged.
Separate newly executed gates from inherited validation and identify which RTL
revision a fit measures. Never move an item to 100% without its integration and
acceptance gates. Keep the full-603e and MVP denominators distinct.

| Round | MVP estimate | Change and validation boundary |
| --- | ---: | --- |
| Timer wave baseline, 2026-09-21 | About 65% | First explicit MVP scorecard, reconstructed after TB/DEC acceptance; not a historical velocity series. Full gate: 172 named targets, 24 strict RTL lint profiles, 140 bench prelint profiles, 241 Python tests; six compiled workloads. |
| Bounded recovery/status round, 2026-09-21 | About 65% (unchanged) | Rename identities retained across recovery; independent focused recovery/memory/fault gates, 24 strict lint profiles and 241 Python tests passed with 142 source hashes stable. Prior 172-target full regression predates this change; no new fit. All six compiled firmware workloads rebuilt and passed; prior negative controls were not repeated. |
| XER state-saving round, 2026-09-21 | About 65% (unchanged) | SPR1 read/write and alias through precise flags retirement; 28,721 core checks, 189 CQ/flags checks, 1,213,761 decode checks, 243 Python tests and all six firmware workloads pass. See XER verification for the complete focused gate. No full regression or fit. |
| Event-entry reset round, 2026-09-21 | About 65% (unchanged) | Test-only hardening: EXT/DEC at four reset boundaries, 14,909 independent checks, fresh-boot state and event reuse; 24 lint profiles and 243 Python tests pass. All 144 focused-gate source hashes stable; production RTL unchanged. |
| Runtime BAT round, 2026-09-22 | About 68% (67.6% weighted) | BAT/live context rises from 60% to 85%; other system scores unchanged. Five new suites and four runtime lint profiles pass, plus seven compiled workloads and two negative controls. Full legacy regression, 28 combined lint profiles and 243 Python checks pass; 233 final input hashes remain stable. No new FPGA fit. |
| DSI protection round, 2026-09-22 | About 69% (69.1% weighted) | Load/store and supervisor scores each rise from 65% to 75%; other scores unchanged. Full regression and separately added live-context cancellation target pass, with 243 Python checks, eight firmware workloads and a syndrome negative control. Production RTL stayed stable during the gate; no new FPGA fit. |
| CPU segment-register round, 2026-09-22 | About 71% (70.5% weighted) | Segment/page/refill rises from 25% to 35%; all other scores unchanged. Five new suites, three additional integration lint profiles, full legacy regression, 243 Python checks, nine firmware workloads and a readback negative control pass. Segment descriptors still do not drive page translation. No new FPGA fit. |
| Prefilled page-hit round, 2026-09-22 | About 72% (71.9% weighted) | Segment/page/refill rises from 35% to 45%; all other scores unchanged. Clean broad regression plus the separately finalized router suite, 159 bench lint profiles, 243 Python checks, ten firmware workloads and an instruction-page negative control pass. External TLB preload remains a deliberate shortcut; no CPU software refill or new FPGA fit. |
| CPU TLBIE round, 2026-09-22 | About 73% (72.6% weighted) | Segment/page/refill rises from 45% to 50%; other scores unchanged. Decode, lifecycle, privilege/default-off, service and router suites pass, along with broad regression, 243 Python checks and eleven firmware workloads. Three compiled TLBIE modes verify I/D invalidation and retained neighbors; wrong-set negative is rejected. No CPU refill or new FPGA fit. |
| Requested three-round sequence: round 1, prepared refill, 2026-09-22 | Unchanged: 72.6% weighted | Opt-in kind-5 normalized refill now prepares without mutation and commits captured bank/set/way/entry atomically. Four feature combinations, legacy corpus, page/invalidate integration and a live-input mutation negative pass. This service foundation does not yet expose CPU TLB loads, so system percentages remain unchanged. |
| Requested three-round sequence: round 2, seed registers, 2026-09-23 | About 73% (72.9% weighted) | Segment/page/refill 50% → 52%. DCMP/ICMP/RPA now support full-width committed CPU reads/writes, privilege enforcement and cancellation. 2,062 decode, 1,417 enabled-core and 88 disabled-core checks pass, with neighboring supervisor/context/XER/TLBIE/SR regressions. CPU TLB loads and automatic miss state are still absent at this acceptance point. |
| Requested three-round sequence: round 3, CPU TLB loads, 2026-09-23 | About 74% (74.0% weighted) | Segment/page/refill 52% → 60%; other system percentages unchanged. Privileged real-mode TLBLD/TLBLI capture CPU seed state and commit prepared entries at retirement, with cancellation/error drain. Full regression, 177 strict test configurations, 243 Python checks, twelve compiled workloads and missing-load negative pass. No fixture preloading in the CPU-load workload; no architectural miss handler or new FPGA fit. |

Recovery round details: [recovery metadata verification](RECOVERY_METADATA_VERIFICATION.md).
The score is unchanged because this hardening adds no new architectural capability.

XER state-saving follow-up: explicit SPR 1 access now uses the committed flag
owner, with byte-count preservation, user-mode access and the 603e read alias.
[XER_ACCESS.md](XER_ACCESS.md) records the contract; [XER_VERIFICATION.md](XER_VERIFICATION.md)
records focused validation. The expanded timer firmware passes 436 retirements /
4,494 cycles, the other five workloads pass unchanged, and a corrupted XER
expectation fails through the mailbox. No new full regression or fit was run.
The score remains about 65% because this small state-save addition does not
materially change the broader integration estimate. Runtime BAT/page-MMU and
timing work remain open.

Event-entry reset follow-up: [reset contract](EVENT_RESET_CONTRACT.md) and
[verification](EVENT_RESET_VERIFICATION.md) record eight direct-core scenarios.
The postreset stream checks nine register reads, eight quiet retirements after
EE enable and one fresh event per scenario. Context offers require an explicit
modeled instruction/event obligation; delayed accepted fetch responses are
canceled by the reset-aware fixture. No existing physical store is rolled back.
This is verification progress, so system percentages and the remaining-effort
forecast stay unchanged. Production RTL and prior firmware evidence are unchanged;
no full regression, compiler rebuild or FPGA fit was repeated.

The reset negative control omits only DEC pending clearing in a temporary timer
copy. The real oracle rejects the stale postreset event at cycle 71, rather than
timing out. The production timer is unchanged.


Runtime BAT follow-up: [protocol](RUNTIME_BAT_PROTOCOL.md),
[focused verification](RUNTIME_BAT_VERIFICATION.md) and
[compiled firmware evidence](RUNTIME_BAT_FIRMWARE.md) define the accepted slice.
The service owns one committed bank and one private proposal; only accepted
retirement changes the mapping. Killed requests drain before reuse, while
retained recovery targets survive delayed acknowledgment. No broader page-MMU,
DSI, cache-coherency, transport or timing claim is implied.


DSI protection follow-up: [contract](DATA_EXCEPTIONS.md),
[verification](DATA_EXCEPTION_VERIFICATION.md) and
[compiled firmware](DATA_EXCEPTION_FIRMWARE.md) record the accepted behavior.
Typed BAT PP denials save fault state only at retirement; skipped loads/stores
suppress writes, and a handler can repair permission and retry. Faulted loads
retain allocation ownership for release even after write permission clears.
Physical errors, BAT misses and unknown typed causes retain ordered diagnostics.
The remaining effort range stays at 6–10 focused engineer-weeks for integrated
simulation and 8–14 for timing-checked FPGA acceptance; page refill and combined
physical integration still dominate the uncertainty.


CPU segment-register follow-up: [CPU contract](CPU_SEGMENT_REGISTERS.md),
[verification](CPU_SEGMENT_VERIFICATION.md) and
[compiled firmware](SEGMENT_FIRMWARE.md) record the accepted management slice.
Writes remain private until retirement; canceled requests drain without changing
the bank. Direct/indexed forms, privilege, aliases, GPR0, pending events and
retained recovery targets are tested. The 10-point subsystem increase adds
1.4 weighted percentage points; it does not imply software page refill works.
The next proposed boundary is [page-hit routing](plans/stale/PAGE_PATH_NEXT_SLICE.md).
Remaining effort stays at 6–10 / 8–14 focused engineer-weeks because page refill
and combined timing dominate uncertainty. All 260 final acceptance input hashes
remained stable; the full legacy gate and separately added five-test gate both
passed. Production RTL stayed fixed during validation.


Prefilled page-hit follow-up: [protocol](PAGE_PATH_PROTOCOL.md),
[router verification](PAGE_PATH_VERIFICATION.md),
[actual-core verification](CORE_PAGE_VERIFICATION.md) and
[compiled workload](PAGE_FIRMWARE.md) define the accepted scope. CPU fetch/data
requests now use committed SR context and prefilled TLB entries after clean BAT
misses. Management is an external normalized control interface; full CPU-managed
refill and architectural page fault/miss handling still block the MVP. This
adds 1.4 weighted percentage points. The remaining effort estimate stays at
6–10 focused engineer-weeks for integrated simulation and 8–14 for timing-checked
FPGA acceptance. A first regression attempt was rejected by its source-freeze
guard; the subsequent clean broad run and separate final router target passed.


CPU TLBIE follow-up: [contract](CPU_TLBIE.md),
[protocol](TLB_INVALIDATE_PROTOCOL.md), [verification](TLBIE_VERIFICATION.md)
and [compiled evidence](TLBIE_FIRMWARE.md) record retirement-owned indexed
invalidation. A proposal does not mutate entries; commit clears both ways in
both banks at the selected set, while abort drains without mutation. This adds
0.7 weighted percentage points. The next dependencies are
[precise miss state and CPU TLB loads](TLB_REFILL_DEPENDENCIES.md). Remaining
effort stays at 6–10 focused engineer-weeks for simulation and 8–14 for timing-
checked FPGA acceptance; no CPU-serviced page miss or unified fit is claimed.

Three-round sequence, round 1 accepted: [prepared refill contract](TLB_PREPARED_REFILL.md)
and [verification](TLB_PREPARED_REFILL_VERIFICATION.md). Segment/page/refill
remains 50%; all other scores and timeline estimates remain unchanged.

Three-round sequence, round 2 accepted: [seed state](CPU_TLB_SEED_STATE.md) and
[verification](CPU_TLB_SEED_VERIFICATION.md). Weighted completion is 72.88%,
reported as 72.9%; segment/page/refill is 52%. The three writable seed SPRs
do not implement automatic miss-state capture, TGPR or handler retry. Remaining
effort estimates stay unchanged.

Three-round sequence complete: [CPU load contract](CPU_TLB_LOAD.md),
[router protocol](TLB_LOAD_PROTOCOL.md), [verification](TLB_LOAD_VERIFICATION.md)
and [compiled evidence](TLB_LOAD_FIRMWARE.md). Weighted completion is now 74.0%;
segment/page/refill is 60%, other system scores unchanged. The twelve compiled
workloads pass, with three modes each for TLBIE and CPU loads. Next is precise
architectural miss handling, including resolution of the documented manual
conflicts and firmware/vector overlap. The 6–10 / 8–14 engineer-week planning
ranges remain unchanged until a CPU-serviced miss and combined fit reduce the
main uncertainties. No fit was run in these three rounds.

## Page-exception sequence: round 1 accepted, 2026-09-23

Opt-in page PP denial now reuses the precise DSI response and retirement path.
The CPU repairs denied update loads and stores with TLBLD and retries through
RFI; canceled denials do not install DAR/DSISR or write destinations. See
[contract](PAGE_DATA_EXCEPTIONS.md), [independent checks](PAGE_DATA_EXCEPTION_VERIFICATION.md)
and [compiled evidence](PAGE_DSI_FIRMWARE.md). Removing the handler repair is
rejected by the compiled test. Other page causes remain diagnostic.

Segment/page/refill moves 60% → 63%; weighted completion moves 74.0% → 74.42%
(74.4% reported). Other system scores and the 6–10 / 8–14 engineer-week effort
ranges stay unchanged. The broad judgment range is now 60–80%; its wider upper
bound avoids implying precision beyond the weighted estimate. No new FPGA fit.

## Page-exception sequence: round 2 accepted, 2026-09-23

Opt-in page instruction faults now reuse the precise ISI path: PP maps to SRR1
protection, while segment N and PTE G map to the shared no-execute/guarded bit.
N works before TLB lookup. Held and canceled responses retain their exact
request ownership. The compiled workload repairs PP/G via TLBLI and N via
MTSR, then retries all three with RFI; omitting the first TLBLI repair is
rejected. See [contract](PAGE_INSTRUCTION_EXCEPTIONS.md),
[independent checks](PAGE_INSTRUCTION_EXCEPTION_VERIFICATION.md) and
[compiled evidence](PAGE_ISI_FIRMWARE.md).

Segment/page/refill moves 63% → 66%; weighted completion moves 74.42% → 74.84%
(74.8% reported). Other scores and effort ranges remain unchanged. This is
protection/no-execute recovery; automatic miss handlers and TGPR remain open.

## Page-exception sequence: round 3 accepted, 2026-09-23

The optional miss-result path now retains exact EA, committed SR, PR/IR/DR and
access direction through the matching response and diagnostic retirement.
Instruction misses, data misses and resident C=0 stores are distinct; canceled
responses cannot install metadata or architectural state. Fifteen compiled
profiles pass, including three CPU-installed instruction/load/store miss modes.
An isolated wrong-SR mutation is rejected. See [contract](PAGE_MISS_RESULTS.md),
[core ownership](PAGE_MISS_CORE.md), [independent verification](PAGE_MISS_RESULT_VERIFICATION.md)
and [compiled evidence](PAGE_MISS_FIRMWARE.md).

Segment/page/refill moves 66% → 68%; weighted completion moves 74.84% → 75.12%
(75.1% reported). Across these three rounds the overall increase is 1.12
percentage points. Other system scores stay fixed, avoiding double-credit for
page integration in the fetch, LSU and supervisor rows. The scorecard was
updated after each accepted round.

The full regression passes all 187 registered simulation configurations and
243 Python checks. Strict lint passes those test configurations, 39 standalone
profiles and the combined enabled wrapper. Production RTL hashes stayed
unchanged through acceptance. No automatic miss entry, TGPR, HASH/IMISS/DMISS
state, PTE table search or miss retry is claimed. The remaining planning ranges
stay 6–10 focused engineer-weeks for simulation acceptance and 8–14 for a
timing-checked FPGA result; no new fit or timing-closure result was produced.

## Miss-entry sequence: round 1 accepted, 2026-09-23

CPU-owned SDR1 now supports privileged reads and retirement-owned real-mode
writes with drain/refetch, cancellation and retained recovery targets. A pure
miss/hash derivation unit validates the supported SDR1 shape and computes both
PTEG addresses; it is not yet connected to architectural miss entry.

Independent checks pass: decode 705, enabled core 1,303, disabled core 43 and
derivation 1,034. Compiled SDR1 firmware passes 51 retirements in 564 cycles;
omitting its first SDR1 write is rejected at cycle 287. Existing live-context
and CPU TLB-load gates pass. See [SDR1](CPU_SDR1.md),
[verification](SDR1_VERIFICATION.md), [hash derivation](MISS_DERIVATION.md) and
[compiled evidence](SDR1_FIRMWARE.md).

Segment/page/refill moves 68% → 70%; weighted completion 75.12% → 75.40%.
Other scores and the 6–10 / 8–14 engineer-week estimates stay unchanged.
TGPR, architectural miss entry and handler table search remain open. No new
FPGA fit or timing claim.

## Miss-entry sequence: round 2 accepted, 2026-09-23

The opt-in TGPR bank preserves normal r0–r3 across serialized MTMSR/RFI
transitions. RFI clears TGPR even when SRR1.WAY is set. Direct bank tests pass
33 checks in each enabled/disabled profile; actual-core tests pass 1,305/36,
including held/canceled transitions, invalid modes and recovery ownership.
Compiled firmware passes 109 retirements in 1,078 cycles; omitting its first
bank switch is rejected at cycle 709. Live-context and SDR1 preservation
gates also pass. See [CPU contract](CPU_TGPR.md), [bank contract](TGPR_REGISTER_FILE.md),
[verification](TGPR_VERIFICATION.md) and [compiled evidence](TGPR_FIRMWARE.md).

Segment/page/refill moves 70% → 73%; weighted completion 75.40% → 75.82%
(75.8%). Other scores and effort ranges remain fixed. Automatic miss entry,
handler table search and translated cache/bus integration remain open. No
new FPGA fit. This bank foundation does not claim hardware miss recovery.

## Miss-entry sequence: round 3 accepted, 2026-09-23

Well-formed instruction, data-load and data-store misses (including C=0
stores) now enter the three architectural miss vectors at matching retirement.
Entry atomically captures IMISS/DMISS, ICMP/DCMP and HASH1/2, saves CR0/key/type
in SRR1, and selects TGPR. CPU handlers fill the sole TLB banks and RFI retries
the access. Tested C=0 repair uses way 0; a resident way-1 entry needs
software way selection or indexed invalidation. Invalid context/SDR1 and disabled features remain diagnostics.
Cancellation cannot install miss state. The compiled workload caught and
verified a fix for a post-entry data/fetch drain reservation.

All twenty compiled workloads pass, including the new four-event handler
(675 retirements, 7,458 cycles). Omitting its TLBLI is rejected at cycle 3,280.
The final SDR1 image includes required pre-write SYNC barriers and passes
55 retirements/598 cycles; its omitted-write negative fails at cycle 293.
Independent boundary tests are documented in [TLB_MISS_VERIFICATION.md](TLB_MISS_VERIFICATION.md);
the standalone exception unit passes 175 enabled and 131 disabled checks.
The full regression passes 199 registered simulation configurations and
243 Python checks. All 43 standalone lint profiles and both existing
measurement wrappers pass strict lint. Production RTL stayed unchanged
through the final acceptance gates.

Segment/page/refill moves 73% → 80%; weighted completion 75.82% → 76.80%.
Across this three-round sequence the increase is 1.68 percentage points from
75.12%. The scorecard was updated at each acceptance point. Other system
scores stay fixed to avoid counting the same integration work twice.

This is software-seeded handler retry, not page-table search: PTEG lookup,
R/C writeback, failed-search exception conversion and replacement policy
remain open. Translated cache/60x integration, remaining exceptions and
setup/hold closure are still MVP blockers. No new FPGA fit was run. Remaining
estimates stay 6–10 focused engineer-weeks for simulation acceptance and
8–14 for a timing-checked FPGA result. See [CPU contract](CPU_TLB_MISS.md),
[exception state](EXCEPTION_TLB_MISS.md) and [compiled evidence](MISS_ENTRY_FIRMWARE.md).

## Table-search sequence: round 1 accepted, 2026-09-23

The response capsule now retains the matched TLB way for a clean C=0 store.
SRR1.WAY uses that captured value; true misses still select way 0 and reject
forged nonzero way metadata. Compiled refill/retry passes in both resident
ways (684 retirements, 7,503 cycles each). Independent core checks pass
3,316 enabled / 336 disabled; router checks pass 181 / 161. All 199 strict
simulation lint configurations pass. Ordered stores retain their existing
irrevocable boundary after offer; cancellation before offer has no effects.

Segment/page/refill moves 80% → 82%; weighted completion 76.80% → 77.08%.
LRU remains open. A source audit found an earlier miss-address truncation
error: IMISS/DMISS must retain full EA, not clear the low 12 bits. Round 2
will correct this before the software table-search and failed-search gates.
The overall effort ranges remain 6–10 / 8–14 engineer-weeks; no new fit.

## Table-search sequence: round 2 accepted, 2026-09-23

IMISS and DMISS now retain the full faulting effective address. The LSU supplies
its original EA for DMISS, retaining byte offsets omitted from the word-aligned
router capsule. Direct core tests pass 3,581 enabled / 336 disabled checks,
including byte-update retry; pure derivation passes 1,035 checks.

The CPU now searches primary and secondary eight-entry PTEGs, rejects decoys,
writes R/C back to physical memory, fills the TLB and retries. The independent
compiled gate passes four events, 5,140 retirements and 54,838 cycles, checking
all 128 PTE words and read/write/fill ordering. Removing the R/C halfword store
is rejected at cycle 30,602. This acceptance supports PP=2; failed searches and
other permissions still terminate diagnostically until round 3.

Segment/page/refill moves 82% → 86%; weighted completion 77.08% → 77.64%.
Remaining effort stays 6–10 / 8–14 engineer-weeks. Broad preservation regression
is running; no new FPGA fit or timing claim.

## Table-search sequence: round 3 accepted, 2026-09-23

The shared software handler now applies the complete PP/KEY permission matrix
and converts absent, protected and guarded mappings to ordinary ISI/DSI. It
restores CR0, clears TGPR without clobbering normal registers, preserves SRR0
and records full DAR for data faults. Guarded ISI uses the architectural
`0x10000000` cause, distinct from permission `0x08000000`.

The independent compiled gate passes 21 miss cases, 10 ordinary vectors and
11 allowed fills: 73,464 retirements, 782,367 cycles and 3,485,002 checks.
It checks all 32 normal GPRs and CR at vector entry, precise fault records,
PTE scan order, and no PTE write/refill/physical access on denied paths. A
wrong guarded syndrome is rejected at cycle 115,083. The successful-search
profile also passes with the expanded handler (5,152 retirements / 55,018
cycles); omitted R/C writeback is rejected at cycle 30,694. Integration fixed
an ordinary-handler ADDI r0 return-address bug and overlapping ELF segments.

Segment/page/refill moves 86% → 90%; weighted completion 77.64% → 78.20%.
Across the requested three rounds: 76.80% → 78.20%, a 1.40-point increase.
Other system scores stay fixed. Full regression passes all 199 registered
simulation configurations and 243 Python checks; 43 standalone lint profiles
and both historical measurement wrappers pass. All twenty compiled workloads pass on the final runner. The 336 frozen source
input hashes stayed unchanged through the final compiled suite and negative
controls; production RTL also stayed frozen through the broad regression.
No new FPGA fit, timing closure or OS-boot claim.

See [search handler](TABLE_SEARCH_HANDLER.md),
[search verification](TABLE_SEARCH_VERIFICATION.md),
[fault firmware](TABLE_FAULT_FIRMWARE.md) and
[fault verification](TABLE_FAULT_VERIFICATION.md).

## Translated-60x sequence: round 1 accepted, 2026-09-23

`ppc_core_bat_bus60x` now composes the existing translated core and scalar
60x arbiter/adapter. The established core, MMU and transport modules are
unchanged. Strict default/full-feature wrapper lint passes. An independent
pin-driven target verifies CPU-programmed BAT identity/alias mappings, byte
store and halfword/word loads, physical byte lanes, SC/RFI context changes
and retirement backpressure: 22 retirements, 34 address tenures, 1,674 checks.

Integration moves 70% → 72%; weighted completion 78.20% → 78.34%. This is
uncached scalar transport with fixed CI/WT/GBL pins; WIMG-driven cache and
coherence behavior is not implemented. Instruction TEA remains a reset-only
terminal transport stop. Compiled page-search/fault bus execution is the next
gate. No FPGA fit or timing claim; effort estimates remain unchanged.

## Translated-60x sequence: round 2 accepted, 2026-09-23

The unchanged page-search and table-fault ELFs now pass on the new wrapper
with RAM serviced exclusively through public 60x pins. Search: 4 misses,
5,152 retirements, 124,927 cycles, 623,059 checks. Fault matrix: 21 misses,
10 ordinary ISI/DSI vectors, 11 fills, 73,464 retirements, 1,772,615 cycles,
9,604,532 checks. The oracle checks physical PTE scans/R-C byte lanes, refill
ordering, full fault state, normal GPR/CR preservation and denied-access
suppression. Architectural results match the abstract-port workloads.

Omitting physical R/C writeback is rejected at cycle 69,737; changing guarded
ISI to the permission syndrome is rejected at cycle 261,790. Integration
corrected two test assumptions: handled misses set the sticky translation
diagnostic, and a terminal instruction loop need not leave the bus idle.
Acceptance requires the observed success mailbox write to retire.

60x transport moves 70% → 75%; integration 72% → 75%. Weighted completion
78.34% → 78.90%. Cache/attribute composition, broader transport exceptions
and timing closure remain open; no new FPGA fit.

## Translated-60x sequence: round 3 accepted, 2026-09-23

The retry gate proves one upstream translated request survives an identical
ARTRY reoffer, DRTRY rejects provisional poison in favor of replacement data,
and held retirement/store effects occur exactly once: 23 retirements, 36
physical address offers, 1,747 checks. Nonzero BAT WIMG metadata is observed
while the public bus retains its documented fixed cache-inhibited policy.

The error/reset gate passes 159 checks across instruction TEA, translated
data TEA, reset while waiting for address grant, and clean restart. It proves
no fabricated instruction retirement or data GPR/memory effect. It does not
claim all reset edges or architectural recovery from transport errors.

60x transport moves 75% → 78%; integration 75% → 78%. Weighted completion
78.90% → 79.32%; the requested three rounds move 78.20% → 79.32% (+1.12).
Other systems stay fixed. All 202 registered simulation configurations,
243 Python checks, 45 standalone lint profiles and twenty existing compiled
workloads pass, along with both new bus profiles and two negative controls.
The final 342 source input hashes remain stable; established RTL was unchanged.
No FPGA fit was run. Remaining effort stays 6–10 focused engineer-weeks for
integrated simulation and 8–14 for a timing-checked FPGA result.

See [wrapper contract](TRANSLATED_BUS60X.md),
[direct/retry verification](TRANSLATED_BUS60X_VERIFICATION.md),
[error/reset verification](TRANSLATED_BUS60X_ERRORS.md), and
[compiled bus evidence](TRANSLATED_BUS60X_FIRMWARE.md).

## Translated-cache sequence: round 1 accepted, 2026-09-23

The new `ppc_core_bat_cached_bus60x` places physical instruction caching
after translation/permission checks. WIMG=0000 uses the cache; all other
instruction attributes use scalar bypass, and data remains uncached. External
maintenance drains accepted fetch/cache activity before invalidation and holds
new fetches until its completion is acknowledged. It is not a CPU store or
frontend synchronization instruction.

Default/full-profile strict lint and an independent CPU-programmed BAT test
pass: 41 retirements, 4 line bursts, 15 hits, 5 inhibited scalar instruction
bypasses and 3,342 checks. Instruction-cache integration moves 65% → 75%;
weighted completion 79.32% → 79.82%. This accepts the directed foundation.
The complete compiled fault matrix is still under investigation in round 2;
no full cached-firmware or timing acceptance is claimed at this point.

## Translated-cache sequence: round 2 accepted, 2026-09-23

The unchanged search/fault ELFs pass with pin-only RAM on the cached wrapper.
Search: 5,152 retirements, 97,941 cycles, 573,675 checks, 41 line fills and
2,554 hits. Fault matrix: 21 cases/misses, 10 ordinary vectors, 11 fills,
73,464 retirements, 831,968 cycles, 5,251,837 checks, 85 fills and 74,250 hits.
The R/C-write omission is rejected at cycle 73,944; wrong guarded-ISI syndrome
is rejected at cycle 173,770. See [firmware evidence](TRANSLATED_ICACHE_FIRMWARE.md).

This workload exposed a shared fetch-capacity deadlock: an instruction response
held against a full IQ retained the unified router while an older instruction
needed a data transaction. New offers now require downstream queue space; held
offers remain stable. One outstanding request and the sole IQ producer reserve
that slot. Focused firmware passes; the shared-core change requires the broad
regression currently in progress before final sequence acceptance.

Cache80%, integration82%; weighted79.82% → 80.35%. Other scores stay fixed.
No new FPGA fit or timing claim; maintenance/remapping adverse cases are round3.

## Translated-cache sequence: round 3 accepted, 2026-09-23

The canonical coherence gate passes 2,275 checks and 65 retirements: CPU BAT
remapping changes the physical tag; a CPU store to the same PA stays stale
until explicit invalidate plus accepted frontend restart; permission removal
prevents even a warm physical-cache probe. The drain gate passes 1,436 checks
and 47 retirements: maintenance waits for an accepted refill, redirect discards
old bytes, held completion blocks fetches, and one accepted beat followed by
TEA cannot publish a poisoned line. Reset restores execution.

Cache80→85%, integration82→85%; weighted80.35→80.81%. The three rounds move
79.32→80.81% (+1.49 points). Fetch remains90%: the capacity fix closes an
integration defect rather than expanding its scope. The focused fetch test
passes 304 checks. Legacy fixtures were adjusted to establish a held
request before redirect and require full-IQ offer suppression; explicit
response backpressure remains tested in the standalone fetch gate. The final
complete regression passes. No new fit or timing result is claimed.

See [direct/coherence gates](TRANSLATED_ICACHE_VERIFICATION.md),
[drain and partial-fill failure](TRANSLATED_ICACHE_DRAIN.md), and
[compiled cached firmware](TRANSLATED_ICACHE_FIRMWARE.md).

### Final sequence verification

The frozen final `make -j4 regression` exits successfully: all 205 registered
simulation build configurations, strict lint profiles and 243 Python checks
pass. Historical cached and timer/BAT measurement wrappers also pass lint;
this is not a new synthesis, fit or timing result. Twenty preserved compiled
ELF workloads pass, plus scalar-bus and cached-bus executions of the existing
search/fault ELFs. Both cached negative images fail at their intended checks.
All 348 source-input hashes remain unchanged through final acceptance.

The shared production change outside the new wrapper is the reviewed fetch
capacity gate. Legacy corpus fixtures now require IQ credit pressure instead
of naturally held instruction responses; their architectural scoreboards,
request/retirement backpressure and held-packet stability checks remain.
The 304-check standalone fetch gate retains explicit response backpressure.

Final weighted MVP estimate: **80.81% (about 81%)**, up from 79.32%.
Cache85%, integration85%; all other system scores stay fixed. Remaining effort
stays **6–10 / 8–14 engineer-weeks** for simulation / timing-checked FPGA
acceptance pending a combined-top fit and broader event/maintenance stress.

## Bounded cached-interrupt round — accepted, 2026-09-23

One orchestration round adds a CPU-programmed BAT/EE/IR test of an external
interrupt while an accepted translated cache refill is held. Four old beats
drain before event acceptance; the handler reads exact SRR0/SRR1, holds an
actual retirement stable under backpressure, and RFI resumes the alias through
a cache hit without a second physical refill. No stale target instruction
retires before the handler. Canonical strict simulation passes 1,051 checks
and 18 retirements. An independent Sol review found no remaining blocker.

Fresh validation also passes the enabled/disabled core IRQ configurations,
three neighboring translated-cache gates and default/full-feature wrapper
lint. All production RTL is unchanged; 349 source input hashes are frozen.
The prior full 205-configuration regression, 243 Python checks and compiled
firmware results are inherited, not rerun this round. The new target increases
the registered simulation build count to 206; a full 206-configuration run is
not claimed. No FPGA fit was run.

**MVP remains 80.81% (about 81%).** All system percentages and the 6–10 /
8–14 engineer-week ranges stay unchanged: this is bounded verification
hardening. IRQ collisions with data, synchronous exceptions, terminal errors,
maintenance, and broader cached event/reset stress remain open. The IRQ source
is acknowledged by the testbench, not a modeled interrupt-controller driver.
See [test contract and evidence](TRANSLATED_ICACHE_INTERRUPTS.md).

## Bounded cached-timer round — accepted, 2026-09-23

One Sol implementation/review set adds DEC-to-EXT promotion while an accepted
translated cache refill blocks drain. The CPU writes DEC=0; one public timer
tick creates the request. The test observes DEC selection and a frontend
fence before asserting EXT, so this exercises promotion rather than initial
EXT priority. All four old beats drain before EXT acceptance. DEC remains
pending, then takes after the external handler's RFI before any target
retirement. Both handlers read exact SRR0/SRR1; the final RFI resumes through
the cached alias with no second refill. Actual handler retirement backpressure
and pulse-qualified, mutually exclusive event traces are checked.

Canonical strict simulation passes **2,748 checks**, 25 retirements, one EXT
and one DEC. Five neighboring timer/IRQ/cache-drain configurations and both
wrapper lint profiles pass. Production RTL is unchanged; all 350 frozen source
input hashes remain stable. Full regression, Python and compiled firmware
results remain inherited; the registered build count is now 207, without a
claim that the full 207-configuration suite ran this round. No fit was run.

**MVP remains 80.81% (about 81%).** All system percentages and the 6–10 /
8–14 engineer-week ranges stay unchanged for this verification-only round.
This single boundary does not cover continuous timer cadence, high saved-MSR
mask differentiation, event/data or maintenance collisions, or timing closure.
See [timer/cache verification](TRANSLATED_ICACHE_TIMERS.md).
