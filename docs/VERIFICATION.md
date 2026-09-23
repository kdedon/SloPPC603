# Verification

## Current gate

The subsequent [event-entry reset gate](EVENT_RESET_VERIFICATION.md) passed eight new EXT/DEC reset scenarios, 24 strict RTL lint profiles and 243 Python tests with 144 gate-input hashes stable. A temporary DEC-pending reset mutation fails the intended stale-event check. Production RTL is unchanged from the XER round; no full regression, firmware rebuild or FPGA fit was repeated.

The subsequent [XER SPR access focused gate](XER_VERIFICATION.md) passed 24 strict RTL lint profiles, 243 Python tests and the targeted decoder/flag/core/recovery programs with 147 source/metadata/build hashes stable. It did not repeat the complete regression or FPGA fit.

The subsequent reset/allocation-only rename owner change passed [focused recovery, update and fault validation](RECOVERY_METADATA_VERIFICATION.md), aggregate strict lint and 241 Python tests. The complete timer regression below predates that narrow change; this final round did not repeat the full regression or FPGA fit.

The opt-in time-base/decrementer profile passed the source-frozen full gate on 2026-09-21: 172 named test targets, 24 strict RTL lint profiles, 140 direct bench prelint profiles and 241 Python tests, with all 146 source hashes stable. See [timer verification](TIMER_VERIFICATION.md) for independent counter, decode, privilege and event evidence, provenance and remaining coverage.

Run `make -C ppc603e/sim regression` from the workspace root; `all` is an alias for the same complete local gate. It runs strict RTL lint, every simulation in `test`, metadata consistency and Python checker tests in `check-spec`, the recovery policy tests, and the standalone recovery-selector RTL test. Focused targets remain available for development. This gate covers the implemented features and bounded profiles; it does not establish complete ISA, timing, bus or FPGA conformance.

RTL lint uses `verilator --lint-only -Wall` without global warning suppression. Core and focused testbenches use `--binary --timing --assert -Wall`; their local BLKSEQ annotations permit procedural clock/reference-model blocking assignments without suppressing RTL warnings.

`make -jN` may run independent targets concurrently within one invocation. The twenty control/memory program targets, two data-bus program targets, and two unified-bus program targets each share one build prerequisite for their Verilator output directory. Each executable is built once per invocation before its consumers run; program fixtures have separate directories and are only read by the benches. The existing independent BAT/TLB/vector targets depend on their associated base test before reusing its executable. Use a modest job count to limit compiler memory usage. Separate make invocations must use separate build directories, and `clean`/`clean-cache` must run after builds finish. For example:

```sh
make -C ppc603e/sim -j2 regression
make -C ppc603e/sim -j2 BUILD_DIR=build-parallel \
  test-core-control-memory test-core-shifts
```

## Supervisor wrapper profiles

`test-core-bus60x-supervisor` exercises SC, handler execution, RFI, MFMSR and SYNC/EIEIO/ISYNC through the scalar physical-bus wrapper and RAM pin responder. `test-core-bus60x-supervisor-disabled` runs the same bench with the profile disabled and requires the default SC diagnostic and clean halt. Both belong to `test` and use distinct build directories. Strict lint also elaborates default and supervisor-enabled BAT, scalar-bus, cached-bus and managed-cache wrappers. These checks establish profile forwarding and the selected exception/barrier path, not asynchronous interrupt or translated exception support.

## Typed fetch faults and recovery storage

The aggregate includes enabled/default typed fetch-fault profiles and focused
FIFO/rename recovery storage checks. See [FETCH_FAULT_VERIFICATION.md](FETCH_FAULT_VERIFICATION.md)
for independent manual expectations, cause/PC precision, handler retry/skip,
wrong-path cancellation, reset/backpressure coverage and final run evidence.
Physical TEA remains a separate terminal transport outcome.

## Live supervisor context

The aggregate includes opt-in committed-context core/BAT profiles, exhaustive
MTMSR decode and bounded completion-ring checks. See
[LIVE_CONTEXT_VERIFICATION.md](LIVE_CONTEXT_VERIFICATION.md) for contracts,
independent expectations, integration cases and frozen regression evidence.

## External interrupt boundary

The aggregate includes opt-in external IRQ, disabled-profile rejection and
committed-EA dependency checks. See
[EXTERNAL_INTERRUPT_VERIFICATION.md](EXTERNAL_INTERRUPT_VERIFICATION.md) for
manual expectations, level/recognition policy, precise resume-PC and recovery
oracles, and frozen regression evidence.

## Historical foundation results

The sections below record incremental checks at their stated revision boundaries. Early descriptions of missing instructions and reference support describe those historical revisions; see the current README and the later sections for subsequent coverage.

