# PowerPC 603e implementation task plan

Date: 2026-09-12. Scope: CPU-only SystemVerilog core, Verilator verification, and Cyclone V fit/timing evidence. The intended final machine retains the original brief's 603e structure, full architectural features, dual dispatch, and documented timing/60x protocol fidelity. Board integration is excluded. This document decomposes that brief into assignable work; it does not certify the original brief's technical assumptions.

## Baseline and task conventions

**P00, P01 and P04 are complete. P02 timing-table and diagram transcription is accepted with explicit interpretation gaps; bus contracts remain partial. P03a–P03f metadata slices cover the initial subset, ADD, register logical, rotate, shift and compare families; 168 forms execute in RTL, including the bounded serialized control/memory milestone. P05 tagged execution now serves 168 forms, and P06b connects explicit local recovery; full timing/ISA prerequisite gates remain open. P04’s early fit succeeds, with setup/hold timing unmet and assigned to later closure work. P13 now includes bounded actual-handler/RTL comparison; full P13 acceptance remains queued.** See [WORK_QUEUE.md](WORK_QUEUE.md) for assignments, ownership and review status; [PROGRESS.md](PROGRESS.md) records the approximate overall completion after each round. The first pass provides an executable single-dispatch integer scaffold, not completion of the original plan's Phase 0 or Phase 1. Comprehensive instruction semantics, full vector execution, remaining specification coverage and processor conformance are still open; toolchain and early Quartus setup have since been completed.

For each task, copy its ID/title, prerequisites, scope, and acceptance criteria into an issue. Attach the relevant source references and test results to its completion record. If a task is too large, split it by instruction family or protocol scenario while retaining its parent ID and acceptance gate. The FPU and cache tasks in particular should become several implementation issues once their contracts are reviewed.

Every RTL task must pass strict RTL lint plus the existing regression and its feature-specific tests. Docs-only tasks require review of source references and unresolved assumptions. A feature is done only when implementation and its acceptance test land together. No empty/stub module counts as a completed execution unit, and diagnostic halt is never counted as an implemented architectural exception.

## Dependency overview

| Milestone | Required tasks | Result |
|---|---|---|
| Executable scaffold | P00 | Completed: minimal integer path with rename and ordered retirement |
| Reviewed contracts/tooling | P01–P04 | Source-backed ISA/timing/bus contracts and reproducible tools |
| Integer machine | P05–P12 | Tagged execution, recovery, branches, integer ISA, real-mode LSU, dual dispatch, timing harness |
| Supervisor/reference | P13–P16 | Reference comparison, precise state/exceptions, system operations |
| Memory system | P17–P22 | MMU, 60x bus/BFM, caches, coherency, reservations |
| Floating point | P23–P25 | FP state, arithmetic, special cases, timing and comparison |
| Full integration | P26–P29 | Endian modes, variants, platform signals, complete regressions |
| FPGA delivery | P30 | Measured fit/resources and 50 MHz timing closure |

Useful independent work after contracts: the reference adapter P13, bus BFM P18, and build setup P04. After supervisor state exists, the FPU work can proceed independently of cache implementation. Integration dependencies remain mandatory even if testbench-driven unit work starts earlier.

## Foundation

### P00 — Executable CPU scaffold [DONE]

- **Prerequisites:** original brief.
- **Delivered:** `rtl/ppc_{pkg,fifo,fetch,decode,iu,regfile_gpr,rename,completion,core}.sv`, explicit file list, simulation Makefile, self-checking core bench, README and architecture/status/task documents.
- **Acceptance evidence:** `make -C ppc603e/sim all` passed with Verilator 5.020; three runs of 256 checked results plus illegal/Rc/OE rejection and reset/backpressure checks.
- **Original boundary (superseded by P05 preparation below):** seven instruction forms; one dispatch/retirement lane; finished results inserted directly into CQ; abstract fetch transport. No architectural exception or 60x implementation.

### P01 — Audit source coverage and freeze architectural assumptions [DONE]

- **Accepted evidence:** [SOURCES.md](../../references/SOURCES.md), [REFERENCE_AUDIT.md](../../REFERENCE_AUDIT.md), and [CODING_CONVENTIONS.md](../../CODING_CONVENTIONS.md). Primary inventory and decisions are reviewed; unresolved feature evidence has assigned owners.

