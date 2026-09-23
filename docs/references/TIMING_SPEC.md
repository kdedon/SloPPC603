# Instruction timing contract: P02a/P02c transcription

Date: 2026-09-12. **Chapter 6 table and visible figure transcription complete; semantic binding and conformance remain open.** The machine-readable transcription is `sim/spec/timing.json` (schema version 1). It contains all **190 rows** of UM Tables 6-1 through 6-6, **39 rules**, **13 footnote definitions**, and all **162 visible instruction-stage cells** across **35 instruction rows** in Figures 6-3/6-4/6-5. There are 20 logged issues: `TIM-U09` is resolved by specific FP-table evidence; the others retain open qualifications or semantic binding work. No timing checker or executable figure replay has been implemented.

The source is local `1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf`, MPC603EUM/AD, 11/97. PDF locators are one-based physical pages. The full page map and source precedence are in `SOURCES.md`. No rule in this document is evidence that the current RTL implements the required timing.

## Coverage and provenance

| Table | Subject | Rows | Printed pages | PDF pages | Stable row IDs |
|---|---|---:|---|---|---|
| 6-1 | Branch | 4 | 6-23 | 269 | TIM-T61-001 through 004 |
| 6-2 | System register | 18 | 6-23 | 269 | TIM-T62-001 through 018 |
| 6-3 | CR logical / movement | 12 | 6-24 | 270 | TIM-T63-001 through 012 |
| 6-4 | Integer | 52 | 6-24 through 6-26 | 270-272 | TIM-T64-001 through 052 |
| 6-5 | Floating-point execution | 34 | 6-26 through 6-27 | 272-273 | TIM-T65-001 through 034 |
| 6-6 | Load/store and LSU management | 70 | 6-28 through 6-30 | 274-276 | TIM-T66-001 through 070 |

IDs identify source table rows, not fully expanded opcode forms. Rc/OE/LK/AA families retain the manual's notation. Duplicate opcodes with different SPR conditions remain separate rows. P03 must supply exhaustive legal decode forms before these rows can drive instruction generation. This transcription does not certify 603, 602 or EC603e variants; it records EC603e FP exclusions and PID6/PID7v timing distinctions where evidenced.

## Observation points and cycle meaning

UM §6.1 (PDF 247-248, 6-1-6-2) defines latency as execution until results are ready for a subsequent instruction, finish as the final execute cycle, completion as removal from the completion buffer, and writeback as transfer into architectural registers. §6.2 (PDF 250-251, 6-4-6-5) places operand/instruction latching at the end of dispatch. §6.3.3 (PDF 257-259, 6-11-6-13) permits a dispatched instruction to wait in a reservation station and imposes serialization.

P12 must bind these distinct events to actual RTL monitors:

| Event | Meaning |
|---|---|
| `dispatch_accept` | End of accepted dispatch stage; instruction owns allocated CQ/rename resources. |
| `execute_start` | First occupied execution cycle once required operands and execution resource are ready. |
| `finish` | Final execution cycle, CQ marked finished; result availability remains subject to serialization rules. |
| `complete` | In-order removal from CQ without exception, after older unresolved predictions permit it. |
| `writeback` | Architectural register update; can coincide with completion or follow in a nonflushable buffer. |
| `deallocate` | Resource-release legend category transcribed from schedules; its binding to exact resource-release events remains open. |

The proposed interval convention counts occupied execution cycles: an N-cycle execution starting in cycle E finishes in cycle E+N-1. This is not an unconditional dispatch-edge-to-finish-edge delta. A no-wait pipeline binding may derive that delta, but stalls, serialization and monitor sampling must be explicit. The JSON records this convention as a proposal for P12, not an implemented checker.

Table cycles use processor clocks. Chapter 6 warns that its bus drawings resolve only half-clock increments and refers accurate bus timing to chapter 8 (PDF 247, 6-1). Core and bus cycles must not be substituted. PID7v's lack of 1:1 clock mode is a recorded source/project mismatch, not resolved by this timing extraction.

### Table symbols

