# System completion scorecard

Updated: 2026-10-05. Scope: single-issue, big-endian integer CPU with supervisor
mode, a snooping MEI data cache, a pin-accurate chip boundary, resumable exceptions, external/decrementer interrupts, CPU-managed BAT
and page translation, and an integrated cache/60x path. FPGA acceptance also
requires reviewed constraints and passing setup/hold. Board bring-up is excluded.

This is the current status index. Feature contracts linked below control exact
behavior; [ARCHITECTURE.md](ARCHITECTURE.md) gives the datapath overview; [MVP_EXECUTION_PLAN.md](plans/current/MVP_EXECUTION_PLAN.md) holds the MVP waves
and accepted-round history. The [2026-09-20 inventory](CODEBASE_INVENTORY_2026-09-20.md) and round-40 percentages are historical snapshots.

## How to read the estimates

Percentages are engineering judgments about accepted scope, not measured code
coverage, elapsed effort, a probability of success, or a time-remaining ratio.
Weights represent the chosen MVP delivery scope and total 100. A working
standalone component earns partial credit; integration, adverse cases and
acceptance evidence are still required. The aggregate is `sum(weight × completion)
/ 100`, rounded to a whole percent. Keep weights fixed between rounds unless the
user changes scope. Treat small score changes as bookkeeping, not velocity.

**MVP estimate: about 97% complete (weighted 97.43%); MVP release check passed 2026-09-29; the batch gates through 2026-10-04 pass on later RTL.** The
remaining work is concentrated in platform exceptions (machine check, trace,
debug) and timing closure. These are
hard acceptance blockers regardless of the weighted score. Final FPGA acceptance
is currently unmet.

## MVP systems

| System | Weight | Complete | Accepted capability | Gaps and deliberate shortcuts |
| --- | ---: | ---: | --- | --- |
| Fetch and dispatch | 3% | 100% | Buffered fetch, precise supported fetch faults, drain/refetch on live context and events; reset/interleaving stress in branch-heavy translated code and inhibited fetches on the translated cached top | One outstanding instruction request with reserved queue capacity; single dispatch. |
| Integer execution, multiply/divide, GPR/CR/XER | 8% | 93% | Every encoding executes or takes the manual's exception (illegal and invalid forms at 0x700, `tw`/`twi` traps, FP forms at 0x800 with MSR[FP] held 0; 85,376-word decode sweep); Broad scalar arithmetic/Boolean/rotate/shift/compare corpus, tagged flags, iterative divide, compiled integer firmware | Explicit XER access now supports state saving; compiler/ISA subset remains explicit; iterative 33×9 DSP multiply with rB byte-class early-out matching every Table 6-4 cycle set (operand mapping inferred, `TIM-U02` open). |
| Rename, completion and recovery | 6% | 95% | Tagged dependencies, ordered retirement, retained-prefix recovery, precise supported events | Five rename slots/CQ entries; finite generation-token lifetime contract; recovery timing and unsupported diagnostic ownership remain bounded policies. |
| Branches and control flow | 4% | 100% | Direct/conditional/LR/CTR branches, handler entry and RFI | Serialized companion lane; prediction, folding and dual issue excluded. A page-crossing branch storm under EXT/DEC, bus retries and resets covers the combined path. |
| Load/store and memory ordering | 7% | 97% | BE scalar D/indexed/update operations; `lmw`/`stmw` and string forms cracked per register with precise restart; `lwarx`/`stwcx.` reservation; byte-reverse; unaligned scalars split in hardware with DR=1 page-cross alignment; DSI/TLB-miss restart mid-access; ordered stores, load cancellation/drain, alignment faults and resumable BAT and page protection DSI; denied accesses suppress destination/base/memory effects; translated `dcbf`/`dcbst`/`dcbi`/`dcbz` probes with DSI/TLB-miss and no transfer; guarded CI stores write once across ARTRY | Serialized; cached accesses and real `dcbz`/`dcbf`/`dcbst`/`dcbi` go through the data cache; data TEA is a precise machine check, untyped router faults are asserted unreachable in the translated profile; `eciwx`/`ecowx` with EAR DSI and the atomic/external-control 60x transfer types are accepted; multiple/string timing not modeled. |
| Supervisor state and synchronous exceptions | 7% | 99% | SC/RFI, live MTMSR/MFMSR, selected SPRs, program/alignment, every ISI and DSI cause of the supported instructions (protection, guarded, N, direct-store T=1, software page fault); `dcbz` alignment with Table 4-13 DSISR and privileged `dcbi`; DAR/DSISR capture and handler repair/retry | Machine check (0x200) from TEA with ME/RI and `checkstop_o`, MSR SE/BE/POW, single-step and branch trace (0xD00) and IABR (0x1300) are accepted. MSR[LE]/ILE select little-endian mode ([little-endian](LITTLE_ENDIAN.md)); MSR[FP] writes are rejected without the FPU; MCP, CKSTP_IN, APE and DPE (HID0[EBD]) take machine check or checkstop on the chip top; no soft stop; every exception is taken with TGPR=1 and clears it (UM Table 4-7); PVR/HID0/HID1/EAR implemented; HID0 ILOCK locks the instruction cache. |
| External interrupts and TB/DEC | 6% | 95% | EE masks, precise resume PC, admitted EXT latching, TB64/DEC32, priority and retirement-only writes; translated cached IRQ/refill drain, DEC-to-EXT promotion and RFI hits; hundreds of seeded EXT/DEC events per run across TLB misses, reloads, held bus tenures and resets on the translated cached top | Synchronous pins/tick; no CDC or bus-clock divider; local bounded event-recognition policy; board-level reset and interrupt-controller behavior open. |
| BAT translation and live context | 8% | 95% | CPU-owned privileged BAT SPR reads/writes, retirement-only mapping changes, cancellation/drain, live IR/DR/PR, supported instruction/data-protection faults; compiled mapping replacement with pending EXT/DEC; IBAT remap, WIMG and IR changes over cached lines and BAT-over-TLB priority under retries and resets | Abstract, scalar 60x and bounded cached 60x paths accepted; final timing remains open. any BAT value is stored with reserved fields cleared; overlaps resolve to the lowest entry (UM 5.3); deterministic zero reset differs from silicon. |
| Segment registers, page TLB and software refill | 11% | 97% | CPU-owned SR/SDR1/compare/RPA; SR/SDR1 context changes under ARTRY/DRTRY/holds; TLBLD/TLBLI, TLBIE and TLBSYNC against sole I/D banks; precise PP/N/G/direct-store exceptions; architectural I/load/store miss and C=0 entry with full-EA/HASH capture, TGPR, primary/secondary PTEG search, R/C writeback, PP/key checks, ordinary failed-search ISI/DSI and refill/RFI retry; LRU replacement, remap and invalidation verified under EXT/DEC and reset stress on the translated cached top | True misses report the per-set TLB LRU way in SRR1.WAY; changed-bit hits retain the matched way. Software fixture is single-writer, using a halfword R/C update for stores; concurrent PTE writers and nested misses are outside its contract. Bounded SDR1/provenance checks and read-only real-mode miss SPR policy; loads require V=1/H=0, supported RPA shape and IR=DR=0; TLBISYNC is treated as negated. External-management frontend coherence and final timing remain open. |
| 60x physical transport | 6% | 97% | Scalar master and separate four-beat line reads; seeded ARTRY/DRTRY (corrupted cancelled beats, multi-cycle DRTRY) and held tenures across every translated MMU stress mode; translated scalar wrapper runs real search/fault ELFs, with physical PA/byte lanes, ARTRY/DRTRY, TEA/reset checks; seeded ARTRY/DRTRY/held-fill stress and compiled firmware on the translated cached top | Scalar path fixes CI=1/WT=0/GBL=0; cached wrapper permits WIMG=0 instruction fills only. Cached data with WIMG, GBL snooping, ARTRY windows and push priority are accepted with the data cache. TEA on data, scalar fetch and line fill (partial fill discarded) enters machine check or checkstop in the MVP profile; the default profile keeps diagnostics; one active-address reset point covered. Inbound data parity, BR negation after a foreign ARTRY and push pipelining are accepted on the chip top. DBWO is ignored; the two-CPU bench has no address pipelining, DRTRY or TEA. |
| Instruction cache and maintenance | 4% | 97% | 16-KiB four-way physical cache, block-RAM data array, translated WIMG=0 fills/hits, scalar bypass, remap and explicit stale-code invalidate/restart, denied warm-line suppression and partial-fill TEA/reset; CPU `icbi` drains held/retried fills then clears the set; `dcbst`/`sync`/`icbi`/`isync` code patching under EXT/DEC, mode and BAT changes, retries and external maintenance | Conservative WIMG policy; real-mode fetches get WIMG=0001 and are never cached (to check against UM §5.2); HID0 ILOCK, ICE/ICFI drive cache maintenance (every ICE change invalidates, more than required); no automatic code coherence (not architected). External maintenance is not a CPU/store barrier. |
| Toolchain and reproducible builds | 3% | 100% | Pinned compiler, BE ELF loader, twenty-two compiled workloads plus scalar-bus and cached-bus runs of the same search/fault ELFs (TLBIE, TLB-load and page-miss profiles each have three modes; MMU stress has nine), parallel-safe regression and source-hashed fit archives | Small bare-metal memory/ABI profile; no arbitrary OS/binary compatibility claim. |
| Integration and verification | 6% | 99% | Collected line coverage with a waiver-gated control-arm review, one `make -C sim ci` gate and a 64-seed reference-acceptance run; independent directed/reference tests, seeded cached-top cache-maintenance stress with a scripted ARTRY/DRTRY/hold 60x target, 259 Python checks, CPU-owned translation over scalar 60x, runtime BAT suites and firmware negatives; seeded nine-mode MMU/event/reset stress on the MVP-profile translated cached top | No formal verification or toggle coverage; images with bench-injected events or 603e software TLB reload are not comparable with DingusPPC. |
| FPGA fit, timing and release | 7% | 100% | Release check on the MVP release commit: translated (66.89 MHz), cached physical (69.65), timer/BAT (70.43) and chip (67.29) tops meet 50 MHz and 66 MHz setup and hold at every corner with no SDC critical warning ([release](RELEASE.md)); refit on `04b5bad` (2026-09-30): 0 failing endpoints at 66 MHz on all four; on `6cb15bb` (2026-10-04) all meet 50 MHz; integrated and timer/BAT meet 66 MHz, translated (−0.446 ns) and chip (−0.448 ns) miss it | Board bring-up excluded; new RTL changes require fresh fits. |
| Data cache, writeback and coherence | 10% | 100% | 16-KiB four-way write-back MEI cache integrated end to end ([integration](DATA_CACHE_INTEGRATION.md)): LSU → cache → BIU cache master and 60x snooper; on in `ppc603e` and the translated top with HID0[DCE]=0 at reset; coherence against a DMA master verified at the pins (reads, RWITM, write-with-kill/flush, kill, flush, clean, ARTRY and push); core bench 191,813 checks and chip firmware with the cache on | None in MVP scope: page-table WIMG, guarded-load ordering, pipelined foreign address tenures and snooped address parity are verified; DBWO is ignored as the manual permits for this configuration. |
| Chip package and pin interface | 4% | 99% | Top `ppc603e` whose ports are the 603e pins ([package](CHIP_PACKAGE.md)): MCP, SRESET, SMI, checkstop, straps, TBEN, RSRV, TLBISYNC, parity and snooping (TS/A/TT/GBL in, ARTRY out); chip images boot with ICE and DCE enabled in software and pass mmu-stress, lsu, machine-check and full-decode with the cache on; pin-level coherence bench with a DMA master and a two-CPU bench (`test-chip-mp`); inbound data parity with DPE | JTAG/COP excluded; misses 66 MHz since batch 9 (−0.448 ns on `6cb15bb`). Power modes: [POWER_MANAGEMENT.md](POWER_MANAGEMENT.md). |