- **Prerequisites:** P00.
- **Deliver:** `docs/SOURCES.md` with PDF page versus printed-page mapping, available/missing chapters, reference precedence, model/revision distinctions, and an explicit decision log. Locate the HDL guideline referenced by the original brief; if unavailable, document local coding conventions. Audit DingusPPC license and semantic/model coverage before integration.
- **Acceptance:** verify manual completeness rather than repeating the abridgement estimate; identify primary evidence for queue/resource sizes, reset state, endian fetch/data behavior, FPU/variant capabilities, and uncertain bus rules. Each unresolved item has an owner/task and a conservative implementation boundary. Original resource estimates are labeled unmeasured.

### P02 — Transcribe timing and bus contracts

- **Prerequisites:** P01.
- **Deliver:** reviewed `TIMING_SPEC.md`, `BUS_SPEC.md`, machine-readable timing rows and bus scenario manifest under `sim/spec/`. Use chapter 6 tables/rules/schedules and chapter 7/8 pin/tenure diagrams from available source material.
- **Accepted bounded address/lane tables:** [BUS_ADDRESSING.md](../../references/BUS_ADDRESSING.md) now covers Tables 8-4 through 8-7, including physical DH lanes in 32-bit mode and two-beat aligned doublewords. Endian steering, CPU-address translation, cache transaction selection and full bus timing remain open.

- **Acceptance:** every row/scenario has section/page provenance, mode conditions, and a precise observation point; ambiguous rules remain marked unresolved. Distinguish dispatch, execute finish, completion, throughput, signal assertion polarity, and sampling cycles. No checker derives its expected behavior solely from RTL.

### P03 — Build the full ISA/variant matrix and decoder metadata

- **Prerequisites:** P01, P02.
- **Deliver:** exhaustive machine-readable opcode/form table, generator and generated `ISA_MATRIX.md`; include unit, operands, writes, privilege, serialization, latency reference, and per-variant legality. Preserve OE/Rc and reserved-bit distinctions.
- **Acceptance:** reconcile 603e supported/unsupported instructions with source listings; detect overlapping decode patterns; ensure every implemented decode entry and every required form has a matrix row. Keep unverified 602 behavior explicitly pending.

### P04 — Reproducible simulation, cross-toolchain, and early synthesis setup [DONE]

- **Accepted evidence:** [BUILD_STATUS.md](../../BUILD_STATUS.md), reproducible BE/LE artifacts, canonical lint/regression, and saved Cyclone V reports with 35 virtual/zero physical pins. This task requires an early fit, not final timing closure; negative setup/hold slack remains explicit P30 work.

- **Prerequisites:** P00, P01.
- **Deliver:** cross-compiler container/build recipe, `crt0.S`, linker script, tohost test convention, BE/LE targets; Quartus project/SDC and core-only measurement wrapper; build scripts and tool version recording. Preserve local smoke testing without Docker.
- **Acceptance:** compile/disassemble a tiny test with expected byte order; lint and run the existing bench from documented commands; run an early synthesis/fit to expose unsupported constructs and report resources without claiming final timing. Confirm the actual target device/tool availability. Never configure hundreds of abstract debug pins as board I/O.

## Integer execution and recovery

### P05 — Tagged dispatch, reservation station, and unfinished completion entries

- **Accepted preparation:** width-one tagged IU foundation for the existing seven forms, including a pending-operand reservation station, registered issue/result channel, owner-checked rename wakeup, and unfinished CQ entries. See [EXECUTION_CONTRACT.md](../../EXECUTION_CONTRACT.md). Strict lint and the existing 768-result regression pass; focused completion and execution checks cover adversarial ownership and backpressure.
- **P05c evidence:** [STAGE_TIMING.md](../../STAGE_TIMING.md) binds an actual-core trace to the current implementation contract, with 14 checked instructions and 18 checker tests. [TIMING_DECISIONS.md](../../TIMING_DECISIONS.md) fixes current-subset event bindings while retaining the extra dispatch interval, conservative completion spacing and graphical/deallocation fidelity questions.
- **Parent boundary:** full P02/P03 contracts and source-reconciled timing observation points remain open. This implementation stage is not full P05 timing conformance, a flush protocol, or proof of unlimited stale-token rejection across generation wrap.

