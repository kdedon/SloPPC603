# P05c: current IU stage observation

Current extension: [DIVIDER_TIMING.md](DIVIDER_TIMING.md) adds 20/37-cycle DIVW/DIVWU reservation. The single-cycle relations below continue to apply to the original instruction subset and its stage probe; they do not describe divide finish timing.

Status: reviewed relations and executable probe for the seven legal P05 forms. The full-core probe passes 14 dispatches, issues, finishes and retirements. It covers pending RAW operands, finish-to-dependent-issue bypass, retirement stalls and full resources. This establishes the accepted implementation event contract; it does not establish complete 603e stage timing or implement a Figure 6-3/6-4/6-5 replay.

The additive contract is `sim/spec/stage_timing.json`. Its seven form anchors refer to existing `timing.json` IDs; its eight `ST-Mxx` records separate source statements from implementation bindings. Neither the existing transcription nor canonical RTL was modified.

## Sources and interpretation

All PDF references below name the local primary source `../../1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf` (MPC603EUM/AD, 11/97). Physical PDF page numbers are one-based. The printed chapter-6 page is the PDF page minus 246. Source review used the original chapter text and the accepted, visually checked figure transcription in [`TIMING_SPEC.md`](references/TIMING_SPEC.md).

| Source | Reviewed relation | Disposition for this implementation |
|---|---|---|
| §6.1, PDF 247 / 6-1 | Latency measures execution until results are ready for a subsequent instruction. Finish is the final execute cycle, updating the completion buffer. Some cases can finish and complete in one cycle. | Measure computation between IU capture E and accepted finish E+1. Do not interpret one table cycle as dispatch-to-finish. Same-cycle completion is deliberately absent. |
| §§6.1–6.2, PDF 248, 250 / 6-2, 6-4 | Reservation stations can hold unavailable operands; end of dispatch latches operands/instruction. | Our D captures the RS; E captures IU inputs. The extra boundary and exact mapping of source end-of-dispatch remain a P12 decision. |
| §6.3.3, PDF 257–258 / 6-11–6-12 | A pending instruction can begin execution in the cycle its data is returned. | Ownership-qualified producer finish and dependent issue may share an edge. The probe exercises this five times. |
| §§6.3.3–6.3.3.2, PDF 258–259 / 6-12–6-13 | Completion retires in order; rename results feed dependents before architectural commitment. Serialization delays results for particular classes. | The seven ordinary IU forms do not acquire the SRU/system serialization requirements. Pending-source identities are reconstructed independently from instructions for the checker. |
| §6.1 and §6.2, PDF 248, 251 / 6-2, 6-5 | Writeback updates architectural registers at completion or through a nonflushable writeback buffer. | Legal commit combines CQ removal, architectural GPR write and rename release. No separate writeback buffer exists. |
| §6.3.3 and §6.6, PDF 258, 267–268 / 6-12, 6-21–6-22 | Five CQ/five GPR rename resources; CQ head must be finished; rename lifetime discussion includes deallocate. | Resources release at commit, becoming reusable after that edge. No full same-edge reclamation. Exact manual release availability remains open. |
| §6.4.2/§6.4.5, PDF 264 / 6-18 | IU has one execute phase; selected PID7v additions may also execute in SRU without serialization. | Only width-one IU routing is exercised; no SRU parallelism or two-wide completion claim. |
| Table 6-4, PDF 270–271 / 6-24–6-25; footnote PDF 272 / 6-26 | `addi`, `addis`, `ori`, `oris`, `xori`, `xoris`, and `add` each have one execute cycle. The add family contains additional forms. | Current `add` is OE=0/Rc=0; no CR/XER side effects. Form/page/latency references are checked against the accepted transcription. |

The integer execute duration is one cycle for both recorded PID6/PID7v table scopes. This does not erase their unit-routing, width or clock-mode differences. These measurements use the scaffold's clock. They do not measure 60x bus clocks or reconcile its disclosed 1:1 bootstrap clock with PID7v's supported ratios.