`tb/tb_core.sv` contains an encoded program, variable-latency instruction responder, and sequential architectural reference model. No DingusPPC source is linked or copied. The program is deterministic and includes hand-computed anchors independent of generated expected values.

| Check | Coverage |
|---|---|
| Supported arithmetic/logic | Three runs of 256 instructions, seven supported instruction forms, generated register/immediate combinations |
| Dependencies | Repeated writers, read-after-write, rename pressure, architectural fallback, ordinary r0 reads/writes versus add-immediate literal zero |
| Protocol/order | Sequential request addresses, retirement PCs/opcodes, stable request/response/retirement under backpressure |
| Capacity/reuse | Initial 140-cycle retirement stall, full-IQ fetch-credit stalls, many wraps of the non-power-of-two IQ/CQ |
| Stop | Illegal opcode, `add.`, and `addo` diagnostic events; no GPR write on fault; no subsequent retirement |
| Reset | Reset before execution, during buffered work, and after halt; responder also cancels its pending work |
| Liveness | 5,000-cycle watchdog per reset epoch |

Observed on 2026-09-12 with Verilator 5.020: RTL lint passed and simulation reported `PASS: 3 x 256 integer results, illegal/Rc/OE rejection, queue pressure, reset recovery`.

This is a scaffold regression, not full ISA validation or a timing/bus conformance test. Random opcode generation is intentionally restricted to supported forms. No full DingusPPC execution suite, formal proof, final CPU fit, or processor timing-conformance validation has been run. P04 adds an early bootstrap synthesis/fit flow; BUILD_STATUS.md records its actual results and virtual-I/O assumptions.

## Expansion gates

The task plan assigns each feature its directed and integration tests. Keep architectural semantics, internal timing, and bus protocol checks separate: DingusPPC is a candidate semantics oracle, not an internal-cycle oracle, and its software-TLB/variant coverage must be audited. A timing deviation needs a source-linked explanation, not a weakened assertion.

Each task must preserve this smoke regression until it is intentionally replaced by an equivalent test of the new interface. New completion/rename logic requires adversarial finish ordering, stale-result rejection after flush, and resource-exhaustion tests. Architectural store effects must be checked at commitment. Final fit/timing claims require saved Quartus reports and explicit device/clock constraints.

## Accepted foundation checks

- `python3 -m unittest discover -s ppc603e/sim/cosim -p 'test_*.py'`: seven parser tests passed; the actual corpus inventory has 5,620 integer, 2,054 FP and 397 disassembly rows. This validates parsing, not execution semantics.
- `python3 ppc603e/sim/spec/check_timing.py`: 190 timing rows, 39 rules and 384 source locators pass structural checks. Broken references, duplicate graphical cycles and inconsistent FP stage sums are rejected; 35 graphical instruction rows / 162 cells are structurally checked; the data is not yet a cycle checker.
- BE/LE cross artifacts passed ELF32 PowerPC, entry, byte-order and symbol checks; clean-build reproducibility passed. See the toolchain README and BUILD_STATUS.md for commands and versions. The compiled program cannot execute on the current branch/LSU-free core.

## Tagged execution checks

`make -C ppc603e/sim test` runs the original core regression plus focused execution/completion benches and the stage probe:

- `tb_completion` (906 checks passed): fill all five slots, finish younger entries first, hold retirement, reject invalid/duplicate/stale identities after ring reuse, combine allocation/finish/retirement, and drain an ordered diagnostic fault behind unfinished work.
- `tb_execution`: pending operand ownership and wakeup, rename RAW/WAW and release/allocation cases, reservation issue stalls, registered IU latency, result backpressure, turnover and reset cancellation.

Generation checks cover distinguishable stale tokens. They do not prove rejection of arbitrary replay after an entire finite generation counter wraps, and no flush/redirect protocol exists yet. The single-IU integration issues in order; adversarial out-of-order finish is a direct completion-unit stimulus.

`make -C ppc603e/sim check-spec` validates timing, bus and ISA metadata and runs the ISA, ADD-family, bus-decoder and stage-checker tests, including 10,560 compiled decoder legality probes against the seven executable masks. Operand semantics remain covered by the core regression; full ISA metadata and timing/bus conformance remain separate work.

Observed after P05 integration on 2026-09-12: strict canonical lint, all three Makefile simulation targets and ISA/timing checks passed. No Quartus rebuild was performed for the changed RTL.

Bus structural validation passes for 54 signal groups, all 23 Chapter 8 figure references and 14 scenarios (seven selected relative-event tables). Nine diagrams remain inventory-only. These manifests are source preparation, not exhaustive waveforms or a running bus BFM.