- **Prerequisites:** P02, P03.
- **Deliver:** `ppc_dispatch.sv`, registered IU issue/result channels, operand-ready tags and wakeup, CQ allocation at dispatch and finish-by-tag, generation/epoch handling for reused entries. Keep width one initially.
- **Acceptance:** delayed results can finish out of order but retire in order; RAW/WAW hazards and full resources stall correctly; no double allocation/release; a result for a stale generation cannot corrupt a reused entry. Adopt P02 observation points for timing.

### P06 — Precise flush and architectural recovery

- **Accepted P06a preparation:** [RECOVERY_CONTRACT.md](../../RECOVERY_CONTRACT.md) and the executable policy model cover prefix age cuts, simultaneous events, survivor mappings, finite producer lifetime and untagged fetch drain. Fifteen tests pass after independent review. A standalone [prefix-selector RTL prototype](../../RECOVERY_SELECTOR.md) passes 245,760 snapshot checks; it is not connected to the CPU. Bounded local recovery integration is admitted by P05d; full parent prerequisites remain open.

- **Accepted P06b1 backend:** [RECOVERY_BACKEND.md](../../RECOVERY_BACKEND.md) implements sequential CQ prefix recovery, rename survivor reconstruction and local RS/IU cancellation. Direct state/cancellation benches pass 5,871/1,066 checks, and existing no-redirect regressions pass. P06b2 now connects frontend drain, IQ clearing and diagnostic-state integration through explicit core control. This does not complete P06.

- **Accepted P06b2 current-subset integration:** [CORE_RECOVERY.md](../../CORE_RECOVERY.md) documents accepted redirect events, old-request drain, latest-target selection and diagnostic cleanup. The actual-core independent stream scoreboard passes 985 checks and the direct fetch bench passes 99. Branch/exception decode, external producer recovery and full parent conformance remain open.

- **Prerequisites:** P05.
- **Deliver:** age-aware kill/redirect protocol for IQ, units, CQ, rename map and outstanding fetch; restore surviving mappings or reconstruct them. Make memory responses safe across redirects using cancellation/drain or transaction epochs.
- **Acceptance:** redirect with full queues, multiple writers to one GPR, simultaneous finish/commit/flush, and delayed old responses; preserve all older effects and eliminate every younger effect. No speculative store reaches memory.

### P07 — Integer ALU and CR/XER semantics

- **Accepted P07a contract:** [CR_XER_CONTRACT.md](../../CR_XER_CONTRACT.md) defines one in-flight flag owner, allocation-controlled masks, committed CA/SO capture, atomic retirement and recovery. It is a bounded implementation contract, not flag RTL.
- **Accepted P07b non-record logical slice:** [LOGICAL_EXECUTION.md](../../LOGICAL_EXECUTION.md) adds eight executable forms. The actual-core bench passes 94 logical results, all eight record-form rejection cases and registered timing checks; existing regressions pass. The [CX-I01/I02 foundation](../../FLAGS_STATE.md) adds independent flag references, allocated CQ deltas and committed CR/XER owner control. The [CX-I03 record-logical slice](../../RECORD_LOGICAL.md) now adds owner-gated dispatch, captured SO and CR0 execution, with independent full-core commitment/recovery tests. The [ADD/ADDC slice](../../ADD_FLAGS.md) adds CA/OV/SO execution; [ADDE](../../ADDE.md) now adds captured carry input. [ADDME/ADDZE](../../ADD_UNARY.md) now complete the reviewed ADD family; other integer families remain pending.

