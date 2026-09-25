---
name: hdl-coding-guidelines
description: Load for any RTL/SystemVerilog/VHDL design, review, timing-closure, CDC, FSM, handshake, arbiter/memory-controller, BRAM/M10K/MLAB/DSP inference, SDC or Quartus-report work on Cyclone V / MiSTer cores (5CSEBA6U23I7, Quartus 18.1); encodes the project's HDL guidelines as checkable rules, anti-pattern and bring-up checklists.
---

# HDL Coding Guidelines — Operating Manual (Cyclone V / MiSTer)

Distilled from the 23-file reference bundle in `references/source/`.
Pointers below are written `see references/source/<file>#section`. `references/README.md` summarizes every source
file so you can pick the right depth doc. Rule labels: **[C]** contract (violating breaks correctness),
**[V]** convention, **[I]** inference/judgment. When a [C] and a convenience conflict, [C] wins.

Target: Cyclone V SoC `5CSEBA6U23I7` (DE10-Nano): ~110K ALMs, 5.6 Mbit M10K+MLAB, 112 DSP, 16 GCLK,
6 PLLs. Flops power up to **0** (an `initial q = 1` does not survive to silicon; reset anything whose
post-power-up value matters). Resource budget is rarely the constraint; **cycle accuracy and correctness
under stall/CDC are.**

---

## 0. Before writing anything: the pre-RTL plan

Rule: no non-trivial RTL without a plan a reviewer can read without opening the code.
WHY: every late CDC discovery, pipeline-depth misalignment and fmax surprise traces back to a missing plan.
Failure it prevents: AP#40 (no plan), AP#41 (software transliteration), AP#8 (for-loop as iteration).

Plan must name: clocks (source pin/PLL, frequency, sync/async relation); reset polarity + sync-release plan
per domain; throughput (1/clk, 1/N clk, bursty, cmd/resp); latency (fixed/variable/backpressured);
datapath widths + signedness + wrap/saturate policy; resource strategy (parallel vs shared; flops vs MLAB
vs M10K vs DSP); flow control at every boundary (always-ready, ready/valid, FIFO, credit, req/ack);
pipeline cuts; and for emulation cores: original chip identity, datapath width, control style
(microcoded vs hardwired), bus structure, memory-port topology, per-operation external cycle counts.
- Every `for` loop is elaborated into parallel hardware; a many-cycle loop is an FSM with a counter, a
  streaming loop is a pipeline. [C]
- Module hierarchy = hardware hierarchy (datapath / control / interface), never a C call-graph. [V]
- Emulation cores mirror the original chip; the plan is a reverse-engineering artifact, not an invention. [I]
See `references/source/10-hardware-mindset-and-microarchitecture.md#3.1`, `#7`;
`17-era-faithful-microarchitecture.md#2` (plan addendum).

---

## 1. Language subset and block discipline (applies to every line)

| Rule | Why | Prevents |
|---|---|---|
| `always_ff` uses `<=` only; `always_comb` uses `=` only; never mix in one block. [C] | NBA gives register-swap semantics; blocking matches dataflow. Mixing splits scheduling regions between simulators. | AP#2 sim/synth mismatch |
| Exactly one driver per signal (one `always` or one `assign`). [C] | Two drivers = multi-driver error or `X`. | AP#50, elaboration errors |
| Every `always_comb` output assigned on every path: defaults at top of block, then overrides; every `case` has `default:` even when `unique`. [C] | Unassigned path = inferred latch; `unique`/`priority` do **not** replace `default:`. | AP#4 latch |
| No combinational loop: a comb signal never appears in its own RHS cone (incl. across hierarchy). [C] | Timing model breaks; `(loop)` in reports. | AP#3 |
| One logical concern per `always` block; sequential blocks hold at most a register + enable/increment; complex next-state goes in `always_comb` driving `_d`. [C] | Monolithic blocks correlate bugs and hide fmax. | AP#1 |
| Reset (or reset-like) branch first in `always_ff`: `if (!rst_n) q <= RESET; else if (en) q <= d;` [V] | Structural priority; engages ALM CE/SCLR/ACLR/SLOAD hardware. | LUT-built control, wrong priority |
| Use `logic` everywhere except `inout` (`wire`). `typedef enum logic [N-1:0] {...} name_e;` — explicit storage, no anonymous enums. [C] | Quartus FSM extractor needs explicit storage type. | FSM not extracted |
| Every literal has width+base (`8'h00`, not `0`); `'0` only for parameter-width zero. Concatenation operands sized explicitly; port widths match exactly. [C] | Silent truncation/zero-extension; 32-bit phantom fields. | AP#5, AP#6, AP#71 |
| Signed arithmetic: every operand `logic signed`; cast with `signed'()`/`unsigned'()` at each crossing. One unsigned operand makes the whole expression unsigned. [C] | `a(-128) + incr(1'b1)` gives +129, not -127. | AP#5, AP#66 |
| `` `default_nettype none `` at top of every file; `localparam` for every magic number; parameterize widths with `$clog2`. [V] | Typos become elaboration errors, not 1-bit wires. | silent implicit nets |
| Forbidden: `casex`, `full_case`/`parallel_case` pragmas, `always_latch`, `X` literals as don't-care, internal tri-state (`Z` inside fabric), `defparam`, tasks in RTL, `interface`/`modport`, classes, dynamic arrays, `#delay`, hierarchical refs, 2-state types in datapath. [C/V] | Sim/synth divergence or non-synthesizable. | AP#7 and friends |
| `always_comb` self-read: a name assigned in the block is excluded from its sensitivity; write top-down, never read a `_d` you assign later in the same block. [C] | `c = b; b = a;` gives stale `c`. | AP#44 |