## Third-batch checks

- `test-stage` compiles the actual core with `tb_stage_timing`, writes a pre-update edge trace and checks independently decoded operands/results, issue/finish/retirement timing, full capacity and stalled offers. The 14-instruction trace covers all seven forms, five pending RAW forwards, 27 retirement-stall edges and 21 full-resource edges. Eighteen checker tests include 16 intentional failures. Manual/implementation stage differences remain documented in STAGE_TIMING.md.
- `test-recovery` passes 15 policy-model tests, including 1,500 deterministic mixed transitions and 100 fetch-stall scenarios. No recovery RTL equivalence is claimed; the accepted proposal's external cancellation, irrevocable head and caller-integration assumptions remain explicit.
- Bus encoding checks cover all 32 TT codes (26 source patterns), three PID7v ABE overlays and nine listed transfer-size combinations. Thirteen query tests pass. Address alignment/decomposition and exhaustive bus waveforms remain separate work.
- ADD-family preparation records 20 concrete OE/Rc forms across add/addc/adde/addme/addze, while the RTL still implements only the original seven forms. Its reference evaluator checks carry, signed overflow, sticky SO and final-SO CR0 behavior; it is preparation for future RTL tests, not evidence of implemented CR/XER state.

The canonical RTL and its prior FPGA measurement boundary are unchanged by this batch.

## Fourth-batch recovery preparation

`make -C ppc603e/sim test-recovery-select` compiles the standalone prefix selector with strict Verilator warnings and checks 245,760 coherent CQ snapshots. The independent oracle covers wrapped queue age, stale/out-of-range pivots, all/keep/exclude policies, every done bitmap, reset and absent requests. Astra reviewed the implementation and oracle without a correctness finding. This module remains outside the canonical CPU and Quartus source lists; sequential cancellation, rename reconstruction and fetch recovery are not implemented.

[TIMING_DECISIONS.md](TIMING_DECISIONS.md) records the current dispatch/execute/finish/commit bindings and the acceptance tests required for bounded local recovery. It preserves the existing stage probe and explicitly records the extra dispatch interval and conservative finish-to-retirement spacing.

The combined fourth-batch `check-spec test-recovery` run passed 62 tool tests and 15 recovery-model tests. The ISA suite includes 10,560 compiled decoder probes; metadata now has 42 reviewed forms, seven implemented and zero overlaps. Seven register-logical semantic tests cover hand-anchored Boolean results, encoding/register placement, complement width and CR0/XER effects. Bus addressing adds nine tests covering 15 aligned rows and eight four-byte starts (14 transfer rows), malformed/out-of-scope queries and source-conflict preservation. The printed Table 8-5 TSIZ discrepancy remains visible alongside its provisional interpretation.

## Fifth-batch backend recovery checks

Canonical CQ and rename now have sequential recovery inputs, with post-commit survivor snapshots and qualified same-edge finishes. RS/IU add local cancellation, and the core wires the backend identity path while tying redirect requests off. Thus the existing core tests continue to exercise no-redirect behavior; whole-core recovery remains a later gate.

The changed canonical RTL passes strict lint, the 906-check completion regression, 768-result core regression, focused execution regression and the unchanged 14-instruction stage probe. The local cancellation bench passes 1,066 checks, including generation wrap through destroyed local tokens. `check-spec test-recovery` passes 72 tool tests and 15 policy-model tests. Eight new rotate-semantic tests cover all 1,024 mask endpoints through an independent bit-string oracle, rotation boundaries, insert preservation and CR0/XER behavior. The 10,560 compiled decoder probes still match the seven executable forms.

The direct `test-recovery-state` bench passes 5,871 checks: contiguous CQ state after every transaction, wrapped age independent of rename tags, same-edge commit/finish/cut, old-ready and pending WAW survivors, later wake and retirement values, stale live pivots, irrevocable stalled heads, killed result drain, rejected-request progress and 260 legal cancellation/reuse iterations through generation wrap. Independent review of the actual RTL found no correctness issue. No Quartus rebuild was performed, and existing measurement hashes remain historical.


## Sixth-batch full-core recovery checks

`test-core-recovery` passes 985 strict checks against an independent expected dispatch PC, instruction word and ordered surviving-value stream. The run has 10 accepted/four rejected redirects, six killed entries and 45 retirements; coverage counters observe three RS and two IU cancellations, a full-IQ cut and coincident old response. Directed cases include held-request/repeated-target drain, rejected alignment/identity, younger diagnostic removal, terminal diagnostic commit and reset during drain. `test-fetch-recovery` separately passes 99 focused transport checks. Astra reviewed actual RTL and strengthened the stream oracle and stimulus scheduling before final acceptance.