- **Prerequisites:** P03, P05.
- **Accepted P07 logical-shift slice:** [LOGICAL_SHIFTS.md](../../LOGICAL_SHIFTS.md) implements SLW/SRW Rc0/Rc1 with full six-bit count, preservation and recovery checks. [SRAW/SRAWI](../../ARITHMETIC_SHIFTS.md) now implement CA replacement and both Rc forms with independent program and recovery coverage.
- **Accepted P07 compare slice:** [CONTROL_MEMORY.md](../../CONTROL_MEMORY.md) executes all four L=0 compares, selected-field CR masks and committed-SO capture; source and preservation checks cover every BF.
- **Accepted P07 rotate slice:** [ROTATE_EXECUTION.md](../../ROTATE_EXECUTION.md) implements RLWINM/RLWNM with both Rc values; [RLWIMI](../../ROTATE_INSERT.md) now implements both Rc forms using renamed old-rA and a separately captured SH.
- **Accepted P07 SUBF/NEG slice:** [SUBTRACT_NEGATE.md](../../SUBTRACT_NEGATE.md) implements eight OE/Rc forms with CA preservation, signed overflow and exact NEG reserved-field rejection. [SUBFC](../../SUBFC.md) now implements four carry-writing OE/Rc forms; [SUBFE](../../SUBFE.md) now implements captured carry input in four OE/Rc forms. [SUBFME/SUBFZE](../../SUBTRACT_UNARY.md) now implement eight OE/Rc forms with fixed operands, reserved-field rejection and captured carry. [SUBFIC](../../SUBFIC.md) now implements signed immediate subtraction and carry replacement. [ADDIC/ADDIC.](../../ADD_IMMEDIATE.md) now implement signed immediate carry arithmetic and primary-opcode-selected CR0 recording. [ANDI./ANDIS.](../../AND_IMMEDIATE.md) now implement unsigned immediate masks with unconditional recording. [CNTLZW/EXTSB/EXTSH](../../UNARY_LOGICAL.md) now implement six unary Rc forms with reserved-field rejection and XER preservation. [MFCR/MTCRF](../../CR_TRANSFERS.md) now implement full-CR reads and selected-field writes with precise recovery. [Eight CR logical operations](../../CR_LOGICAL.md) now implement snapshot-based Boolean operations with allocation-controlled single-bit writes. [MCRF/MCRXR](../../CR_STATE.md) now implement captured whole-field moves and atomic XER status transfer/clear. Full integer reference acceptance remains queued.
- **Deliver:** remaining integer arithmetic, logical, rotate/mask, shifts, extensions and compares; CR/XER result fields and rename/commit handling, including carry/overflow/sticky SO and Rc forms.
- **Acceptance:** directed boundary cases plus supported integer CSV subsets through a documented adapter; wraparound, signed comparison, shift limits, mask wrap, carry chains, CR fields, OE/Rc combinations; expand the ISA matrix only for tested forms.

### P08 — Multiply/divide execution and scheduling

- **Accepted functional slice:** [MULLI/MULLW](../../MULTIPLY_LOW.md) implement five forms through the existing registered IU. [MULHW/MULHWU](../../MULTIPLY_HIGH.md) add four high-word forms. [DIVWU](../../DIVIDE_UNSIGNED.md) adds four unsigned divide forms with a documented zero-divisor result policy. [DIVW](../../DIVIDE_SIGNED.md) adds four signed divide forms with guarded zero and signed-overflow policies. [DIVIDER_TIMING.md](../../DIVIDER_TIMING.md) adds 20/37-cycle divide reservation and delayed finish with cancellation. A synthesizable 16-step radix-4 divider now supplies the quotient while preserving those timing and recovery rules. Multiply now uses conservative maximum-latency reservations (MULLI 3, MULLW/MULHW 5, MULHWU 6) with held-result and cancellation semantics. The operand-to-latency mapping and remaining P08 scheduling/closure gates remain open; P08 is not complete.

- **Prerequisites:** P02, P05, P07.
- **Deliver:** multiply and iterative divide datapaths, operand-dependent/variant timing where documented, unit reservation and result arbitration.
- **Acceptance:** signed/unsigned edge cases and source-defined undefined-result treatment; resource contention and flush during long operations; measured latency/throughput against P02, with no stale writeback after kill.

### P09 — BPU, branches, prediction and folding

- **Accepted bounded functional slice:** [CONTROL_MEMORY.md](../../CONTROL_MEMORY.md) supplies serialized b/bc/bclr/bcctr, committed LR/CTR moves and BF-selected comparison dependencies. Prediction, folding, speculative SPR rename and full branch timing remain pending; full P09 is not complete.

- **Prerequisites:** P02, P06, P07.
- **Deliver:** `ppc_bpu.sv`, unconditional then conditional/LR/CTR branches, CR/LR/CTR dependencies and rename, static prediction and one unresolved prediction, folding and fetch redirect.
- **Acceptance:** taken/not-taken, relative/absolute, link, CTR decrement, dependent CR/LR/CTR, misprediction with late results; source-backed folded branch accounting and chapter 6 branch schedules. Confirm branch effects appear correctly in architectural traces.

