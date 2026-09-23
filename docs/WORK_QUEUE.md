# Agent work queue

Started 2026-09-12. This is the execution ledger for [TASK_PLAN.md](TASK_PLAN.md); task definitions and acceptance criteria remain there. Parent coordinates review and integration. Three worker slots are available alongside the parent. Queue entries describe dependencies, not calendar promises.

Current priority after round40: continue bounded **P14/P17** supervisor work from the reviewed segment-register contract. Split register storage/indexing, CPU instruction binding, and TLB context capture into separate increments. SPRG0–SPRG3 access is accepted; the larger parent tasks remain incomplete. See the latest round below.

## Agent sizing and ownership

- **Astra / high:** ambiguous processor specification, execution/recovery architecture, critical protocol/FP design and review.
- **Sol / medium or high:** bounded implementation and verification against a defined contract; high for tool integration or substantial RTL changes.
- **Luna / medium:** inventories, deterministic generators, report checks and narrow documentation changes; escalate if the task requires architecture decisions.

These are project assignments based on complexity, not measured pricing or performance claims. Agents receive bounded briefs and only the necessary context. Each writing task owns an explicit file set. Shared package/core changes are integrated by one owner at a time. A returned task is reviewed and tested before its dependents are released.

## Dispatched foundation wave

| Slice | Agent | Model / effort | File ownership | Status |
|---|---|---|---|---|
| P01a primary-manual audit | `manual_audit` | Astra / high | `docs/SOURCES.md` | Accepted |
| P01b reference/license/test inventory | `reference_inventory` | Luna / medium | `docs/REFERENCE_AUDIT.md` | Accepted after model-identity and scope corrections |
| P04a build/toolchain foundation | `build_foundation` | Sol / high | `toolchain/`, `quartus/`, `docs/BUILD_STATUS.md` | Accepted after review; P04 setup gate complete, early fit passes but timing remains unmet |
| P13a parser-only reference preparation | `reference_inventory` | Luna / medium | `sim/cosim/` | Accepted after review fixes; seven parser tests and actual corpus inventory passed; full P13 remains pending |
| P02a non-FP timing extraction | `manual_audit` | Astra / high | `docs/TIMING_SPEC.md`, `sim/spec/timing*.json` | Accepted: 156 rows, 35 rules, 284 checked source locators; full P02 remains partial |
| P04 virtual-pin evidence review | `manual_audit` | Astra / high | Read-only QSF and reports | Accepted: final report has 0 physical/35 virtual pins; setup and hold violations recorded |
| P01c coding conventions and integration | parent | Inherited | `docs/CODING_CONVENTIONS.md`, task/status docs | Accepted; baseline regression passed |

P01 accepted finding: the 455-page local MPC603e manual is internally complete; the original abridgement estimate is unsupported. Timing and bus chapters are locally available. Reviewed evidence and the decision log are in SOURCES.md. Missing architecture-companion, variant and clock-fidelity questions remain assigned feature work.

## Next bounded assignments

| Slice | Release condition | Agent size | Deliverable / ownership |
|---|---|---|---|
| P02d4 address/lane cases | Table slice accepted in round 27; endian mapping remains open | Sol/high; parent source review | Tables 8-6/8-7 physical-lane queries, explicit endian boundary and preserved source conflicts |
| P02d3 remaining waveform cases | P02b reviewed | Sol/high per scenario | Numerical edge/pin rows for selected inventoried diagrams and mode-conditioned retry/error collisions |
| P03g extension family | Accepted in round 25 | Sol/high | CNTLZW/EXTSB/EXTSH exact masks, unary/CR0 semantics and source inventory reconciliation |
| CX-I01/I02 flag-state foundation | Accepted in round 8 | Sol/high; Astra review | Complete bounded foundation; see acceptance record below |
| CX-I03 record-logical RTL | Accepted in round 9 | Sol/high; Astra review | Complete bounded record-logical slice; see acceptance below |
| CX-I04/I05 flag recovery/integration | Record subset accepted in round 9 | Sol/high; Astra review | Extend existing oracle to each future XER-writing family |

P06a's model is reviewed preparation; it is not equivalent to accepted recovery RTL. Full parent prerequisites and the current retirement consumer's no-cancellation contract remain explicit.

## Later work lanes

Only release work after the explicit prerequisites in TASK_PLAN.md pass. Split any broad parent task into a bounded interface, implementation and verification slice; never give one worker the whole CPU or all floating-point support.

| Lane | Tasks | Default allocation |
|---|---|---|
| Integer semantics | P07, P08 | Sol/high per instruction family; Luna for vector inventories; Astra reviews flags/latency edge cases |
| Branch/LSU/dual issue | P09–P11 | Astra/high for contracts and recovery interactions; Sol/high for bounded RTL/test slices |
| Timing/reference | P12, P13 | Sol/high for harness/comparator; Luna for deterministic manifests and report checks |
| Supervisor/MMU | P14–P17 | Astra/high for precision, priority and translation rules; Sol/high implementation with independent review |
| Bus and caches | P18–P22 | Separate bus-model and bus-RTL owners; Astra/high protocol/coherency review, Sol/high bounded implementation |
| Floating point | P23–P25 | Astra/high arithmetic/rounding contracts; Sol/high per operation/test family; escalate difficult numerical discrepancies |
| Modes/integration | P26–P29 | Astra/high on endian/variant/exception ambiguities; Sol/high integration; Luna for coverage reconciliation |
| Fit/timing closure | P30 | Sol/high builds/optimization; Astra/high reviews changes affecting architectural timing |

## Completion protocol

Each worker returns changed files, commands/results, source provenance where relevant, remaining acceptance gaps and blockers. Parent reviews the actual changes, resolves cross-task interfaces, runs appropriate integration checks and records accepted status. A tool/environment blocker affects only dependent work. Completed child slices do not automatically complete their parent task.

Dependency validation: all 31 parent task IDs and prerequisites resolve in an acyclic graph. With P00/P01/P04 accepted, P02 is the next eligible full parent task. P02b bus contracts remain partial; P02c table/figure transcription is accepted with interpretation gaps, and P03a covers the current decoder subset. P13a is explicitly independent parser preparation, not early release of the full cosimulation task.

## Accepted continuation batch

| Slice | Owner | Scope / file ownership | Status |
|---|---|---|---|
| P02c | `manual_audit` (Astra/high) | FP rows and graphical timing schedules; TIMING_SPEC.md, timing.json | Accepted: 190 total rows, 39 rules, 384 locators; 35 graphical instruction rows / 162 cells; unresolved interpretations retained |
| P02b | `build_foundation` (Sol/high); Astra review | Signal inventory and source-backed bus scenarios; BUS_SPEC.md, bus*.json, check_bus.py | Accepted bounded transcription: 54 groups, 23 figures, 14 scenarios / 7 relative-event tables; retry/error mode corrections reviewed; full bus contracts remain partial |
| P03a | `isa_metadata` (Sol/high) | Source-family inventory and current-subset executable decode metadata; ISA_MATRIX.md, isa*.json, dedicated generators/tests | Accepted: seven masks, 226 source rows, 10,560 compiled legality probes; full ISA legality remains a separate gate |
| P05a | Parent; Astra review | EXECUTION_CONTRACT.md; current-subset tagged pipeline contract and acceptance tests | Reviewed; transport/finish, pre-edge reads and finite-generation limits clarified |
| P05b | Parent | package, rename, reservation station, IU, core and build integration | Reviewed by Astra; strict lint and 768-result integration pass |
| P05b CQ | `manual_audit` (Astra/high) | completion ownership/state and adversarial completion bench | Accepted: 906 focused checks; independent finish and ordered retire |
| P05b tests | `isa_metadata` (Sol/high) | focused rename/station/IU bench | Accepted: RAW/WAW, stale release, pre-edge source, station wake/stalls, IU registered result/turnover/reset |

Dependency refinement: infrastructure preparation for the existing seven forms can use accepted P02a scheduling/resource anchors and P03a current-subset metadata. Full P02/P03 and P05 conformance are not inferred from that preparation. This permits useful execution work alongside independent bus/FP transcription while retaining explicit later integration gates.

## Accepted third batch

| Slice | Owner | Exclusive file scope | Acceptance gate | Status |
|---|---|---|---|---|
| P02d1 transfer encodings | `build_foundation` (Sol/high) | BUS_ENCODINGS.md, bus_encodings.json, bus_decode.py and focused tests; bus source-link updates | Reviewed TT/size/mode records and query tests; no exhaustive waveform claim | Accepted: 32 TT codes, 3 ABE overlays, 9 size combinations; 13 tests |
| P03b ADD family | `isa_metadata` (Sol/high) | ISA metadata/generator and ADD-family semantic preparation | OE/Rc/carry/overflow/SO/CR0 anchors, exact masks, current decoder acceptance unchanged | Accepted: 20 ADD-family forms, 26 total metadata entries / 7 implemented; 7 ISA and 6 semantic tests |
| P05c current-IU stage observations | `manual_audit` (Astra/high) | STAGE_TIMING.md, stage_timing.json, dedicated checker and new observation bench | Source/implementation events distinguished; compiled traces and negative checker tests | Accepted bounded observation: 14 compiled instructions, 5 RAW bypasses; 18 checker tests; manual stage decisions remain open |
| P06a policy/model | Parent; independent Astra review | RECOVERY_CONTRACT.md, sim/recovery/ | Prefix recovery, irrevocable retirement, finite token reuse and held fetch drain tests | Accepted proposal after Astra review: 15 tests, 1,500 mixed transitions and 100 fetch scenarios; no recovery RTL |

This batch prepares recovery interfaces without adding recovery/branch ports to current RTL. Full P06 parent gates remain in force; P05d below refines bounded local recovery prerequisites. The bus task is intentionally narrowed to transfer encodings; remaining waveform/lane/collision contracts are separate slices.

## Accepted fourth batch

| Slice | Owner | Exclusive scope | Status |
|---|---|---|---|
| P02d2 address decomposition | `build_foundation` (Sol/high) | BUS_ADDRESSING.md, bus_addressing.json, bus_address.py and tests | Accepted after Astra review: 15 aligned rows, eight four-byte starts / 14 accesses; nine tests; printed TSIZ conflict preserved |
| P03c register logical family | `isa_metadata` (Sol/high) | ISA metadata/generator and logical-family evaluator/tests | Accepted: 16 logical forms, 42 total reviewed entries / seven implemented; seven semantic tests and decoder probes pass |
| P05d timing decisions | `manual_audit` (Astra/high) | TIMING_DECISIONS.md | Accepted: explicit current-stage bindings and bounded local recovery readiness; full conformance open |
| P06b0 prefix-selector prototype | Parent; Astra review | sim/recovery/rtl/, tb_recovery_select.sv, RECOVERY_SELECTOR.md, build integration | Accepted after Astra review: strict standalone build and 245,760 snapshot checks pass |

P06b0 is combinational interface preparation outside the canonical CPU and Quartus source lists. It does not release the full P06 implementation or claim sequential recovery.