Canonical lint, the 768-result no-redirect core regression and the unchanged 14-instruction timing probe pass. The combined specification/policy suite passes 81 tool tests plus 15 model tests, including seven shift-semantic tests and 10,560 compiled decoder probes. The canonical backend modules did not change in this batch; their prior unit results remain recorded above. New fetch/core benches are included in `make test`.

These tests establish the current seven-form core's explicit recovery control. Branch/exception decode, data-memory recovery and external producer lifetime are not implemented. No Quartus measurement was rerun.


## Seventh-batch logical execution checks

The canonical package/decode/IU now implement eight non-record register-logical forms, bringing executable support to 15 forms. `test-core-logical` passes 94 legal logical retirements and all eight Rc=1 diagnostic rejections. Independent opcode/field constants and Boolean truth anchors check the generated program; a per-bit oracle checks RAW/WAW chains, writable r0, negative/complement values and mixed register combinations. The actual-core bench reaches full CQ/IQ occupancy and request/response/retirement stalls, and checks each logical producer's D<E, F=E+1 and C>F timing.

After the operation enum/datapath expansion, strict lint and every existing Makefile RTL regression passed: 768 original results, 906 CQ checks, focused execution, the seven-form stage probe, 1,066 local cancellation checks, 5,871 recovery-state checks, 985 full-core recovery checks and 99 fetch checks. The logical bench is now included in `make test`. No Quartus measurement was rerun.

Final seventh-batch `check-spec test-recovery` passed 91 tool tests plus 15 policy-model tests. The compiled decoder comparison covers 10,560 probes with 75 accepted by both metadata and RTL. Metadata has 60 reviewed forms, 15 implemented and zero overlaps. Eight compare-semantic tests cover signed/unsigned relations, immediate extension, BF-selected CR preservation and current SO; compare execution remains pending. The CR/XER contract is reviewed preparation, with no flag-state RTL claimed.

## Round 8 CR/XER foundation

Current-core compatibility passes strict lint and all pre-existing RTL targets: 768 baseline results, 906 completion checks, focused rename/RS/IU checks, the unchanged 14-instruction stage trace, 1,066 local cancellation checks, 5,871 backend recovery checks, 985 core recovery checks, 99 fetch recovery checks, and 94 logical results plus eight record-form rejections. The baseline, stage and cancellation fixtures now explicitly reject unexpected flag metadata/candidates from these flag-free instructions.

The independent flag reference adds fourteen tests, including 500 deterministic masked commits and negative sticky-SO, CR0 relation, partial-commit, release-edge and recovery-identity cases. Final specification and policy suites pass 105 tool tests plus 15 recovery-model tests (120 total). Decoder legality remains unchanged at 15 executable forms; metadata/model coverage does not enable flag instructions.

Focused state/CQ flag RTL passes 37 standalone checks and 168 coupled checks, independently reviewed. Nonzero untouched CR/XER bits are seeded only in the standalone fixture to verify preservation. The coupled bench checks CQ packet removal and flag update on the same edge, without an architectural GPR file. Full-core nonzero flag execution and its recovery scoreboard remain CX-I03–I05 work.

## Round 9 record-logical validation

Canonical and measurement-wrapper strict lint pass after connecting record decode, captured SO and CR0 commitment. All existing RTL regressions pass. The nonrecord logical bench still checks 94 results, with its eight terminal cases changed to high-XO-bit mutations because Rc=1 is now decoded. The direct record RS/IU bench passes 77 checks, using literal CR0 nibbles for negative/positive/zero results with both SO inputs. It changes live inputs while the captured operation waits and verifies held IU result stability.

Independent `test-core-record-logical` passes 10,252 checks (33 retirements, 14 record commits, three killed records); `test-core-record-edges` passes 43 checks. Both are accepted after review. The former owns a surviving-stream and full architectural-state oracle; the latter isolates recovery/commit edge priorities with actual GPR/CR0 effects. The main bench verifies all GPRs and full CR/XER after each edge, independent stream order and prefix recovery, record D/E/F/C, owner admission and forwarding before commit. The edge bench checks accepted finish/commit redirects, rejected finished-head cuts and IU/CQ reset. No XER-writing instruction or FPGA remeasurement is included.

Round-9 specification reconciliation passes 105 tool tests plus 15 policy tests (120 total). All 10,560 compiled decoder probes agree with the 23 implemented masks (115 accepted probes). Metadata retains 60 reviewed entries and zero overlaps.

## Round 10 ADD/ADDC validation