### P10 — Real-mode LSU and committed stores

- **Accepted bounded functional slice:** [CONTROL_MEMORY.md](../../CONTROL_MEMORY.md) supplies aligned non-update integer D/indexed loads/stores, big-endian lanes, a latched store reservation and killed-load response drain. The [update-form slice](../../LSU_UPDATE.md) adds 14 aligned forms and atomic base/data retirement. Two-stage pipelined timing, split unaligned accesses and architectural fault delivery remain pending; full P10 is not complete.

- **Prerequisites:** P06, P07.
- **Deliver:** two-stage LSU with uncached data request/response interface, effective address generation, scalar integer loads/stores and update/indexed forms, sign extension, alignment classification, store queue and fault hooks.
- **Acceptance:** address/byte-lane boundary cases, read/write dependencies and backpressure; killed stores never issue externally; data failures preserve precise ordering. Architectural exception vectoring integrates through P14. Endian support comes through P26.

### P11 — Dual dispatch and dual completion

- **Prerequisites:** P05, P07, P09, P10.
- **Deliver:** two-wide IQ access/admission, operand reads, atomic multi-resource allocation, two completion candidates and commit ports; enforce unit, dependency, destination and serialization restrictions. Enable `DISPATCH_WIDTH=2` only when implemented.
- **Acceptance:** source-backed legal pairs dispatch/retire together; forbidden pairs stall the correct slot; same-GPR/CR conflicts, resource exhaustion and first-slot fault/redirect tested; width-one and width-two runs have identical architectural traces.

### P12 — Timing conformance harness

- **Prerequisites:** P02, P08, P09, P11.
- **Deliver:** `tb/timing/` issue/finish/complete event monitors, generated per-row tests, and manual worked-schedule replays; make missing rows fail coverage checks.
- **Acceptance:** implemented integer timing rows and chapter 6 schedules pass. Extend this harness with each subsequent unit. Any deviation has a source-linked explanation and explicit disposition; a mismatch cannot silently become the expected value.

## Supervisor state and architectural comparison

### P13 — DingusPPC architectural reference adapter

- **Bounded executable slice:** [REFERENCE_RUNNER.md](../../REFERENCE_RUNNER.md) compares actual RTL traces with original local integer/branch/CR/SPR handlers and detects injected field/trace mismatches. The v2 full-RAM corpus covers all 168 currently implemented forms, including the 28 scalar memory forms, using original instruction handlers with an explicit flat memory service. Whole-machine dispatch, upstream full integer/FP suites and architectural exception comparison stay open.

- **Prerequisites:** P01, P03, P05.
- **Deliver:** isolated reference build/test adapter under `sim/cosim/`, CSV parser, encoded-program runner, retirement/state comparator and mismatch artifacts. Audit actual vector counts and variants.
- **Acceptance:** upstream integer/FP reference tests build and run, supported core subset compares, an injected mismatch is detected with first divergent instruction/state. Document oracle gaps, undefined behavior policy and licensing. Do not treat the reference as a cycle oracle.

### P14 — Supervisor registers and precise exceptions

- **Incremental register slice:** [SPRG0–SPRG3](../../SPRG_INTEGRATION.md) adds eight exact opt-in MFSPR/MTSPR forms, supervisor checks before allocation, commit-owned full-width state, cancellation and hard-reset behavior. This is scratch-register coverage only; it does not complete P14 or add new event classes.

- **Bounded standalone slice:** [exception state](../../EXCEPTION_STATE.md) provides MSR/SRR0/SRR1 transitions for selected SC/program/RFI events, with source-qualified masks, held results and explicit rejection. The caller must supply a precise committed boundary. The [opt-in CPU integration](../../SUPERVISOR_INTEGRATION.md) adds actual SC/RFI, selected illegal/privileged events, MFMSR and SRR access with precise serialized state changes and fetch recovery. Full event priority, other fault sources, MTMSR/CSR coverage and architectural reset remain open; P14 is not complete.