Fourth-batch integration: `make -C ppc603e/sim check-spec test-recovery` passed 62 tool tests and 15 policy tests, including compiled decoder probes. Standalone selector strict build passed separately. Next implementation priority is P06b1 sequential CQ/rename recovery with atomic local RS/IU cancellation, followed by P06b2 fetch drain and whole-core integration. Follow TIMING_DECISIONS.md acceptance gates, including diagnostic-stop cleanup and no-redirect regression preservation. Full 603e timing and broad ISA/bus completion remain open.

## Accepted fifth batch

| Slice | Owner | Scope | Status |
|---|---|---|---|
| P06b1 sequential backend state | `build_foundation` (Sol/high) | CQ prefix updates, post-commit survivor snapshots, rename rebuild and focused state bench | Accepted: 5,871 checks, independently reviewed |
| P06b1 local cancellation/integration | Parent | RS/IU cancellation, identity-qualified wiring, existing bench compatibility and regression | Accepted: 1,066 cancellation checks; canonical lint and all existing no-redirect regressions pass |
| P06b1 independent review | `manual_audit` (Astra/high) | Interface and actual implementation review | Actual RTL accepted; focused coverage additions pass |
| P03d rotate family | `isa_metadata` (Sol/high) | Three rotate families, masks/semantics/reference tests | Accepted: six forms, eight semantic tests, 48 total reviewed / seven implemented; primary-table conflict recorded |

The core ties redirect requests off until frontend drain and diagnostic recovery are integrated. This batch exercises sequential backend state directly and does not expose a partially working whole-core redirect interface.

Fifth-batch validation: strict canonical lint, 906 original completion checks, 768 core results, focused execution and unchanged stage probe pass; direct backend state/cancellation benches pass 5,871/1,066 checks. Specification/policy suite passes 72+15 Python tests and 10,560 compiled decode probes. Canonical RTL changed and has not been remeasured in Quartus. Next priority is P06b2 frontend drain and enabled whole-core recovery, with independent surviving-stream tests and diagnostic-stop cleanup.


## Accepted sixth batch

| Slice | Owner | Scope | Status |
|---|---|---|---|
| P06b2 fetch drain | `build_foundation` (Sol/high) | Canonical fetch and direct recovery bench | Accepted after Astra review: 99 strict checks |
| P06b2 core integration | Parent | Explicit recovery control, IQ clear, diagnostic identity cleanup, independent core stream bench, old ties/wrapper | Accepted after Astra review: 985 checks; 10 accepted/four rejected redirects, six killed entries, 45 retirements; RS/IU/full-IQ/coincident-response coverage |
| P06b2 independent review | `manual_audit` (Astra/high) | Actual fetch/core/FIFO and direct/integrated benches | Accepted after strengthening independent PC/word oracle and stimulus scheduling |
| P03e shifts | `isa_metadata` (Sol/high) | slw/srw/sraw/srawi metadata and semantics | Accepted: eight forms/seven semantic tests; 56 reviewed entries/seven implemented, 200 source rows still pending |

Validation: canonical strict lint, 768-result core regression and unchanged 14-instruction timing probe pass; specification/policy suite passes 81+15 Python tests and 10,560 compiled decoder probes. Unchanged backend benches retain their previous accepted results. Core requests are now enabled through the explicit internal/test event interface; no branch/exception decoder is implied. Next implementation work is the CR/XER ownership/partial-write contract and bounded integer execution expansion. Full P06 architectural exception/external producer extensions and full timing conformance remain open.

## Accepted seventh batch

| Slice | Owner | Scope | Status |
|---|---|---|---|
| P07a CR/XER contract | `manual_audit` (Astra/high) | CR_XER_CONTRACT.md | Accepted by root: single-owner, allocation-controlled masked delta, atomic commit and recovery contract |
| P07b non-record register logical RTL | Parent | Canonical package, decode and IU; shared integration | Accepted after Astra review: eight new forms, 15 executable total; strict lint and existing RTL suite pass |
| P07b logical verification | `build_foundation` (Sol/high) | tb_core_logical.sv | Accepted: 94 legal logical operations, eight record rejections, dependency/r0/stall/timing checks |
| P03f compare metadata | `isa_metadata` (Sol/high) | Compare reference/masks and ISA inventory; reconcile eight newly implemented logical forms | Accepted: four compare forms, eight semantic tests; 60 reviewed/15 implemented; zero overlaps |

Dependency refinement: non-record register-logical forms have no CR/XER write or input dependency, so their already-reviewed semantics can execute before flag-state implementation. Rc forms and carry/overflow instructions remain gated by the CR/XER contract.

Final seventh-batch validation: 91 tool tests plus 15 policy-model tests pass; 10,560 compiled decoder probes agree with 15 executable masks (75 accepted probes). Metadata totals 60 reviewed forms/15 implemented and 196 source rows awaiting full transcription. Next release is CX-I01/I02 flag-state foundation, then record-logical execution and integrated flag recovery per the accepted contract. CR/XER RTL, architectural compare execution and FPGA remeasurement remain pending.

## Accepted eighth batch

| Slice | Owner | Scope | Status |
| --- | --- | --- | --- |
| CX-I01 reference/checkers | `isa_metadata` (Sol/high); Astra review | Independent masked commit, arithmetic adapters and owner lifecycle | Accepted: 14 tests, 500 deterministic commits, semantic and lifecycle negative cases |
| CX-I02 state foundation | `build_foundation` (Sol/high); Astra review | Package/CQ deltas, `ppc_flags`, focused state and coupled CQ benches | Accepted: 37 state checks and 168 coupled checks; strict lint passes |
| Current-core compatibility | Parent; Astra review | Zero flag permissions/candidates, canonical flag state wiring, build lists and regression | Accepted: all existing RTL regressions and 120 Python tests pass |

The coupled bench verifies CQ packet removal and flag update on one accepted retirement edge; it does not instantiate the architectural GPR file. Current core instructions remain flag-free, so nonzero GPR+CR/XER instruction-level commitment and recovery evidence remain CX-I03–I05. The standalone state fixture seeds nonzero CR1–7 and XER low bits solely to test preservation. No new instruction forms are enabled: 15 remain executable. FPGA fit/timing has not been remeasured.

Next release: CX-I03 record-logical decode and execution, atomic owner-gated dispatch with captured SO, then CX-I04/I05 independent full-core retirement/recovery checks. Keep record encodings unsupported until these effects and checks are connected. Source/extension metadata and remaining bus contracts remain available independent lanes.

Overall completion after round 8: **approximately 12%**, with a **10–15% planning range**. The weighted estimate advances from 11.9 to 12.26 points as the integer/recovery workstream moves from 35% to 38%; rounded overall progress is unchanged. [PROGRESS.md](PROGRESS.md) retains the full weights and scope.

## Accepted ninth batch

| Slice | Owner | Scope | Status |
| --- | --- | --- | --- |
| CX-I03 record-logical RTL | `build_foundation` (Sol/high); Astra review | Decode, atomic ownership admission, held SO and CR0 result | Accepted: eight new forms, 23 executable total; no XER writes |
| CX-I03 direct execution | Parent; Astra review | SO0/1 capture with pending RS and held IU | Accepted: 77 checks |
| CX-I04/I05 bounded record integration | `isa_metadata` (Sol/high); Astra review | Independent surviving stream, full GPR/CR/XER retirement oracle, admission and recovery | Accepted: 10,252 checks, 33 retirements, 14 record commits, three killed record owners |
| Record recovery edge cases | `build_foundation` (Sol/high); Astra review | Actual-core coincident finish/commit redirects, rejected finished-head cuts, IU/CQ reset | Accepted: 43 checks |
| Integration/metadata | Parent | Caller compatibility, old rejection cases, build targets and ISA reconciliation | Accepted: all prior RTL regressions; 120 Python tests; 10,560 decoder probes, 115 accepted |

The broad oracle predicts sequential/redirect dispatch PC and word, maintains an independent age-ordered queue, and checks pre-edge retirement eligibility, exact identity, D/E/F/C and all architectural registers. The edge bench checks the first offered target/fallthrough word with retirement stalled before accepting it. These checks close review findings in test independence; no RTL correctness finding remained.

Record-logical forms update CR0 only. Integrated programs use reachable SO=0; the direct unit fixture verifies both SO inputs. Metadata remains 60 reviewed entries, now 23 implemented and 37 pending, with zero overlaps. Source inventory remains 226 rows, 30 reconciled and 196 pending. Full timing, XER-writing arithmetic and FPGA remeasurement remain open.

Next bounded implementation: base ADD Rc/OE variants and `addc` through allocated CA/OV/SO masks, with mathematical carry/overflow and sticky-SO sequence checks; follow with extended ADD CA-input forms. Keep unsupported variants illegal until both execution and independent architectural/recovery tests pass. Extension metadata and remaining bus contracts remain independent lanes.

Overall completion: **approximately 13%** (planning range **10–15%**). The fixed-weight estimate advances from 12.26 to 12.62 points as integer/recovery moves from 38% to 41%; see [PROGRESS.md](PROGRESS.md).

## Accepted tenth batch

| Slice | Owner | Scope | Status |
| --- | --- | --- | --- |
| ADD/ADDC flags RTL | `build_foundation` (Sol/high); Astra review | Seven additional OE/Rc forms, held CA/OV/SO controls, final-SO CR0 | Accepted: 30 total executable forms |
| Arithmetic corpus | `isa_metadata` (Sol/high); Astra review | Independent full-state/stream/owner oracle, directed boundaries and deterministic mixed instructions | Accepted: 18,967 checks, 83 retirements, 75 ADD/ADDC operations, all eight forms, 66 exact commit+1 owner admissions |
| Nonzero-XER recovery | Parent; Astra review | Real instruction seeding, RS/IU/finished-younger CQ kills, kept finish/commit redirects | Accepted: 3,439 checks across five cases |
| Held-control verification | `build_foundation` (Sol/high); Astra review | Delayed source wake, changed live controls and held complete IU packets | Accepted: 28 checks |
| Integration/metadata | Parent | Caller ties, extended-ADD diagnostic replacements, canonical targets and ISA status | Accepted: strict core/wrapper lint, all prior RTL tests, 120 Python tests and 10,560 decode probes (150 accepted) |

The arithmetic oracle uses a wide signed mathematical range for overflow, independent stream PC/word/identity and complete post-edge architectural-state comparison. Coverage distinguishes carry-only, overflow-only and both, ADD preserving CA, nonoverflowing OE clearing OV while preserving SO, CA-only preservation, and Rc observing its own newly set SO. A record-logical instruction now observes SO=1 set by actual arithmetic. No test forces architectural state in the full core. Independent review found no remaining correctness issue in this scope.

Metadata remains 60 reviewed entries: 30 implemented and 30 pending, with zero overlaps. Source inventory remains 226 rows, 30 reconciled and 196 pending. Full timing, dual issue and FPGA remeasurement remain open.

Next bounded implementation: ADDE with captured committed CA, then ADDME/ADDZE with their distinct signed-overflow equations and reserved-rB enforcement. Each slice must preserve current masked commitment/recovery and provide directed CAin=0/1 arithmetic, stale-state and ownership tests before enabling decode.

Overall completion: **approximately 13%** (planning range **10–15%**). Integer/recovery progresses from 41% to 44%, moving the fixed-weight total from 12.62 to 12.98 points; the rounded estimate is unchanged. See [PROGRESS.md](PROGRESS.md).