Strict canonical and measurement-wrapper lint pass. All existing RTL regressions pass after new station controls are tied off in older direct fixtures; baseline unsupported terminal variants are now extended ADD encodings. The arithmetic corpus passes 18,967 checks with 83 ordered retirements, 75 ADD/ADDC operations, all eight OE/Rc forms and 66 exact owner admissions at commit+1. It independently checks full GPR/CR/XER state, stream identity, D/E/F/C and ownership, signed mathematical overflow, CA/OV boundaries, sticky SO, partial-write preservation and record-logical observation of SO=1.

The new actual-core recovery bench passes 3,439 checks: an actual arithmetic seed makes CR/XER nonzero, then a candidate whose flags differ is killed in RS, IU or finished-younger CQ, or survives simultaneous finish/commit redirects. The explicit surviving PC/word and all architectural registers are checked each edge. The direct ADD fixture passes 28 checks for held controls and complete results through pending operands and IU stalls. All three benches are independently reviewed with no remaining finding.

Final specification checks pass 105 tool tests and 15 policy tests (120 total). All 10,560 compiled decoder probes agree with 30 implemented masks (150 accepted probes). Metadata remains 60 reviewed entries with zero overlaps. Extended ADD forms are still rejected; no full timing or new Quartus measurement is claimed.

## Round 11 ADDE validation

Strict canonical and measurement-wrapper lint pass, along with all existing RTL regressions. The independent ADDE corpus passes 21,700 checks with 89 ordered retirements, 72 ADDE operations, seven actual ADDC seeds and all four OE/Rc combinations. It checks full GPR/CR/XER, independent PC/word/tag and D/E/F/C, signed three-operand mathematical overflow, CA0/1 boundaries, maximum unsigned sum, carry rescue, sticky SO and masked preservation. It observes 78 exact owner commit+1 admissions and seven seed-to-ADDE next-edge captures. ADD and ADDC still ignore input CA; ADDME/ADDZE diagnostics remain supported rejection cases.

The direct fixture passes 37 checks while captured CA remains stable through changed live inputs, a pending operand and stalled IU results. `test-core-adde-recovery` passes 3,434 checks across RS/IU/finished-younger CQ kills and surviving finish/commit redirects. A redirected ADDE consumes the carry that actually survives the preceding cut, with an explicit expected retirement stream and full-state comparisons. No full-core state is forced. All new tests are independently reviewed with no remaining finding.

Final specification tests pass 105 tool tests plus 15 policy tests (120 total). All 10,560 compiled decoder probes agree with 34 implemented masks (170 accepted probes); 60 metadata entries retain zero overlaps. No Quartus remeasurement or full timing conformance is claimed.

## Round 12: ADDME/ADDZE

The accepted [unary ADD slice](ADD_UNARY.md) adds `test-core-add-unary` (27,278 checks), `test-add-unary-execution` (64), `test-addme-recovery` (3,434) and `test-addze-recovery` (3,434) to the aggregate RTL test target. Independent mathematical/full-state checks cover all eight forms and 16 reserved-rB rejections. Recovery distinguishes killed and committed carry writers through redirected ADDE consumption.

Strict canonical core and measurement-wrapper lint, all 20 previous RTL targets, the four new targets, 105 tool tests and 15 recovery-model tests pass. The compiled decoder checker passes 10,560 probes, with 178 accepted by both metadata and RTL. The metadata generator validates 60 reviewed entries, 42 implemented and zero overlaps. These results establish the bounded subset only; no FPGA or complete 603e timing acceptance is implied.

## Round 13: RLWINM/RLWNM

The accepted [rotate slice](ROTATE_EXECUTION.md) adds `test-core-rotate` and `test-rotate-execution` to the aggregate RTL target. The core test passes 722,063 checks, 4,176 retirements and 4,112 rotate commits, including all 4,096 family/Rc/mask-pair cases, actual SO1/XER preservation, nonzero r0 aliases, complete architectural and expected retirement state, three killed owners and a kept-owner redirect. The direct test passes 64 captured-mask/SO and packet-stall checks.

Strict canonical core and measurement-wrapper lint, all 24 prior RTL targets, both new targets, 105 tool tests and 15 recovery-model tests pass. Compiled decode validation passes 10,560 probes with 188 accepted by both RTL and metadata. The generator validates 60 reviewed entries, 46 implemented and zero overlaps. RLWIMI remains unsupported, and no FPGA timing or full processor conformance claim follows from these tests.

## Round 14: temporary control/memory program milestone

`test-core-control-memory` generates a 631-word symbolic program and compares 579 architectural retirements against a model that executes operation names independently of RTL decode. It passes 44,883 checks, including all GPR/CR/XER/LR/CTR state and byte-memory hashes, 31 reads, 22 writes, control-flow truth tables and request/retirement backpressure. `test-core-memory-edges` passes 799 checks of alignment and error diagnostics, killed-load obligations, store authorization/irrevocability, and branch cancellation/commit arbitration. See [CONTROL_MEMORY.md](CONTROL_MEMORY.md) for the precise scope.