Case preference order: `case` > `case inside` > `casez` (with `?`, mutually exclusive items) > never `casex`.
See `12-synthesizable-sv-subset.md#3.2` (allowed), `#3.3` (forbidden), `#3.4` (width rules W-1..W-5);
`13-registers-and-combinational-blocks.md#3.1`–`#3.4`.

Canonical shapes (copy these; do not improvise):
```systemverilog
always_ff @(posedge clk or negedge rst_n) begin      // one register, one concern
  if (!rst_n)      q <= RESET_VALUE;                 // priority 1: reset
  else if (clr)    q <= '0;                          // priority 2: sync clear
  else if (en)     q <= d;                           // priority 3: enable; else hold
end
always_comb begin                                    // defaults first, then overrides
  state_d = state_q; out_a = 1'b0; out_b = 1'b0;
  unique case (state_q)
    StIdle: if (start) begin state_d = StRun; out_a = 1'b1; end
    StRun:  if (done)  state_d = StIdle;
    default: ;                                       // mandatory even if all states listed
  endcase
end
```

---

## 2. Clocks and resets

- Every flop is clocked from a pin, PLL output, or GCLK/RCLK/PCLK net. **Never** gate/AND/MUX/divide a clock in fabric; use a PLL for frequency and `ALTCLKCTRL`/`clkena` for MUX/gate. [C] WHY: fabric clocks corrupt the fitter clock plan and STA. Prevents AP#9.
- "Stop the clock" = clock-enable: `if (en) q <= d;`. [V]
- Reset is async-assert / sync-release: external `arst_n & pll_locked` → per-domain 2FF (3FF if MTBF demands) release synchronizer with async-clear, data tied high → `rst_n`. Never wire a raw async reset to every flop. [C] WHY: release inside setup/hold window → metastable flops. Prevents AP#10.
- One reset polarity per project (this project: active-low `rst_n`); invert exactly once at a boundary and rename the net. [C] Prevents AP#11.
- The async-reset source must itself be registered, never a glitchable comb term. [V] Prevents AP#43.
- Single clock domain by default; add a domain only when an external interface mandates it. Each added domain costs synchronizers, async FIFOs, verification. [V]
- Analyze reset fanout; re-synchronize per region if recovery/removal fails at scale. [I] Prevents AP#12.
See `11-clocking-resets-and-cyclone-v-clock-networks.md#2`, `#5` (minimal pattern), `#8` (grep list).

```systemverilog
wire  async_n = arst_n_in & pll_locked;              // lock gates release
logic s1, s2;
always_ff @(posedge clk or negedge async_n)
  if (!async_n) {s1, s2} <= 2'b00; else {s1, s2} <= {1'b1, s1};
wire  rst_n = s2;                                    // released 2 clk edges after async_n rises
```
Grep-lint before commit (zero hits): `always_ff @(posedge <net driven by assign a & b>)`; two polarities on one reset net;
`posedge arst` where `arst` is an `assign` of comb terms.

---

## 3. Before writing an FSM

1. Two-block by default: `always_ff` state register (reset to a named enum state) + `always_comb` next-state/outputs. Three-block when outputs must be registered (adds 1 cycle). One-block only for tiny FSMs with inherently registered outputs. [C/V]
2. `always_comb` opens with `state_d = state_q;` and a default for every output; `unique case (state_q)`; `default: ;` arm always present. [C] Prevents AP#13 (hang on illegal codepoint), AP#4.
3. Never `next = 'x`. [C]
4. If outputs are combinational (two-block), document it in the header; downstream must not assume registered. Prevents AP#45.
5. Two states with identical outputs and next-state functions are one state — tabulate the transition table and merge. Prevents AP#14.
6. Encoding: binary default; one-hot when decode depth is the critical path; for era-faithful work pin encoding with `STATE_MACHINE_PROCESSING = User-Encoded` / `state_machine_encoding` attribute. [O]
7. Microcoded control (ROM addressed by `{state,inputs}` → `{next_state,control_word}`) adds one cycle of next-state latency — only correct where the original chip did the same. [I]
8. Verify: FSM appears in Synthesis "State Machines" list with the right state count; force an unenumerated code in sim and confirm return to idle.
See `14-finite-state-machines.md#3.2`, `#3.5`, `#3.6`, `#8`.