## Accepted eleventh batch

| Slice | Owner | Scope | Status |
| --- | --- | --- | --- |
| ADDE RTL | `build_foundation` (Sol/high); Astra review | Four OE/Rc forms, captured committed CA, widened sums and carry-sensitive overflow | Accepted: 34 total executable forms |
| Independent ADDE corpus | `isa_metadata` (Sol/high); Astra review | Three-operand arithmetic and full-state/stream/owner oracle | Accepted: 21,700 checks, 89 retirements, 72 ADDE operations, seven ADDC seeds, all four forms |
| CA capture and recovery | Parent; Astra review | Direct held-CA fixture; ADDE mode in existing five-case recovery bench | Accepted: 37 direct checks and 3,434 recovery checks |
| Integration/metadata | Parent | Caller ties, updated unsupported forms, targets and ISA status | Accepted: strict core/wrapper lint, all prior RTL tests, 120 Python tests and 10,560 decoder probes (170 accepted) |

ADDE always owns flags, captures committed CA and replaces CA on commitment. Its corpus observes 78 exact owner commit+1 admissions, including seven seed-to-ADDE next-edge captures. Independent arithmetic checks cover CA0/1 boundaries, maximum unsigned sum, carry-sensitive overflow/rescue, sticky SO and masked preservation. Recovery checks distinguish the carry surviving a killed writer from that left by a committed writer, then consume it in a redirected ADDE. No full-core RTL state is forced. Independent review found no remaining correctness issue in scope.

Metadata remains 60 reviewed entries: 34 implemented and 26 pending, with zero overlaps. Source inventory remains 226 rows, 30 reconciled and 196 pending. Full timing, dual issue and FPGA remeasurement remain open.

Next bounded implementation: ADDME/ADDZE, including reserved rB=0 enforcement, captured CA, and their distinct signed mathematical sums. Preserve existing arithmetic, record, ownership and recovery tests, and add independent CA0/1 boundaries before enabling those forms.

Overall completion: **approximately 13%** (planning range **10–15%**). Integer/recovery progresses from 44% to 46%, moving the fixed-weight total from 12.98 to 13.22 points; the rounded estimate remains unchanged. See [PROGRESS.md](PROGRESS.md).

## Accepted twelfth batch

| Slice | Owner | Scope | Status |
| --- | --- | --- | --- |
| ADDME/ADDZE RTL | `build_foundation` (Sol/high); Astra review | Eight OE/Rc forms, immediate second operand, reserved-rB rejection and captured CA | Accepted: 42 total executable forms |
| Independent unary corpus | `isa_metadata` (Sol/high); Astra review | Independent signed/unsigned arithmetic and complete state/stream/owner checks | Accepted: 27,278 checks, 107 retirements, 74 unary operations, nine seeds, eight forms and 16 reserved-rB rejections |
| Capture and recovery | Parent; Astra review | Seven held-input cases and five recovery cases per family | Accepted: 64 direct checks; 3,434 ADDME and 3,434 ADDZE recovery checks |
| Integration/metadata | Parent | Regression diagnostics, targets, implementation matrix and documentation | Accepted: strict core/wrapper lint, all prior RTL tests, 120 Python tests and 10,560 decoder probes (178 accepted) |

[ADD_UNARY.md](ADD_UNARY.md) records the arithmetic and recovery boundaries. Review found no remaining correctness issue in scope. The reviewed matrix contains 60 entries: 42 implemented and 18 pending, with zero overlaps. All 20 reviewed ADD-family forms execute. Source inventory remains 226 rows, 30 reconciled and 196 pending. No new FPGA measurement or full timing acceptance is claimed.

Next bounded implementation: RLWINM/RLWNM with both Rc values, using the reviewed rotate/mask contract. Assign Sol/high RTL and independent full-core verification owners with Astra/high review. Cover wrapped masks, zero/full-width rotations, r0/RAW/WAW, captured SO, masked CR0 and recovery. Keep RLWIMI pending until its old-destination operand and dependency contract is explicitly implemented and tested.

Overall completion: **approximately 13%** (planning range **10–15%**). Integer/recovery increases from 46% to 48%, moving the fixed-weight total from 13.22 to 13.46 points. See [PROGRESS.md](PROGRESS.md).

## Accepted thirteenth batch

| Slice | Owner | Scope | Status |
| --- | --- | --- | --- |
| RLWINM/RLWNM RTL | `build_foundation` (Sol/high); Astra review | Four Rc forms, decoded/captured mask, immediate or register count, final masked CR0 | Accepted: 46 executable forms |
| Independent rotate corpus | `isa_metadata` (Sol/high); Astra review | Bitwise rotate and circular-distance mask oracle, complete state/stream, mask sweep and recovery | Accepted: 722,063 checks, 4,176 retirements, 4,112 rotates and 4,096 exhaustive mask cases |
| Capture/integration | Parent; Astra review | Held mask/SO fixture, dispatch caller ties, targets, metadata and docs | Accepted: 64 direct checks, core/wrapper lint, all 24 prior RTL targets, 120 Python tests, 10,560 decode probes (188 accepted) |

[ROTATE_EXECUTION.md](ROTATE_EXECUTION.md) records semantics and acceptance boundaries. Review strengthened nonzero r0 source/destination/count aliases and pre-write coverage sampling; the amended corpus passes with no remaining findings. The current metadata has 60 entries: 46 implemented and 14 pending, zero overlaps. Source inventory remains 226 rows, 30 reconciled and 196 pending. No new FPGA measurement was performed.

Next bounded implementation: SLW/SRW with both Rc values. Assign Sol/high RTL and independent actual-core verification owners, with Astra/high review. Follow the reviewed six-bit register-count contract: counts 32–63 yield zero, higher bits are ignored, and count zero preserves the source. Include signed-looking data, nonzero r0/RAW/WAW aliases, captured SO/final-result CR0, XER preservation and recovery. Keep arithmetic shifts pending their CA-specific acceptance and RLWIMI pending the old-destination source contract.

Overall completion: **approximately 14%** (planning range **10–15%**). Integer/recovery increases from 48% to 50%, moving the fixed-weight total from 13.46 to 13.70 points. See [PROGRESS.md](PROGRESS.md).

## Accepted fourteenth batch: temporary program milestone

User-directed temporary priority: seek a larger functional increment under limited usage, then return to the original plan. One RTL implementation owner and targeted independent review were used; the parent owned independent tests and integration.

| Slice | Owner | Scope | Status |
| --- | --- | --- | --- |
| Serialized control/memory lane | `build_foundation` (Sol/high); targeted Astra review | Branches, LR/CTR moves, BF comparisons, aligned D/indexed integer memory, tagged completion and protocol recovery | Accepted within CONTROL_MEMORY contract; full P09/P10 remain pending |
| Independent program and edge fixtures | Parent; Astra review | Symbolic oracle, memory loop/calls/conditions/full state, faults and irrevocable/cancelled obligations | Accepted: 44,883 program checks and 799 edge checks |
| Source/metadata/integration | Parent; cached source review from Astra | 30 new entries plus four enabled comparisons, source reconciliation, caller ties, targets and docs | Accepted: 80 implemented of 90 reviewed, 15,808 decoder probes (615 accepted), all 26 prior RTL targets and 120 Python tests |

The program executes 579 retirements, 31 reads and 22 writes. Source inventory now has 50 boundedly reconciled rows and 176 pending; SPR-move scope is only LR/CTR. Store reservation explicitly authorizes external effects before final completion acknowledgment. Faulted-load rename state survives only until terminal halt/reset; resumable exceptions must handle it differently. No FPGA remeasurement, branch prediction/folding or BPU/LSU timing acceptance is claimed.

The fixed-weight estimate rises **13.70→18.10%, approximately 18%** (planning range **15–22%**). Credit: source45→47, integer50→52, branch/LSU0→40. The requested20–25% target was not fully reached; scope was held to preserve usage and correctness rather than stretching the estimate.

The temporary push is complete. **Return to the original next batch: SLW/SRW with both Rc values**, followed by the remaining integer work and original task dependencies. Broader branch/LSU work remains in P09/P10 with the deferred gates above.

## Accepted fifteenth batch: SLW/SRW

| Slice | Owner | Scope | Status |
| --- | --- | --- | --- |
| Logical-shift RTL | `build_foundation` (Sol/high); targeted Astra review | Exact XO24/536, real register mapping, low-six count and Rc-only flags | Accepted: four forms, 84 executable total; no interface changes |
| Independent verification | Parent; Astra review | Symbolic bit-selection program, pending-data/count fixture and two recovery modes | Accepted: 173,321 program checks, 91 direct checks and 3,439 per recovery mode |
| Integration | Parent | Metadata, generated matrix, targets, unchanged-profile and old-parameter regressions | Accepted: all 28 prior RTL targets, strict core/wrapper lint, 120 Python tests and 15,808 decode probes (635 accepted) |

The program includes 1,280 systematic source/count/form cases and additional upper-bit/alias cases, with actual SO0/SO1 and full CR/XER preservation. Recovery keeps or kills exact producers while preserving seeded CA/OV/SO. Source counts remain 50 boundedly reconciled rows and 176 pending; the matrix has 84 implemented of 90 reviewed entries. No FPGA measurement or full timing acceptance was added.

Overall completion: **18.10→18.34%, approximately 18%**, planning range **15–22%**. Integer/recovery progresses 52→54%; other weights and workstream estimates remain unchanged.

Next bounded batch: **SRAW/SRAWI**, including negative discarded-bit CA, count0/31/32/63 distinctions, five-bit immediate counts, record final-SO behavior and recovery. The ALU enum is now full (16 values); widen it explicitly before adding operations. Keep RLWIMI pending its old-destination dependency and continue the original parent-task gates.


## Round 16 — arithmetic word shifts

Accepted SRAW/SRAWI and both Rc forms: 88 executable forms of 90 reviewed.
`build_foundation` (Sol/high) implemented the shared arithmetic-shift operation;
`manual_audit` (Astra/high) performed targeted RTL review with no actionable findings.
The coordinator owns independent tests, metadata and integration.

The program checks 2,684 retirements and 206,971 full-state assertions. Direct
execution has 91 checks; SRAW and SRAWI recovery each have 3,434 checks. Counts,
negative discarded-bit carry, real r0, aliases, captured controls, held packets,
and kept/killed flag owners are covered. See [ARITHMETIC_SHIFTS.md](ARITHMETIC_SHIFTS.md).

All 32 prior RTL targets, strict core/wrapper lint, 120 Python tests and 15,808 compiled decode probes pass (655 accepted).

Next: prepare and implement RLWIMI's old-rA merge dependency, including rS=rA,
mask wraparound and recovery. Preserve the original P03/P07 acceptance gates.


## Round 17 — rotate insert

`build_foundation` (Sol/high) implemented RLWIMI with two renamed sources and captured SH; `manual_audit` (Astra/high) completed targeted review with no actionable findings. The coordinator owns independent tests, integration and documentation. Both Rc forms execute, bringing the bounded reviewed subset to 90/90.

The program passes 218,905 checks / 2,839 retirements, including all 2,048 mask/Rc combinations. Direct execution passes 73 checks. Recovery exercises an uncommitted old destination and kept/killed flag owners. See [ROTATE_INSERT.md](ROTATE_INSERT.md).