| Symbol | Contract meaning and limits |
|---|---|
| Scalar such as `1` or `37` | Base execute latency; does not by itself specify initiation interval, dispatch wait, retirement time or external memory completion. |
| `*` | Branch may fold for an effective cost of zero. This is not zero physical delay and does not bypass dependency/target-fetch conditions. |
| `&` | Variable cycles due to serialization. All class rules apply even to rows without this marker. The marker does not supply a complete additive total-cycle formula. |
| `^` | CR result immediately forwarded to BPU for branch resolution. It does not promise early architectural CR writeback. |
| `2:1` | Two-cycle execution latency and one-cycle initiation interval for pipelined LSU work. It is not a two-stage occupancy vector. |
| `2/5&` | Hit/miss times for cache management requiring conditional bus activity, plus serialization constraints; it is not a full external-bus response deadline. |
| `2+n&` / `1+n&` | Base plus number of words accessed, with serialization. Partial-word and zero-count string cases are not expanded here. |
| Comma list | Listed possible multiply cycle counts; operand-to-count mapping is unresolved. A test accepting any listed count would not prove exact operand-dependent timing. |
| `1-1-1` / `2-1-1` | Dash-separated stage occupancy in Table 6-5, in multiply/add/round-convert order; do not confuse it with colon notation. |

All applicable footnotes are preserved as referenced JSON objects with their own page locators. SRU add-row note 1 allows `add`/`addo`, excluding Rc forms for SRU, while separate immediate/compare rows remain SRU-capable. General serialization rules take precedence over assuming unmarked SRU rows can freely execute early.

## Dispatch, completion and resource contract

The 39 rule objects preserve their section/page sources, conditions and unresolved interpretations. Important rule groups are:

- `TIM-DISP-DQ0` / `TIM-DISP-DQ1`: in-order two-slot dispatch; second slot checks resources remaining after the first slot; unit, rename and CQ availability plus serialization constraints.
- `TIM-CQ-ALLOC`: five completion buffers allocated at dispatch. `TIM-CQ-CQ0` / `TIM-CQ-CQ1`: oldest finished/nonfaulting/nonpredicted work completes first; second completion must be integer/load and obey pair limits of two GPR, one CR and one FPR writes.
- `TIM-RENAME-*` / `TIM-WB-LIMITS`: five GPR/four FPR renames; update loads may consume two GPR destinations; separate LR/CTR/CR limits and unresolved LR shadow allocation. Completion and rename release need distinct observations.
- `TIM-SER-COMPLETE`, `TIM-SER-DISPATCH`, `TIM-SER-REFETCH`: exact class lists from §6.3.3.2 (PDF 259, 6-13), including conditional `mtspr(XER)` serialization and `isync` refetch. The row's rule reference must be evaluated with its condition; it does not make every `mtspr` dispatch-serialized.
- `TIM-BPU-*`: folding, one unresolved prediction, target/CR/counter/link dependencies, younger architectural-update prohibition and misprediction cleanup. These are separate from the two general dispatcher slots.
- `TIM-IU-OCCUPANCY`, `TIM-SRU-ADDCOMPARE`, `TIM-LSU-PIPELINE`: unit pipeline constraints; multicycle IU blocks another IU execute start, PID7v SRU add/compare can execute alongside IU, generic LSU base timing is 2:1.

The DQ[0] source literally lists “Instruction is dispatch serialized and completion buffer is empty” among all dispatch requirements (§6.6.1.2, PDF 267, 6-21). A literal conjunction would exclude ordinary instructions. `TIM-U05` records a **provisional conditional interpretation**: if the instruction is dispatch-serialized, CQ must be empty. This must be reviewed with the schedules and serialization prose; the raw anomaly is not hidden.

## Variant dispositions and unresolved timing

The JSON keeps original table values alongside explicit model-specific overrides:

| Issue | Disposition / owner |
|---|---|
| `TIM-U03` divide | Raw Table 6-4 says 37; PID7v=20 and PID6=37 follow explicit §1.1 / §6.3 (PDF 45 / 251, 1-5 / 6-5). P02/P08/P27 retain both sources. |
| `TIM-U04` LR | §6.3 distinguishes `mtspr(LR)` rename and branch-update LR shadow despite summary one-LR wording (PDF 252 / 258, 6-6 / 6-12). P09 must model resource distinctions. |
| `TIM-U06` cache reload | Generic chapter 6 reload blocking conflicts with PID7v hit-under-reload enhancement (PDF 44, 1-4). P20 and P02 must apply model conditions. |
| `TIM-U07` store | Generic Table 6-6/§6.4.4 latency is 2:1; overview advertises PID7v single-cycle store. Observation-point distinction is unresolved; do not replace all store latencies with one. |
| `TIM-U08` table identities | Preserve `mull` spelling, `subf[.]` OE omission, `sc` extended field `--1`, and `mttb` versus generic `mtspr` timing overlap. P03 owns encoding/SPR reconciliation; JSON is not a decoder oracle. |
| `TIM-U09` FP serialization | **Resolved classification:** Table 6-5 explicitly marks `mtfsb0` with completion-serialization `&`; §6.4.3 also blocks the FPU pipeline. Preserve the generic list omission as an editorial discrepancy; apply completion serialization. |
| `TIM-U02`, `TIM-U13` operand conditions | Multiply selection and string word-count edge cases need source-backed per-operand conditions. |
| `TIM-U10`, `TIM-U12`, `TIM-U14` memory/resources | Complete cache, alignment, bus, clock-mode and exact availability/deallocation contracts remain necessary. No exact stage/queue implementation is inferred where source remains silent. |
| `TIM-U01`, `TIM-U11`, `TIM-U15` observation/coverage | Visible graphical schedules are now transcribed. Monitor edge binding and terminology/graphic conflicts must be resolved before automated conformance claims. |
| `TIM-U16`, `TIM-U18` FP | `mtfsfi` visibly prints spaced `1 1 1&^`, retained raw and provisionally normalized to three stages. Exact same-cycle re-admission and exceptional-operand timing remain qualified. |
| `TIM-U17`, `TIM-U19`, `TIM-U20` diagrams | Graphic writeback ordering, Figure 6-5 short final `fsub`, cycle-zero prose, and repeated dispatch shading are preserved explicitly below. |

## Floating-point timing

Table 6-5 contributes 34 rows: 14 on PDF 272 / 6-26 and 20 on PDF 273 / 6-27. The raw cycle strings, all `&`/`^` markers, and the final stage-notation footnote are preserved. Stage names come from §6.2 (PDF 250-251 / 6-4-6-5).

| Family | Transcribed timing | Qualification |
|---|---|---|
| `fdivs`, `fres` | 18 execute cycles | Scalar notation is nonpipelined; §6.4.3 blocks further FP dispatch until execution completes. |
| `fdiv` | 33 execute cycles | Same nonpipelined/blocking distinction. |
| `fmul`, `fmadd`, `fmsub`, `fnmadd`, `fnmsub` | `[2,1,1]`, four execute cycles | Structural minimum initiation interval is inferred as two cycles, contingent on available stages and no other stall; exact dispatch admission is not certified. |
| Other ordinary staged FP rows, including `frsqrte` | `[1,1,1]`, three execute cycles | Structural minimum initiation interval is inferred as one cycle under ready/no-stall conditions. `frsqrte` is not transcribed as an iterative division. |
| `mtfsb0`, `mtfsb1`, `mtfsfi`, `mffs`, `mtfsf` | Three-stage notation plus completion serialization | Despite staged table notation, §6.4.3 lists these as pipeline blockers until execution completes. `mtfsfi` spaces instead of dashes remain a logged notation anomaly. |
| `mcrfs` | `[1,1,1]&`, three execute cycles plus completion serialization | No `^`; it is specifically excluded from immediate CR forwarding in §6.4.3. It is not named in the same pipeline-blocker list. |

`TIM-FPU-PIPELINE`, `TIM-FPU-BLOCKERS`, `TIM-FPU-CR-FORWARD` and `TIM-FPU-MTFSB0-SERIAL` capture these rules. All FP rows require supported/enabled FPU state and legal forms. EC603e cannot execute these timing paths normally. A `^` applies when the instruction produces CR results; it does not promise architectural CR writeback before retirement. Tables provide base execution timing, not complete exceptional-operand/exception-delivery bounds.

For staged rows, `pipeline_stage_occupancy` is literal/provisionally normalized source notation and `execute_latency_cycles` is its sum. `initiation_interval_cycles` remains null because Table 6-5 does not use a colon throughput entry. Where warranted, the separately named `inferred_minimum_initiation_interval_cycles` exposes the structural inference and its conditions; consumers must not silently treat it as unconditional dispatch spacing.

## Worked schedules: literal graphical cells

All visible instruction rectangles were inspected in rendered source pages. The following compact tables reproduce their cycle/stage cells; identical data appear in each JSON schedule's `instructions[].cells`. **These are literal legend categories, not architectural event assertions.** They are kept separate from adjacent prose landmarks, which retain their original source cycle numbering.

Legend: `F` fetch, `D` dispatch-colored occupancy, `H` held in IQ, `P` predicted, `E` execute, `W` black writeback category, `A` striped deallocate. For example, `5D 6D` records two occupied dispatch-colored cycles, not two accepted dispatches. A trailing `~` marks a partially visible cell beyond the last labeled cycle at the figure's right edge; no later cell is invented.