- **Prerequisites:** P06, P07, P10, P13.
- **Deliver:** `ppc_spr.sv`, `ppc_exc.sv`, MSR/SRR/DAR/DSISR, privilege checks, system call, traps, `mtmsr`/`rfi`, exception priority/vector selection, SPR access and reset semantics. Replace diagnostic halt with architectural fault entry.
- **Acceptance:** directed entry/return, masking, SRR contents, oldest-fault selection and younger cancellation; enumerate every vector and mark hardware sources pending until integrated. Retain diagnostic halt only as an explicit test/debug facility, if needed.

### P15 — System unit and serialized/multi-access instructions

- **Bounded executable slice:** [ISYNC/SYNC/EIEIO](../../SERIALIZATION_INTEGRATION.md) now execute in the opt-in profile, drain older implemented work and block younger effects through retirement. ISYNC refetches PC+4 through accepted recovery. Cached modified-code protocols, global coherent ordering, multi-access instructions and decoded cache/TLB channels remain open; P15 is not complete.

- **Prerequisites:** P10, P14.
- **Deliver:** SRU CR/SPR operations, `lmw`/`stmw` and string instruction sequencing, `sync`/`eieio`/`isync` execution rules, cache/TLB command channels, dispatch/completion/refetch serialization classes.
- **Acceptance:** source-defined partial effects and restart state on mid-sequence faults; string counts/register wrapping; barrier ordering; no younger memory/system effects across serialized instructions. Cache/TLB command behavior completes with P17/P22.

### P16 — Time base, decrementer, interrupts, debug exceptions

- **Prerequisites:** P14.
- **Deliver:** TB/TBEN, DEC, external interrupt/SMI/machine-check request arbitration, trace and IABR, synchronized external-control ingress where required.
- **Acceptance:** rollover, masking/unmasking, simultaneous sources, precise PC/state and priority; test every implemented event vector against chapter 4. Pin-driven power/checkstop integration remains P28.

## Translation and external memory

### P17 — BAT, segments, software-loaded TLB and miss handling

- **Segment storage slice:** the [standalone segment-register bank](../../SEGMENT_REGISTERS.md) implements sixteen descriptors, direct/indexed selection and a held internal snapshot. CPU move instructions and TLB context routing remain separate increments. The local zero-reset policy is not a silicon SR initialization guarantee.

- **Next bounded preparation:** [segment-register contract](../../SEGMENT_REGISTER_CONTRACT.md) records exact four-form encodings, privilege, T-dependent fields, reset and context-synchronization rules. It is a proposed next slice, with no new implemented instruction or MMU credit.

- **Bounded standalone slice:** [BAT translation](../../BAT_TRANSLATION.md) provides four-pair selected-bank translation, real-mode bypass, PP/WIMG, guarded/protection checks and explicit local invalid-configuration outcomes. The [committed BAT service](../../BAT_SERVICE.md) adds both banks, privileged SPR requests and held translation responses. The [BAT CPU wrapper](../../CORE_BAT.md) adds actual instruction/data routing under a fixed startup context; the separate [page TLB service](../../TLB_SERVICE.md) adds both 64-entry banks, page permissions, software-selected refill and indexed invalidation. Live CPU SPR/MSR routing, segment state, integrated page lookup/miss handlers and architectural fault delivery remain open; P17 is not complete.

- **Prerequisites:** P14, P15.
- **Deliver:** I/D MMUs, BATs, segment state, TLB arrays/replacement, miss SPR generation and TGPR switching, permissions/WIMG, TLB-management operations and synchronization hooks.
- **Acceptance:** real/BAT/TLB paths, privilege/protection faults, instruction/data misses, R/C scenarios and invalidation; execute reviewed manual example miss handlers. Use architectural comparisons only where the reference implements the relevant model. Variant-specific TLB behavior remains gated by P27.

### P18 — Independent 60x bus-functional model and checkers

- **Bounded executable slice:** [BUS_MASTER.md](../../BUS_MASTER.md) adds a task-driven scalar target and adversarial tests, plus a separately written core RAM responder. [BUS_INTEGRATION.md](../../BUS_INTEGRATION.md) adds arbiter ownership/fairness, instruction-error checks and independent instruction/data pin integration. Full P02 scenario mapping and independent checker mutation coverage remain open.