Next bounded batch: review SUBF/NEG encoding and subtract carry/overflow semantics, expand P03 metadata with independent references, then implement the accepted P07 slice. Source inventory remains 50 boundedly reconciled rows and 176 pending; completing the existing 90 reviewed forms does not complete P03 or P07.

Round17 integration: all 36 prior RTL targets, strict core/wrapper lint and 120 Python tests pass. The strengthened insert recovery fixture passes 3,445 checks. Compiled decode passes 15,808 probes with 660 accepted.


## Round 18 — SUBF/NEG

The source reviewer (`manual_audit`, Astra/high) verified primary encodings and secondary semantics before acceptance. `build_foundation` (Sol/high) implemented the shared subtract datapath; targeted review found no actionable findings. The coordinator owns independent tests, metadata and integration. Eight forms bring the current subset to 98 reviewed/implemented; source reconciliation advances 50→52 of 226 rows.

New tests: 113,111 program checks / 1,465 retirements, 73 direct checks, 3,439 checks per recovery variant, and five metadata/reference tests. See [SUBTRACT_NEGATE.md](SUBTRACT_NEGATE.md).

Next: SUBFC with reviewed unsigned no-borrow CA semantics and OE/Rc behavior; then SUBFE/SUBFME/SUBFZE with captured carry. Keep P03/P07 parent gates open and retain TIM-U08's SUBF timing notation caveat.

Round18 integration passes all 39 prior RTL targets, strict core/wrapper lint, 110 tool tests and 15 recovery-model tests. No regression failures remain.


## Round 19 — SUBFC

Source review (`manual_audit`, Astra/high) verified XO8, no-borrow CA and timing/source locators; `build_foundation` (Sol/high) implemented the bounded four forms. Targeted RTL review found no actionable findings. The coordinator owns tests, metadata and integration.

New tests pass 186,650 program checks / 2,420 retirements, 73 direct checks and 3,434 recovery checks. The program includes 512 immediate ADDE consumers with separately seeded incoming CA. Two additional Python tests enforce metadata and no-borrow anchors. 102 forms execute; source reconciliation is53/226. See [SUBFC.md](SUBFC.md).

Next: SUBFE, then SUBFME/SUBFZE, with source review for incoming-CA arithmetic, overflow boundaries, reserved fields and flag recovery. Full P03/P07 acceptance remains open.

Round19 integration passes all 43 prior RTL targets, strict core/wrapper lint, 112 tool tests and 15 recovery-model tests. No regression failures remain.


## Round 20 — SUBFE

Source review (`manual_audit`, Astra/high) verified XO136, captured carry, borrow-adjusted signed overflow and source/timing locators. `build_foundation` (Sol/high) implemented the four forms; targeted RTL review found no actionable issues. The coordinator owns independent tests, metadata and integration.

New checks: 186,650 program / 2,420 retirements, 127 direct, 3,434 per CA-seeded recovery variant, and two new Python tests. One handwritten direct expectation was corrected by mathematical checking; no RTL change was needed. 106 forms execute; source reconciliation54/226. See [SUBFE.md](SUBFE.md).

Next: SUBFME/SUBFZE, including fixed B injection, reserved rB rejection, captured carry, overflow boundaries and recovery. P03/P07 remain partial.

Round20 integration passes all 46 prior RTL targets after updating the obsolete SUBFE rejection fixture, strict core/wrapper lint, 114 tool tests and 15 recovery-model tests. No failures remain.


## Round 21 — SUBFME/SUBFZE

Source review (`manual_audit`, Astra/high) verified XO232/200, reserved rB, fixed-operand arithmetic and timing/source locators. `build_foundation` (Sol/high) implemented a decode-only extension using ALU_SUBFE. Targeted RTL review found no actionable findings. The coordinator owns independent tests, metadata and integration.

New checks: 89,010 program / 1,152 retirements, 145 direct, 3,434 per recovery variant and two Python tests. Eight forms bring coverage to114 reviewed/executable forms; source reconciliation56/226. See [SUBTRACT_UNARY.md](SUBTRACT_UNARY.md).

Next: SUBFIC, reviewing signed immediate extension, real rA0, carry without OE/Rc, and recovery before implementation. Keep P03/P07 parent gates open.

Round21 integration passes all 50 prior RTL targets, strict core/wrapper lint, 116 tool tests and 15 recovery-model tests. No failures remain.


## Round 22 — SUBFIC

Source review (`manual_audit`, Astra/high) verified primary8, signed SIMM, real rA0 and CA-only effects. `build_foundation` (Sol/high) implemented the decode-only change. The reviewer returned clear RTL findings before reporting a usage limit; the coordinator completed tests, metadata and integration locally.

New checks: 150,687 program / 1,953 retirements and 3,434 per recovery variant. Two Python tests cover all immediate payload masks and signed/flag anchors. 115 forms execute; source reconciliation57/226. See [SUBFIC.md](SUBFIC.md).

Next: ADDIC/ADDIC., reviewing signed immediate arithmetic, carry-only versus record effects, real rA0 and recovery. P03/P07 remain partial. Avoid relying on the exhausted review agent until usage is available.

Round22 integration passes all 54 prior RTL targets, strict core/wrapper lint, 118 tool tests and 15 recovery-model tests. No failures remain.


## Round 23 — ADDIC/ADDIC.

The coordinator completed source review, decode implementation, independent symbolic/literal verification and integration locally because review-agent usage was exhausted. No new agents were started. Primary opcodes12/13 select nonrecord/record behavior independently of immediate bits; CA is replaced, OV/SO preserved and rA0 remains real.

New checks: 186,805 program / 2,422 retirements, 3,434 per recovery form, and two Python tests. There are117 reviewed/executable forms and59 reconciled source rows. See [ADD_IMMEDIATE.md](ADD_IMMEDIATE.md).

Next: ANDI./ANDIS., checking zero-extended versus shifted unsigned immediate, unconditional CR0 recording and SO preservation. Full P03/P07 remain partial.

Round23 integration passes all 57 prior RTL targets, strict core/wrapper lint, 120 tool tests and 15 recovery-model tests. No failures remain.


## Round 24 — ANDI./ANDIS.

The coordinator completed local source review, decode implementation and independent verification. Both primary28/29 forms always record CR0 and preserve XER. The secondary ANDIS. pseudocode's addition typo is explicitly retained, with prose and tagged software corroboration supporting AND. No agents were started.

New checks: 186,805 program / 2,422 retirements, 3,439 per recovery form and three Python tests. Coverage is119 reviewed/executable forms and61 reconciled rows. See [AND_IMMEDIATE.md](AND_IMMEDIATE.md).

Next: CNTLZW/EXTSB/EXTSH, with reserved-field and Rc/SO source contracts, zero/sign boundaries and recovery. Full P03/P07 remain partial.

Round24 integration passes all 60 prior RTL targets, strict core/wrapper lint, 123 tool tests and 15 recovery-model tests. No failures remain.

## Round 25: CNTLZW / EXTSB / EXTSH accepted

Root implemented the bounded RTL, program oracle, direct decoder/execution fixtures and three recovery variants. `isa_metadata` (Sol/high) independently reconciled the six forms, primary/secondary source locators and negative metadata tests in its owned files. Root reviewed the resulting contracts and integrated validation; the previously exhausted review agent was not restarted.

Six new targets, all 63 prior RTL targets, strict core/wrapper lint and 142 Python tests pass. The core retires 3,459 program instructions under stalls with 266,649 full-state checks; direct execution has 1,513 checks, decoder routing/reserved/permission coverage 6,330, and recovery 3,439 per operation. ISA counts are 125 reviewed/implemented forms, 64 reconciled source rows and 162 pending rows. Full CPU progress is approximately 21%, fixed weighted score 20.64% (previously 20.28%).

Next bounded assignment: review and implement MFCR/MTCRF, covering selected CR-field masks, source/destination hazards and precise recovery. Follow with CR logical operations. Full P07 vector/reference acceptance, P08 multiply/divide, dual issue and source-defined timing remain open.

## Round 26: MFCR / MTCRF accepted

`build_foundation` (Sol/high) implemented the bounded special-lane and CR-mask RTL, including the measurement-wrapper packet digest. `isa_metadata` (Sol/high) reconciled exact source encodings, field effects and metadata tests. Root reviewed the shared state path, implemented independent full-core/completion/recovery/decode tests, updated documentation and integrated the regressions.

The two new forms bring the subset to 127. All four new RTL targets and all 69 prior targets pass; strict core/wrapper lint and 146 Python tests pass. Full-state execution has 224,689 checks over 2,914 retirements, recovery 11,247, coupled completion/flags 3,244 and exhaustive decoder coverage 131,072. The stage-timing fixture now explicitly asserts that its original instructions cannot acquire the new multi-field CR permissions. No RTL correction was needed after the initial implementation.

Overall progress is approximately 21%, fixed weighted score 20.96% (previously 20.64%). Next bounded assignment: CR logical operations, with bit-source/destination aliases, preservation and exact recovery; then remaining CR-transfer/state operations and integer acceptance work. Multiply/divide, dual issue and full timing remain separate open tasks.

## Round 27 parallel assignments — accepted

| Task | Owner | File boundary | Acceptance |
|---|---|---|---|
| Eight CR logical operations | `build_foundation`, Sol/high | CPU RTL, ISA metadata/generator and generated matrix | Source-reviewed Boolean semantics, exact one-bit permission, alias-safe snapshot and strict lint |
| 32-bit bus lane tables/query | `isa_metadata`, Sol/high | Bus addressing JSON/tool/tests and BUS_ADDRESSING.md | Primary table provenance, explicit endian scope, all transcribed lane cases and mutation tests |
| Integration and independent CPU validation | Parent | Program oracle, new CPU tests, Makefile and shared status docs | Truth tables, every CR destination, preservation/recovery, regressions and review of both returned slices |

The two worker tasks have no shared writable files. Bus tooling does not modify CPU RTL or earn implemented bus credit. Dependencies within each task remain explicit; root accepts completed work after validation.

Both independent worker slices are accepted after parent review and integration. The CPU slice adds eight CR logical forms (135 total), with all truth inputs/destinations, alias snapshots, single-bit permission enforcement and precise recovery. The bus slice adds exact 32-bit Tables 8-6/8-7 queries, physical DH lanes, explicit doubleword beats and preserved source anomalies; endian steering and bus RTL remain open.

All four new CPU targets and all 73 prior RTL targets pass. Strict core/wrapper lint and 154 Python tests pass, including the 13 bus-address tests. Parent also checked independent literal bus lane/address examples against the primary table text. The expanded ISA probe passes 26,048 words with 807 accepted. The three regression batches completed successfully; no post-implementation RTL correction was needed. The stage probe now explicitly checks that its original instruction subset cannot acquire single-bit CR permissions.

Overall completion is approximately 22%, fixed weighted score 21.58% (previously 20.96%). Source-contract credit includes the bus table work; no bus hardware or endian implementation credit is assigned. Next independent lanes are MCRF/MCRXR and remaining bus waveform contracts, with broad parent acceptance gates still open.

## Round 28 parallel assignments — accepted