Evidence: [core recovery](CORE_RECOVERY.md), [integer ISA inventory](references/ISA_MATRIX.md),
[alignment](ALIGNMENT_VERIFICATION.md), [live context](LIVE_CONTEXT_VERIFICATION.md),
[interrupts](EXTERNAL_INTERRUPT_VERIFICATION.md), [timers](TIMER_VERIFICATION.md),
[runtime BAT acceptance](RUNTIME_BAT_VERIFICATION.md), [TLB service](TLB_SERVICE.md),
[segment bank](SEGMENT_REGISTERS.md), [CPU segment verification](CPU_SEGMENT_VERIFICATION.md), [page-hit protocol](PAGE_PATH_PROTOCOL.md),
[page verification](PAGE_PATH_VERIFICATION.md), [page firmware](PAGE_FIRMWARE.md), [CPU TLBIE](CPU_TLBIE.md),
[TLBIE verification](TLBIE_VERIFICATION.md), [compiled firmware](COMPILED_FIRMWARE_VERIFICATION.md),
[cached FPGA fit](INTEGRATED_SYNTHESIS_BASELINE.md),
[timer/BAT FPGA fit](TIMER_SYNTHESIS_BASELINE.md),
[translated MVP FPGA fit](TRANSLATED_SYNTHESIS_BASELINE.md).
The generated ISA matrix describes its metadata profile; later live-context/timer
extensions have their own decode tests and contracts. Its form count is not the
completion denominator.

## Full-603e estimate and systems outside this MVP

**Approximately 81% of full-603e project scope (weighted 81.53%)** follows the
[full CPU weighting audit](FULL_CPU_COMPLETION_AUDIT.md) (2026-10-05 update).
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
| Dual dispatch/retirement and superscalar scheduling | 60% | `DISPATCH_WIDTH=2` build option, default 1 ([design](DUAL_DISPATCH_DESIGN.md), slices 0–6). Open: width 2 at 66 MHz and as default, two-word fetch through the wrappers, slice 7. |
| Branch prediction and folding | 50% | Static prediction (y bit, backward taken) and fetch-time folding of `b` and predicted-taken `bc` ([control](CONTROL_MEMORY.md)). Open: `bclr`/`bcctr` folding, branches without a CQ entry, branch in DQ1. |
| Data cache, writeback and coherence | In the MVP | MVP row above (100% of MVP scope). The full audit scores data cache 90% and coherence 85%: one-cycle hits need the pipelined LSU (off by default); BR negation after a foreign ARTRY and push pipelining are open. |
| Floating point, FPR and FPSCR | 75% | FPU in the core behind `ENABLE_FPU` (default off): arithmetic pipelined to Table 6-5, overlapped 64-bit FP loads and stores, the 602 FPU (V12), COMPACT FPU ([integration](FPU_CORE_INTEGRATION.md), [COMPACT](FPU_COMPACT.md)); package top with the FPU meets 50 MHz. Open: FP loads/stores at Table 6-6, 66 MHz (50.09 MHz fitted), FULL FPU in the dual-dispatch MiSTer core. |
| Little endian, additional variants and power modes | 60% | 602 core and `ppc602` top with its FPU, the 603 with XATS direct-store (V5), bus clock ratios, doze/nap/sleep ([variants](CPU_VARIANTS.md), [power](POWER_MANAGEMENT.md)). Open: little endian, misaligned LE (V13). |
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
[CORE_STATUS_REVIEW.md](CORE_STATUS_REVIEW.md) records the 2026-09-21 independent core assessment.
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