- **Prerequisites:** P02.
- **Deliver:** `tb/bfm/bus60x_bfm.sv`, memory/arbiter/snoop agents, signal-level assertions and programmable waits/retry/error injection; cycle-table replay runner.
- **Acceptance:** all P02 scenarios map to tests; deliberately malformed transfers trip each checker; validate the BFM separately so shared CPU/BFM mistakes cannot define the protocol.

### P19 — 60x bus master and physical signal wrapper

- **Bounded executable slice:** [BUS_MASTER.md](../../BUS_MASTER.md) implements single-outstanding 64-bit scalar transfers, grants/waits, ARTRY/DRTRY, TEA and explicit OEs with core data integration. The [unified wrapper](../../BUS_INTEGRATION.md) connects both core transports with captured instruction/data attributes. A separate [line-read master](../../BUS_LINE_READ.md) adds four-beat cacheable reads, critical-doubleword wrapping, retries/errors and full-line responses. A [cached-core wrapper](../../CACHED_BUS_INTEGRATION.md) now shares line refill and scalar data on physical pins. Burst writes, pipelining, parity, snooping, other modes and full timing acceptance remain open.

- **Prerequisites:** P02, P18.
- **Deliver:** `ppc_bus60x.sv`, independent address/data tenures, bounded pipelining, grants, retries, late cancellation, error reporting, address-only transactions, 32/64-bit transfers, output enables and parity paths.
- **Acceptance:** source-backed tenure diagrams reproduced; all BFM checks pass including overlapping tenures, ordering, ARTRY/DRTRY/TEA and mode-specific beat order. Snoop response plumbing is present; cache intervention completes at P22.

### P20 — Instruction cache and fetch/MMU integration

- **Bounded standalone slice:** `ppc_icache` supplies 16-KiB physical storage, strict four-way LRU, complete-line refill, local invalidate and killed-refill drain. The [cached-core wrapper](../../CACHED_BUS_INTEGRATION.md) now connects actual CPU fetch and shares the physical bus with scalar data. The [cached reference](../../REFERENCE_CACHED.md) covers all 168 implemented forms through that path. The [managed wrapper](../../ICACHE_CONTROL.md) adds local full-invalidate and scalar bypass, verified with explicit CPU restart for changed code and all-form reference profiles. MMU integration, decoded architectural controls, early forwarding and FPGA storage inference remain open; P20 is not complete.

- **Prerequisites:** P09, P17, P19.
- **Deliver:** I-cache tags/data/strict four-way LRU, line refill and critical-word handling, invalidate/lock/disable controls, instruction translation and fetch-fault integration; storage suitable for M10K inference.
- **Acceptance:** hit/miss/conflict/replacement, killed refill, boundary fetch, execute faults, invalidation/refetch and source-defined cache control; run integer tests through bus-backed instruction fetch.

### P21 — Data cache and LSU/MMU integration

- **Prerequisites:** P10, P17, P19.
- **Deliver:** D-cache tags/data/replacement, write-back, castout queue, WIMG routing, store/refill ordering and fault propagation; storage inference checks.
- **Acceptance:** dirty eviction and refill overlap, stalled bus, byte updates, inhibited/guarded mappings and access faults; all real-mode and translated LSU tests run through the cache. Coherent intervention remains P22.

### P22 — MEI coherency, cache operations and reservations

- **Prerequisites:** P15, P18, P20, P21.
- **Deliver:** snoop lookup/intervention/push, MEI transitions, cache-management bus effects, touch/zero/flush/invalidate instructions, `lwarx`/`stwcx.`, RSRV and TLB synchronization integration.
- **Acceptance:** manual MEI transition matrix, modified snoop push, retries while casting out, local/external reservation invalidation, success/failure CR effects, code-store plus cache-sync/refetch sequences. Cache/BFM tests must observe external effects, not just internal state.

## Floating point

### P23 — FPR/FPSCR, FP dispatch and memory path

- **Prerequisites:** P03, P05, P10, P14.
- **Deliver:** 32 FPRs, four FPR rename slots, FP operand/result channels, FPSCR/CR update rules, FP-unavailable exception, FP loads/stores and moves/conversions scaffolding that rejects unimplemented arithmetic.
- **Acceptance:** FPR hazards and commit limits, memory bit preservation, FP enable/disable and precise faults; unknown FP operations cannot retire as successful results.

