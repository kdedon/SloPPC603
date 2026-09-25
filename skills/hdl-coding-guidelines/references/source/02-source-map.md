# Source Map

> Citation hub for the Cyclone V HDL Bundle.
> Populated in Phase 3 from the §9 Provenance footers of all 18 topic docs (`10-...md` through `41-...md`).

This file maps each archive source to the topic docs that cite it. It is the inverse view of the per-doc §9 footers — useful when an agent wants to know "which docs build on the Intel memory inference guide?" or "which docs cite ZipCPU's AXI rules?"

## Format

Each entry is one row:

| Source (archive path or live URL) | Revision / date | Cited by | Why |
|---|---|---|---|

Code sources link to their upstream repository at the pinned commit; document captures link to the live document. For sources only available live (Cummings papers that failed to fetch, Intel app-shell HTML, Intel subsection pages not captured locally), the row's path is the live URL and any local file (if present) is a fetch-failed stub or app-shell with no body content; such rows are marked **live URL only**.

The "Cited by" column lists the numeric prefix of each topic doc that cites the source (e.g. "13, 14, 17" means docs `13-registers-and-combinational-blocks.md`, `14-finite-state-machines.md`, `17-era-faithful-microarchitecture.md`).

Cross-references between topic docs and to `01-glossary.md` are not citations and are not listed here. 

## Sources

### Intel / Altera