All 26 preexisting RTL targets and both new targets pass. Core and measurement-wrapper strict lint pass. The 105 tool tests plus 15 recovery-model tests pass. The expanded compiled decoder check passes 15,808 probes, 615 accepted by metadata and RTL, including reserved branch options and all SPR selectors. Added packet fields required explicit zero-effect checks in the historical stage/recovery fixtures; their behavior and acceptance counts remain unchanged. The program fixture changes backpressure on falling edges to avoid sampling-edge stimulus races.

The source matrix has 90 reviewed entries, 80 implemented, 10 pending and no overlaps. Historical Quartus measurements remain unchanged, and these functional results do not establish BPU/LSU timing or full processor conformance.

## Round15: logical shifts

`test-core-shifts` uses the existing symbolic-program fixture with a separate generated profile. It passes 173,321 checks and 2,247 retirements, including 659 SLW and 659 SRW operations. Independent bit selection covers 5 source values × 64 counts × 4 forms, upper count bits, nonzero aliases, SO0/SO1 and complete architectural state. `test-shift-execution` passes 91 delayed-data/count and held-packet checks. `test-slw-recovery` and `test-srw-recovery` each pass 3,439 checks across killed RS/IU/CQ and retained finish/commit redirects.

All 28 previous RTL targets remain passing, including the unextended control/memory program and existing recovery parameterizations. Strict core/wrapper lint and 105 tool plus 15 recovery-model tests pass. Compiled decode validation passes 15,808 probes, with 635 accepted by both metadata and RTL. The source matrix has 90 reviewed entries, 84 implemented and six pending; source-row reconciliation is unchanged. See [LOGICAL_SHIFTS.md](LOGICAL_SHIFTS.md) for semantic and timing boundaries.

## Round 16 arithmetic shifts

New program: 206,971 checks / 2,684 retirements. Direct execution: 91 checks. SRAW/SRAWI recovery: 3,434 checks each. See [ARITHMETIC_SHIFTS.md](ARITHMETIC_SHIFTS.md). The accepted metadata subset is 88 of 90 reviewed entries; only RLWIMI remains pending within that bounded set. All 32 previous RTL targets pass, along with strict core/wrapper lint and 105 tool plus 15 recovery-model tests. Compiled decode validation passes 15,808 probes with 655 accepted by both metadata and RTL.

## Round 17 rotate insert

The new full-state program passes 218,905 checks / 2,839 retirements, including 2,245 RLWIMI operations and all 2,048 MB/ME/Rc combinations. Direct execution passes 73 checks. Recovery specifically exercises an uncommitted older destination mapping. The compiled decoder passes 15,808 probes with 660 accepted by metadata and RTL; all 90 reviewed forms are implemented. See [ROTATE_INSERT.md](ROTATE_INSERT.md).

Round17 integration: all 36 prior RTL targets, strict core/wrapper lint and 120 Python tests pass. The strengthened insert recovery fixture passes 3,445 checks. Compiled decode passes 15,808 probes with 660 accepted.

## Round 18 SUBF/NEG

The independent program passes 113,111 checks / 1,465 retirements, direct execution 73 checks, and SUBF/NEG recovery 3,439 checks each. Five additional Python tests enforce reserved-field and side-effect metadata and literal reference anchors. Compiled decoder validation passes 15,808 probes with 684 accepted; 98 reviewed forms execute. See [SUBTRACT_NEGATE.md](SUBTRACT_NEGATE.md).

Round18 integration passes all 39 prior RTL targets, strict core/wrapper lint, 110 tool tests and 15 recovery-model tests. No regression failures remain.

## Round 19 SUBFC

The independent program passes 186,650 checks / 2,420 retirements, direct execution 73 checks and recovery 3,434 checks. Two new Python tests cover metadata and no-borrow anchors. The compiled decoder passes 15,808 probes with 704 accepted. There are 102 reviewed/executable forms. See [SUBFC.md](SUBFC.md).

Round19 integration passes all 43 prior RTL targets, strict core/wrapper lint, 112 tool tests and 15 recovery-model tests. No regression failures remain.

## Round 20 SUBFE

Program: 186,650 checks / 2,420 retirements. Direct execution: 127 checks. CA1 and CA0 recovery: 3,434 checks each. Two Python tests cover metadata and borrow-adjusted overflow anchors. Decoder: 15,808 probes, 724 accepted. 106 reviewed forms execute. A handwritten direct-test expectation was corrected; see [SUBFE.md](SUBFE.md).