1. Accepted 2026-09-27: LRU replacement, direct-store DSI/ISI, TLBSYNC and
   seeded event/reset stress on the translated cached top. Machine check,
   trace and debug exceptions remain outside the supported set.
2. Broaden the now-integrated cache/MMU/bus acceptance: interrupts and context
   changes around cache hits/refills, external-maintenance sequencing, and
   remaining instruction attributes (roughly 1–3 weeks). Keep data uncached
   and distinguish the external control contract from architectural `icbi`.
3. Fit the combined translated cached top under reviewed interface constraints,
   then close setup/hold and run broader integration stress (roughly 2–4 weeks,
   overlapping the above; redesign could extend the range). Preserve the old
   fit archives as historical configurations.

The 6–10 / 8–14 engineer-week ranges remain conservative because the combined
translated cache/bus topology has only a first fit, which misses 50 MHz setup. The
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
| Bounded recovery/status round, 2026-09-21 | About 65% (unchanged) | Rename identities retained across recovery; independent focused recovery/memory/fault gates, 24 strict lint profiles and 241 Python tests passed with sources unchanged. Prior 172-target full regression predates this change; no new fit. All six compiled firmware workloads rebuilt and passed; prior negative controls were not repeated. |
| XER state-saving round, 2026-09-21 | About 65% (unchanged) | SPR1 read/write and alias through precise flags retirement; 28,721 core checks, 189 CQ/flags checks, 1,213,761 decode checks, 243 Python tests and all six firmware workloads pass. See XER verification for the complete focused gate. No full regression or fit. |
| Event-entry reset round, 2026-09-21 | About 65% (unchanged) | Test-only hardening: EXT/DEC at four reset boundaries, 14,909 independent checks, fresh-boot state and event reuse; 24 lint profiles and 243 Python tests pass. Sources stayed unchanged through the gate; production RTL unchanged. |
| Runtime BAT round, 2026-09-22 | About 68% (67.6% weighted) | BAT/live context rises from 60% to 85%; other system scores unchanged. Five new suites and four runtime lint profiles pass, plus seven compiled workloads and two negative controls. Full legacy regression, 28 combined lint profiles and 243 Python checks pass; Sources stayed unchanged through the gate. No new FPGA fit. |
| DSI protection round, 2026-09-22 | About 69% (69.1% weighted) | Load/store and supervisor scores each rise from 65% to 75%; other scores unchanged. Full regression and separately added live-context cancellation target pass, with 243 Python checks, eight firmware workloads and a syndrome negative control. Production RTL stayed stable during the gate; no new FPGA fit. |
| CPU segment-register round, 2026-09-22 | About 71% (70.5% weighted) | Segment/page/refill rises from 25% to 35%; all other scores unchanged. Five new suites, three additional integration lint profiles, full legacy regression, 243 Python checks, nine firmware workloads and a readback negative control pass. Segment descriptors still do not drive page translation. No new FPGA fit. |
| Prefilled page-hit round, 2026-09-22 | About 72% (71.9% weighted) | Segment/page/refill rises from 35% to 45%; all other scores unchanged. Clean broad regression plus the separately finalized router suite, 159 bench lint profiles, 243 Python checks, ten firmware workloads and an instruction-page negative control pass. External TLB preload remains a deliberate shortcut; no CPU software refill or new FPGA fit. |
| CPU TLBIE round, 2026-09-22 | About 73% (72.6% weighted) | Segment/page/refill rises from 45% to 50%; other scores unchanged. Decode, lifecycle, privilege/default-off, service and router suites pass, along with broad regression, 243 Python checks and eleven firmware workloads. Three compiled TLBIE modes verify I/D invalidation and retained neighbors; wrong-set negative is rejected. No CPU refill or new FPGA fit. |
| Requested three-round sequence: round 1, prepared refill, 2026-09-22 | Unchanged: 72.6% weighted | Opt-in kind-5 normalized refill now prepares without mutation and commits captured bank/set/way/entry atomically. Four feature combinations, legacy corpus, page/invalidate integration and a live-input mutation negative pass. This service foundation does not yet expose CPU TLB loads, so system percentages remain unchanged. |
| Requested three-round sequence: round 2, seed registers, 2026-09-23 | About 73% (72.9% weighted) | Segment/page/refill 50% → 52%. DCMP/ICMP/RPA now support full-width committed CPU reads/writes, privilege enforcement and cancellation. 2,062 decode, 1,417 enabled-core and 88 disabled-core checks pass, with neighboring supervisor/context/XER/TLBIE/SR regressions. CPU TLB loads and automatic miss state are still absent at this acceptance point. |
| Requested three-round sequence: round 3, CPU TLB loads, 2026-09-23 | About 74% (74.0% weighted) | Segment/page/refill 52% → 60%; other system percentages unchanged. Privileged real-mode TLBLD/TLBLI capture CPU seed state and commit prepared entries at retirement, with cancellation/error drain. Full regression, 177 strict test configurations, 243 Python checks, twelve compiled workloads and missing-load negative pass. No fixture preloading in the CPU-load workload; no architectural miss handler or new FPGA fit. |
| Page-exception round 1, page DSI, 2026-09-23 | 74.0% → 74.42% | Segment/page/refill 60% → 63%. |
| Page-exception round 2, page ISI, 2026-09-23 | 74.42% → 74.84% | Segment/page/refill 63% → 66%. |
| Page-exception round 3, miss results, 2026-09-23 | 74.84% → 75.12% | Segment/page/refill 66% → 68%. |
| Miss-entry round 1, SDR1, 2026-09-23 | 75.12% → 75.40% | Segment/page/refill 68% → 70%. |
| Miss-entry round 2, TGPR, 2026-09-23 | 75.40% → 75.82% | Segment/page/refill 70% → 73%. |
| Miss-entry round 3, miss vectors, 2026-09-23 | 75.82% → 76.80% | Segment/page/refill 73% → 80%. |
| Table-search round 1, matched way, 2026-09-23 | 76.80% → 77.08% | Segment/page/refill 80% → 82%. |
| Table-search round 2, PTEG search, 2026-09-23 | 77.08% → 77.64% | Segment/page/refill 82% → 86%. |
| Table-search round 3, failed-search faults, 2026-09-23 | 77.64% → 78.20% | Segment/page/refill 86% → 90%. |
| Translated-60x round 1, scalar wrapper, 2026-09-23 | 78.20% → 78.34% | Integration 70% → 72%. |
| Translated-60x round 2, bus firmware, 2026-09-23 | 78.34% → 78.90% | 60x transport 70% → 75%; integration 72% → 75%. |
| Translated-60x round 3, retry/error/reset, 2026-09-23 | 78.90% → 79.32% | 60x transport 75% → 78%; integration 75% → 78%. |
| Translated-cache round 1, cached wrapper, 2026-09-23 | 79.32% → 79.82% | Instruction cache 65% → 75%. |
| Translated-cache round 2, cached firmware, 2026-09-23 | 79.82% → 80.35% | Instruction cache 75% → 80%; integration 78% → 82%. |
| Translated-cache round 3, coherence/drain, 2026-09-23 | 80.35% → 80.81% | Instruction cache 80% → 85%; integration 82% → 85%. |
| Bounded cached-interrupt round, 2026-09-23 | 80.81% (unchanged) | Verification only. |
| Bounded cached-timer round, 2026-09-23 | 80.81% (unchanged) | Verification only. |
| Gate-1 MMU/event round, 2026-09-27 | 81.51% → 82.66% | Page TLB 90% → 94%; supervisor 75% → 78%; interrupts/timers 85% → 88%; integration 85% → 87%. |
| Cache maintenance and held-refill round, 2026-09-27 | 82.66% → 83.81% | Cache 95%, load/store 78%, supervisor 80%, 60x 80%, integration 89%. |
| Verification breadth round, 2026-09-27 | 83.81% → 85.01% | Fetch 92%, branches 93%, BAT/context 88%, segment/page 95%, 60x 83%, integration 94%. Seeded ARTRY/DRTRY/held-tenure retry stress with SR/SDR1/PTE changes, branch storm and BAT/cache collisions; line coverage, `ci` and reference-acceptance targets. No production RTL change. Checks inherited from the branch head (`4560b1a`); see [verification gates](VERIFICATION_GATES.md). |
| Load/store extensions round, 2026-09-27 | 85.01% → 85.94% | Load/store 90%, integer 86%. Multiple/string, `lwarx`/`stwcx.`, byte-reverse and hardware-split unaligned scalars with precise mid-access restart. Fresh on the merge: `make -C sim ci` and coverage; fit inherited from the branch (same RTL). See [verification](LOAD_STORE_EXTENSIONS_VERIFICATION.md). |
| Machine check, trace and IABR round, 2026-09-28 | 85.94% → 87.46% | Supervisor 92%, load/store 92%, 60x 88%, integration 95%. TEA machine check and checkstop, trace, IABR, integrated with cracked instructions; seeded TEA in the MMU stress. Fresh on the branch head (`60e0916`, same tree as the merge): `make -C sim ci` and translated fit. See [verification](EXCEPTION_MACHINE_CHECK_TRACE_VERIFICATION.md). |
| Gate-3 timing round, 2026-09-28 | 87.46% → 90.26% | FPGA 45% → 85%. Interface timing contract and SDCs; reset off datapath storage, registered IQ head, ungated wake payload. Fresh on the branch (`710b517`, same tree as the merge): `make -C sim ci` and fits of all three tops. See [interface timing](INTERFACE_TIMING_CONTRACT.md). |
| Full decode and final signoff round, 2026-09-28 | 90.26% → 91.80% | Integer 90%, load/store 94%, supervisor 95%, instruction cache 97%, FPGA 95%. No encoding halts; final `ci` and fits of all three tops on the combined RTL. See [verification](FULL_DECODE_VERIFICATION.md). |
| Scope change, 2026-09-28 | 91.80% → 80.93% | User added the data cache (with coherence), a pin-level chip package and a 603e-style multiplier to the MVP, and accepted the other contracted design choices (single dispatch, one outstanding fetch, five rename slots, big-endian, integrator-owned interrupt synchronization). Weights rebalanced to fit two new rows; fetch and branches 100%, rename and interrupts 95%. No new checks. |
| Standalone data cache round, 2026-09-28 | 80.93% → 84.43% | Data cache 0% → 35%. Inherited from the branch (`02a2404`): regression and the cache fit; fresh on the merge: lint, check-spec, test-dcache and the seven mutations. See [verification](DATA_CACHE_VERIFICATION.md). |
| Multiplier round, 2026-09-28 | 84.43% → 84.67% | Integer 90% → 93%. DSP product datapath with 603e early-out latencies; compiled-firmware CPI unchanged (17.076). Inherited from the branch (`9213494`): `make -C sim ci` and translated fit (62.06 MHz); fresh on the merge: lint, check-spec, multiply and data-cache benches. See [verification](MULTIPLY_TIMING_VERIFICATION.md). |
| Chip package round, 2026-09-28 | 84.67% → 87.67% | Chip package 10% → 85%. Pin-level top, BIU grouping, pin exceptions and data-cache slot. Fresh on the merge with the data cache and multiplier: `make -C sim ci` (540 PASS lines, pin bench, coverage 76.2%); chip fit inherited from the branch (`4274bd0`). See [verification](CHIP_PACKAGE_VERIFICATION.md). |
| Diagnostic residuals round, 2026-09-28 | 87.67% → 88.84% | Supervisor 98%, BAT 95%, segment/page 97%, integration 98%. Diagnostic halts replaced with manual behavior (only LE/ILE remains, out of scope); compiled images compared against DingusPPC. Inherited from the branch (`55e2b78`/`4498a25`): `ci`, reference-acceptance and translated fit; fresh on the merge: lint and check-spec; the final gate covers the combination. See [residuals](DIAGNOSTIC_RESIDUALS.md). |
| Fetch-to-decode and signoff round, 2026-09-28 | 88.84% → 89.05% | FPGA 95% → 98%. Registered fetch-to-decode stage (firmware CPI +1.1%). Fresh on the combined tree: `make -C sim ci` (538 PASS lines, coverage 76.3%) and fits of all four tops, each meeting 66 MHz at every corner. |
| Chip boot round, 2026-09-28 | 89.05% → 89.25% | Chip package 85% → 90%. Chip images enable HID0[ICE] in software; the reset strap is removed. Fresh on the branch, same tree as the merge (`46c5dd7`): `make -C sim ci` (555 PASS lines, 36 firmware profiles). See [verification](CHIP_PACKAGE_VERIFICATION.md). |
| Data cache LSU round, 2026-09-28 | 89.25% → 91.25% | Data cache 35% → 55%. Core load/store side connected behind `ENABLE_DCACHE` (default off). Fresh on the merge: `make -C sim ci` (542 PASS lines). See [integration](DATA_CACHE_INTEGRATION.md). |
| Data cache integration round, 2026-09-28 | 91.25% → 95.73% | Data cache 90%, load/store 97%, 60x 95%, chip package 97%, FPGA 99%. BIU cache master, 60x snooping, cache on in the chip and translated tops. Fresh on the merge: `make -C sim ci` (553 PASS lines, 37 firmware profiles, coverage 75.8%) and translated/chip fits; cached-physical and timer/BAT fits inherited from the branch (their files unchanged). See [integration](DATA_CACHE_INTEGRATION.md). |
| MVP signoff round, 2026-09-29 | 95.73% → 97.20% | Page WIMG, guarded loads, pipelined snoops, snooped address parity; `make -C sim release-check` passes on the release commit (ci, reference-acceptance, four fits with STA and 66 MHz paths). Data cache 100%, chip 98%, FPGA 100%, toolchain 100%, integration 99%. |
| Batch 3, 2026-09-30 | 97.20% (unchanged) | Outside MVP scope: bus clock ratios (`bus_ce`, `PLL_CFG`), 602 caches and multiply timing (V10), `ppc602` pin top and `chip602` project (V11), FPU and area trims. Batch gate passed on `e882ea1`, including a timing-clean MiSTer build; the batches 4+5 gate on `24535f5` also covers it. See [602 package](CHIP_PACKAGE_602.md), [variants](CPU_VARIANTS.md). |
| Batches 4+5, 2026-09-30 | 97.20% (unchanged) | Outside MVP scope: 66 MHz round for the 602 (multiply first product after issue, `mfrom` table, registered D-cache lookup), FPU shell area and retiming, FPU in the core behind `ENABLE_FPU` (default off), power modes V14 (`test-chip-power` 101 checks), opcode self-test (1047/1047). Fresh on `24535f5`: `make -C sim ci` (coverage 73.9%, 1934/2616), `xrand-sweep` (60 runs), FPU suite, translated/integrated/timer-bat/chip fits with 0 failing endpoints at 66 MHz, chip602 68.68 MHz slow 100 C, FPU `fullfit` 51.55 MHz and `full602fit` 35.69 MHz, MiSTer default and self-test builds timing-clean. See [FPU integration](FPU_CORE_INTEGRATION.md), [power](POWER_MANAGEMENT_VERIFICATION.md). |
| Batch 6, 2026-09-30 | 97.20% (unchanged) | Outside MVP scope: FP arithmetic issues at dispatch, pipelined to Table 6-5; SoC and MiSTer FPU option; Whetstone (`demo-whetstone-hf` 14.244 MWIPS at 50 MHz); FP self-test (`test-selftest-fpu` 1218/1218); CI preparation. Fresh on `04b5bad`: `ci` (73.5%, 1945/2646), `xrand-sweep` (60 runs), FPU suite, five fits with 0 failing endpoints at 66 MHz, `fullfit` 51.55 MHz, `full602fit` 35.69 MHz, MiSTer default, `--suite selftest` and `--fpu --suite whetstone` builds timing-clean. Failed: `--fpu --suite selftest`, hold slack −0.044 ns on the core clock at the slow corners (setup +0.394 ns); the same RTL with the Whetstone image passed. See [FPU verification](FPU_CORE_INTEGRATION_VERIFICATION.md). |
| Batch 7, 2026-10-01 | 97.20% (unchanged) | Outside MVP scope: FP doublewords as one 64-bit access, FP loads and stores overlapped with younger work, COMPACT FPU (`FPU_IMPL`), 602 FPU in the core (V12), FPU forward-pick timing, 603 direct-store on XATS (V5), dual-dispatch design. Fresh on `537ee1f`: `xrand-sweep` (60 runs), FPU suite, `ci` after bench fixes `262f408` and `0aa02ef` (failed targets rerun); translated, integrated, timer-bat and chip 0 failing at 66 MHz, chip602 −0.166 ns (36 endpoints); FPU `fullfit` 50.58, `full602fit` 51.28, `compactfit` 57.85, `compact602fit` 59.51 MHz; MiSTer default, self-test and COMPACT FPU self-test builds timing-clean. Failed: `--fpu --suite whetstone` and `--fpu --suite selftest`, setup −1.89 ns (fixed in batch 8). See [FPU verification](FPU_CORE_INTEGRATION_VERIFICATION.md), [variants](CPU_VARIANTS.md). |
| Batch 8, 2026-10-01 | 97.20% (unchanged) | Outside MVP scope: dual-dispatch slices 0–2 (dispatch/retire trace and schedule checker, shifting IQ, two-word fetch, two-lane GPR file, rename and CQ), pipelined load/store unit (P3, `ENABLE_LSU_PIPE`, off by default), FPU issue-path timing (package top with the FPU meets 50 MHz), chip `--fpu`/`--dual` builds, MiSTer `--fpu` core with Whetstone and FP Mandelbrot. No gate of its own; branch records inherited ([dual dispatch](DUAL_DISPATCH_DESIGN.md), [LSU](LSU_PIPELINE.md), [FPU verification](FPU_CORE_INTEGRATION_VERIFICATION.md)); the batch 9 gate covers it. |
| Batch 9, 2026-10-01 | 97.20% (unchanged) | Outside MVP scope: dual dispatch and retirement behind `DISPATCH_WIDTH=2` (slices 3–6, default 1), cached one-cycle load hits with the LSU unit, MiSTer `--dual` and `--lsu-pipe`. Fresh on `71d048c`: `ci` (73.1%, 2045/2798), `xrand-sweep` (70 runs), FPU suite, `make -C toolchain rtl-all`; width-1 fits meet 50 MHz on all five tops; at 66 MHz integrated and timer-bat 0 failing, translated −0.213 ns, chip −0.577 ns, chip602 −0.202 ns; FPU fits 50.09, 50.60, 57.85, 59.51 MHz. Inherited from `9e738ce`/`6d64392`: width 2 + unit + FPU benches, references and benchmarks. MiSTer `--fpu-compact --dual --lsu-pipe` timing-clean (+0.905 ns, 69% ALMs); `--fpu --dual --lsu-pipe` failed (97% ALMs, −2.606 ns). See [dual dispatch](DUAL_DISPATCH_DESIGN.md#with-the-pipelined-loadstore-unit). |
| Batch 10, 2026-10-03 | 97.20% → 97.43% | Supervisor 98% → 99% (DPE, MCP/CKSTP_IN listed, ILOCK effective; LE/ILE V13 outside MVP scope), 60x transport 95% → 97% (inbound data parity, BR negation after a foreign ARTRY, push pipelining), chip package 98% → 99% (DPE, two-CPU bench `test-chip-mp`, which found and fixed three coherence faults). Also: MiSTer loadable program images, CI workflows, GPL-2.0-or-later relicense. Fresh on `2f049c5`: `ci` (73.3%, 2078/2836, 14 waived arms), `xrand-sweep` (70 runs), FPU suite, `make -C toolchain rtl-all`; all five fits meet 50 MHz; at 66 MHz integrated and timer-bat 0 failing, translated −0.082 ns, chip −0.465 ns, chip602 −0.539 ns; FPU fits 51.57, 50.58, 53.43, 60.07 MHz; MiSTer `--fpu-compact --dual --lsu-pipe` timing-clean (70% ALMs). Open: DBWO, real-mode fetch caching (UM §5.2). See [chip verification](CHIP_PACKAGE_VERIFICATION.md), [little-endian](LITTLE_ENDIAN_VERIFICATION.md). |
| Batch 11, 2026-10-04 | 97.43% (unchanged) | Outside MVP scope: dual-dispatch slice 7 (a folded branch in DQ1 beside DQ0 work at width 2; `bclr`/`bcctr` fold when predicted taken with no older LR/CTR writer pending; branches without a CQ entry not built), FP loads and stores through the LSU unit (loads at Table 6-6 2:1). Also on main: `fec2aad` makes `firmware_runner.cpp` GPL-3.0-or-later (it links DingusPPC). Fresh on `6cb15bb`: `ci` (73.4%, 2092/2852, 14 waived arms, 21 runs; rerun alone after an out-of-memory kill), `xrand-sweep` (70 runs), FPU suite, `make -C toolchain rtl-all`; all five fits meet 50 MHz; at 66 MHz integrated and timer-bat 0 failing, translated −0.446 ns (regressed from −0.082: LR/CTR fold-target mux), chip −0.448 ns, chip602 −0.063 ns; FPU fits unchanged (51.57, 50.58, 53.43, 60.07 MHz). Failed: MiSTer `--fpu-compact --dual --lsu-pipe` (71% ALMs): CPU clock +0.959 ns, but `pll_hdmi` setup −0.353 ns, a framework-domain placement at SEED 2; no rbf published. See [dual dispatch](DUAL_DISPATCH_DESIGN.md#slice-7), [LSU](LSU_PIPELINE.md#fp-accesses-through-the-unit-2026-10-03). |
| Batch 13, 2026-10-05 | 97.43% (unchanged) | Outside MVP scope: the batch 12–13 performance line (retire in the writeback cycle, CR flag-token waiter, LSU base wait, early redirect, load priority, 8-entry data µTLB, SRU route, second IU finish port), the LSU store queue, branch removal behind `ENABLE_BRANCH_REMOVAL` (off), FP loads through the LSU, a bus fix, the 602/rename timing fix `497429b`, the [source reconciliation](references/SOURCE_RECONCILIATION.md) and [manual inventory](references/MANUAL_INVENTORY.md) (AUD-75 to AUD-86). Fresh on `0ff3a45`: `xrand-sweep`, FPU suite, integrated (+1.535 / +0.076 ns, 9,421 ALMs) and timer-bat (+1.169 / +0.118 ns, 9,493 ALMs) at 50 MHz; FPU fits unchanged. Fresh on `152f36d`: `ci` (rtl-smoke and rtl-alignment failed on a bench bug fixed in `941082a`), `test-dispatch-rules test-reference-machine test-reference-machine-mmu` at width 1 and width 2 + LSU unit (11 PASS each), translated +0.476 / +0.117 ns. Fresh on `497429b`: chip +0.950 / +0.119 ns (15,385 ALMs), chip602 +0.245 / +0.118 ns (13,677). Fresh on `cc16ceb`: `lint check-spec`, `make -C toolchain rtl-all` (38 profiles), `test-chip602-pins test-chip-icache-real` at both widths. 66 MHz regressed to −3.3 to −5.5 ns (from −0.45 on `6cb15bb`). Failed: MiSTer `--fpu-compact --dual --lsu-pipe` does not route at 87% ALMs (seeds 2–5). See [LSU](LSU_PIPELINE.md#store-queue), [performance](PERFORMANCE_TARGET.md). |
| Batch 14, 2026-10-06 | 97.43% (unchanged) | Outside MVP scope: manual-mismatch fixes AUD-75/77/79/81/83 with regressions. Fresh: preflight, ci, references (width 1 and width 2 + LSU), chip and translated 50 MHz fits. Full 603e 81.20% → 81.53%. |

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
and combined timing dominate uncertainty. Sources stayed unchanged through
acceptance; the full legacy gate and separately added five-test gate both
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
and both historical measurement wrappers pass. All twenty compiled workloads pass on the final runner. Sources stayed
unchanged through the final compiled suite and negative controls; production RTL also stayed frozen through the broad regression.
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
Established RTL was unchanged.
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

Cache 80%, integration 82%; weighted 79.82% → 80.35%. Other scores stay fixed.
No new FPGA fit or timing claim; maintenance/remapping adverse cases are round 3.

## Translated-cache sequence: round 3 accepted, 2026-09-23

The canonical coherence gate passes 2,275 checks and 65 retirements: CPU BAT
remapping changes the physical tag; a CPU store to the same PA stays stale
until explicit invalidate plus accepted frontend restart; permission removal
prevents even a warm physical-cache probe. The drain gate passes 1,436 checks
and 47 retirements: maintenance waits for an accepted refill, redirect discards
old bytes, held completion blocks fetches, and one accepted beat followed by
TEA cannot publish a poisoned line. Reset restores execution.

Cache 80% → 85%, integration 82% → 85%; weighted 80.35% → 80.81%. The three rounds
move 79.32% → 80.81% (+1.49 points). Fetch remains 90%: the capacity fix closes an
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
Sources stayed unchanged through final acceptance.

The shared production change outside the new wrapper is the reviewed fetch
capacity gate. Legacy corpus fixtures now require IQ credit pressure instead
of naturally held instruction responses; their architectural scoreboards,
request/retirement backpressure and held-packet stability checks remain.
The 304-check standalone fetch gate retains explicit response backpressure.

Final weighted MVP estimate: **80.81% (about 81%)**, up from 79.32%.
Cache 85%, integration 85%; all other system scores stay fixed. Remaining effort
stays **6–10 / 8–14 engineer-weeks** for simulation / timing-checked FPGA
acceptance pending a combined-top fit and broader event/maintenance stress.

## Bounded cached-interrupt round — accepted, 2026-09-23

One orchestration round adds a CPU-programmed BAT/EE/IR test of an external
interrupt while an accepted translated cache refill is held. Four old beats
drain before event acceptance; the handler reads exact SRR0/SRR1, holds an
actual retirement stable under backpressure, and RFI resumes the alias through
a cache hit without a second physical refill. No stale target instruction
retires before the handler. Canonical strict simulation passes 1,051 checks
and 18 retirements. An independent review found no remaining blocker.

Fresh validation also passes the enabled/disabled core IRQ configurations,
three neighboring translated-cache gates and default/full-feature wrapper
lint. All production RTL is unchanged.
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

One implementation/review round adds DEC-to-EXT promotion while an accepted
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
wrapper lint profiles pass. Production RTL is unchanged. Full regression, Python and compiled firmware
results remain inherited; the registered build count is now 207, without a
claim that the full 207-configuration suite ran this round. No fit was run.

**MVP remains 80.81% (about 81%).** All system percentages and the 6–10 /
8–14 engineer-week ranges stay unchanged for this verification-only round.
This single boundary does not cover continuous timer cadence, high saved-MSR
mask differentiation, event/data or maintenance collisions, or timing closure.
See [timer/cache verification](TRANSLATED_ICACHE_TIMERS.md).

## Integrated timing-closure round — accepted, 2026-09-27

AUD-01 and AUD-16 changes close the cached physical top at the provisional
50 MHz constraint: slow-corner setup +1.316 / +1.653 ns (100 C / -40 C), from
-3.904 / -4.538 ns; all hold slacks positive; 11,576 ALMs, 3,072 MLAB bits.
Special-unit operands come from the committed GPR file; branch/ISYNC
redirects are registered one edge after commit (a taken branch costs one more
cycle); arbitrary-pivot recovery sits behind `ENABLE_TEST_REDIRECT`; GPR
sources are predecoded at IQ push; the GPR file has one write port and three
MLAB copies, with an update load's base write one edge after retirement.

Fresh: `make -C sim regression` (pass), `make -C toolchain rtl-all` (pass),
`./quartus/integrated/build.sh --docker`. The timer/BAT fit was not rerun.

**MVP 81.51% (about 82%), up from 80.81%:** FPGA fit/timing 35% → 45%.
Effort ranges are unchanged. See
[integrated fit](INTEGRATED_SYNTHESIS_BASELINE.md).

## RS result bypass (AUD-21) — accepted, 2026-09-27

A pending RS operand whose producer will occupy the IU is marked at capture
and takes the accepted IU result through a registered select, so the wake
compare and completion qualification leave the ALU → IU-operand loop while
dependent ops still issue back to back. Worst setup into the IU operand flops
went from +3.343 to +8.075 ns (slow 100 C); Fmax 53.67 → 54.10 MHz. Compiled
firmware cycle counts are identical before and after.

Fresh: `make -C sim -j2 regression` (pass, 420 PASS lines, 0 failures),
`make -C toolchain -j2 rtl-all` (24/24),
`./quartus/integrated/build.sh --docker`, commit `20424d7`.

**MVP stays 81.51%:** efficiency round, no row changes. See
[integrated fit](INTEGRATED_SYNTHESIS_BASELINE.md).

## Gate-1 MMU/event round — accepted, 2026-09-27

Direct-store segments (SR.T=1) raise DSI DSISR[5] (+[6] for stores) and ISI
SRR1[3] instead of a diagnostic (UM Table 5-3), completing the DSI/ISI causes
of the supported instructions. `tlbsync` decodes as a supervisor no-op with
TLBISYNC negated (UM §5.4.3.2). The new compiled image
`rtl-mmu-stress-cached` checks LRU replacement ways, R/C, tlbie/tlbsync
remapping, direct-store and page-fault DSI/ISI on the MVP-profile translated
cached top under seeded EXT/DEC (about 170 of each per run, every resume PC
checked), bus delays and retirement stalls, in nine modes; eight reset the
CPU during miss handlers, PTE reads and R/C writes, TLB loads and
invalidates, line fills, held IRQs and DEC entry, then require a clean
rerun. A wrong LRU update is caught (mailbox `0x8e000031`).

Fresh: `make -C sim regression` (436 PASS lines, 231 + 28 + 15 Python
tests), `make -C toolchain rtl-all` (25 profiles, ELFs rebuilt in the pinned
container), and `./quartus/translated/build.sh --docker`, which **misses
50 MHz setup by 0.351 ns** on the existing dispatch/completion path (see
[translated fit](TRANSLATED_SYNTHESIS_BASELINE.md)); hold meets. The FPGA row
stays at 45%.

**MVP 81.51% → 82.66% (about 83%):** page TLB 90% → 94%, supervisor 75% →
78%, interrupts/timers 85% → 88%, integration 85% → 87%. Effort ranges are
unchanged. See [stress evidence](MMU_STRESS_FIRMWARE.md),
[page DSI](PAGE_DATA_EXCEPTION_VERIFICATION.md),
[page ISI](PAGE_INSTRUCTION_EXCEPTION_VERIFICATION.md) and
[TLBSYNC](TLBIE_VERIFICATION.md).


## Cache maintenance and held-refill round — accepted, 2026-09-27

Gate 2: the cache control instructions ([contract](CACHE_CONTROL.md)) behind
`ENABLE_CACHE_INSTRUCTIONS`. CPU `icbi` drains an accepted fetch, its retried
or held line fill and response before clearing all four ways of the indexed
set, and cannot be withdrawn by a cut; `dcbf`/`dcbst`/`dcbi`/`dcbz` translate
as loads or stores and complete without a transfer, so DSI and TLB misses
follow the access class; a translated `dcbz` takes the caching-inhibited
alignment exception; `dcbt`/`dcbtst` are no-ops; user `dcbi` is privileged.
External maintenance keeps its own handshake and shares the drain.

Fresh on the merged tree (a038548, with AUD-21 and gate 1): `make -C sim
regression` (446 PASS lines, 274 Python tests), `make -C toolchain rtl-all`
(26 profiles) and `./quartus/translated/build.sh --docker`: setup meets every
corner (52.0 MHz) but hold misses by 0.198 ns at slow -40 C on the virtual
`retire_ready_i` input into the GPR MLAB address (zero-minimum virtual-I/O
assumption, same class as the timer/BAT hold; not gate-2 logic). Before the
merge (0a974ff) the same profile met setup and hold at 52.31 MHz. New
benches: managed-cache `icbi`, actual-core cache control and probe TLB misses,
the translated cache-operation bench, a four-seed cached-top stress and the
compiled cache-operation firmware. A pre-drain invalidate and a no-op `icbi`
are both rejected ([verification](CACHE_CONTROL_VERIFICATION.md)). The first
fit missed setup by 0.724 ns; tying off the special-lane cancel without the
test redirect fixed it ([fit](TRANSLATED_SYNTHESIS_BASELINE.md)).

**MVP 82.66% → 83.81% (about 84%), on top of gate 1:** instruction cache
85% → 95%, load/store 75% → 78%, supervisor/synchronous exceptions 78% → 80%,
60x transport 78% → 80%, integration 87% → 89%. Full-603e audit 46.29% → 46.79%. Remaining for
this area: page-table context changes under randomized ARTRY (gate 1's stress
has bus delays but no ARTRY), no data cache or HID0.

## Verification breadth round (2026-09-27)

Recorded: `make -C sim -j2 ci` and `make -C sim -j2 reference-acceptance`,
commit `4560b1a` (branch head; docs edits only uncommitted), 2026-09-27. Both
pass: `ci` runs regression (274 Python checks), the container firmware build,
27 compiled-firmware profiles and coverage in 54 minutes; reference acceptance
compares every DingusPPC profile plus 64 stress seeds at 512 blocks. The merge
onto main adds no RTL, so these results are inherited, not rerun.

The new retry target (`tb/bfm/bus60x_retry_target_bfm.sv`) adds seeded ARTRY,
one-to-three-cycle DRTRY with corrupted cancelled beats, and held tenures. The
MMU stress now changes SR, SDR1 and PTEs under those retries, runs a
page-crossing branch storm, remaps IBATs over cached lines and checks BAT
priority over resident TLB entries: 25 runs in 11 plain and 14 retry modes,
each with about 5,000–6,300 ARTRY and 3,100–4,000 DRTRY. Line coverage is
74.2% of `rtl/` points (minimum 72%) with every control case arm reached or
waived with a reason. Negative controls (VSID ignored in TLB lookup, DRTRY
ignored by the line reader) fail as required
([verification gates](VERIFICATION_GATES.md),
[MMU stress](MMU_STRESS_FIRMWARE.md)).

**MVP 83.81% → 85.01% (about 85%):** fetch 90% → 92%, branches 90% → 93%,
BAT/context 85% → 88%, segment/page 94% → 95%, 60x 80% → 83%, integration
89% → 94%. The full audit is unchanged (verification only). Open: TEA in the
stress (waits on machine check), DingusPPC comparison of the compiled corpus,
formal verification and toggle coverage.

## Load/store extensions round (2026-09-27)

Recorded: `make -C sim -j2 ci` and `make -C sim coverage` on the merge of the
load/store branch onto `2970961`, 2026-09-27; see
[verification](LOAD_STORE_EXTENSIONS_VERIFICATION.md). `lmw`/`stmw` and the
string forms crack into per-register micro-ops that restart precisely on a
mid-sequence DSI or TLB miss; `lwarx`/`stwcx.` keep a reservation per PEM
§4.2.6; byte-reverse forms; unaligned scalars split in hardware, with alignment
only for page crossings under DR=1 and the forms the manual requires. The
translated fit meets 50 MHz; Fmax fell from 65.37 to 61.40 MHz.

**MVP 85.01% → 85.94% (about 86%):** load/store 78% → 90%, integer 85% → 86%.
The integer audit found forms still missing: `tw`/`twi`, PVR/HID0/HID1/EAR
moves, `eciwx`/`ecowx`; undefined encodings and FP forms halt instead of taking
the illegal-instruction and FP-unavailable exceptions. A decode-completion round
owns them.

## Machine check, trace and IABR round (2026-09-28)

Recorded: `make -C sim -j2 ci` on `60e0916` and `./quartus/translated/build.sh
--docker` on `f90fcac` (same RTL), 2026-09-28; the merge onto main adds no
change. `ci` passes: 459 regression PASS lines, 274 Python checks, container
firmware build, 30 compiled-firmware profiles, coverage 75.9% (18 runs). The
translated fit meets 50 MHz setup and hold at every corner; Fmax 62.72 MHz
(slow 100 C), 9,714 ALMs.

`ENABLE_MACHINE_CHECK` turns TEA on fetches, line fills, loads and stores into a
machine check at 0x200 (ME cleared, checkstop when ME=0); `ENABLE_DEBUG_EXCEPTIONS`
adds single-step/branch trace at 0xD00 and IABR at 0x1300. On cracked multiple
and string instructions, trace arms only on the final micro-op, IABR marks the
instruction before cracking and a mid-sequence TEA or DSI restarts it whole
(16 scenarios, 1,578 checks per seed). The MMU stress adds seeded TEA with a
recovering handler: 96 and 86 TEAs, 85 and 77 machine checks in modes 14 and 15
([contract](EXCEPTION_MACHINE_CHECK_TRACE.md),
[verification](EXCEPTION_MACHINE_CHECK_TRACE_VERIFICATION.md)).

**MVP 85.94% → 87.46% (about 87%):** supervisor 80% → 92%, load/store 90% →
92%, 60x 83% → 88%, integration 94% → 95%. **Full audit 46.79% → 48.59%**,
covering this round and the load/store extensions: load/store 67% → 75%,
supervisor 70% → 80%, 60x 65% → 70%, coherence and reservations 0% → 10%
(local reservation, no snooping).

## Gate-3 timing round (2026-09-28)

Recorded: `make -C sim -j2 ci` and `./quartus/{translated,integrated,timer-bat}/build.sh
--docker` on `710b517` (timer-bat on `f4425cd`, same RTL and SDC), 2026-09-28; the
merge onto main adds no change. `ci` passes (coverage 75.9%). All three tops
meet 50 MHz setup and hold at every corner:

| Top | Setup slack, slow 100 C / -40 C (ns) | Worst hold (ns) | Fmax, worst slow corner | 66 MHz |
| --- | --- | ---: | ---: | --- |
| Translated | +4.763 / +4.672 | +0.116 | 65.24 MHz | misses by 0.176 ns |
| Cached physical | +4.239 / +4.178 | +0.133 | 63.20 MHz | misses by 0.670 ns |
| Timer/BAT | +5.771 / +6.116 | +0.122 | 70.28 MHz | meets |

The [interface timing contract](INTERFACE_TIMING_CONTRACT.md) defines clock,
reset, register-to-register boundary budgets, the falling-edge ABB/DBB release
and interrupt synchronization; each SDC cuts only port-to-boundary-register hops
and the reset synchronizer input. RTL: datapath payloads (IQ, RS, rename values)
lose their reset, the IQ output comes from a head register, the wake payload no
longer waits on the finish checks, and the special/IU result select uses the
registered busy flag. Behavior is unchanged. The cached-physical top was last fitted
before the load/store and machine-check merges, so its drop from 66.04 MHz is not
attributable to this round alone.

**MVP 87.46% → 90.26% (about 90%):** FPGA 45% → 85%. Remaining: final signoff
fits after the decode-completion merge, 66 MHz on the cached tops (I-cache data
through decode into the IQ).

## Full decode and final signoff round (2026-09-28)

Recorded: `make -C sim -j2 ci`, `./quartus/{translated,integrated,timer-bat}/build.sh
--docker` and `./quartus/report-target-paths.sh <top> --docker`, merge of the
full-decode branch (`1a98067`) onto `4ba4353` plus uncommitted merge
resolution, 2026-09-28. `ci` passes: 532 PASS lines, 231 + 28 + 15 Python
tests, container firmware build, 31 compiled-firmware profiles, coverage 76.6%
(1,414 of 1,847 lines, 19 runs). Every top meets 50 MHz setup and hold at every
corner:

| Top | Setup slack, slow 100 C / -40 C (ns) | Worst hold (ns) | Fmax, worst slow corner | 66 MHz |
| --- | --- | ---: | ---: | --- |
| Translated | +3.715 / +3.722 | +0.117 | 61.41 MHz | misses by 1.133 ns, 500 endpoints |
| Cached physical | +4.739 / +4.619 | +0.113 | 65.02 MHz | misses by 0.229 ns, 9 endpoints |
| Timer/BAT | +6.244 / +6.654 | +0.116 | 72.70 MHz | meets |

`ENABLE_FULL_DECODE` makes every 32-bit word execute or take the manual's
exception: illegal and invalid forms at 0x700, `tw`/`twi`, FP forms at 0x800
with MSR[FP] held 0, PVR/HID0/HID1/EAR, `eciwx`/`ecowx`, and the atomic and
external-control 60x transfer types ([contract](FULL_DECODE.md),
[verification](FULL_DECODE_VERIFICATION.md)). The larger decode sits on the
fetch-to-IQ path, so the translated Fmax fell from 65.24 to 61.41 MHz; the worst
66 MHz path runs from the I-cache data RAM through decode into the IQ entries.

**MVP 90.26% → 91.80%:** integer 86% → 90%, load/store 92% → 94%,
supervisor 92% → 95%, instruction cache 95% → 97%, FPGA 85% → 95%.

## Scope change (2026-09-28)

The user moved three items into the MVP: the data cache with MEI coherence and
snooping, a chip package whose exposed edges are the 603e pins, and a multiplier
matching the 603e's pipelined, early-out timing. The remaining contracted design
choices are accepted as MVP scope: single dispatch, one outstanding instruction
request, five rename/CQ slots (as on the 603e), big-endian only, and interrupt
and reset synchronization owned by the integrator per the
[interface timing contract](INTERFACE_TIMING_CONTRACT.md).

Weights change to make room for two rows: data cache 10%, chip package 4%;
segment/page 14 → 11, BAT 10 → 8, fetch, integer, rename, supervisor,
interrupts, 60x, instruction cache, toolchain and integration each lose one
point. Fetch and branches move to 100% and rename and interrupts to 95%, because
their remaining gaps were those accepted choices. **MVP 91.80% → 80.93%**
under the new weights; this is a denominator change, not lost work.

## Fetch-to-decode and signoff round (2026-09-28)

Recorded: `make -C sim -j2 ci` and `./quartus/{translated,integrated,timer-bat,chip}/build.sh
--docker` with `./quartus/report-target-paths.sh <top> --docker`, merge of
`fetch-decode-stage` onto `e73215f` plus uncommitted merge resolution,
2026-09-28. `ci` passes: 538 PASS lines, 231 + 28 + 15 Python tests, container
firmware build, every compiled-firmware profile, coverage 76.3% (1,418 of 1,859).

| Top | Setup slack, slow 100 C / -40 C (ns) | Worst hold (ns) | Fmax | 66 MHz |
| --- | --- | ---: | ---: | --- |
| Translated | +5.899 / +6.028 | +0.110 | 70.92 MHz | meets |
| Cached physical | +6.338 / +6.339 | +0.111 | 73.21 MHz | meets |
| Timer/BAT | +5.706 / +5.584 | +0.072 | 69.85 MHz | meets |
| Chip (`ppc603e`) | +5.029 / +4.899 | +0.118 | 66.22 MHz | meets |

A one-entry register between fetch and the IQ holds the fetched word, PC, fault
and miss context, so the I-cache RAM output is registered before decode; firmware
CPI rises 1.1%. The residuals bench was missing the chip branch's pin ports after
the earlier merge (`e73215f` fixes it); the combined run above passes.

**MVP 88.84% → 89.05%:** FPGA 95% → 98%.

## Data cache integration round (2026-09-28)

Recorded: `make -C sim -j2 ci`, `./quartus/{translated,chip}/build.sh --docker` and
`./quartus/report-target-paths.sh <top> --docker`, merge of the data-cache
integration branch (`3529a0e`) onto `b907e59` plus uncommitted merge resolution,
2026-09-28. `ci` passes: 553 PASS lines, 231 + 28 + 15 Python tests, 37
compiled-firmware profiles, coverage 75.8% (1,752 of 2,311). The translated top
(66.74 MHz) and chip top meet 50 MHz and 66 MHz at every corner with no failing
endpoint at 15.152 ns; cached physical (72.86 MHz) and timer/BAT (75.36 MHz)
fits come from the branch, whose changes do not touch their files.

The cache now reaches the pins: a third 60x master handles fills, castouts,
single beats and address-only tenures, the snooper answers other masters' global
tenures with ARTRY in the manual's window and pushes modified lines first, and
`ppc603e` enables the cache (HID0[DCE]=0 at reset; the chip boot code sets DCE
after ICE). Coherence is checked at the pins against a DMA master on three seeds
(about 15k DMA tenures each, 116–128 retried, 123–135 pushes).

**MVP 91.25% → 95.73%:** data cache 55% → 90%, load/store 94% → 97%, 60x 88%
→ 95%, chip package 90% → 97%, FPGA 98% → 99%.

## MVP signoff (2026-09-29)

Recorded: `make -C sim release-check RELEASE_ARGS="--allow-dirty -j 2"`, merge of the
MVP-gaps branch (`c55ed4c`) onto `94d7ed5` plus uncommitted merge resolution,
2026-09-29. Every step passes: `ci` (552 PASS lines, coverage 76.5%, 1,773 of
2,317), `reference-acceptance`, and the translated, cached-physical, timer/BAT
and chip fits with STA and 66 MHz target paths.

| Top | Setup slack, slow 100 C / -40 C (ns) | Worst hold (ns) | Fmax | 66 MHz |
| --- | --- | ---: | ---: | --- |
| Translated | +5.050 / +5.111 | +0.107 | 66.89 MHz | meets |
| Cached physical | +5.643 / +5.706 | +0.101 | 69.65 MHz | meets |
| Timer/BAT | +5.802 / +5.890 | +0.118 | 70.43 MHz | meets |
| Chip (`ppc603e`) | +5.138 / +5.175 | +0.118 | 67.29 MHz | meets |

This round adds page-table WIMG tests with the data cache, guarded loads that
never reach the bus speculatively, snooping of pipelined address tenures from
other masters, and address-parity checking on snooped tenures; DBWO stays
ignored as the manual permits here.

**MVP 95.73% → 97.20%.** Remaining gaps are listed in the rows; none blocks
the release.