| Source | Revision | Cited by | Why |
|---|---|---|---|
| [Quartus Standard: Design Recommendations](https://docs.altera.com/r/docs/683323/current) + live https://docs.altera.com/r/docs/683323/current | 18.1 capture (local is app-shell, body via live URL) | 11, 16, 17, 32, 40, 41 | Synchronous design practices, HDL coding styles, umbrella reference behind Arria V/Cyclone V Design Guidelines rules; operator-cost framing; warning-string catalog; report-reading discipline. |
| live https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/recommended-hdl-coding-styles | 18.1, **live URL only** | 12, 13, 14 | Intel-specific synthesis recommendations for Verilog/SystemVerilog; FSM encoding override via `state_machine_encoding`. |
| live https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/register-and-latch-coding-guidelines | 18.1, **live URL only** | 12, 13, 14, 41 | Register power-up values, secondary control signals, latch avoidance, latch inference from undriven outputs in `always_comb`. |
| live https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-memory-functions-from-hdl-code | 18.1, **live URL only** (chapter index) | 22, 30 | RAM/ROM templates, read-during-write, byte enables, dual-port memories; MLAB-vs-M10K sizing guidance. |
| live https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/single-clock-synchronous-ram-with-old-data-read-during-write-behavior | 18.1, **live URL only** (subsection-level fetch) | 30 | Verbatim Intel `single_clk_ram` template; old-data RDW selection via nonblocking. |
| live https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/single-clock-synchronous-ram-with-new-data-read-during-write-behavior | 18.1, **live URL only** (subsection-level fetch) | 30 | Verbatim Intel `single_clock_wr_ram` template; new-data RDW selection via blocking, registered-read. |
| live https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-rom-functions-from-hdl-code | 18.1, **live URL only** (subsection-level fetch) | 30 | Verbatim Intel `sync_rom` case-statement ROM template. |
| live https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/specifying-initial-memory-contents-at-power-up | 18.1, **live URL only** (subsection-level fetch) | 30 | Verbatim `$readmemb` init template; init-file rule for ROM/RAM. |
| live https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-multipliers-and-dsp-functions | 18.1, **live URL only** | 31 | Registered-template requirement, signedness, fitter framing; verbatim signed-multiplier template. |
| live https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/inferring-multiply-accumulator-and-multiply-adder-functions | 18.1, **live URL only** | 31 | Multiply-add / MAC patterns; verbatim multiply-adder template ("addition is always the second-level operator"). |
| live https://docs.altera.com/r/docs/683323/18.1/intel-quartus-prime-standard-edition-user-guide-design-recommendations/managing-metastability-with-the-software-44819 | 18.1, **live URL only** (local app-shell only) | 23 | Synchronizer chain recognition, dedicated-module rule, SDC-on-CDC-paths, Synchronizer Statistics report, MTBF reading. |
| [Quartus Standard: Timing Analyzer](https://docs.altera.com/r/docs/683068/current) + live https://docs.altera.com/r/docs/683068/current | 18.1 capture (local is app-shell; **live URL primary**) | 23, 40, 41 | SDC syntax/semantics, `create_clock`, `derive_pll_clocks`, `derive_clock_uncertainty`, `set_input_delay`/`set_output_delay`, `set_false_path`, `set_multicycle_path`, `set_clock_groups -asynchronous`; setup/hold/recovery/removal slack definitions; TimeQuest report navigation. |
| [Cyclone V Device Handbook Vol. 1](https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration) + live https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration | 2026-05-20 capture (local is app-shell; body via live URL) | 17, 22, 30, 31, 32, 40 | ALMs, MLAB/M10K capacity and port modes, DSP precision set and operational modes, clock networks, PLLs, I/O context, ALM carry-chain claim, true-dual-port vs simple-dual-port. |
| live https://docs.altera.com/r/docs/683375/current/clock-networks-and-pll.html | 2026-05-20, **live URL only** (local sibling capture is app-shell) | 11 | Cyclone V RCLK and PCLK device-level enumeration, exact GCLK/RCLK/PCLK counts. |
| [Cyclone V Product Table](https://docs.altera.com/api/khub/documents/s60vJiu_kjIh2yag_Ea_yg/content) + live https://docs.altera.com/api/khub/documents/s60vJiu_kjIh2yag_Ea_yg/content | 2025-09-24 capture (PDF exceeds Read tool capacity; cite via live URL or via `01-glossary.md` distillation) | 10, 11, 16, 17, 30, 31 | Cyclone V resource ranges (110K ALMs, 5.6 Mbit M10K+MLAB, 112 DSP, 16 GCLK, 6 FPGA-side PLLs on 5CSEBA6); DE10-Nano `5CSEBA6U23I7` resource budget anchor. |
| [AN-662 Arria V and Cyclone V Design Guidelines](https://cdrdv2-public.intel.com/654271/an662.pdf) | Altera AN-662-1.3, Nov 2016 (PDF behind `.txt` extension; extracted via `pdftotext`) | 10, 11, 40 | Pre-RTL planning, synchronous design, fabric-clock prohibition, async-assert/sync-release, clock-network tiers, IOE placement, full SDC discipline (Table 14), vendor-IP boundary. |

### Methodology papers (Cummings)

| Source | Revision | Cited by | Why |
|---|---|---|---|
| [Cummings, SNUG 1998 FSM](http://www.sunburst-design.com/papers/CummingsSNUG1998SJ_FSM.pdf) + [Cummings, SNUG 1998 FSM](http://www.sunburst-design.com/papers/CummingsSNUG1998SJ_FSM.pdf) | SNUG 1998 (Rev 1.1) | 13, 14, 17 | FSM coding styles for synthesis; one-block vs two-block tradeoffs; blocking/nonblocking discipline; registered outputs; one-hot-with-zero-idle excerpt. |
| live http://www.sunburst-design.com/papers/CummingsSNUG2000SJ_NBA.pdf (local capture is fetch-failure stub) | SNUG 2000, **live URL only** | 13 | Blocking vs nonblocking methodology; single-driver, NBA-in-seq, no-mix rules; two-region NBA model. |
| live http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO1.pdf (local capture is fetch-failure stub) | SNUG 2002, **live URL only** | 22, 24 | Async FIFO design pattern; Gray-coded pointers; safe full/empty flags; Gray empty/full in Gray. |
| live http://www.sunburst-design.com/papers/CummingsSNUG2008Boston_CDC.pdf (local capture is fetch-failure stub) | SNUG 2008, **live URL only** | 23, 24 | CDC taxonomy; 2FF chain structure; chain-depth conventions; multi-bit anti-rule; failure-mode framing. |

### FPGACPU.ca

| Source | Revision | Cited by | Why |
|---|---|---|---|
| [FPGA Design Elements](http://fpgacpu.ca/fpga/index.html) | capture 2026-05-20 | 10 | FPGA Design Elements index; Elastic Pipelines part-library framing. |
| [fpgacpu.ca Verilog Coding Standard](http://fpgacpu.ca/fpga/verilog.html) | capture 2026-05-20 | 10, 11, 12, 13, 16, 17, 31, 32, 40 | Practical Verilog style; one-driver-per-signal; `` `default_nettype none ``; sync-release cross-confirmation; clock-enable pattern; Cyclone V flop power-up = constant zero; register-everything default; bit-width/signedness discipline; mux 8:1 threshold; sign-extension as explicit work; pre-RTL plan rule. |
| [fpgacpu.ca System Design Standard](http://fpgacpu.ca/fpga/system.html) | capture 2026-05-20 | 10, 16, 17, 40 | Modularization; Core/Instance/Adapter/Shim hierarchy; mirroring discipline; minimize-warnings rule; timing-constraints-as-design discipline. |
| [fpgacpu.ca Handshake](http://fpgacpu.ca/fpga/handshake.html) | capture 2026-05-20 | 20 | Ready/valid composability; rules 1-3; direction-of-drive; legal combinational asymmetry; reset; `handshake_complete` recipe. |
| [fpgacpu.ca CDC](http://fpgacpu.ca/fpga/cdc.html) | capture 2026-05-20 | 22, 23, 24 | Metastability primer; one-bit crossing limits; multi-bit crossing warnings; latency-cases enumeration; pointer-rather-than-data framing. |
| [`FPGADesignElements`](https://github.com/laforest/FPGADesignElements/tree/2450a548eeee2a4dc1c06878b7c00617dd94e2a8) | commit `2450a54` | 10, 12, 13, 14, 15, 16, 17, 20, 21, 23, 24, 30, 31, 32 | Verilog-2001 building-block library. Modules cited: `Register*.v`, `Counter_Binary.v`, `Accumulator_Binary*.v`, `Width_Adjuster.v`, `Word_Reducer.v`, `Bit_Shifter*.v`, `Arbiter_*.v`, `Multiplexer_*.v`, `Adder_Subtractor_Binary*.v`, `Multiplier_Binary_Parallel.v`, `Divider_Integer_Signed*.v`, `Arithmetic_Predicates_Binary.v`, `Priority_Encoder.v`, `Address_Decoder_*.v`, `Pipeline_FIFO_Buffer.v`, `Pipeline_Half_Buffer.v`, `Pipeline_Skid_Buffer.v`, `Register_Pipeline*.v`, `CDC_Bit_Synchronizer.v`, `CDC_Pulse_Synchronizer_*phase.v`, `CDC_Flag_Bit.v`, `CDC_Word_Synchronizer.v`, `CDC_FIFO_Buffer.v`, `Binary_to_Gray_Reflected.v`, `RAM_Single_Port.v`, `RAM_Simple_Dual_Port.v`, `RAM_True_Dual_Port.v`, `RAM_Multiported_LE.v`, `fsm.html` page. |

### Style guides

| Source | Revision | Cited by | Why |
|---|---|---|---|
| [lowRISC SystemVerilog style guide](https://github.com/lowRISC/style-guides/blob/735d9112220033467e930b9afff250f76794a6fd/VerilogCodingStyle.md) | snapshot @ 2026-05-20 (commit `735d911` per source map) | 10, 11, 12, 13, 14, 41 | Industrial SystemVerilog style; sequential/combinational separation; reset conventions (`rst_n`); polarity-consistency; `_q`/`_d` naming; enum with explicit storage type; two-block FSM mandate; `unique case`; `casex` prohibition; full_case/parallel_case prohibition; reset-coverage and no-`X`-in-RTL rules. |
| [`lowrisc-style-guides`](https://github.com/lowRISC/style-guides/tree/735d9112220033467e930b9afff250f76794a6fd) | commit `735d911` | _(not cited as a project tree; the `lowrisc_systemverilog_style.md` raw file is the citation surface)_ | Source repo for the style guide above. |

### VerilogPro

| Source | Revision | Cited by | Why |
|---|---|---|---|
| [Verilog Pro: CDC Part 1](https://www.verilogpro.com/clock-domain-crossing-part-1/) | capture 2022-09-29 / 2026-05-20 | 23 | Single-bit CDC; source-register rule; chain depth 2 vs 3; pulse-via-2FF failure; feedback synchronizer; one-flop symptom; pulse-misses-edge. |
| [Verilog Pro: CDC Part 2](https://www.verilogpro.com/clock-domain-crossing-part-2/) | capture 2026-05-20 | 24 | Multi-bit CDC anti-rule; MCP formulation; FIFO-vs-MCP selection; 2-phase MCP variant; bus-narrowing; quasi-static exception. |
| [Verilog Pro: always_comb, always_ff](https://www.verilogpro.com/systemverilog-always_comb-always_ff/) | capture 2022-04 / 2026-05-20 | 12, 13 | SV procedural block intent; `always_ff` strict synthesis promise; `always_comb` guarantees; sensitivity-list and sim/spec gotchas. |
| [Verilog Pro: Verilog always block](https://www.verilogpro.com/verilog-always-block/) | capture 2022-04 / 2026-05-20 | 12, 13 | Verilog-2001 `always @(posedge clk)` baseline; combinational scheduling. |

### ZipCPU

| Source | Revision | Cited by | Why |
|---|---|---|---|
| [ZipCPU: AXI rules](https://zipcpu.com/blog/2021/08/28/axi-rules.html) | capture 2026-05-20 | 20, 21, 41 | Ready/valid rules; skid buffer motivation; registered `READY` recommendation; "everything else" as payload; SVA property form; three-properties rule; assume-vs-assert discipline; immediate-assertion anchor; `f_past_valid`. |
| [ZipCPU: formal verification](https://zipcpu.com/formal/formal.html) | capture 2026-05-20 | 41 | Formal verification mindset; "SVA writes the bug"; invariant-vs-recomputation; deep-formal pointer. |
| [ZipCPU: class Verilog](https://zipcpu.com/tutorial/class-verilog.pdf) + [ZipCPU: class Verilog](https://zipcpu.com/tutorial/class-verilog.pdf) | capture 2026-05-20 | 10, 11, 16 | Verilog class material; for-loop-elaboration rule; async-reset framing for formal (external interfaces vs internal logic); Yosys `opt_merge -share_all` redundancy framing. |
| [ZipCPU: Pipeline Control](https://zipcpu.com/tutorial/lsn-04-pipeline.pdf) + [ZipCPU: Pipeline Control](https://zipcpu.com/tutorial/lsn-04-pipeline.pdf) | capture 2026-05-20 | 10, 15, 40 | Pipeline-control flow material; three pipeline strategies; cycle-level schedule; backpressure-freeze; pipelining as architectural remedy. |

### Reference projects

| Source | Revision | Cited by | Why |
|---|---|---|---|
| [`verilog-axis`](https://github.com/alexforencich/verilog-axis/tree/48ff7a7e2ef782cf778d47910cf85835c64b1bce) | commit `48ff7a7` | 10, 12, 15, 20, 21, 22, 24, 40, 41 | AXI Stream FIFOs (`axis_fifo.v`, `axis_async_fifo.v`), register slices / skid buffers (`axis_register.v`, `axis_pipeline_register.v`, `axis_srl_register.v`), arbiters, adapters (`axis_adapter.v`), Quartus SDC examples (`syn/quartus/sync_reset.sdc`, `axis_async_fifo.sdc`), cocotb tests (`tb/axis_register/test_axis_register.py`). |
| [`verilog-axi`](https://github.com/alexforencich/verilog-axi/tree/516bd5dadc3365b7f9e225d2af8fe0b8d804fe53) | commit `516bd5d` | 22, 30 | AXI / AXI-Lite register slices (`axi_register_rd.v`, `axi_register_wr.v`); MLAB-targeting attribute pattern (`axi_vfifo_enc.v`: `(* ram_style = "distributed", ramstyle = "no_rw_check, mlab" *)`). |
| [`wb2axip`](https://github.com/ZipCPU/wb2axip/tree/df8e7649acf68544a152e39a4589c8e894a4cd0b) | commit `df8e764` | 20, 21, 22, 41 | Formally verified bus bridges, skid buffer (`rtl/skidbuffer.v`), sync/async FIFOs (`rtl/sfifo.v`, `rtl/afifo.v`), SVA properties; bound-module formal pattern (`bench/formal/faxis_master.v`). |

### Standards (not in archive)

| Source | Revision | Cited by | Why |
|---|---|---|---|
| IEEE 1800-2017 §16 (SystemVerilog Assertions) and §23.11 (`bind`) | 2017, **standard reference, no archive capture** | 41 | Construct semantics for `$past`, `$stable`, `disable iff`, `|->`, `|=>`, `bind`. |

### Intel HDL Design Guidelines (separate document, doc ID 683082)

| Source | Revision | Cited by | Why |
|---|---|---|---|
| live https://www.intel.com/content/www/us/en/docs/programmable/683082/current/hdl-design-guidelines.html | 2026-05-20, **live URL only** (local `quartus_standard_hdl_design_guidelines.html` is an app-shell, 71 lines) | 15 | Pipeline-register justification; retiming inference chain; Quartus retiming variation. Distinct from doc 683323 (Design Recommendations). |

---

## Unused sources (in earlier skeleton, no topic doc cited)

These sources were listed in the Phase 0/1 skeleton but no topic doc's §9 footer cites them. Flagged for spec-author review — they may indicate scope gaps, or simply that the bundle did not end up needing them.

| Source | Note |
|---|---|
| [projf-explore](https://github.com/projf/projf-explore/tree/dd212c2) @ commit `dd212c2` | Listed in skeleton as "practical Verilog examples, display pipelines." No §9 footer in docs 10-41 cites any file from this tree. Bundle scope (Cyclone V HDL idioms, ready/valid, CDC, memory/DSP inference, timing) did not surface a need for projf-explore's graphics-pipeline examples. |
| [DE1-SoC Computer Manual](https://fpgacademy.org/Downloads/DE1-SoC_Computer_ARM.pdf) + extracted text | Listed in skeleton as Cyclone V DE1-SoC context. No §9 footer cites it. The HDL-craft scope of this bundle did not require board-level/system reference material. |
| [`lowrisc-style-guides`](https://github.com/lowRISC/style-guides/tree/735d9112220033467e930b9afff250f76794a6fd) @ commit `735d911` (project tree) | The raw markdown [lowRISC SystemVerilog style guide](https://github.com/lowRISC/style-guides/blob/735d9112220033467e930b9afff250f76794a6fd/VerilogCodingStyle.md) is cited heavily (see Style guides above); the cloned project tree itself is not cited as a code source — only its style-guide markdown file is load-bearing. |

---

## Summary statistics

- **Total unique cited sources**: 30 (excluding cross-references to other bundle docs).
- **Live-URL-only entries** (no usable local body content; local capture is app-shell or fetch-failure stub): 15.
- **Standards references** (no archive): 1 (IEEE 1800-2017).
- **Unused sources flagged**: 3 (projf-explore, DE1-SoC PDF, lowrisc-style-guides project tree).
- **Topic docs with §9 footers read**: 18 of 18.