Round20 integration passes all 46 prior RTL targets after updating the obsolete SUBFE rejection fixture, strict core/wrapper lint, 114 tool tests and 15 recovery-model tests. No failures remain.

## Round 21 unary extended subtraction

Program: 89,010 checks / 1,152 retirements. Direct execution: 145 checks. Recovery: 3,434 checks each for SUBFME/SUBFZE. Two Python tests cover exact masks/reserved rB and carry/overflow anchors. Decoder: 15,808 probes, 732 accepted. 114 reviewed forms execute. See [SUBTRACT_UNARY.md](SUBTRACT_UNARY.md).

Round21 integration passes all 50 prior RTL targets, strict core/wrapper lint, 116 tool tests and 15 recovery-model tests. No failures remain.

## Round 22 SUBFIC

Program: 150,687 checks / 1,953 retirements. Recovery: 3,434 checks each with positive/negative immediates. Two Python tests cover all16-bit payload masks and signed immediate/real-r0/flag anchors. Decoder: 15,808 probes, 737 accepted. 115 reviewed forms execute. See [SUBFIC.md](SUBFIC.md).

Round22 integration passes all 54 prior RTL targets, strict core/wrapper lint, 118 tool tests and 15 recovery-model tests. No failures remain.

## Round 23 ADDIC/ADDIC.

Program: 186,805 checks / 2,422 retirements. Recovery: 3,434 checks per form. Two Python tests cover all immediate masks, record permissions and literal arithmetic/flag anchors. Decoder: 15,808 probes, 747 accepted. There are117 reviewed/executable forms. See [ADD_IMMEDIATE.md](ADD_IMMEDIATE.md).

Round23 integration passes all 57 prior RTL targets, strict core/wrapper lint, 120 tool tests and 15 recovery-model tests. No failures remain.

## Round 24 ANDI./ANDIS.

Program: 186,805 checks / 2,422 retirements. Recovery: 3,439 checks per form. Three Python tests cover all immediate masks, mandatory recording, literal mask/flag anchors and the preserved source discrepancy. Decoder: 15,808 probes, 757 accepted. There are119 reviewed/executable forms. See [AND_IMMEDIATE.md](AND_IMMEDIATE.md).

Round24 integration passes all 60 prior RTL targets, strict core/wrapper lint, 123 tool tests and 15 recovery-model tests. No failures remain.

## Round 25: CNTLZW / EXTSB / EXTSH

Six new RTL targets pass: 266,649 full-state program checks over 3,459 retirements; 1,513 direct pipeline checks; 6,330 decode routing/permission/reserved-field checks; and 3,439 recovery checks per operation. The program executes each family 720 times.

The compiled decoder agrees with the 125-entry ISA matrix on 15,808 probes (763 accepted). `check-spec` and `test-recovery` pass: 127 tool tests plus 15 recovery tests, 142 total. Strict core and measurement-wrapper lint pass. Sources reconcile 64 of 226 Appendix A.1 inventory rows; 162 remain pending.

All 63 prior RTL targets also pass. The long first run ended with process status 143 during `test-core-adde-recovery`; resumption exposed a truncated generated PCH cache. Removing only that target's generated `.gch` files and rerunning the remaining 14 targets completed successfully. Logs: `/tmp/ppc-round25-new.log`, `/tmp/ppc-round25-routing.log`, `/tmp/ppc-round25-regression.log`, `/tmp/ppc-round25-regression-rest-clean.log`, `/tmp/ppc-round25-spec.log`. No RTL change was required for the interrupted build.

## Round 26: MFCR / MTCRF

Four new targets pass: 224,689 full-state checks over 2,914 retirements (523 MFCR, 522 MTCRF); 11,247 recovery-edge checks; 3,244 coupled completion/flag checks including all 256 FXM masks; and 131,072 decoder checks across every register, mask and reserved-bit combination. Zero masks, full masks, r0, nonzero preserved XER, field ordering and precise recovery are covered.

The compiled decoder agrees with 127 metadata entries on 15,808 probes (765 accepted). `check-spec` and `test-recovery` pass: 131 tool tests plus 15 recovery tests, 146 total. The final metadata-focused rerun passes 19 tests. Source reconciliation is 66/226 inventory rows, leaving 160 pending. Strict core and wrapper lint pass.

All 69 prior RTL targets pass, run as three bounded groups. The stage-timing fixture initially reported unused new retirement fields under strict lint; its flag-free assertion now checks `write_cr_fields == 0` and `cr_mask == 0`, and the affected group was resumed successfully. Logs: `/tmp/ppc-round26-new.log`, `/tmp/ppc-round26-decode.log`, `/tmp/ppc-round26-regression1.log`, `/tmp/ppc-round26-regression2.log`, `/tmp/ppc-round26-regression2-rest.log`, `/tmp/ppc-round26-regression3.log`, `/tmp/ppc-round26-spec.log`.