### P24 — Pipelined FPU arithmetic and rounding

- **Prerequisites:** P02, P23.
- **Deliver:** source-backed add/subtract/multiply/fused operations, single/double precision, normalize/round/convert stages, comparisons and FPSCR semantics; split by operation family into child issues.
- **Acceptance:** appropriate audited FP vectors, independent edge cases across rounding modes, NaNs/infinities/zeros/denormals, cancellation and fused rounding; pipeline throughput, CR/FPSCR ordering and kill behavior.

### P25 — Iterative FP operations and complete FP verification

- **Prerequisites:** P12, P13, P24.
- **Deliver:** divide and supported estimate operations, documented special modes, variable-latency scheduling, complete FP matrix and cosim/timing coverage.
- **Acceptance:** audited vector suite under applicable rounding modes, special-value/exception cases, estimate accuracy according to source, multi-instruction FPSCR behavior and all implemented FP timing rows. Keep unsupported operations explicitly illegal/unavailable as specified.

## Modes, integration, and delivery

### P26 — Endian behavior and alignment end to end

- **Prerequisites:** P02, P14, P17, P20, P21, P22, P23.
- **Deliver:** verified instruction/data endian rules, MSR LE/ILE entry transitions, address and lane transformations, byte-reverse forms, misalignment behavior and multi-access restrictions by supported revision.
- **Acceptance:** BE/LE compiled tests plus independently encoded byte images; cross-line and misaligned accesses, exception entry/return, cache/bus byte-lane checks and supported reference LE comparisons. Resolve the original brief's instruction-fetch/endian assumptions from primary evidence first.

### P27 — CPU capability variants

- **Prerequisites:** P01, P03, P08, P17, P22, P25, P26.
- **Deliver:** one reviewed capability/configuration record for default PID7v 603e and each enabled alternative (PID6, 603, 602, EC603e as verified); PVR, cache/TLB geometry, instruction legality, FP availability and timing differences.
- **Acceptance:** every enabled configuration has dedicated legality, geometry, timing and mode tests; unresolved 602 behavior remains explicitly experimental/disabled rather than guessed full support. Missing primary evidence is a recorded dependency for claiming that variant complete.

### P28 — Power/reset/checkstop and remaining pin behavior

- **Prerequisites:** P16, P19, P22.
- **Deliver:** source-defined hard/soft reset, power states and QREQ/QACK, checkstop/MCP/parity reactions, remaining supported pin modes including reduced-pinout behavior after source review. Keep v1 core/bus ratio 1:1.
- **Acceptance:** quiescence with outstanding traffic, wakeup, reset during tenure, parity/machine-check/checkstop priority, mode-specific output enables; explicitly document JTAG/COP scope. No setup/hold or higher clock-ratio fidelity claim without the additional specification and implementation.

### P29 — Full architectural, timing and protocol integration gate

- **Prerequisites:** P04, P12–P17, P20–P28.
- **Deliver:** reproducible regression runner, coverage reports/matrix, compiled self-checking programs, random-stream cosim with retained seeds and diagnostics.
- **Acceptance:** full audited integer/FP vectors; every required exception, instruction, timing row and bus scenario accounted for; target 10^7 architectural instructions with zero unexplained mismatches; cache/MMU/FP/LE program tests and schedule replays. Coverage gaps or approved deviations are explicit, not counted as passes.

### P30 — Cyclone V fit, timing closure and release evidence

- **Prerequisites:** P04, P29.
- **Deliver:** finalized project/SDC, reproducible Quartus build, saved fit/timing reports, resource table, documented critical-path changes and final CPU interface specification.
- **Acceptance:** fits 5CSEBA6U23I7; 50 MHz target met with reviewed unconstrained-path/clock reports and documented external timing assumptions; inspect actual RAM/DSP inference. Rerun affected architectural/timing tests after optimization. Deliver the core and harness with honest unsupported/deviation lists; board integration remains outside scope.

## First follow-up assignments

Start with P01, then P02/P03 to settle semantics and timing before extending the execution machine. P04 can establish reproducibility during that work. P05 and P06 are the next RTL foundation; adding broad instruction coverage before completion/recovery can represent delayed execution would create avoidable rework.