| Task | Owner | File boundary | Acceptance |
|---|---|---|---|
| MCRF/MCRXR | `build_foundation`, Sol/high | CPU RTL, ISA metadata, decoder bench and generated matrix | Two exact encodings, captured source state, existing atomic flags retirement, 137 implemented forms and 76 reconciled source rows |
| Figure 8-13 read burst contract | `isa_metadata`, Sol/high | Bus scenario JSON/checker/tests and BUS_SPEC.md | Seven bounded rows, six signal roles, normal DRTRY mode, explicit sampling/fidelity limits and preserved unresolved details |
| Independent special-lane validation | `isa_metadata`, Sol/high, after bus slice | New direct execution bench only | All 16 nibbles at every MCRF source/destination, all eight MCRXR flag patterns, held inputs and cancellation |
| Integration | Parent | Program oracle, core/recovery bench, literal tests and shared documentation | Source review, full-state execution, old regressions and acceptance |

All four new targets and all 77 prior RTL targets pass, as do strict core/wrapper lint and 166 Python tests (151 tools plus 15 recovery). The new core program retires 1,460 instructions with 112,725 checks; recovery adds 11,247, exhaustive reserved decode 131,072 and direct execution 45,730. The ISA/RTL comparison accepts 810 of 26,048 probe words. Initial integration exposed stale metadata expectations during concurrent edits; final synchronized checks pass without RTL corrections.

The bus inventory now contains 15 scenarios / eight cycle tables, with eight diagrams still inventory-only. Figure 8-13 records prose-supported TA pacing and protocol-relative DRTRY cancellation/replacement. Cycle labels are not promoted to unverified sampling edges, and unlabeled data polygons, electrical delays and omitted TEA timing remain open. No bus implementation credit is assigned.

See [CR_STATE.md](CR_STATE.md) and [BUS_SPEC.md](BUS_SPEC.md). Overall completion is approximately **22%**, fixed weighted score **21.78%** (previously 21.58%). The rounded percentage remains unchanged because these are bounded additions to the full CPU scope.

Next independent candidates: a source-reviewed low-word multiply slice with exact OE/Rc behavior and bounded execution/recovery tests; and one remaining bus waveform contract with mode-specific source anchors. Full integer reference acceptance, dual dispatch, divide and source-defined timing remain open and must not be marked complete by these slices.

## Round 29 parallel assignments — accepted

| Task | Owner | File boundary | Acceptance |
|---|---|---|---|
| Low-word multiply | `build_foundation`, Sol/high | Package/decode/IU, ISA metadata/generator/tests/matrix, new direct benches | MULLI plus four MULLW OE/Rc forms, low32 product, signed overflow, sticky SO, CA preservation and exact decode |
| Figure 8-17 delayed single-beat reads | `isa_metadata`, Sol/high | Bus scenario JSON/checker/tests and BUS_SPEC.md | Five bounded rows, five roles, conditional grant opportunity, TA waits, late DRTRY cancellation and explicit fidelity limits |
| Integration and review | Parent | Symbolic program, recovery variants, literal tests, Makefile and shared docs | Full-state execution, source/literal review, all prior regressions and final acceptance |

Five new targets and all 81 prior RTL targets pass, with strict core/wrapper lint and 175 Python tests (160 tools plus 15 recovery). The new program performs 2,114 retirements with 163,078 full-state checks; both recovery cases add 3,434 checks. Direct decoder coverage is 605,185 checks and execution 55, including delayed operand wake and result stalls. The full ISA probe agrees on 835 accepted words out of 26,048. Metadata contains 142 implemented forms and 78 reviewed source rows, with 148 pending. No RTL correction was needed after the initial implementation. Review corrected a direct test's purported overflow input and the exact MULLI source page before final acceptance.

Figure 8-17 adds the prose-supported clock 3/4 TA waits, a hypothetical clock 6 DBG opportunity, and DRTRY assertion during labeled clock 11 followed by sampling at the next rising boundary. The manual's second-access pipelining condition remains explicit. The bus inventory is now 16 scenarios / nine cycle tables, with seven diagrams still inventory-only. Its 11 focused tests include nine new targeted mutation cases; this is source preparation and earns no bus hardware credit.

[MULTIPLY_LOW.md](MULTIPLY_LOW.md) records the CPU acceptance boundary. MULLI's 2/3 and MULLW's 2/3/4/5 source latencies remain unimplemented; the current registered IU supplies functional semantics only. P08 is still partial. Overall completion is approximately **22%**, fixed weighted score **22.10%**, previously 21.78%.

Next independent candidates: MULHW/MULHWU signed/unsigned high-word semantics and Rc variants, alongside a remaining bus diagram such as Figure 8-18. Multiply scheduling, divide, dual issue and complete integer reference acceptance remain separate tasks.

## Round 30 parallel assignments — accepted

| Task | Owner | File boundary | Acceptance |
|---|---|---|---|
| MULHW/MULHWU | `build_foundation`, Sol/high | Package/decode/IU, ISA metadata/generator/tests/matrix, new direct benches | Four signed/unsigned high-word forms, reserved OE-position rejection, preserved XER and Rc-only CR0 |
| Figure 8-18 single-beat write delays | `isa_metadata`, Sol/high | Bus scenario JSON/checker/tests and BUS_SPEC.md | Six bounded rows, TA pacing versus DBG start delays, write semantics versus DRTRY grant exclusion, explicit fidelity limits |
| Integration and review | Parent | Symbolic program, recovery variants, literal tests, Makefile and shared docs | Full-state signedness/alias/flag checks, source review, full regressions and acceptance |

All five new targets and all 86 prior RTL targets pass, as do strict core/wrapper lint and 184 Python tests (169 tools plus 15 recovery). The program performs 2,076 retirements with 160,152 full-state checks; both recovery variants add 3,434 checks. Direct decoder coverage is 655,361 checks and execution adds 64, including unsigned high results that record LT and both Rc0 candidate paths. Metadata has 146 implemented forms and 80 reviewed source rows, with 146 pending; the compiled probe agrees on 855 accepted words out of 26,048. No post-implementation RTL correction was needed.

Two long regression commands were terminated during compilation without reporting test failures. Integration removed only the interrupted targets' generated precompiled headers and resumed unfinished targets in smaller batches. All resumed commands completed with exit zero; no regression remains unfinished.

Figure 8-18 adds six selected rows distinguishing TA wait cycles from a delayed DBG grant and the final undelayed write. The source contract does not infer a data-drive onset from within-cycle drawing offsets. DRTRY does not retry or complete a write, but a preceding read's asserted DRTRY can still exclude a new data grant. The bus inventory is now 17 scenarios / ten cycle tables, with six diagrams still inventory-only. Its 15 focused tests include nine Figure 8-18 mutation cases. This is source preparation, not a bus RTL implementation.

See [MULTIPLY_HIGH.md](MULTIPLY_HIGH.md) and [BUS_SPEC.md](BUS_SPEC.md). Overall completion is approximately **22%**, fixed weighted score **22.42%**, previously 22.10%. Source-defined multiply latency and scheduling remain open, so P08 is still partial.

Next independent candidates: a bounded divide family with explicit exceptional-input semantics and recovery, alongside another remaining bus waveform such as Figure 8-19. Operand-dependent multiply timing, divide scheduling, dual dispatch and full reference acceptance remain separate open tasks.

## Round 31 parallel assignments — accepted

| Task | Owner | File boundary | Acceptance |
|---|---|---|---|
| DIVWU | `build_foundation`, Sol/high | Package/decode/IU, ISA metadata/generator/tests/matrix, new direct benches | Four unsigned divide forms, guarded zero divisor, OE/CR0 behavior, CA preservation and explicit undefined-result policy |
| Figure 8-19 burst delays | `isa_metadata`, Sol/high | Bus scenario JSON/checker/tests and BUS_SPEC.md | Ten bounded rows, write TA delay, read DRTRY replacement and third-address ordering with source conflicts retained |
| Integration and review | Parent | Symbolic program, recovery variants, literal tests, Makefile and shared docs | Architectural versus local-policy checks, source review, full regressions and acceptance |

Five new targets and all 91 prior RTL targets pass, as do strict core/wrapper lint and 194 Python tests (179 tools plus 15 recovery). The program performs 1,979 retirements with 152,683 full-state checks; both normal and zero-divisor recovery variants add 3,434 checks. Direct decoder coverage is 393,218 checks and execution adds 73, including all zero-divisor OE/Rc combinations, signed classification of unsigned quotients and held results. Metadata contains 150 implemented forms and 81 reviewed source rows, with 145 pending. The compiled probe agrees on 875 accepted words out of 26,048. All regression batches completed successfully; no post-implementation RTL correction was needed.

The source leaves zero-divisor rD and CR0 LT/GT/EQ undefined. This scaffold selects zero/EQ for reproducibility; independent tests check the defined OV/SO/CR0.SO and carry behavior separately. The current registered IU does not implement PID6 37-cycle or PID7v 20-cycle divide latency. P08 remains partial.

Figure 8-19 adds ten selected rows and preserves two source conflicts: the prose's clock0 versus the rendered 1–20 axis, and critical-quadword versus critical-doubleword terminology. It allows final In3 acceptance to coincide with replacement In2 confirmation, avoiding an unsupported extra cycle. The bus inventory is now 18 scenarios / eleven cycle tables, with five diagrams still inventory-only; 19 focused tests include eleven Figure 8-19 mutation cases. This is source preparation, not bus RTL.

See [DIVIDE_UNSIGNED.md](DIVIDE_UNSIGNED.md) and [BUS_SPEC.md](BUS_SPEC.md). Overall completion is approximately **23%**, fixed weighted score **22.74%**, previously 22.42%.

Next independent candidates: signed DIVW, including zero and minimum-signed/-1 exceptional inputs with explicit defined/undefined boundaries; and a remaining bus waveform such as Figure 8-15 or 8-16. Full multiply/divide scheduling, dual dispatch and architectural reference acceptance remain open.

## Round 32 parallel assignments — accepted

| Task | Owner | File boundary | Acceptance |
|---|---|---|---|
| Signed DIVW | `build_foundation`, Sol/high | Package/decode/IU, ISA metadata/generator/tests/matrix, direct benches and prior DIVWU exclusion fixture | Four signed divide forms, truncation toward zero, guarded zero/overflow, defined flag behavior and explicit undefined-result policies |
| Figure 8-15 fastest single-beat reads | `isa_metadata`, Sol/high | Bus scenario JSON/checker/tests and BUS_SPEC.md | Five bounded rows, conditional latency/throughput relation, address/data overlap and explicit normal-DRTRY profile assumption |
| Integration and review | Parent | Symbolic program, three recovery variants, literal tests, Makefile and shared docs | Sign/remainder identities, architectural versus local-policy checks, source review and full regressions |

Six new targets and all 96 prior RTL targets pass, along with strict core/wrapper lint and 204 Python tests (189 tools plus 15 recovery). The program performs 1,979 retirements with 152,683 full-state checks; normal, zero-divisor and signed-overflow recovery variants add 3,434 checks each. Direct decoding adds 393,218 checks and execution 127. The previous DIVWU fixture now rejects unsupported DIVD rather than newly legal DIVW. Metadata has 154 implemented forms and 82 reviewed source rows, with 144 pending. The compiled probe agrees on 895 accepted words out of 26,048. All regression commands completed successfully; no post-implementation RTL correction was needed.