## Round 27: parallel CR logical and bus-address tasks

The four new CPU RTL targets pass: 296,832 program checks over 3,851 retirements (140 executions per CR logical operation), 44,991 recovery checks, 4,016 coupled completion/flags checks and 524,288 exhaustive decode checks. The metadata probe now sweeps both opcode-19 and opcode-31 spaces: 26,048 probes, 807 accepted, 135 implemented entries and zero overlaps. Source reconciliation is 74/226 inventory rows, with 152 pending.

The bus-address validator covers 64-bit tables (15 aligned rows and eight four-byte starts/14 accesses) plus 32-bit tables (15 aligned requests/16 beat rows and eight starts/14 accesses). Its 13 focused tests pass. Parent independently checked literal byte, halfword, split-word and two-beat doubleword results against primary Tables 8-6/8-7. A row-attribution test was corrected to match the selected four-byte table, with both applicable aligned/example tables retained in query provenance. Raw source anomalies remain mutation-protected.

Combined `check-spec`/`test-recovery` passes 139 tool tests plus 15 recovery tests, 154 total. Strict core and measurement-wrapper lint pass. The stage probe explicitly forbids both new selected-bit retirement fields on its original instruction subset.

All 73 prior RTL targets pass in three bounded batches, for 77 total RTL targets including the four new ones. No blanket lint suppression was added. Evidence logs: `/tmp/ppc-round27-new.log`, `/tmp/ppc-round27-decode.log`, `/tmp/ppc-round27-regression1.log`, `/tmp/ppc-round27-regression2.log`, `/tmp/ppc-round27-regression3.log`, `/tmp/ppc-round27-spec.log`, `/tmp/ppc-round27-bus-review.log`. Bus source tables were independently read from local primary PDF326/327. No bus RTL, endian mapping, FPGA fit or timing-conformance claim follows from these checks.
## Round 39 acceptance lanes

The aggregate also includes `test-serialization-decode`,
`test-core-serialization`, `test-bat-memory-router`, `test-core-bat`,
`test-tlb-service`, `test-tlb-independent`, and `test-reference-bat`.
All use strict Verilator warnings and assertions. `lint` includes the actual
BAT wrapper and standalone page TLB in addition to the existing default and
opt-in CPU, bus/cache, exception and measurement tops.

The TLB independent lane supplies external 93-bit request/90-bit expected
response vectors from a Python virtual-page dictionary and literal page
permission table. It covers all 128 slots, both ways/banks, tag/VSID aliases,
page offsets, PP/key/WIMG/C combinations, rejected management operations and
indexed invalidation under held-response/turnover conditions. Five Python
anchor tests protect the oracle's address and permission boundary cases.

The [BAT reference lane](REFERENCE_BAT.md) independently observes CPU-side
accepted effective addresses and checks exact relocated physical addresses
and data payloads before comparing all architectural and RAM state with
original handlers. It complements the standalone translation oracle and
actual-core deny/redirect/reset tests. It does not add an integrated TLB,
architectural fault-delivery or cycle oracle.

## Round 40 SPRG gates

`test-sprg-decode` independently checks 8,097 conditions, including eight literal encodings, all GPR/SPR selectors, reserved Rc/XO/primary fields and default-profile exclusion. `test-core-sprg` checks 192 conditions covering all four complete registers, consecutive access and isolation, stalled commit/read results, cancelled writes, real-RFI problem-state read/write privilege failures and hard-reset zero. Both are part of the aggregate. Existing full default reference lanes still cover 168 forms; these opt-in SPRG forms are covered by the separate focused tests.

## Fetch-credit coverage after translated-cache integration

The cached fault workload exposed a shared-router deadlock from an instruction
response offered against a full IQ. Fetch now reserves downstream capacity
before a new offer, retaining held requests. Current core corpus coverage
therefore requires full-IQ suppression of new offers; earlier historical
references to naturally occurring IQ-induced response stalls no longer
describe that behavior. Response-stability assertions remain, and the
standalone fetch test explicitly covers response backpressure and redirect
drain in 304 checks. Core recovery now has 986 checks, including a request
clocked into a held offer before the first redirect.

The translated cached wrapper adds direct, remap/coherence/permission,
maintenance/partial-fill-error and compiled page-search/fault gates. See
[the current scorecard](SYSTEM_COMPLETION.md) and
[translated cache verification](TRANSLATED_ICACHE_VERIFICATION.md).