---

## 4. Before writing a handshake (ready/valid, req/ack)

Three [C] rules — violating any one silently corrupts data and Quartus will not warn:
1. **No valid-drop.** Once `valid` asserts, it and the payload hold until the cycle `valid && ready`. `valid` may fall the cycle after a transfer only.
2. **Payload stable while `valid && !ready`** — every bit including sideband (`last`, `keep`, `id`, `user`).
3. **Work happens exactly on `valid && ready` — "plus nothing."** Every internal state that affects the interface changes only on that cycle (`handshake_complete = valid && ready`). Counting down words and advancing on `count != 0` alone loses the last word when `ready` dips.

Derived rules:
- `valid` must not depend combinationally on `ready` (loop or valid-retraction). `ready` may inspect `valid` combinationally. Producer/consumer direction is fixed: producer drives `valid`+payload, consumer drives `ready`. [C] Prevents AP#49, AP#50.
- Reset clears `valid`. [V]
- Canonical producer: `if (!valid || ready) begin valid <= next_valid; data <= next_data; end`.
- Every request/ack pair must: hold `req` and payload until `ack` is observed; advance state only on the ack cycle; for cross-domain req/ack use toggles through 2FF (see §6), never pulses.
- Every handshake interface carries the three SVA properties (no-valid-drop, payload-stable, reset-clean) bound in simulation (`41-quartus-reports-and-verification.md#5` Pattern B).
See `20-ready-valid-handshakes.md#2`, `#4` (four waveform cases), `#5`, `#8` (checklist).

```systemverilog
// Producer: valid and payload move only when the slot is free or being drained
always_ff @(posedge clk) begin
  if (!rst_n)                 valid <= 1'b0;
  else if (!valid || ready)   valid <= next_valid;
end
always_ff @(posedge clk) if (!valid || ready) data <= next_data;
// Consumer: act on the handshake cycle, nothing else in the condition
always_ff @(posedge clk) if (valid && ready) begin /* consume */ end
```