DIVW truncates normal signed quotients toward zero. Division by zero and minimum-signed/-1 are detected before division; zero/EQ outputs are local choices for the source's undefined fields. Defined OV/SO/CR0.SO and CA behavior is tested separately. Functional multiply/divide forms execute, but PID-specific latency, iterative datapaths and dedicated scheduling remain unimplemented, so P08 is still partial.

Figure 8-15 adds five selected rows and keeps minimum latency/maximum throughput qualitative. Delaying data does not change the stated throughput until it delays the third address tenure; the contract does not quantify that threshold or its impact. Read-data acceptance need not follow completed address tenure. Normal DRTRY is an explicit profile selection, not inferred from the negated trace. The bus inventory is now 19 scenarios / twelve cycle tables, with four diagrams still inventory-only; 23 focused tests include eleven Figure 8-15 mutation cases. No bus RTL credit is assigned.

See [DIVIDE_SIGNED.md](DIVIDE_SIGNED.md) and [BUS_SPEC.md](BUS_SPEC.md). Overall completion is approximately **23%**, fixed weighted score **23.06%**, previously 22.74%.

Next independent candidates: a source-backed P08 divider timing/reservation slice with explicit issue-to-finish edges and recovery obligations, alongside remaining Figure 8-16. Full multiply timing, dual dispatch and architectural reference acceptance remain separate open tasks.

## Round 33 — parallel capability milestones (accepted)

The user authorized a temporary three-track detour before resuming the ordered queue. Acceptance is bounded by executable behavior and independent tests, not by completing all parent tasks.

| Track | Owner | Scope and ownership | Acceptance boundary |
|---|---|---|---|
| P18/P19 bus foundation | `isa_metadata` | New bus master, signal-level BFM/checks, dedicated tests and BUS_MASTER.md | Single-outstanding uncached 64-bit scalar transfers; grants, waits, retry/error handling and core data integration. No cache/burst/full-protocol claim. |
| P13 architectural reference | `manual_audit` | Isolated sim/cosim reference runner/comparator and REFERENCE_RUNNER.md | Actual local DingusPPC execution against a supported RTL subset, first-divergence reporting and injected mismatch detection. Full upstream/FP acceptance remains separate. |
| P10 LSU expansion | `build_foundation` | Existing CPU RTL, ISA metadata and dedicated update-form tests/LSU_UPDATE.md | Aligned update-addressing forms, atomic architectural effects, alias legality, stalls/faults/recovery. Full pipelining and exception vectoring remain separate. |
| Integration | Parent | Core/bus integration fixture, independent program validation, Makefile and shared progress documentation | Review sources/contracts, run affected and existing regressions, record remaining gates and earned progress. |

CPU RTL has one writer. Bus and reference work use separate new modules/tools. The parent coordinates packet/interface changes and accepts all three tracks before assigning completion credit.

All three bounded tracks are accepted after parent integration and independent review. The aggregate now contains **110 executable targets**: 102 prior targets plus the three dedicated LSU tests, LSU program, bus adapter test, two core/bus programs and real-reference run. All passed. Strict core, measurement-wrapper and bus lint pass, as do **222 Python tests** (195 tools, 12 cosim, 15 recovery). One old recovery bench initially failed strict lint because the new result field was unused; it now asserts that ordinary IU execution leaves the update field zero, and its resumed group passes. No regression remains unfinished.

The LSU adds 14 aligned D/indexed update forms, for **168 implemented forms and 96 reviewed source rows**, with 130 pending rows. Dedicated checks cover exact decoding/invalid aliases (192), allocation-owned second-write authorization/fault masking (17), and full-core atomic writes, stalled/irrevocable retirement, killed offered loads, misalignment, load/store error suppression and old-source store aliases (92). The independent program performs 1,370 retirements and 106,065 full-state checks, including 202 reads and 72 writes. The special lane still serializes memory; full P10 timing/pipelining and architectural exception entry remain open.

The bus master connects that unchanged data interface to the bounded non-global, cache-inhibited, 64-bit scalar profile. The independent parent RAM responder passes the original 579-retirement program and the 1,370-retirement update program; the latter adds 127,055 checks. The task-driven direct bus test passes 584 checks over 21 responses, covering address retry qualification, waits/grant exclusion, provisional/read-replacement data, TEA including late/extended cases, response stalls, malformed exchanges, pin release and reset. Parent review found and corrected a missing same-edge replacement capture before acceptance; a separate read-only agent review then identified additional coverage cases, which now pass. Exact table/page references were corrected during review. Full P18/P19, instruction-fetch integration, parity, burst, pipelining, 32-bit mode, cache/coherency and FPGA edge timing remain open.

The reference adapter executes unmodified local DingusPPC handlers with explicit `-fwrapv`, a closed adapter-owned dispatch gate and recorded source/build hashes. Actual RTL matches **5,943 snapshots × 38 fields**, across 111 corpus encoding groups. The same comparator detects eight field corruptions and four structural trace failures; eight unsupported opcode/model gates also pass. The reference source remains unchanged. This is bounded P13b acceptance, not the original whole-machine dispatcher or full integer/FP/reference gate.

See [LSU_UPDATE.md](LSU_UPDATE.md), [BUS_MASTER.md](BUS_MASTER.md) and [REFERENCE_RUNNER.md](REFERENCE_RUNNER.md). Overall completion is approximately **26%**, fixed weighted score **26.36%**, previously 23.06%.

The temporary capability detour can now return to the ordered queue: source-backed P08 divider timing/reservation, then remaining multiply timing and the other dependency-ordered work. LSU pipelining, expanded reference coverage and full bus scenario coverage retain their parent acceptance gates and must be scheduled explicitly rather than assumed complete.


## Round 34 — parallel timing, unified bus and reference milestones (accepted)

The user requested another wave of substantial parallel work. Existing agents retained bounded ownership, with the parent implementing independent pin-level program integration and running the broad regression.

| Milestone | Owner | Files and acceptance boundary |
| --- | --- | --- |
| P08 divider reservation | `build_foundation` | IU/core latency parameter, direct/full-core timing and recovery checks, DIVIDER_TIMING.md. Default PID7v 20 and PID6 37 execute cycles; iterative quotient hardware and multiply timing remain separate. |
| P19 unified instruction/data transport | `isa_metadata` | Captured-owner fair router, reusable core/bus wrapper, instruction TC attribute, arbiter/error tests and BUS_INTEGRATION.md. Scalar cache-inhibited profile; instruction TEA is a reset-only transport diagnostic. |
| P13c non-memory reference breadth | `manual_audit` | Original-handler reference adapter/corpus, legality gates, coverage manifest and REFERENCE_RUNNER.md. All 140 implemented non-memory forms; 28 scalar memory forms and undefined divide outputs remain outside comparison. |
| Independent integration and review | Parent | Unified pin RAM responder, relocated symbolic programs, Makefile and shared documentation; broad regression and strict lint. Reference owner also reviews divider timing independently. |

The unified responder uses instruction ROM below 0x4000 and byte RAM at 0x6000, avoiding the older separate-port fixture's overlapping address ranges. The program generator exposes the two supported memory-base fixtures and preserves the default 0x1000 output. The responder derives its data solely from public bus pins; core hierarchy is used only for architectural state comparison and handshake accounting. Baseline and update programs pass 579/1,370 retirements, with 651/1,442 actual instruction pin reads, and 31/202 data reads plus 22/72 writes. The update run performs 143,595 checks, including branch-path draining, full GPR/CR/XER/LR/CTR/memory state and stalls.

The expanded reference run matches 8,500 retirements across 38 fields, with 142 encoding groups. Metadata reconciliation independently inventories all 140 non-memory forms, and the original handlers supply the expected state. It passes 12 injected comparator failures and 43 input/model/undefined-result rejection gates. SPR specialization uses GCC flatten/LTO to remove unreachable machine-service paths while retaining original LR/CTR handler semantics; unsupported XER SPR moves remain rejected. Undefined divide outputs are rejected using live pre-instruction operands before invoking the handler.

Remaining parent gates include iterative divide hardware, operand-dependent multiply timing, dual issue, precise instruction/data exceptions, LSU pipelining, caches, full bus modes and upstream memory/FP/reference acceptance. This round does not close P08, P13 or P19 in full.

Round 34 acceptance: all **117 executable targets** (the full aggregate dependency set, run in bounded batches), **223 Python tests** (195 tooling, 13 cosim, 15 recovery), and strict core/bus/system/measurement-wrapper lint pass. The final direct divider timing test passes 1,071 checks; actual-core tests pass 58/92 checks for 20/37 cycles, and all five full-core divide recovery variants pass 5,339 checks each. Bus direct/arbiter/fetch-error tests pass 637/64/39 checks. Review corrected an instruction-request shape gap, a cancellation-aware test assertion, and a TC source-page locator before acceptance. The reference manifest hashes match the final CPU sources and the original reference checkout remains clean. No new FPGA fit or timing-closure result is claimed.

Overall completion is approximately **28%**, fixed weighted score **27.92%**, previously 26.36%. The ISA remains at 168 implemented forms, with 96 of 226 source rows reviewed. Next in the ordered queue is operand-dependent multiply timing and scheduling; the iterative divider datapath remains an explicit P08 task. Memory reference integration and remaining bus modes/scenarios may be scheduled independently with their existing acceptance boundaries.


## Round 35 — iterative hardware, burst reads and full-RAM reference (accepted)

The user requested another wave of independent substantial work. Existing agents owned three bounded milestones; the parent implemented a separate burst pin responder, updated build wiring, reviewed interfaces and ran the aggregate regression.

| Milestone | Owner | Implementation and boundary |
| --- | --- | --- |
| P08 iterative divider | `build_foundation` | New ppc_divider.sv, IU integration, arithmetic/timing tests, division metadata and docs. Sixteen radix-4 iterations replace the quotient operator while retaining 20/37-cycle accepted finish, flags and recovery. Multiply timing and full P08 closure remain open. |
| P19 burst line reads | `isa_metadata` | Separate ppc_bus60x_line_read.sv, line_read_files.f, task-driven target/tests and BUS_LINE_READ.md. Actual four-beat cacheable reads with critical-doubleword wrapping and complete-line responses. No cache or core-wrapper connection. |
| P13d full-RAM reference | `manual_audit` | Original load/store handlers, explicit flat memory service, v2 comparator/corpus/core bench, rejection cases and provenance. All 168 implemented forms, normal aligned memory only; original MMU and architectural exceptions remain outside scope. |
| Independent integration | Parent | Literal burst-order pin tester, Make/Quartus source wiring, broad tests and shared docs. Reference owner independently reviewed radix-4 arithmetic and IU cancellation. |

The divider uses 34-bit trial remainders and one/two/three-times-divisor comparisons to generate two quotient bits on each of 16 iteration edges. Signed operations use unsigned magnitudes and restore the quotient sign; exceptional input classes retain the documented local zero-result policy. The IU waits for both the complete quotient and the configured reservation interval. Supported timing configurations 20/37 continue to finish at E+N, and settings below 17 cannot accommodate the iteration schedule. No quotient division operator remains in synthesized RTL. Direct tests compare 524 signed/unsigned cases against a separate arithmetic oracle and reconstruction bounds, with 11,544 checks. Source metadata and the generated ISA matrix now describe the real implementation without changing any instruction encoding or form count.