### TIM-FIG63: Figure 6-3

Source: UM PDF 256 / 6-10. 12 instruction rows, 53 cells.

| Instruction | As drawn | Cycle/stage cells |
|---:|---|---|
| 0 | `add` | `0F 1D 2E 3W 4A` |
| 1 | `fadd` | `0F 1D 2E 3E 4E 5W 6A` |
| 2 | `add` | `1F 2D 3E 4W 5A` |
| 3 | `fadd` | `1F 2D 3E 4E 5E 6W 7A` |
| 4 | `br` | `2F 3E` |
| 5 | `fadd` | `2F 3D` |
| 6 | `fadd` | `3F` |
| 7 | `fadd` | `3F` |
| 8 | `add` | `4F 5D 6E 7W 8A` |
| 9 | `add` | `4F 5D 6D 7E 8W 9A` |
| 10 | `add` | `5F 6H 7D 8E 9W 10A~` |
| 11 | `fsub` | `5F 6H 7D 8E 9E 10E~` |

The source labels clock cycles 0-9. Rows 10/11 extend partly into cycle 10. Rows 5/6/7 end on the redirected path without later stages shown. Instruction 9 is shaded dispatch in both cycles 5 and 6, matching the discussion of waiting for the IU; this must not allocate two CQ entries. The branch is fetched in cycle 2 and drawn execute in cycle 3, while adjacent prose describes immediate resolution/request on encounter in cycle 2.

### TIM-FIG64: Figure 6-4

Source: UM PDF 257 / 6-11. 11 instruction rows, 50 cells.

| Instruction | As drawn | Cycle/stage cells |
|---:|---|---|
| 0 | `add` | `0F 1D 2E 3W 4A` |
| 1 | `fadd` | `0F 1D 2E 3E 4E 5W 6A` |
| 2 | `add` | `1F 2D 3E 4W 5A` |
| 3 | `fadd` | `1F 2D 3E 4E 5E 6W 7A` |
| 4 | `br` | `2F 3E` |
| 5 | `add` | `8F 9D 10E 11W 12A~` |
| 6 | `fsub` | `8F 9D 10E 11E 12E~` |
| 7 | `add` | `9F 10D 11E 12W~` |
| 8 | `fsub` | `9F 10D 11E 12E~` |
| 9 | `add` | `10F 11D 12E~` |
| 10 | `fsub` | `10F 11D 12E~` |

The source labels cycles 0-11; several rows are clipped within cycle 12. §6.3.2.3 explicitly makes this example a 1:1 processor/bus clock ratio. It is not a faithful PID7v clock-mode example. The ADDRESS/DATA shapes are retained only as qualitative annotations: address roughly cycles 5-7, four beats roughly halfway through cycle 6 to halfway through cycle 10. Prose says first return at cycle 7, while new instruction fetch-colored rectangles begin at cycle 8. No edge-accurate bus waveform is claimed.

### TIM-FIG65: Figure 6-5

Source: UM PDF 263 / 6-17. 12 instruction rows, 59 cells.

| Instruction | As drawn | Cycle/stage cells |
|---:|---|---|
| 0 | `add` | `0F 1D 2E 3W 4A` |
| 1 | `bc` | `0F 1P 2P 3E` |
| 2 | `fadd` | `1F 2D 3E 4E 5E 6W 7A` |
| 3 | `add` | `1F 2D 3E 4W 5A` |
| 4 | `fadd` | `2F 3D 4E 5E 6E 7W 8A` |
| 5 | `bc` | `2F 3P 4P 5E` |
| 6 | `add` | `3F 4D 5E` |
| 7 | `fadd` | `3F 4D 5E` |
| 8 | `and` | `6F 7D 8E 9W 10A` |
| 9 | `fsub` | `6F 7D 8E 9E 10E 11W~` |
| 10 | `or` | `7F 8D 9E 10W 11A~` |
| 11 | `fsub` | `7F 8D 9E 10E 11W~` |

The source labels cycles 0-10; final rows extend partly into cycle 11. Adjacent prose explicitly kills instructions 6/7 when branch 5 resolves incorrectly in cycle 5. Three discrepancies must remain visible: prose says dispatch in cycle 0 while rectangles show fetch; instruction 11 `fsub` has only two gray execute cells (9,10) before black cycle 11 while Table 6-5 specifies three stages; and graphical writeback ordering differs from architectural in-order requirements.