### FIFOs
- Producer `ready` = `!full` and it **must** be wired back and honored; unconnected/tied-high `tready` overflows silently under real burst rates that the TB never generated. If the producer cannot stall (fixed-rate source), size so it never fills **and** export an overflow flag. [C] Prevents AP#38.
- Sync FIFO: one clock, binary pointers of width `ADDR_WIDTH+1` (extra MSB disambiguates full from empty), `full = wr == (rd ^ {1'b1, {AW{1'b0}}})`, `empty = wr == rd`, no synchronizers (copying async structure adds 2 cycles for nothing — AP#20).
- Async FIFO: two clocks, Gray pointers, 2FF per pointer in the opposite domain, `full`/`empty` in own domain (§6).
- Depth = worst-case producer burst × worst-case consumer stall window + margin (< 2×); both numbers come from the plan. Guessed power-of-two depths are AP#53/#54. Storage: ≤ ~32 words flops/MLAB, deeper M10K; confirm tier in Fitter RAM Summary.
- FWFT (head presented without a read pulse) is the default; a 2-deep FWFT FIFO **is** a skid buffer.
See `22-fifos-synchronous-and-asynchronous.md#2`, `#5.1`, `#8.2` (symptom→cause table).

### Skid buffer / register slice (when `ready` chains fail timing)
- Insert **only** when TimeQuest names the `ready` or output path critical, or the boundary must be registered by contract. Prevents AP#17.
- Exactly two storage entries; `o_ready = !r_valid` is a flop output with **no** comb path from downstream `i_ready`. Registering only the forward path adds latency with zero timing gain (AP#51). Depth > 2 is a FIFO, not a skid buffer (AP#52). Prefer `OPT_OUTREG=1` on Cyclone V.
- After insertion, re-run TimeQuest: the new worst path must start at `r_valid` and be a *different* path.
See `21-skid-buffers-and-register-slices.md#5` (canonical wb2axip source), `#7`.

---

## 5. Before writing an arbiter, bus mux, or memory controller

- Internal shared buses are one-hot-select muxes, never tri-state (`Z` in fabric is not synthesizable on Cyclone V). Grant is one-hot; `default:` drives a defined value for no/multiple grant. [C]
- Requesters raise and **hold** `request` until `grant` rises, then hold through the transaction; grants hold until the request is released. A combinational grant (priority arbiter) must be pipelined where it lands on the critical path — register the grant, and pipeline data/valid alongside it. [V]
- Mirror the original chip's port topology: single-port memory + arbitration where the chip had that; do not "fix" contention with a true-dual-port M10K — software depends on the stalls. [I] Prevents AP#36, AP#32.
- Read-data return discipline (memory controllers, SDRAM/SRAM slots):
  - Never sample a shared read-data bus at a fixed cycle count from request; carry a `valid`/`ack` (or an explicit slot-owner tag) that travels **with** the data through every pipeline stage under the same enable, and capture on that qualifier. A fixed count breaks the moment latency, arbitration order, or refresh inserts a cycle. Prevents AP#15, AP#46.
  - Data and its qualifier freeze together on stall; one enable expression for the pair (same `always_ff`). Prevents AP#46.
  - Registered read for any M10K/MLAB path: consumers accept the 1-cycle latency; combinational reads fall to LUT-RAM with `DEPTH × WIDTH` area. Prevents AP#63.
  - Quasi-static OSD/config registers crossing to the memory clock: acceptable as per-bit 2FF **only** if the value is stable for thousands of destination cycles before use; otherwise MCP. Mark them `set_false_path` explicitly and comment the stability argument.
- Every `/`, `%`, variable shift, variable bit-select `a[idx]`/`a[idx +: K]`, and mux wider than 8:1 is a multi-LUT-layer structure; keep them off the critical path, register the selector a cycle early, or use one-hot select for N > 16. [C] Prevents AP#22, AP#39, AP#70.
See `17-era-faithful-microarchitecture.md#3.2`–`#3.3`, `#4.2`; `32-arithmetic-patterns-and-operator-cost.md#3.1`–`#3.3`.

---

## 6. Before writing a CDC crossing

Single bit:
- Source: a **register**, with no combinational logic between it and the synchronizer. [C] Prevents AP#59.
- Destination: ≥ 2 flops, no logic between, in a **dedicated module** tagged `(* PRESERVE *)`, `(* useioff = 0 *)`, `(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION \"FORCED IF ASYNCHRONOUS\"" *)`. [C] Prevents AP#55, AP#56 (invisible to MTBF analysis, retimed away).
- Pulses/events: toggle a level on the source, 2FF the toggle, any-edge-detect at destination (2-phase pulse synchronizer; ≈ 1 event per 4–8 source cycles). Never feed a pulse into a 2FF chain. [C] Prevents AP#57.
- SDC: `set_clock_groups -asynchronous -group {a} -group {b}` (preferred) or `set_false_path -from/-to` per pair. [C] Prevents AP#58.
- Never synchronize a signal already in the destination domain. [I] Prevents AP#20.

Multi-bit — pick exactly one of three: [C]
| Pattern | Use when | Cost |
|---|---|---|
| Dual-clock async FIFO, Gray pointers each through 2FF, full/empty computed in own domain from local Gray vs synchronized Gray (full = top **two** bits differ) | bursts, streams, rates close | one M10K/MLAB |
| MCP / word synchronizer: payload crosses unsynchronized, `req` toggle 2FF'd in, `ack` toggle 2FF'd back; payload held stable until ack returns | occasional wide words, config | 2 payload regs, 5–8 cycle round trip |
| Gray-coded counter sampled raw (±1 stale tolerated) | observing a free-running count | counter width |
Never N independent 2FF chains on data bits (phantom words that never existed). Never a binary pointer across the boundary; convert to Gray **before** the crossing register. Prevents AP#19, AP#21, AP#60, AP#61, AP#62.
Verify: every crossing appears in TimeQuest `Report Metastability` with MTBF (decades+); a missing row is an unsynchronized crossing. Functional simulation cannot find CDC bugs. Document the pattern in the module header.
See `23-cdc-single-bit.md#3.1`–`#3.3`, `#7`; `24-cdc-multi-bit.md#3.4`, `#4.3`; `22-fifos-synchronous-and-asynchronous.md#5.2`.

```systemverilog
module cdc_bit_sync #(parameter EXTRA_DEPTH = 0) (input logic dst_clk, input logic bit_in, output logic bit_out);
  localparam DEPTH = 2 + EXTRA_DEPTH;
  (* useioff = 0 *) (* PRESERVE *)
  (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION \"FORCED IF ASYNCHRONOUS\"" *)
  logic [DEPTH-1:0] sync_q;
  always_ff @(posedge dst_clk) sync_q <= {sync_q[DEPTH-2:0], bit_in};   // no logic between stages
  assign bit_out = sync_q[DEPTH-1];
endmodule
// Gray for any pointer that crosses: gray = bin ^ (bin >> 1), registered on the source side BEFORE crossing.
```
Latency facts to design around: a level crossing lands in 1–3 destination cycles (phase-dependent); the destination
sees ordering preserved but never cycle-aligned correspondence. Never reason "it arrives in exactly 2 cycles".

---

## 7. Pipelines and anything in a timing-critical cone

- **Valid follows data**: every data stage has a sibling `valid` flop, same enable, same reset, same depth. Backpressure freezes `(data, valid)` together. [C] Prevents AP#15, AP#46.
- Add a pipeline register only for a path a TimeQuest report (or known-unmeetable fmax) names; otherwise delete it. Retiming moves existing flops; it never creates a stage you did not write. [V/I] Prevents AP#17.
- Deliverable for any pipelined block: a stage × cycle schedule table; walk sim against it. [V]
- Cycle-accuracy boundary: internal pipelining is legal **only if** every externally observable cycle (bus phases, memory latency, IRQ ack, refresh, video timing) is unchanged. A stage that shifts the pin schedule by one cycle is forbidden. [C] Prevents AP#33.
- Split long ternary/case nests at the point where the next selector depends on a prior result; pre-register one-hot selects. Prevents AP#16.
- Operator cost (Cyclone V) — consult before placing anything on a critical path:

| Operator | Hardware | Critical-path safe? |
|---|---|---|
| `+`/`-` ≤ 32 b | ~1 ALM/bit on dedicated carry chain | yes; pipeline when > 32 b |
| `*` by constant; `/`,`%`,`<<`,`>>` by constant / power of two | shift-add, rewiring, bitmask (0 DSP) | yes |
| `*` two signals ≤ 27×27 | 1 DSP, 2-cycle registered template | yes when registered |
| `/`,`%` variable divisor | iterative restoring divider, ≈ W/step cycles, W² area | **never**; IP or reformulate |
| `<<`,`>>` variable amount | barrel shifter, log2(W) mux layers | costly at W ≥ 8; register the amount a cycle early |
| `a[idx]`, `a[idx +: K]` variable | W-input mux (×K) | costly at W ≥ 16 |
| `==`,`<` ≥ 32 b | adder-length carry chain | pipeline (split halves + AND) |
| mux ≤ 4:1 / 8:1 / > 16:1 | 1 LUT per bit / warning threshold / use one-hot select | yes / pipeline / one-hot |
| priority encoder > 8 inputs | isolator + log stage grows with W | pipeline per 8 bits |
- Accumulators: size to `W + $clog2(K)` or saturate explicitly; counters mod-N are `$clog2(N)` bits with an explicit wrap test. Prevents AP#69, AP#30.
See `15-pipelines-and-latency-thinking.md#2`, `#3.2`, `#5`; `32-arithmetic-patterns-and-operator-cost.md#3.1`–`#3.2`; `16-resource-and-state-economy.md#3.2`.

---

## 8. Inferring BRAM (M10K / MLAB) and DSP

Memory tier decision (in this order): (1) > 2 read ports → flops (`RAM_Multiported_LE` style, comb reads); (2) needs init contents → M10K (`$readmemh` / case-ROM); (3) choose RDW mode; (4) size: ≤ 16 entries multi-read → flops; 17–~256 × narrow, 1W1R, no init → MLAB (`(* ramstyle = "no_rw_check, mlab" *)`); larger / true-dual-port / init → M10K (`(* ramstyle = "M10K" *)`).
- Canonical template only: one `always @(posedge clk)`, unpacked `reg [W-1:0] mem [0:D-1]`, write under enable, **registered read** `q <= mem[raddr];`. [C] Prevents AP#63, AP#77.
- Read-during-write is chosen by assignment style: nonblocking `<=` → old-data; blocking `=` → new-data (write-forwarding). Anything else → Quartus picks (don't-care, may change between versions). [C] Prevents AP#24.
- True-dual-port only when two ports both write; otherwise simple-dual-port (two per M10K). Prevents AP#65.
- Init file path relative to the Quartus project dir and in the source list; confirm "Memory initialization data loaded" in the log. Prevents AP#64.
- Byte enables: one `if (byteena[i]) mem[addr][8*i +: 8] <= d[8*i +: 8];` per byte, same block.
- Verify in Fitter "RAM Summary" / "Resource Utilization by Entity" that each array landed on the intended tier; a `ramstyle` request silently dropped to MLAB/logic is a port-mode or RDW incompatibility — fix it, do not accept it.

DSP:
- `*` infers a DSP only with ≥ 1 input register **and** an output register in the same `always` block; `signed` on every operand, intermediate wire, and result. Modes 27×27, 18×19 (×2 per block), 9×9; wider needs explicit 18×18 split with pipelined adder tree or `altera_mult_add` IP. [C] Prevents AP#23, AP#66, AP#68.
- Constant-operand `*` must strength-reduce to zero DSPs; if a DSP appears, the constant was hidden (register/port). Prevents AP#67.
- Era rule: if the original chip had no parallel multiplier/barrel shifter, implement iterative shift-add / 1-bit-per-cycle over the documented cycle count; assert exact latency in the TB. [I] Prevents AP#26, AP#37.
- Annotate every `*` with the expected fitter outcome (`// expect: 1 DSP independent mult`).
See `30-memory-inference-cyclone-v.md#3.1`–`#3.6`, `#4.1`; `31-dsp-inference-cyclone-v.md#3.1`–`#3.3`, `#8.5`.

```verilog
// Simple-dual-port, old-data RDW (FIFO body / line buffer / frame buffer). Swap "<=" for "=" to get new-data.
(* ramstyle = "M10K" *) reg [W-1:0] mem [0:DEPTH-1];
initial $readmemh("init.hex", mem);                 // project-relative path, file in the QSF source list
always @(posedge clk) begin
  if (we) mem[waddr] <= d;
  q <= mem[raddr];                                   // registered read: mandatory for M10K/MLAB
end
// DSP: all three in one block, all signed
always @(posedge clk) begin a_r <= a; b_r <= b; p <= a_r * b_r; end   // a,b,a_r,b_r,p all `signed`
```

---

## 9. Writing SDC

Minimum file, in order: `create_clock` per primary pin → `derive_pll_clocks -create_base_clocks` → `derive_clock_uncertainty` → `set_input_delay`/`set_output_delay` (`-max` **and** `-min`) per synchronous I/O → `set_clock_groups -asynchronous` for unrelated domains → `set_false_path` only for async-reset release (cut `-to` the synchronizer flops when the port has other loads), static config, post-synchronizer endpoints → `set_multicycle_path -setup N` **always paired** with `-hold N-1`, only when the RTL (enable/FSM/counter) provably holds the source for N cycles. Run `check_timing` after every edit; zero unconstrained paths. [C]
- A false path is a correctness claim, not a timing fix. Prevents AP#74. A multicycle without RTL evidence samples garbage in hardware while STA reads clean. Prevents AP#75.
- Pin-adjacent registers go in the IOE via QSF `FAST_INPUT_REGISTER` / `FAST_OUTPUT_REGISTER` / `FAST_OUTPUT_ENABLE_REGISTER`. Prevents AP#73.
- Hold violations are frequency-independent; fix structurally (min I/O delays, pipeline), never by slowing the clock.
- Pipelining is the primary remedy for negative slack; widening the period is a retreat; `KEEP`/`MAXFAN`/manual retiming are last resort.
See `40-timing-closure-and-sdc.md#3`, `#5` (complete DE10-Nano SDC), `#7`.

```tcl
create_clock -period 20.000 -name clk_50 [get_ports {FPGA_CLK1_50}]
derive_pll_clocks -create_base_clocks
derive_clock_uncertainty
set_input_delay  -clock clk_sys -max 4.0 [get_ports {data_in[*]}]   ;# and -min
set_output_delay -clock clk_sys -max 4.0 [get_ports {data_out[*]}]  ;# and -min
set_clock_groups -asynchronous -group {clk_sys} -group {clk_audio}
set_false_path -to [get_registers {u_rst_sync|sync_q[*]}]           ;# reset release synchronizer endpoints
set_multicycle_path -setup -end -from [get_registers {u|slow_src*}] -to [get_registers {u|slow_dst*}] 2
set_multicycle_path -hold  -end -from [get_registers {u|slow_src*}] -to [get_registers {u|slow_dst*}] 1
```

---

## 10. Reading Quartus reports (after every compile, in this order)

1. **Synthesis (`.map.rpt`)**: Resource Usage Summary; Inferred Memory Blocks (tier per array); Inferred Multipliers; State Machines (every FSM present, state count = enum count); Optimization Results — every "Removed registers", "Merged registers", "Stuck at 0/1", "node has no driver/fanout", "inferred latch", "truncated/zero-extended" line is a bug or a written waiver. Default position: the warning is right. [C] Prevents AP#76.
2. **Fitter (`.fit.rpt`)**: Resource Utilization by Entity (M10K/MLAB/DSP per module vs plan, ALMs within ±20% of budget); RAM Summary; I/O section (IOE placement); Routing Usage (congestion ⇒ AP#28/#29); Synchronizer Statistics / Report Metastability (MTBF per chain).
3. **TimeQuest (`.sta.rpt`)**: Report Clocks; Report Setup / Hold ≥ 0 per domain; Report Recovery / Removal ≥ 0; Report Unconstrained Paths empty; Report Fanout (unexpected fanout ⇒ mirror copy); Report Metastability lists every async crossing.
4. **Simulation log**: run with `+sva`; every assertion failure fatal; scoreboard PASS is the final line.
Symptom map: latch → §1; combinational loop → §1; removed/merged register → §11; zero DSP with `*` in RTL → §8; M10K request landed in MLAB/logic → §8 RDW/port mode; negative slack through `/`,`>>`,`a[idx]`, wide `case` → §7; CDC path with negative slack → missing SDC (§6), not RTL.
See `41-quartus-reports-and-verification.md#4`; `16-resource-and-state-economy.md#3.6`.

---

## 11. Resource and state economy

Every register claims exactly one of: (a) holds state across cycles, (b) breaks a named critical path, (c) crosses a clock domain, (d) a protocol pipeline stage — else delete it. Every bus bit: (a) consumed downstream, (b) protocol field, (c) reserved with a written forward-compat reason. Put `// Justification: (reg-a) ...` above register declarations. [I]
- No mirror copies of a register in two modules (Merged-registers evidence). No wide bus through hierarchy when leaves read a slice; narrow at the producer. No `signed` on provably unsigned quantities. No defensive same-clock 2FF. Prevents AP#27–#31, AP#20.
- Emulation cores: resource sharing (one ALU, one shifter, one bus) is the era default; don't un-share because area is available. Datapath width = chip width. Prevents AP#32, AP#35.
See `16-resource-and-state-economy.md#2`, `#3.1`, `#5`; `17-era-faithful-microarchitecture.md#3.1`, `#5`.

---

## 12. Verification minimum

- Every non-trivial module: `tb/tb_<module>.sv` with deterministic clock/reset, stimulus queue, reference-model queue, monitor queue, element-by-element `$fatal` compare, prints `PASS`. No waveform-eyeballing sign-off. Prevents AP#78.
- Every handshake: bind `handshake_props` (no-valid-drop, payload-stable, reset-clean). Properties are invariants (ordering, stability, conservation), never a recomputation of the DUT. Prevents AP#79.
- `assert` for DUT properties; `assume` only for environment under a formal solver — never swapped. Prevents AP#80.
- Reset coverage: every register seen at reset and non-reset value. Drive reset at irregular phases; confirm release lands on a clock edge after ≥ 2 cycles.
- Pipelines: sparse/irregular `valid_in`, stall injection, `valid_out` at exactly `cycle_in + depth`, no spurious `valid` after reset.
- Emulation: pin-level cycle trace vs reference (Visual6502, MAME, real silicon) line-for-line; behavioral pass is not era-faithful pass; cycle-stress suites (raster demos, DMA, copy protection) must pass.
See `41-quartus-reports-and-verification.md#3`, `#5`; `17-era-faithful-microarchitecture.md#8.3`.

---

## 13. Anti-pattern checklist (grep for symptoms; full Symptom→Cause→Fix in `90-anti-patterns.md`)

Coding: [1] monolithic always block · [2] mixed `=`/`<=` in one block · [3] combinational feedback loop · [4] latch from incomplete coverage / missing `else`/`default` · [5] width/signedness mismatch on assignment · [6] implicit truncation in concatenation · [7] `casex`/`casez` overlapping patterns · [8] for-loop as software iteration · [40] no pre-RTL plan · [41] software-algorithm transliteration · [42] hierarchy mirrors a C call-graph · [44] `always_comb` self-referential read.
Clock/reset: [9] gated or fabric-derived clock · [10] async reset without sync release · [11] reset polarity inconsistency · [12] reset fanout unanalyzed · [43] reset asserted by glitching comb signal.
FSM: [13] no `default`/safe state · [14] redundant mergeable states · [45] comb FSM outputs consumed as if registered.
Pipeline/datapath: [15] data pipeline without parallel `valid` · [16] long ternary/case nest as one stage · [17] pipeline register "for safety" · [46] data freezes but `valid` advances (or vice versa).
Handshake/skid/FIFO: [18] ready comb chain longer than one LAB · [38] FIFO without producer backpressure · [47] valid drops before transfer · [48] payload changes while `valid && !ready` · [49] `valid` depends combinationally on `ready` · [50] `ready` driven by producer / `valid` by consumer · [51] skid registers forward path only · [52] depth > 2 as "skid buffer" · [53] FIFO under-sized for burst · [54] FIFO over-sized "to be safe".
CDC: [19] bit-by-bit 2FF on a changing bus · [20] defensive 2FF on same-clock signal · [21] binary counter as CDC pointer · [55] one-flop synchronizer · [56] synchronizer not in dedicated module · [57] pulse into level synchronizer · [58] synchronizer with no SDC · [59] comb logic before first sync flop · [60] MCP without payload hold · [61] MCP for high-rate data · [62] full/empty against un-Gray pointer.
Inference/arithmetic: [22] `/`,`%`, variable shift on critical path · [23] multiply not registered for DSP · [24] RDW mode assumed · [25] M10K for ≤ 16-entry register file · [26] DSP where chip used shift-add · [39] variable bit-select · [63] async read → LUT blowup · [64] init file missing at synthesis · [65] true-dual-port where simple-dual-port suffices · [66] mixed-signedness multiply · [67] constant multiply eats a DSP · [68] > 27×27 multiply without alignment pipeline · [69] silent accumulator overflow · [70] wide comb mux on critical path · [71] mixed-width arithmetic.
Economy: [27] register wider than consumer reads · [28] wide bus through hierarchy · [29] mirror-copy register · [30] counter wider than `$clog2(N)` · [31] sign bit where unsigned suffices.
Era faithfulness: [32] shared resource replaced by N copies · [33] pipeline changes external cycle count · [34] linear software FSM instead of chip bus/control · [35] 16/32-bit datapath in 8-bit chip · [36] multi-port memory where chip had single-port + arbitration · [37] barrel shifter where chip shifted 1 bit/cycle.
Timing/verification: [72] no SDC · [73] I/O register not in IOE · [74] `set_false_path` to hide a real path · [75] `set_multicycle_path` without RTL evidence · [76] synthesis warnings ignored · [77] inferred resource not confirmed in Fitter · [78] no scoreboard · [79] SVA re-implements the DUT · [80] `assume` where `assert` was meant.

---

## 14. Core bring-up checklist (sequential gates; each must pass before the next; failing items get a written rationale, never silence)

- **Gate 1 — Plan**: pre-RTL plan predates RTL; names clocks, reset, throughput, latency, widths/signedness/saturation, resource strategy, flow control per boundary; emulation addendum (chip, width, control style, bus, memory ports, external cycle counts).
- **Gate 2 — Clock/reset**: every flop on a clock network; no fabric-derived clock; every reset sync-released or synchronous; one polarity; clock-enable instead of gating.
- **Gate 3 — Subset**: `` `default_nettype none ``; `always_ff`/`<=`, `always_comb`/`=`, no mixing; one driver; no latch warnings; no comb loops; `logic` except `inout`; sized literals; signed discipline; one concern per block; explicit-storage enums.
- **Gate 4 — FSM/pipeline**: two-block split; enum type; named reset state; `default:` arm; no `casex`/pragmas; valid follows data; external cycle counts unchanged; every pipeline register justified by a named path; cycle schedule exists.
- **Gate 5 — Handshake/CDC**: no valid-drop; payload stable; advance only on `valid && ready`; `valid` not comb-dependent on `ready`; skid = 2 entries with registered `o_ready`; FIFOs conformant both ports; async FIFO Gray pointers + 2FF + own-domain full/empty; single-bit CDC in dedicated tagged module fed from a register; pulses via toggle; one bit per crossing; SDC exception for every async path.
- **Gate 6 — Inference**: every RAM on intended tier in Fitter; canonical template; explicit RDW; every multiplier on DSP with I/O registers and `signed`; no `/`,`%`, variable shift on critical path; every Removed/Merged/Stuck/no-driver/no-fanout/latch line resolved; counters `$clog2(N)`; accumulators `W + $clog2(K)`; zero width-mismatch warnings.
- **Gate 7 — Timing**: SDC committed, `check_timing` clean; `create_clock` per primary; `derive_pll_clocks`; I/O delays `-max`/`-min`; `derive_clock_uncertainty`; setup/hold/recovery/removal ≥ 0 or written waiver; every exception has a one-line RTL justification.
- **Gate 8 — Verification**: Report Metastability reviewed, every crossing has MTBF; scoreboarded TB per module; three SVAs per handshake, bound and enabled; assert/assume not swapped; reset coverage; no `X` don't-cares.
- **Gate 9 — Era (emulation only)**: datapath width = chip; external interfaces cycle-exact; no internal tri-state; shared ALU/shifter/bus preserved; no DSP where chip iterated; control style matches; small register files in flops.
- **Gate 10 — Economy**: justification comment per register; every bus bit justified; no defensive 2FF; no spurious `signed`; no mergeable states; no mux > 8:1 in one stage; no mirror copies; no unread high bits.
See `91-core-bringup-checklist.md`.

---

## 15. Review checklist (run over a diff)

For each changed `always` block: kind matches assignment style; one concern; reset first; defaults at top of every `always_comb`; every `case` has `default:`; no name both assigned and later read in the same comb block.
For each new signal/register: one driver; sized literals; `signed` justified; width = `$clog2`/`W + $clog2(K)` where applicable; `// Justification:` present; not a mirror of an existing register; consumer reads all bits.
For each new clock/reset use: clock from network; reset polarity consistent and sync-released; no comb term into an async-clear.
For each handshake touched: `valid`/payload change only when `!valid || ready`; consumer acts on `valid && ready` plus nothing; no `valid = f(ready)`; `ready` chain still ≤ one LAB or a skid buffer inserted with registered `o_ready`.
For each memory/arbiter touched: read data captured on a qualifier that travels with it, never at a fixed count; data+qualifier share one enable; registered read; RDW style explicit; grant one-hot with `default:`; port topology matches the plan/original chip.
For each CDC touched: source is a register; dedicated tagged 2FF module; pulses as toggles; multi-bit via FIFO/MCP/Gray only; SDC `set_clock_groups`/`set_false_path` updated; pattern named in the module header.
For each `*`, `/`, `%`, `<<`, `a[idx]`, wide `case`: cost annotated; off the critical path or pipelined; DSP/strength-reduction expectation commented.
For each SDC change: exception has an RTL-evidence comment; multicycle `-setup N` paired with `-hold N-1`; `check_timing` clean.
For emulation-core changes: no externally observable cycle count moved; no un-sharing of a shared resource; module header cites the chip subsystem it mirrors; cycle-trace regression re-run.
Post-compile evidence attached: new Synthesis warnings resolved; Fitter tier confirmation for any new RAM/DSP; setup/hold/recovery/removal slack; Report Metastability row for any new crossing; TB `PASS` and SVA log.