The burst engine preserves each provisional beat until DRTRY confirmation, supports same-edge replacement and next-beat transfer, and normalizes all four Table 8-2 starting positions into line-base order. Address retry, grant exclusion, waits, mid/late TEA, final retry after DBB release, held response and reset are covered. Parent review removed an incorrect fifth-beat diagnosis: an unqualified TA after final DBB release must not corrupt a line whose final candidate is confirmed. Dedicated checks verify half-cycle ABB/DBB release and retention across nonfinal beats. Parent's separate tester supplies all data solely through physical pins using a literal order table; it passes 14 response scenarios and 16 address attempts, with 563 checks.

The v2 reference runner calls original DingusPPC memory instruction handlers against a bounded 256-byte big-endian RAM service. A mandatory schema header distinguishes its 102-field snapshots from the unchanged 38-field v1 format. It compares every RAM word plus registers after each retirement, without digest or state masking. The corpus executes 9,881 instructions across all 168 implemented forms, including 106 loads and 134 stores. The instruction image remains separate and immutable even where numerical addresses overlap RAM. Flat-memory service and explicit failure callbacks do not claim original MMU, self-modifying code, architectural faults or rollback behavior.

Full processor timing, operand-dependent multiply scheduling, precise exceptions, cache tags/replacement/coherency and burst integration remain open. The new line engine is a tested refill building block, not an implemented instruction/data cache.

Round 35 acceptance: all **121 executable targets** passed across bounded aggregate batches, alongside **227 Python tests** (195 tooling, 17 cosim, 15 recovery) and strict core/scalar-bus/system/line-read/measurement-wrapper lint. The divider passes 11,544 checks over 524 cases; a latency of 16 is rejected at startup as required. The direct burst bench passes 323 checks and the independent pin bench passes 563 checks. Both reference formats were rerun against final RTL and metadata: v1 matches 8,500 retirements, v2 matches 9,881, with all 28/31 manifest hashes verified and the original reference checkout clean. V2 also detects 13 injected comparison failures and 69 rejection cases. No FPGA fit or timing closure is claimed.

Overall completion is approximately **30%**, fixed weighted score **29.68%**, previously 27.92%. The ISA remains at 168 implemented forms, with 96 of 226 source rows reviewed. The ordered queue resumes with operand-dependent multiply timing and scheduling. Cache/core integration and broader architectural reference acceptance remain separately scoped follow-ups.

## Round 36 — multiply timing, instruction-cache foundation and seeded reference (accepted)

The user requested another parallel wave. `build_foundation` owns conservative multiply reservation and accepted-finish/recovery checks; `isa_metadata` owns a standalone 16-KiB instruction-cache controller and direct verification; `manual_audit` owns deterministic mixed-program reference stress with compilation reused across seeds. The parent owns build wiring, independent cache-to-burst integration verification, review, shared documentation and final acceptance.

The cache milestone is bounded to physical addresses, exact four-way LRU and complete-line refill. MMU integration, architectural cache controls, early critical-word forwarding and actual-core routing remain open. The reference milestone extends workload diversity without claiming new ISA implementation. Final completion credit is assigned only after validation. Compiler precompiled-header caches are removed after completed build batches; `make clean-cache` preserves simulation results and manifests.

Source review found that Table 6-4 supplies multiply latency sets without the operand-to-latency mapping. This round therefore uses explicit maximum-latency reservations (MULLI 3, MULLW/MULHW 5, MULHWU 6 cycles); it does not invent an operand classifier or close TIM-U02.

Implementation and review results: the multiplier uses a distinct internal MULLI operation without changing packet widths or architectural encodings. Direct timing tests pass 76 checks and actual-core timing passes 27, including accepted-finish dependent wake. Independent review found no multiplier correctness issue. The cache direct bench passes 1,122 checks, including delayed drain and repeated invalidation; the independent physical-burst bench passes 3,805 checks over 89 fetch responses and 21 bursts. Review corrected same-edge fetch response gating under kill/invalidate.

Seeded reference acceptance includes three default seeds (3,419 retirements) and one MAX512 workload using the same binaries (4,050 retirements), totaling 7,469 full 102-field comparisons, 105 distinct dynamically executed forms and 1,060 memory accesses. Eight injected register/RAM mismatches are rejected. Fixed v1/v2 reference runs separately retain their 8,500/9,881 retirements and all-168-form coverage; all source/binary manifest hashes were verified.

During broad regression, the parent's per-target cleanup traversed sibling builds because the legacy core target uses the build root itself. This caused missing compiler-header failures, not RTL failures. Cleanup was restricted to the exact compiler output directory and affected targets were resumed. Whole-tree `clean-cache` remains an after-build command.

For future parallel regression batches, clean only top-level `.gch` files in an exact `--Mdir` after its last consumer finishes. Keep shared program-build caches until the final profile using that directory, then discard them. Never recursively clean the legacy root Mdir while sibling targets are compiling.

Round 36 acceptance: all **126 executable targets** passed across the aggregate batches and resumed compiler-only failures. All **232 Python tests** (195 tooling, 22 cosim, 15 recovery) and strict core/scalar-bus/line/cache/system/measurement-wrapper lint pass. Final direct multiply timing passes 76 checks; cache direct/integration pass 1,122/3,805. Fixed and seeded reference source/binary hashes match the final implementation. No new FPGA synthesis, fit, storage inference or timing-closure result is claimed. Compiler header caches were removed after all builds finished, preserving executables and reference evidence.

Overall completion is approximately **31%**, fixed weighted score **31.00%**, previously 29.68%. ISA implementation remains 168 forms and source reconciliation remains 96/226. Operand-dependent multiplier timing remains source-gated under TIM-U02. The standalone cache is ready for a separately scoped core-fetch/bus routing task; MMU, architectural cache controls, early refill forwarding, supervisor exceptions and broader conformance remain open.

## Round 37 — cached core, BAT translation and exception state (accepted)

Three independent assignments extend the accepted foundations. `isa_metadata` owns a new cached-core wrapper and fair physical-bus selector, preserving the existing uncached wrapper. `manual_audit` owns a standalone selected-bank BAT translator with explicit bypass/miss/protection/configuration outcomes. `build_foundation` owns a standalone committed-boundary exception-state controller. The parent owns independent original-handler comparison through cached CPU/bus pins, independent BAT vectors, source/interface review, build wiring and acceptance.

The cached fetch path preserves accepted response obligations on redirects; it does not drop a refill response that the current fetch unit must drain. BAT and exception state are standalone hardware interfaces, not integrated MMU or precise-fault delivery. The official Programming Environments Manual is preserved as `MPCFPE.pdf` with provenance in SOURCES.md; 603e-specific definitions take precedence over generic architecture descriptions.

Round 37 acceptance: the selector passes 153 checks and focused cached-core transport passes 628. The independent cached reference matches 9,881 retirements across all 168 implemented forms and the complete 256-byte RAM; 9,992 accepted fetch requests include 8,755 hits and 1,237 miss/burst addresses, with 240 scalar data transactions (134 stores) and 15,844 physical wait cycles. Three injected state corruptions are rejected, and all 142 final source/header/binary/trace hashes match. Speculative bus work may remain at the final recorded retirement; these counts do not claim a drained whole system.

BAT direct tests pass 16,824 checks. The independent interval/addition oracle contributes 45,312 external vectors covering every size, way, privilege, PP permission, validity and boundary, with local invalid configuration cases. Exception-state direct tests pass 68 checks, including held/turnover behavior, same-edge reset withdrawal, saved-PC/vector/MSR rules and TGPR clearing on supervisor RFI. Independent source/RTL review found no material defect; reserved-state mask interpretation and CSR readback limits remain explicit. Review corrected a combinational dependency cone in the new selector's BG qualification; no functional arbitration change or lint suppression was needed.

All **19 new and affected executable targets**, **232 Python tests** (195 tooling, 22 cosim, 15 recovery), and strict core/scalar/line/cache/cached-wrapper/BAT/exception/measurement lint pass. The Make aggregate now exposes 132 executable targets, but this round did not rerun the full aggregate: existing CPU RTL hashes match the previously accepted full regression. Tests covered the new modules, cache/bus transports and fetch/core recovery. No FPGA synthesis, inference, fit or timing closure is claimed. Completed compiler caches are cleaned while binaries, manifests and traces are retained.

Overall completion is approximately **34%**, fixed weighted score **34.24%**, previously 31.00%. ISA implementation remains 168 forms and source reconciliation remains 96/226. The next integration gates are architectural supervisor/CSR/event routing and BAT register/translation routing; exception priority, segment/TLB machinery, cache controls, D-cache/coherency, early refill forwarding and exact multiplier operand timing remain open.

## Round 38 — supervisor execution, BAT service and cache maintenance (accepted)

The user requested another parallel wave. `build_foundation` owns a bounded opt-in CPU supervisor entry/return path; `manual_audit` owns committed IBAT/DBAT storage with held translation/SPR responses; `isa_metadata` owns a managed cached wrapper with safe local invalidation and cache control. The parent owns independent BAT transaction vectors, integration review, Make wiring and regression acceptance. The existing default execution profile and its 168-form reference remain a separate acceptance lane.

Supervisor acceptance must show real SC/handler/RFI execution, committed state changes and no younger effects; valid but unimplemented instructions and LSU failures must not be indiscriminately reclassified as illegal-program exceptions. BAT acceptance must prove bank isolation, privilege checks, coherent accepted snapshots and explicit misses. Cache maintenance must preserve accepted response obligations, drain transport and refetch changed code; local controls do not claim decoded HID0/icbi/isync semantics. No completion credit is assigned before validation. Compiler caches are cleaned in exact build directories only after their last consumer, with whole-tree cleanup deferred until all builds stop.

Round 38 milestone results: the opt-in supervisor decoder passes 846 checks, and actual-core entry/return passes 311 checks after the parent's additional user-mode RFI/MFMSR/MFSRR0/MTSRR1 cases. The core executes SC, reads SRR/MSR in its handler and returns to PC+4. Tests cover pre-finish cancellation, a stalled finished head, internal-vs-external redirect priority, masked reserved-bit readback and unsupported return-state rejection. The default profile retains 168 forms; seven opt-in forms are separately recorded. Only the reviewed zero word becomes an illegal-program event; other unimplemented instructions and memory faults retain diagnostics. The local retirement token is an event boundary, not a claim that a faulting instruction completed normally.

The BAT service passes 540 direct checks and 57,950 independent stateful transactions (695,942 checks with the external corpus). Those transactions cover both banks, all twelve block sizes and four entries, privilege/permission/bypass combinations, rejected candidate writes preserving old state, overlap and privilege-disjoint aliases, and next-request offers during held responses. A corrupt expected response is rejected. The canonical service manifest records final RTL/bench/oracle/vector/executable hashes. The service's zero reset and candidate-write validation are explicitly local policies; core SPR decode, memory routing and the segment/TLB path remain open.