### Graphic semantics remain unresolved

In Figures 6-3/6-4, integer instruction 2 has black `W4` before older floating-point instruction 1 has `W5`. In Figure 6-5, integer instruction 3 has `W4` before older floating-point instruction 2 has `W6`. UM §6.3.3 (PDF 258 / 6-12) requires ordered completion and architectural writeback on retirement. This discrepancy cannot be repaired by silently moving cells, relabeling black bars as rename writes, or allowing out-of-order architectural updates. `TIM-U17` preserves both sources; later monitor binding must resolve their meaning.

The exact geometry of Figure 6-5's final `fsub` was cross-checked against the PDF's filled vector rectangles as well as the raster. It really has only two execute-colored cells. `TIM-U19` records this source-level mismatch instead of adding a third cell. No absent tail stages, complete retirements or bus sampling edges are inferred from the drawing's continuation marks.

The three schedules therefore have `status: graphical_cells_transcribed_with_open_interpretation`; `full_schedule_replays` remains **0**. This closes visible graphical transcription coverage while leaving executable schedule acceptance open.

## JSON schema and consumer rules

Top-level objects are `source_document`, `coverage`, `measurement_contract`, `footnotes`, `rows`, `rules`, `schedules`, and `unresolved`. Row IDs remain stable in printed order. Each row provides `source`, raw mnemonic/unit/cycle fields, decimal opcode lookup fields, variant scope, conditions, typed `timing`, and referenced footnote/rule/issue IDs. Decimal opcode fields are navigation aids; reserved bits, opcode families and SPR selection are P03's responsibility.

`timing.kind` is one of `branch_effective_cycles`, `base_execute_latency`, `variant_execute_latency`, `operand_condition_unresolved`, `latency_and_initiation_interval`, `conditional_cache_latency`, `word_count_expression`, or `pipeline_stage_latency`. Missing or null initiation interval/stage occupancy means **unspecified**, not zero. A consumer must select model and mode, evaluate serialization/resource predicates, and reject cases whose required evidence is unresolved. It must never turn unresolved entries into passing tests or infer expected timing from current RTL.

All rows/rules have `checker_status: not_implemented`; schedules have `status: graphical_cells_transcribed_with_open_interpretation`. These fields prevent transcription coverage from being mistaken for test coverage.

Schedule schema additions are additive under version 1: `instructions` contains `instruction_number`, `mnemonic_as_drawn`, `source`, `cells`, `tail_status`, and `issue_ids`; each cell contains integer `cycle`, `stage`, and `extent` (`full` or `partial_right_edge`). `cycle_bounds` gives first/last labeled and partial-tail cycles. `instruction_row_count`, `cell_count`, `graphic_source`, `cell_semantics`, `legend_mapping`, and `discrepancies` document provenance and interpretation. Schedule stage strings refer to legend categories, especially `writeback`; they are not yet the measured events of the same name.

Coverage counters now include `graphical_schedule_transcriptions`, `schedule_instruction_rows`, and `schedule_cell_count`. Existing row/rule IDs and schema fields are preserved. `TIM-U09` remains addressable with `status: resolved_by_specific_table`; issue-reference presence alone does not mean that issue is still unresolved.

## Verification and exact remaining scope

Verification covers all eight table pages PDF 269-276, their footnotes, and the three figure pages PDF 256/257/263. The new FP rows were compared with their ordered source identities and raw timing symbols. Every visible figure row was mapped to the original legend; partial right-edge cells are marked. JSON syntax, preserved/unique IDs, internal rule/footnote/issue references, counts and PDF-to-printed-page mappings were checked. Schedule cells were checked for unique cycles per instruction, allowed stages, bounds, and complete declared row/cell counts. These checks validate transcription, not hardware behavior.

Remaining P02/P12 acceptance work is explicit:

1. Bind graphical legend categories to precise RTL monitor events and resolve the logged graphic/prose/table discrepancies. Implement executable replay tests only after that review; no replay has passed yet.
2. Resolve or explicitly bound remaining timing issues, including multiply operand-dependent timing, exact admission/deallocation, variable string-count cases, exceptional FP timing, and variant-specific cache/clock behavior.
3. Join the timing contract to separately owned chapter 7/8 bus contracts and the exhaustive P03 ISA metadata, preserving mode and legality conditions.

All six chapter 6 tables and all visible instruction-stage cells are now transcribed. No RTL or cycle checker was changed by P02c. Structural-validator integration is maintained separately by the parent task.