## Precise implementation events

All probe records sample rising-edge inputs and outputs **before nonblocking state updates**. Every event in a record occurs at the same edge; JSON field order does not introduce subcycles. Cycle numbers start with zero on the first sampled active edge after reset. Reset/redirect within a trace is excluded from this checker.

| Event | Observation | Accepted relation |
|---|---|---|
| D: dispatch | `dut.dispatch`, allocation metadata and packed completion identity | Atomic CQ/rename/RS capture. No issue of this instruction on D. |
| E: issue | `dut.issue_valid && dut.issue_ready` | E ≥ D+1. Operands must be ready, possibly through another instruction's finish at E. |
| Finish | `dut.completion.finish_accept` | Exactly E+1 for this legal IU-only core because CQ result-ready is always asserted outside reset. Generic transport acceptance is not sufficient. |
| Retirement offer | `retire_valid` plus packet | Only the oldest already-finished entry, no earlier than finish+1. Packet remains stable while ready is low. |
| Commit/writeback/release | `retire_valid && retire_ready` for a legal GPR writer | Architectural update and CQ/rename release share the edge. Pre-edge counts still include the committing instruction. |

The occupied arithmetic interval is `[E,E+1)`. The trace's result value can be combinationally visible during that interval, but it is accepted into CQ/rename and used by an issuing dependent only at E+1. A ready instruction with no resource stall therefore has D, E=D+1, finish=D+2 and earliest commit=D+3. This is an implementation edge convention, not a claim that manual stage labels refer to those exact boundaries.

The checker processes same-edge finish information before checking RAW issue eligibility, but it separately forbids retirement from using that newly finished state. It calculates source registers, destination registers and expected operands/results from the instruction words and a program-order model; the trace does not supply dependency hints or expected stage delays. The reviewed edge constants are enforced independently of the JSON input, so changing a manifest constant cannot make an altered trace pass automatically.

CQ and rename occupancy are checked before every edge against dispatched, unretired work. Allocation from a full queue fails even if that edge also commits a head. The final edge drains all tracked work. This checks resource counts; it is not a full internal map/slot-ownership proof, which remains covered by the separate execution/completion unit tests.

## Source differences retained

1. **Finish/completion overlap:** §6.1 explicitly allows overlap in some situations. The current registered CQ imposes at least one edge after finish before retirement. P12 must determine which overlap cases are required and how source cycle intervals bind to measured edges before changing that choice.
2. **Dispatch boundary:** source end-of-dispatch latching and the current distinct RS/IU captures are not automatically identical. The minimum D→E delay is tested as an accepted P05 decision, not derived as a universal manual requirement.
3. **Deallocation:** Figures 6-3/6-4 show integer `D1 E2 W3 A4`; Figure 6-5 uses the same pattern in several rows. The current release shares commit. A figure's separate A category does not by itself establish an additional required RTL edge or exact post-edge availability. `ST-O02` retains this P12/P11 decision and `TIM-U14`.
4. **Graphic/prose conflict:** younger integer black W cells precede older FP W cells in Figures 6-3/6-4 (PDF 256/257, printed 6-10/6-11) and Figure 6-5 (PDF 263, 6-17), conflicting with an architectural-writeback reading of ordered completion prose. Preserve `TIM-U17`; do not move cells, reinterpret black as rename write without evidence, or allow younger architectural commit. `ST-O01` also retains the observation issues `TIM-U01/U11/U15`.

`ST-O03` assigns width, SRU routing, dispatch boundary and finish/completion overlap decisions to P11/P12. Current assertions do not decide those future implementations. No new hardware discrepancy against the accepted P05 contract was found in the probe.

## Executable evidence and reproduction

Run from the repository root:

```sh
python3 sim/tools/check_stage_timing.py
python3 -m unittest discover -s sim/tools -p test_stage_timing.py -v
verilator --binary --timing --assert -Wall --top-module tb_stage_timing \
  rtl/ppc_pkg.sv rtl/ppc_fifo.sv \
  rtl/ppc_fetch.sv rtl/ppc_decode.sv \
  rtl/ppc_regfile_gpr.sv rtl/ppc_rename.sv \
  rtl/ppc_dispatch.sv rtl/ppc_iu.sv \
  rtl/ppc_completion.sv rtl/ppc_flags.sv rtl/ppc_core.sv \
  tb/tb_stage_timing.sv --Mdir build/ppc-stage-build
build/ppc-stage-build/Vtb_stage_timing +TRACE=build/ppc-stage-timing.jsonl
python3 sim/tools/check_stage_timing.py build/ppc-stage-timing.jsonl
```

The dedicated bench instantiates the actual core with an abstract fetch responder. It runs two sequences covering all seven forms, starts unstalled, stalls retirement to fill resources/IQ, then drains with periodic retirement stalls. It does not force internal state or modify RTL. Procedural stimulus changes occur away from the sampling edge; hierarchical reads supply the trace and three direct edge-distance assertions.

Measured on 2026-09-12 with strict Verilator `--timing --assert -Wall`:

- 14 each: dispatches, issues, accepted finishes, commits; all seven forms observed.
- 14 issues at D+1; all 14 finishes exactly E+1; 2 commits at finish+1.
- 5 pending-RAW dispatches and 5 issues sharing the producer's accepted-finish edge.
- 27 stalled retirement-offer edges with stable packets; 21 edges with five occupied resources.
- 18 Python tests pass: 2 positive tests and 16 deliberate negative cases, including edge collapse/delay, RAW-before-finish, wrong values, younger retirement, changed stalled packet, early resource release, full same-edge allocation, missing edges, incomplete coverage/drain and changed source/edge constants.

Representative observations: the first instruction has D2/E3/finish4/commit5. The fourth has D8/E9/finish10/commit36 due to the imposed retirement stall. The ninth has D37/E38/finish39; the tenth issues at edge39 using that producer result and finishes40. These numbers describe this stimulus only.

The JSONL schema has one object per edge: integer `edge`, `cq_count`, `rename_count`, `retire_ready`, plus optional `dispatch {id,pc,insn}`, `issue {id,a,b}`, `finish {id,value}`, and `retire {id,pc,insn,gpr,value}`. The retirement object appears whenever valid, including stalled edges. `id` is the packed CQ slot/generation token; the bounded trace requires no reuse of a full token. Trace files and compiled objects are generated in `build/`, not committed fixtures.

Remaining scope: exact manual stage/edge binding and graphical replay; other execution units, serialization, faults/recovery/reset epochs, multiple outstanding result producers, multiply/divide, two-wide admission/retirement and exact deallocation behavior. IU result backpressure is exercised separately by `tb_execution`; it cannot arise naturally in this core because CQ always consumes responses. P05c does not replace those tests or claim complete P05/P12 acceptance.

P05d's [timing decisions](TIMING_DECISIONS.md) now bind the current implementation events and admit bounded local recovery integration. The recorded trace constants stay unchanged. Graphical writeback/deallocation and full processor timing fidelity remain unresolved.

## Record-logical admission extension

CX-I03 adds the single flag-owner resource described in [RECORD_LOGICAL.md](RECORD_LOGICAL.md). A record form can dispatch only when that token is free before the edge; owner commitment does not permit another acquisition on the same edge. Captured SO travels with the operation. Record forms retain the same D/E/F/C minimum relations and one shared GPR/CR0 commitment event. This resource admission choice is deliberately conservative and does not complete full 603e timing conformance. The seven-form JSON trace and its existing measured counts remain unchanged.

ADDE additionally captures committed CA at atomic dispatch. Its independent full-core corpus verifies seed commitment before carry capture, including next-edge acquisition, while retaining D/E/F/C ordering. Carry-input addition does not imply flag forwarding or improved flag throughput.