The managed cache passes 114 direct and 811 actual-core checks, including 26 retirements, changed-code visibility after full invalidation plus accepted restart, real scalar bypass, completion backpressure and fetch-error/reset behavior. Independent original-handler profiles match all 168 default forms and 9,881 retirements each in legacy-cache, managed-enabled and managed-disabled configurations. Enabled profiles record 8,755 hits and 1,237 miss/burst addresses; disabled records no hits/misses/bursts and 9,922 scalar instruction addresses. Each profile compares every GPR/CR/XER/LR/CTR and every word of the 256-byte RAM and rejects three injected corruptions. Final physical transactions may still be speculative at the trace endpoint; these are not drained-system or performance totals.

Review corrected immediate reset withdrawal on the managed bypass response and architectural MFMSR reserved-bit masking. Integration validation also caught missing new-output bindings in the older CR-state testbench and a reference-source freeze violation during a final metadata correction. The bench now explicitly checks that the default profile's supervisor outputs stay zero; affected jobs were restarted, and reference manifests were rebuilt against the final metadata. No warning suppression was added. The Quartus project source list includes the new exception-state dependency and the measurement wrapper passes strict lint; no new synthesis, fit, inference or timing-closure result is claimed.

Round 38 final acceptance: all **140 executable aggregate targets**, **233 Python tests** (196 tooling, 22 cosim, 15 recovery), and strict default/enabled core, bus/cache/BAT/exception/managed/measurement lint pass. Six reference profiles plus the reused-binary maximum seed match **55,493 retirement snapshots** in total. All final RTL freeze hashes and reference manifests match. [The retained acceptance record](../sim/build/round38/acceptance.json) lists every target and final source/reference hashes. This round reran the full default aggregate because CPU/decode/special-lane RTL changed. The two restarted lanes described above completed successfully.

Completed compiler headers were removed in exact directories after their last consumer. Final whole-tree `clean-cache` found zero remaining `.gch` files; `sim` occupies approximately **841 MiB**, retaining executables, manifests, vectors and traces. Agent-owned temporary supervisor/cache/BAT build headers were also removed. A future parallel full regression should balance expected compile cost as well as target counts: the older exhaustive unary execution bench was substantially slower than its neighboring targets.

Overall completion is approximately **37%**, fixed weighted score **37.02%**, previously 34.24%. The default ISA remains 168 forms, with seven separately enabled supervisor forms, and source reconciliation is 99/226. Weights remain unchanged. The next integration gates are BAT register/translation routing into CPU memory requests, decoded cache/context-synchronization commands, and additional precise supervisor/CSR/fault handling. General exception priority, interrupts, segment/TLB machinery, D-cache/coherency, early refill forwarding, exact multiplier operand timing, floating point and FPGA closure remain open.

## Round 39 — serialization, BAT CPU routing and page TLB (accepted)

The user requested another parallel wave. `build_foundation` owns opt-in ISYNC/SYNC/EIEIO execution and source/ISA metadata; `isa_metadata` owns a new actual-core BAT memory-routing wrapper; `manual_audit` owns source-backed software-loaded instruction/data page TLB storage. The parent owns independent translated-reference execution, source/interface review, build wiring and acceptance.

The BAT wrapper's startup configuration is a local integration interface while the CPU is held reset; architectural BAT SPR/MSR routing remains separate. The TLB must use documented indexing, tags, selected-way refill and invalidate behavior, with no invented page walk or miss exception semantics. Barriers use the current serialized LSU and context-restart path, with default 168-form behavior preserved. Final scope credit depends on verification. Full-regression scheduling groups shared compiler directories, starts the largest generated builds first and bounds compiler parallelism; cache cleanup stays limited to exact directories after their last consumer.

Round 39 acceptance: exact opt-in ISYNC/SYNC/EIEIO passes 168 decoder and 124 actual-core checks, including delayed older memory completion, stalled retirement, no younger effects, changed backing instruction refetch, redirect priority/cancellation, wrap and reset. Default decode stays at 168 forms; seven supervisor and three serialization forms are separately opt-in. The inventory now reconciles 102/226 source rows. MTMSR and cached modified-code protocols remain open.

The new BAT router passes 230 checks and its actual-core wrapper passes 330. Setup writes hold the CPU reset; accepted start fixes local IR/DR/PR until hard reset. One captured instruction/data owner translates before physical access, preserves accepted-response obligations across redirects, and suppresses physical activity on denial. A later physical instruction error preserves an earlier translation-fault record. Actual tests cover relocated load/add/store/load, wrong-path physical response drain, bypass and translated instruction miss. WIMG is exposed metadata; live CPU MSR/BAT SPR writes, architectural fault delivery and downstream cache/60x behavior remain separate work.

The page TLB passes 866 direct transactions/3,528 checks and 17,364 independently generated transactions/902,705 checks. The independent oracle uses a virtual-page dictionary and literal permission table; coverage spans both 64-entry banks, all sets/ways, VSID/tag aliases, page offsets, key/PP/WIMG/C combinations, invalidation and rejected refills under held-response/turnover conditions. Nine corrupted/malformed vector gates reject. Refill is normalized software work with implicit R=1 and explicit C-update-needed classification; local empty reset and duplicate rejection do not claim silicon initialization or duplicate behavior. Segment state, replacement choice, PTE accesses, miss SPRs/TGPRs and CPU page routing remain open.

Parent review added an independent accepted-request monitor to the BAT reference: every physical request must equal captured CPU EA plus its literal relocation, with WIMG and write payload preserved. All 9,881 retirements, 168 default forms and the complete RAM match original handlers. The seven reference profiles and reused-binary MAX seed total 65,374 matched snapshots. The reference remains a flat architectural handler oracle; independent address observations establish BAT routing evidence.

All **147 executable aggregate targets**, **239 Python tests** (202 tooling, 22 cosim, 15 recovery), and strict lint pass. The existing 134 non-reference targets ran in disjoint compiler-directory groups, largest builds first, with three workers and two compiler jobs per worker. Six new non-reference gates and seven reference lanes complete the aggregate. The first launch used an unsupported Verilator job-option spelling; it was corrected before compilation. TLB testing exposed an EOF parser assumption, fixed with explicit line/token/width checks. The BAT test responder was corrected to sample handshakes at their acceptance edge. Final source and reference hashes match [the retained acceptance record](../sim/build/round39/acceptance.json).

All builds finished before final cleanup. Four remaining compiler headers reclaimed 0.26 GiB; agent temporary build headers were also removed. `sim` is approximately **892 MiB**, preserving binaries, traces, vectors and manifests. No synthesis, fit, RAM inference or timing-closure result is claimed.

Overall completion is approximately **39%**, fixed weighted estimate **39.16%**, previously 37.02%. Weights are unchanged. Next integration gates are live architectural translation context and BAT SPR routing; segment/miss-register/TGPR state and decoded TLB refill/invalidation; and cache maintenance connected to architectural context synchronization. General exception priority, interrupts, D-cache/coherency, exact operand-dependent multiply timing, floating point and FPGA closure remain open. These dependencies should guide the next wave or resumption of the ordered P14–P17 work.

## Round 40 — incremental supervisor registers (accepted)

The user requested a return to incremental changes. `build_foundation` owns eight opt-in SPRG0–SPRG3 read/write forms, commit-owned storage and ISA metadata. `isa_metadata` independently owns focused decoder and actual-core verification, including privilege, cancellation and stalled retirement. `manual_audit` prepares only the source contract for segment-register operations and cross-checks SPRG source/reset rules. The parent owns integration, regression and acceptance. No live MMU, new fault class, or default instruction-profile expansion is included. The agent assignments reuse existing workers and have separate file ownership.

The eight SPRG forms are accepted under `ENABLE_SUPERVISOR_EXCEPTIONS`: SPR272–275 expose all 32 bits, and the existing special lane changes exactly one bank entry only at matching accepted retirement. User-mode access is normalized to the existing privilege event before allocation, so no GPR or SPRG permissions escape. No new public ports, package operations or module dependencies were needed. Table 4-8 hard-reset zero is implemented; a distinct soft-reset interface remains absent. Default decode remains 168 forms. The metadata now has 186 reviewed entries: 168 default, 15 supervisor opt-in and 3 serialization opt-in. Source rows remain 102/226 because the generic MFSPR/MTSPR mnemonic rows were already reconciled.

Independent decode verification passes **8,097 checks**, including eight literal words, all GPR and SPR selectors, reserved Rc/XO/primary fields and default exclusion. Actual-core verification passes **192 checks**: all four full-width registers and isolation, consecutive reads/writes, held writer/read results with no early architectural change, exact commit, selected-bank overwrite, unfinished cancellation/stale-finish suppression, real-RFI problem-state MF/MT privilege checks and hard-reset clearing. The only behavioral-test correction was the new bench's expected SRR1: an installed old MSR of 87c04000 produces saved 87c44000, matching the existing source-qualified exception mask. RTL was unchanged. The canonical bench reran after that correction and final display cleanup.

The independently reviewed [segment-register contract](SEGMENT_REGISTER_CONTRACT.md) records exact MFSR/MTSR/MFSRIN/MTSRIN masks, indexed high-nibble selection, ordinary r0/alias semantics, supervisor rules, T-dependent register fields, reserved-bit and reset policies, and required context synchronization. It separates standalone bank behavior from live CPU/TLB integration, preserves accepted context snapshots and avoids inventing automatic TLB flush or direct-store support. This is next-task preparation, with no executable MMU credit.

Final acceptance: all **149 executable aggregate targets**, **241 Python tests** (204 tooling, 22 cosim, 15 recovery), and strict lint pass. The 140 existing non-reference gates, two new SPRG gates, and seven reference profiles all ran against frozen RTL/metadata. Including the reused-binary maximum stress seed, **65,374 reference retirement snapshots** matched. These references exercise the default 168-form profile; SPRG acceptance is the separate independent opt-in bench. Final source/binary/reference hashes match [the retained acceptance record](../sim/build/round40/acceptance.json), with regression summaries and lint/Python logs retained alongside it.

Exact completed SPRG build headers were removed before final cleanup. After all remaining builds finished, `clean-cache` removed four more headers and reclaimed 0.26 GiB; agent temporary headers are also gone. `sim` occupies approximately **912 MiB**, retaining executables, vectors, manifests and traces. No new synthesis, fit, inference or timing-closure result is claimed.

Overall completion is approximately **39%**, weighted estimate **39.40%**, previously 39.16%. Only supervisor/system credit moves 30→33%; all workstream weights and other completion scores stay unchanged. This deliberately incremental round adds 0.24 percentage points. Next work can take segment-register storage/indexing first, followed by CPU binding and coherent TLB context capture as separate tasks. General fault priority, live translation context, miss handlers, interrupts, cache coherency, floating point and FPGA closure remain open.

## Round 41 — standalone segment-register bank (in progress)

The next incremental task is a sixteen-entry committed segment-register bank, direct/indexed selection and an internal held context snapshot. `build_foundation` owns new RTL/filelist/documentation; `isa_metadata` owns an independent focused bench; `manual_audit` reviews source rules and accepted-request behavior. The parent owns integration, baseline verification and acceptance. CPU instruction decode, TLB routing, live MSR context, miss handling and architectural reset remain separate tasks. Existing implementation hashes match round40; no existing RTL or ISA changes are planned.
