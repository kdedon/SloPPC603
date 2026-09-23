# MPC603e external bus source contract

**Status:** source transcription for P02b. This document and the JSON manifests define evidence for later bus RTL/BFM work; they do not claim that a 60x pin interface exists in RTL. The current `imem_*` scaffold remains a word-fetch transport.

The primary source is the local *MPC603e & EC603e RISC Microprocessors User's Manual*, `1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf` (MPC603EUM/AD, 11/97). Physical PDF pages are used below. Chapter 7 is PDF 277–308 / printed 7-1–7-32; Chapter 8 is PDF 309–354 / printed 8-1–8-46. `docs/SOURCES.md` records source precedence and PID7v qualifications.

Signal direction is from the processor's point of view. Manual signal names are preserved. “Low” means the rendered manual shows an overbar; it was not inferred from extracted plain text. Encoded buses and clocks do not have a Boolean active level. Later RTL must map external low assertion to an internal positive assertion explicitly.

Machine-readable forms:

- `sim/spec/bus_signals.json`: 54 grouped signal records, 170 named logical bits if each grouped width is summed. Supply-group width is logical and is not a package pin count.
- `sim/spec/bus_scenarios.json`: all 23 Chapter 8 figures inventoried, 19 source scenarios, and 12 selected relative-event cycle tables.
- `sim/spec/bus_encodings.json`: all Table 7-1/7-2 TT values, PID7v Table 7-3 HID0[ABE] overlays, and all nine Table 7-5 `TBST`/`TSIZ` combinations. See `docs/BUS_ENCODINGS.md`.

## Interface rules that cross signal groups

Address and data arbitration are independent. A qualified address grant is `BG` asserted while `ABB` is negated and the `ARTRY` result following the preceding `AACK` is negated. A qualified data grant is `DBG` asserted while `DBB` and `DRTRY` are negated and the `ARTRY` result belonging to that queued address tenure is negated. These are logical conditions over active-low pins, not voltage-level Boolean formulas. UM §§8.3.1 and 8.4.1, PDF 317–319 and 330–331 / printed 8-9–8-11 and 8-22–8-23.

The processor implements one additional level of address pipelining: up to two address tenures can complete before the current data tenure completes. Up to two data tenures can be queued. Data follows address order unless a qualified `DBG` samples `DBWO` asserted to select a queued write ahead of an older read. `DBWO` does not reorder writes with respect to writes, and selects the next read if no write is pending. UM §§8.2, 8.4.2, and 8.10, PDF 316–317, 332, 351–354 / printed 8-8–8-9, 8-24, 8-43–8-46.

Shared bidirectional pins are three-stated between tenures. Processor address and attributes remain driven through `AACK` and become high impedance one bus clock later. Processor write data remains driven through the final/only `TA` and becomes high impedance on the following bus clock. `ABB` and `DBB` use half-clock negation before release. On a read, `DRTRY` can extend data-bus mastership exclusion after the prior master has negated `DBB`; it does not require `DBB` to stay asserted. `ARTRY` uses its special shared-response release sequence: high impedance for one-half processor clock, driven negated for one bus clock, then high impedance unless precharge is disabled. UM Chapter 7 signal timing and §8.5, PDF 280–298 and 340 / printed 7-4–7-22 and 8-32.

`ARTRY` retries the whole transaction. It can assert early during address tenure and must remain asserted through the cycle after `AACK`; assertion in that following cycle is the qualified retry. If the associated data tenure already began, it is aborted. In normal DRTRY mode, the generic/64-bit late-cancel boundary is the cycle after the first/only `TA`. In 32-bit mode it is after the first `TA` for word or smaller transfers, but after the second `TA` for double-word or burst transfers. UM §§7.2.5.2, 8.3.3, and 8.6.1, PDF 290–291, 328–330, and 346 / printed 7-14–7-15, 8-20–8-22, and 8-38.

`TA` acknowledges one beat. On reads in normal DRTRY mode, that beat remains provisional until `DRTRY` is sampled negated on the following clock. `DRTRY` asserted in that following cycle invalidates the beat and may extend exclusion for several cycles. Before `DRTRY` is finally negated, valid data must have appeared with `TA` on the previous clock. Writes ignore `DRTRY`, although an asserted `DRTRY` can still prevent another master's qualified data grant. UM §§7.2.8.1–7.2.8.2 and 8.4.4, PDF 297–298 and 333–337 / printed 7-21–7-22 and 8-25–8-29.

`TEA` has priority over `TA` and `DRTRY`: it terminates the current transaction and causes `DBB` release in the next clock if `DBB` is still asserted. Chapter 7 permits it while `DBB` is asserted or, for a read, in the cycle after `TA`; the more detailed §8.4.4.2 explicitly permits it while `DBB` and/or `DRTRY` is asserted. A BFM must therefore allow `TEA` during a multi-cycle read `DRTRY` extension after `DBB` negates. It does not invalidate data already admitted to a GPR or cache, and the implementation does not identify the causal instruction or latch its address. UM §§7.2.8.3 and 8.4.4.2, PDF 299 and 337 / printed 7-23 and 8-29.

## Complete signal inventory

The tables below summarize every logical group in rendered Figure 7-1 plus the power groups in §7.2.13. Exact qualification, release, reset, mode, and source fields live on every record in `sim/spec/bus_signals.json`.

### Address, data, and termination

| Signal | Width | Direction | Active/meaning | Processor drive and qualification |
|---|---:|---|---|---|
| `BR` | 1 | out | low | Dedicated request; may cancel; retained around accepted grant/retry rules. |
| `BG` | 1 | in | low | Accepted only as a qualified address grant; not accepted between `TS` and `AACK`. |
| `ABB` | 1 | bidirectional | low | Shared address ownership; asserted after qualified `BG`, half-clock negation then high-Z after `AACK`. |
| `TS` | 1 | bidirectional | low | Processor drives one cycle with `ABB`; as input defines the one snoop-sampling cycle. |
| `A[0:31]` | 32 | bidirectional | encoded | Driven with processor address tenure through `AACK`; sampled as snoop address only with `TS`. |
| `AP[0:3]` | 4 | bidirectional | odd parity | One bit per address byte; address timing. HID0 parity control; tracking/reduced-pin modes alter use. |
| `APE` | 1 | out, open drain | low | Address parity error two cycles after snooped `TS`; released in third cycle. HID0[EBA] enables it. |
| `TT[0:4]` | 5 | bidirectional | encoded | Address timing; Tables 7-1/7-2 define commands and snoop action, Table 7-3 PID7v HID0[ABE] overrides. Input-width wording conflict remains open. |
| `TBST` | 1 | bidirectional | low | Address timing; asserted for cache-line burst. A 32-bit uncached 8-byte two-beat transfer leaves it negated. |
| `TSIZ[0:2]` | 3 | out | encoded | Address timing; with `TBST` selects transfer size. |
| `GBL` | 1 | bidirectional | low | Address timing; output marks global transaction, input qualifies snooping. |
| `CI` | 1 | out | low | Address timing; caching inhibited. |
| `WT` | 1 | out | low | Address timing; write through. |
| `CSE[0:1]` | 2 | out | encoded | Address timing; cache-set element 0–3. |
| `TC[0:1]` | 2 | out | encoded | Address timing; privilege and instruction/data transfer code. |
| `AACK` | 1 | in | low | One-cycle address termination. Earliest cycle after `TS`, subject to legacy 1:1/1.5:1 wait restriction. |
| `ARTRY` | 1 | bidirectional | low | Shared retry response with unique release sequence; qualified in cycle after `AACK`. |
| `DBG` | 1 | in | low | Accepted only as qualified data grant. |
| `DBWO` | 1 | in | low | Sampled only with qualified `DBG`; selects queued write before older read. |
| `DBB` | 1 | bidirectional | low | Shared data ownership; asserted after qualified `DBG`, half-clock negation then high-Z after final `TA`; `DRTRY` can extend exclusion after `DBB` negates. |
| `DH[0:31]` | 32 | bidirectional | data | High four byte lanes; sole data lanes in 32-bit mode. Read input/write output. |
| `DL[0:31]` | 32 | bidirectional | data | Low four byte lanes in 64-bit mode; ignored on 32-bit reads and driven low on 32-bit writes. |
| `DP[0:7]` | 8 | bidirectional | odd parity | One per data byte; follows data timing. HID0 tracking/reduced-pin modes alter use. |
| `DPE` | 1 | out, open drain | low | Data parity error two cycles after `TA` unless cancelled by `DRTRY`; released in third cycle. |
| `DBDIS` | 1 | in | low | Write-only control; makes data/parity high-Z next cycle but does not end `DBB` tenure. |
| `TA` | 1 | in | low | Acknowledges each data beat; may be withheld for wait states. |
| `DRTRY` | 1 | in | low | Read late-cancel/confirmation and startup mode strap. |
| `TEA` | 1 | in | low | One-cycle fatal transfer termination; overrides `TA`/`DRTRY`; allowed during extended read `DRTRY` even after `DBB` negates. |

Sources: UM §§7.2.1–7.2.8, PDF 280–299 / printed 7-4–7-23; operational qualification in Chapter 8.

### Interrupt, reset, status, clock, and test

| Signal | Width | Direction | Active/meaning | Qualification, output enable, reset, or mode role |
|---|---:|---|---|---|
| `INT` | 1 | in | low | Asynchronous level-sensitive interrupt; hold until taken; MSR[EE]-qualified. |
| `SMI` | 1 | in | low | Asynchronous level-sensitive system-management interrupt; hold until taken. |
| `MCP` | 1 | in | low | Asynchronous negative-edge machine check; hold two bus clocks; HID0[EMCP]/MSR[ME]-qualified. |
| `CKSTP_IN` | 1 | in | low | Asynchronous nonmaskable stop; hold until reset; releases all processor outputs except `CKSTP_OUT`. |
| `CKSTP_OUT` | 1 | out, open drain | low | Asynchronous stopped indication; negated by `HRESET`. |
| `HRESET` | 1 | in | low | Asynchronous hard reset; outputs high-Z within five clocks; hold 255 clocks after PLL lock. |
| `SRESET` | 1 | in | low | Asynchronous negative-edge soft reset; may negate after two bus clocks. |
| `RSRV` | 1 | out | low | Synchronous reservation state; disabled in reduced-pinout mode. |
| `QREQ` | 1 | out | low | May assert any cycle; held through quiescent state. |
| `QACK` | 1 | in | low | After `QREQ`, hold at least one clock. Startup strap selects full/reduced pinout. |
| `TBEN` | 1 | in | low | May change any cycle; asserted enables time-base count. |
| `TLBISYNC` | 1 | in | low | Stalls after `tlbsync`; startup strap selects 32/64-bit data bus. |
| `SYSCLK` | 1 | in | clock | Bus clock and PLL reference; cannot be stopped or varied during normal operation. |
| `CLK_OUT` | 1 | out/tri-state | clock | High-Z by default; HID0 selects CPU, bus, or half-bus test clock. PID7v drives CPU clock during `HRESET`. |
| `PLL_CFG[0:3]` | 4 | in | encoded | Stable in operation; change only under `HRESET` or sleep. PID-specific ratio limits apply. |
| `TDI` | 1 | in, weak pull-up | data | JTAG serial input, latched on rising `TCK`. |
| `TDO` | 1 | out | data | JTAG serial output; no weak pull-up. |
| `TMS` | 1 | in, weak pull-up | encoded control | TAP mode input, sampled with rising `TCK`. |
| `TCK` | 1 | in, weak pull-up | clock | JTAG scan clock. |
| `TRST` | 1 | in, weak pull-up | low | Asynchronous TAP reset; may coincide with `HRESET`. |
| `TEST[0:2]` | 3 | bidirectional test | unresolved | LSSD controls shown in Figure 7-1; operation and required tie states are outside this manual. |

Sources: UM §§7.2.9–7.2.12, PDF 299–307 / printed 7-23–7-31; JTAG Table 8-10, PDF 350 / printed 8-42.

### Power

| Signal | Direction | Meaning and limit |
|---|---|---|
| `VDD` | supply | Core-named supply; this manual says no electrical distinction from `OVDD`. |
| `OVDD` | supply | I/O-named supply; this manual says no electrical distinction from `VDD`. |
| `AVDD` | supply | PLL supply; connection details require hardware specifications. |
| `GND` | ground | Core-named ground; no electrical distinction from `OGND` in this manual. |
| `OGND` | ground | I/O-named ground; no electrical distinction from `GND` in this manual. |

Source: UM §7.2.13, PDF 308 / printed 7-32. Package multiplicity and pin numbers are intentionally absent because the manual points to the PID hardware specification.

## Startup mode sampling

`HRESET` negation samples three otherwise operational active-low pins:

| Sampled pin | Asserted at `HRESET` negation | Negated at `HRESET` negation | Source |
|---|---|---|---|
| `DRTRY` | no-DRTRY mode | normal late-cancel mode | §8.6.2, PDF 348 / 8-40 |
| `TLBISYNC` | 32-bit data bus | 64-bit data bus | §8.6.1, PDF 347 / 8-39 |
| `QACK` | full pinout | reduced pinout, which also selects 32-bit data | §8.6.3, PDF 348–349 / 8-40–8-41 |

In 32-bit mode, only `DH[0:31]` and `DP[0:3]` carry data/parity. Operations of four bytes or less use one beat; uncached/write-through eight-byte operations use two beats without asserting `TBST`; cache-line transfers use eight beats with `TBST` asserted and `TSIZ=0b010`. In reduced-pinout mode `DL`, `DP`, `AP`, `APE`, `DPE`, and `RSRV` are disabled; disabled bidirectional/output pins drive low when normally driven, open-drain error pins remain high-Z, and disabled input receivers do not sample. UM §§8.6.1 and 8.6.3, PDF 346–349 / printed 8-38–8-41.

## Source cycle tables

Rows name rising `SYSCLK` boundaries. “After edge” describes the cycle that begins at that boundary. These are selected relative-event sketches: symbolic rows such as `TA`, wait, and later capture the relationships needed for the initial contract. They are not exhaustive per-pin/per-edge waveforms or complete BFM expectations, and they do not specify AC setup/hold.

### Initial minimum address tenure — Figure 8-6

UM §8.3.2, PDF 320 / printed 8-12 says arbitration is cycle 0, transfer occupies cycles 1–2, and termination is cycle 3.

| Cycle edge | Sampled at edge | After edge |
|---|---|---|
| 0 | `BG` asserted, request pending | Qualified grant becomes available for edge 1. |
| 1 | CPU accepts qualified `BG` | CPU asserts `ABB` and one-cycle `TS`; drives address and attributes. |
| 2 | Responder samples `TS`, address, attributes | CPU negates `TS`; holds address group and `ABB`; responder asserts `AACK`. |
| 3 | CPU samples `AACK` asserted | CPU negates `ABB`; address group begins specified release; qualified-`ARTRY` window follows. |
| 4 | `ARTRY` negated | Address tenure is accepted; shared address group is idle/high-Z absent a new tenure. |

### Initial normal single-beat read — Figure 8-9

UM §8.4.4.1, PDF 334 / printed 8-26.

| Relative edge | Sampled at edge | After edge |
|---|---|---|
| `QDBG` | CPU accepts qualified `DBG` | CPU asserts `DBB`; responder drives read data. |
| `QDBG+1` | CPU samples data and asserted `TA` | Beat is provisional for the one-cycle late-cancel window; CPU begins `DBB` release. |
| `QDBG+2` | CPU samples `DRTRY` negated | Previous beat is valid; shared data pins are idle/high-Z. |

Normal read completion requires `TEA` and `DRTRY` to remain negated. `TA` alone is not final read validity in normal DRTRY mode.

### Initial normal single-beat write — Figure 8-10

UM §8.4.4.1, PDF 335 / printed 8-27.

| Relative edge | Sampled at edge | After edge |
|---|---|---|
| `QDBG` | CPU accepts qualified `DBG` | CPU asserts `DBB` and drives data/parity. |
| `QDBG+1` | Responder accepts data with asserted `TA` | CPU negates `DBB` and stops driving data under the release rule. |
| `QDBG+2` | Tenure complete | Shared data pins are idle/high-Z. |

`DRTRY` is ignored on writes. `TEA` must remain negated for normal completion.

### Qualified address retry — Figure 8-7

UM §8.3.3, PDF 330 / printed 8-22.

| Relative edge | Sampled at edge | After edge |
|---|---|---|
| `TS` | Snooper samples address, `TT`, and asserted `GBL` | Snoop lookup begins. |
| `AACK` | Master and snooper sample address termination | Retry source holds `ARTRY` asserted through the next cycle. |
| `AACK+1` | Master samples qualified `ARTRY` | Whole transaction is aborted; data tenure is prevented or immediately aborted; snooper may request copyback. |
| `AACK+2` | Retried master ignores `BG` | Only the retrying snooper may make the new priority request under this protocol rule. |
| later qualified `BG` | Snooper accepts grant | Snooper starts the copyback address tenure. |

### Read-data retry — Figure 8-12

UM §8.4.4.1, PDF 336 / printed 8-28.

| Relative edge | Sampled at edge | After edge |
|---|---|---|
| `TA` | CPU samples a read beat with `TA` | Beat is provisional. |
| `TA+1` | CPU samples `DRTRY` asserted | Prior data is invalid; `DBB` may already be negated, while data-bus mastership exclusion remains extended. |
| wait | `DRTRY` remains asserted while `DBB` is negated | Other masters cannot assert `DBB` or obtain a qualified data grant. |
| final asserted-`DRTRY` cycle | CPU samples replacement valid data with `TA` | Responder prepares to negate `DRTRY`. |
| `DRTRY` negation | CPU samples `DRTRY` negated | Data presented with `TA` on the prior clock is valid; extended exclusion can finish. |

### Burst TA pacing and data retry — Figure 8-13

The controlling TA/DRTRY prose is in UM §8.4.4.1, PDF 336 / printed
8-28. The rendered figure is placed at the start of §8.4.4.2, PDF 337 /
printed 8-29. The surrounding normal-burst context is a four-beat 64-bit
transfer. Figure 8-13 itself does not print a bus width, so the manifest
records that contextual basis rather than treating the width as a label read
from the figure. Normal DRTRY mode is required.

| Relative edge or labeled cycle | Sampled at edge | After edge / during labeled cycle |
|---|---|---|
| qualified `DBG` | CPU accepts the qualified grant | CPU asserts active-low `DBB`; the responding slave may drive read data. |
| Figure bus clock 3 | The figure does not label the data value or identify the beat sampled at this edge | `TA` is negated during the labeled cycle, inserting a wait; the pipeline does not advance. |
| Figure bus clock 4 | The pending second beat remains selected after the wait | The responder reasserts `TA` during the labeled cycle and the pipeline resumes. |
| provisional `TA` | CPU samples a read beat with active-low `TA` asserted | The data remains provisional through the immediately following `DRTRY` sample. |
| provisional `TA + 1` | CPU samples active-low `DRTRY` asserted | Data acknowledged on the preceding bus clock is invalidated and the beat is extended. |
| replacement `TA` while `DRTRY` asserted | CPU samples replacement data with `TA` | Responder prepares to negate `DRTRY` on the next bus clock. |
| `DRTRY` negation | CPU samples `DRTRY` negated | Replacement data presented with `TA` on the preceding clock becomes valid; the burst may continue. |

The rendered waveform draws the `TA` transition inside labeled cycle 3: it is
still low at the left rising boundary and then negates. The table therefore
does not claim that `TA` was already high at that boundary. It records the
prose-backed during-cycle wait and cycle-4 reassertion. Other apparent
intra-cycle offsets are not exact timing values.

During this read tenure the CPU drives `DBB`; the responding slave drives
data, `TA`, and `DRTRY`; and the CPU samples the latter three at rising
`SYSCLK` edges. `TA`, `DRTRY`, `DBB`, and the external `DBG` pin are active
low. The plotted qualified-`DBG` row is a derived internal condition, not a
separate pin. The data polygons have no printed values or beat ordinals, and
Figure 8-13 has no `TEA` row. The manifest keeps both facts unresolved rather
than assigning them from waveform shape.

### Fastest single-beat read pipeline — Figure 8-15

UM §8.5, PDF 340 / printed 8-32, with split-transaction context from §8.2.2,
PDF 316 / printed 8-8, and data/termination rules from §§8.4.3–8.4.4.1, PDF
332–334 / printed 8-24–8-26. The figure explicitly labels `D[0–63]`, three
`Read` address tenures, and negated `TBST`, so the selected profile contains
three pipelined 64-bit-bus single-beat reads. It selects normal DRTRY mode only
to state the following-cycle confirmation rule; that mode selection is not
inferred from the figure's always-negated `DRTRY` row.

| Relative event or condition | Observation | Result |
|---|---|---|
| Displayed fastest read 1 | CPU samples the first `In` data with `TA` for its associated address tenure. Address completion need not precede or occupy a different edge. | The beat remains provisional until the following negated `DRTRY` sample under the selected normal profile. |
| Displayed fastest read 2 | CPU samples the second `In` with `TA`; address and data tenure completion may overlap. | The following negated `DRTRY` confirms it without a source-described data wait. |
| Displayed fastest read 3 | CPU samples the third `In` with `TA`; prior data latency has not delayed its address tenure. | Following confirmation completes the source's maximum-throughput example, without defining architectural delivery timing. |
| Conditional data delay below the third-address boundary | A data tenure is delayed while the third address can still proceed without delay. | That read's latency increases, but split-transaction pipelining preserves overall throughput. |
| Conditional delay at the third-address boundary | Data-bus latency delays the third address tenure itself. | The source's unaffected-throughput statement no longer applies; it gives no amount of throughput change. |

“Fastest,” “minimum latency,” and “maximum throughput” are qualitative source
descriptions of this external bus example. They do not create numeric cycle
bounds or architectural instruction, cache-fill, or GPR-delivery latency.
Address and data buses remain independent; associating each `In`/`TA` event
with its address does not require the address tenure to finish first.

The conditional rows also avoid strengthening the word “unless.” A delayed
data tenure leaves throughput unaffected while the third address stays on the
displayed cadence. If the third address is delayed, the unaffected-throughput
guarantee ends, but the manual does not quantify or mandate a particular loss.
Exact 1–12 edge values, delay threshold, arbitration and queue state, `In`
values/lanes/parity, and every three-state transition remain unresolved. This
is not a full waveform, BFM, or RTL contract.

### Single-beat read delay controls — Figure 8-17

UM §8.5, PDF 342 / printed 8-34, with pin roles and termination rules from
§§7.2.6.1, 7.2.6.3, 7.2.7.1, 7.2.8.1, and 7.2.8.2, PDF 292–298 / printed
7-16–7-22. The figure explicitly labels `D[0–63]`, three `Read` address
tenures, and negated `TBST`, so this scenario is limited to three pipelined
64-bit-bus single-beat reads in normal DRTRY mode. `ARTRY` and `TEA` stay
negated in the selected sequence.

| Relative edge or labeled cycle | Observation at the left/sample edge | After edge / during labeled cycle |
|---|---|---|
| Figure clock 3 | No exact `TA` value is assigned to the left rising boundary from the drawn transition. | `TA` remains negated during clock 3 and inserts the first stated wait cycle. |
| Figure clock 4 | The first access remains pending after the clock-3 wait. | `TA` remains negated during clock 4 and inserts the second stated wait cycle. |
| Figure clock 6, second access | The prose does not say a qualified `DBG` was sampled at the left boundary. | `DBG` *could have been* asserted during clock 6. This identifies an available grant opportunity, not a required assertion. |
| Figure clock 11, third access | The drawn `DRTRY` transition occurs after the left rising boundary. | `DRTRY` asserts during clock 11 and flushes the preceding data polygon labeled `Bad`. |
| First sample edge after that transition | CPU samples active-low `DRTRY` asserted. | The preceding acknowledged read data is invalidated. The bus label does not identify an architectural destination or rollback. |

The shown pipelining is conditional: the manual says the second access must
not be another load and gives an instruction fetch as an example. That example
is not converted into a required transaction type. The manifest also keeps
the source's modality for clock 6; “could have been asserted” is not rewritten
as an actual or mandatory `DBG` acceptance.

All bidirectional signals are three-stated between bus tenures, but the manual
does not state every entry and release edge in the accompanying prose. Exact
left-edge values for the within-cycle transitions, complete `Bad`/`In` polygon
mapping, and all other apparent pin changes remain unresolved. This table is a
bounded protocol slice rather than a full Figure 8-17 waveform or a BFM
specification.

### Single-beat write delay controls — Figure 8-18

UM §8.5, PDF 343 / printed 8-35, with grant, drive, and termination rules from
§§8.4.4.1, 7.2.6.1, 7.2.6.3, 7.2.7.1, 7.2.8.1, and 7.2.8.2, PDF 292–298 and
336 / printed 7-16–7-22 and 8-28. The figure explicitly labels `D[0–63]`,
three `SBW` address tenures, and negated `TBST`, so this scenario is limited to
three pipelined 64-bit-bus single-beat writes. `ARTRY` and `TEA` stay negated.

| Relative edge or labeled cycle | Observation at the left/sample edge | After edge / during labeled cycle |
|---|---|---|
| Figure clock 3 | No exact `TA` value is assigned to the left rising boundary from the drawn transition. | `TA` is held negated during clock 3, inserting the first wait; the pending write beat is not acknowledged. |
| Figure clock 4 | The first write remains pending after the clock-3 wait. | `TA` remains negated during clock 4, inserting the second wait while the same beat remains pending. |
| Figure clock 6, second access | No exact `DBG` value is assigned to the left rising boundary. | `DBG` is held negated during clock 6, delaying the start of the second data tenure. |
| Later qualified `DBG`, second access | CPU accepts a qualified grant; no numeric figure clock is assigned. | CPU asserts `DBB` and begins driving the second single write beat. |
| Final access qualified `DBG` | CPU accepts a qualified grant for the final access. | CPU asserts `DBB` and drives the last beat; the source describes this access as not delayed. |
| Final access `TA` | CPU samples `TA` asserted with the final write beat. | The tenure terminates and ordinary `DBB`/data release follows. `DRTRY` has no write-completion role. |

The `TA` and `DBG` delays are distinct. Negated `TA` keeps an already-started
write beat pending; negated `DBG` prevents a qualified grant and postpones the
data-tenure start. The final access has neither displayed delay, but this
example is not generalized into an absolute grant-to-`TA` latency.

`DRTRY` is valid only for read data cancellation, and Figure 8-18 draws it
negated throughout. That does not remove it from data-grant qualification: an
asserted `DRTRY` left by a preceding read can still exclude another master and
prevent a qualified `DBG`, indirectly delaying a later write tenure. The
manifest preserves that arbitration effect separately from write completion.
Exact within-cycle pin values, `Out` data/parity values, and every three-state
entry/release edge remain unresolved; this is not a full waveform or BFM
specification.

### Burst delay controls — Figure 8-19

UM §8.5, PDF 344 / printed 8-36, with 64-bit burst and termination rules from
§§8.4.3–8.4.4.1, PDF 332–336 / printed 8-24–8-28, and pin roles from Chapter
7, PDF 282–298 / printed 7-6–7-22. The figure explicitly labels `D[0–63]`,
asserted `TBST`, and three transfer types in order: `Read`, `Write`, `Read`.
Each is therefore bounded here as a four-beat 64-bit burst. Normal DRTRY mode
is required by the final read's retry.

| Relative event | Observation at event | Result |
|---|---|---|
| Source “clock 0,” first read `In 0` | The first read presents `In 0`; this is not mapped to the displayed 1–20 axis. | Figure 8-19 calls it the “critical quad word”; §8.4.3 instead says “critical double word first.” Both terms remain recorded. |
| First transfer completion | The first read has presented `In 0`, `In 1`, `In 2`, and `In 3`. | The ordering condition that held off the third address is satisfied. |
| Third transfer address start | Only after the first transfer completes may this tenure begin. | CPU asserts `TS` and drives the third address with Read/burst attributes; no numeric edge is assigned. |
| Write third beat, `Out 2` pending | CPU presents the middle write's third labeled beat. | Negated `TA` leaves `Out 2` unacknowledged and prevents advance to `Out 3`. |
| Write third beat accepted | CPU later samples `TA` asserted for `Out 2`. | The burst advances to `Out 3`. |
| Final read third beat, first `In 2` | CPU samples the first `In 2` with `TA`. | The beat remains provisional through the following `DRTRY` sample. |
| Following retry sample | CPU samples active-low `DRTRY` asserted one clock after that `TA`. | The first `In 2` is invalidated and the third beat remains pending. |
| Replacement `In 2` | CPU samples the repeated `In 2` with `TA` during the retry extension. | Responder prepares to negate `DRTRY` on the following clock. |
| `DRTRY` negation | CPU samples `DRTRY` negated. | The replacement `In 2` becomes valid and the burst may advance. |
| Final `In 3` | CPU may sample the fourth labeled beat with `TA` on the same edge that negated `DRTRY` confirms replacement `In 2`, or later. | No extra bubble is required; ordinary DRTRY confirmation can complete the final read. |

The address constraint is deliberately relative: the third transfer's address
waits for the first transfer to complete, while the second address may overlap
the first data tenure. The manual does not identify a numeric release edge for
the third address. It likewise identifies `TA` negation on write beat three and
`DRTRY` on final-read beat three without giving numeric clock labels. The
manifest therefore preserves beat ordering and termination semantics without
deriving wait lengths from waveform width.

The rows are ordered protocol events and need not occupy distinct edges. In
particular, the final `In 3` acceptance may coincide with the `DRTRY`-negation
edge that confirms replacement `In 2`; the table does not impose a bubble.

The phrase “clock 0” conflicts with the rendered 1–20 axis, and “critical quad
word” conflicts with the surrounding 64-bit “critical double word” prose.
Neither is silently corrected. The `In`/`Out` polygons name ordinal beats but
do not supply values, lanes, parity, effective addresses, or cache-line wrap
order. Remaining pin transitions and three-state entry/release edges are also
unresolved. This is not a full every-edge waveform, BFM, or RTL contract.

### Transfer error — Figure 8-20

UM §§8.4.4.2 and 8.5, PDF 337 and 345 / printed 8-29 and 8-37. Figure 8-20 shows `TEA` truncating a burst write on its third displayed beat.

| Relative edge | Sampled at edge | After edge |
|---|---|---|
| beat N | CPU drives write beat while `DBB` is asserted | Responder asserts `TEA` for one cycle. |
| `TEA` | CPU samples `TEA`; `TA`/`DRTRY` are ignored | Transaction terminates; CPU negates `DBB` and stops the burst. |
| `TEA+1` | `DBB`/data are released; `TEA` is negated no later than this | CPU eventually takes machine-check/checkstop behavior according to state. |

## Scenario matrix

`sim/spec/bus_scenarios.json` records these scenarios with source/status:

| Area | Manifested behavior | Remaining work |
|---|---|---|
| Tenures and grants | Independent address/data ownership; qualified `BG`/`DBG`; Figure 8-15 fastest read pipeline; Figure 8-17/8-18 data-grant delays; Figure 8-19 third-address ordering; parking source identified. | Transcribe Figures 8-3–8-5 and 8-8 fully edge by edge. |
| `ARTRY` | Early/qualified retry, whole-transaction abort, late first-beat invalidation, snooper copyback priority. | Enumerate collision timing for every first/final burst beat and no-DRTRY mode. |
| `DRTRY` | Normal read confirmation, multi-cycle retry extension, writes ignored for completion, startup disable, bounded Figure 8-13 burst pacing/replacement rows, Figure 8-17's clock-11 single-beat cancellation, Figure 8-18's write/arbitration distinction, and Figure 8-19's repeated third read beat. | Figure 8-22 beat rows and the selected figures' remaining untranscribed per-pin transitions. |
| `TEA` | Priority over `TA`/`DRTRY`, next-cycle `DBB` release, burst truncation. | Enumerate all read/write and late-error collisions. |
| Bursts | 64-bit four-beat rule, bounded Figure 8-13 and 8-19 TA/DRTRY pacing, Figure 8-19 mixed read/write/read ordering, 32-bit eight-beat rule, `TBST` distinctions. | Complete Figure 8-11 edges, selected-figure remaining edges, and all critical-word wraps. |
| 32-bit | `DH`/`DP0:3`, one/two/eight beats, startup selection, late-`ARTRY` boundary, and Tables 8-6/8-7 lane/address rows. | Figure 8-21/8-22 edges and cache-burst ordering. |
| `DBWO` | Figure 8-23 read-address/write-address/write-data/read-data sequence and fallbacks. | Couple to future queue assertions; verify `eieio` treatment. |
| Snoops | `TS` sampling, `GBL`, TT command action, MEI state source, modified-line `ARTRY`/push. Table 7-2 TT actions are now machine-readable in `bus_encodings.json`. | Transcribe WIM-conditioned state transitions and copyback beats. |

The explicit Chapter 8 diagram inventory contains all 23 figures. Four remain `inventory_only`: Figures 8-3, 8-4, 8-5, and 8-16. Figures 8-1 and 8-2 are context/notation. Twelve have selected relative-event cycle tables, and five have source-backed rule transcriptions without complete per-edge rows. None of the twelve is a complete every-pin waveform.

## Fidelity boundaries and unresolved rules

- The PID7v core-to-bus ratios are 2:1 through 6:1, including half steps; PID7v expressly lacks 1:1 and 1.5:1. The present single-clock FPGA scaffold is a disclosed bootstrap simplification, not a supported PID7v clock mode. Exact clock crossing and electrical PLL behavior remain open. UM §1.1, PDF 44–45 / printed 1-4–1-5.
- `docs/BUS_ENCODINGS.md` and `sim/spec/bus_encodings.json` transcribe Tables 7-1, 7-2, 7-3, and 7-5. The bounded address contract transcribes Tables 8-4 through 8-7. Remaining TC/parity/cache-state tables and encoding matrices require their own source checks. Future BFM assertions must not substitute inferred values for those gaps.
- Complete big/little-endian CPU-pin lane steering is unresolved for cacheable/uncached and 32/64-bit modes. The MCM's 660 bridge transformation is system evidence, not permission to impose bridge behavior at CPU pins.
- Physical setup/hold, pulse width, package pins, pull-up sizing, PLL lock, voltage limits, and mask errata require the missing PID7v hardware specification. The logical cycle tables cannot close those requirements.
- `TEST[0:2]` LSSD behavior is outside the user's manual. Normal-system tie requirements remain unresolved.
- Figure 7-1 and the §7.2.4.1 introduction identify all five `TT[0:4]` bits as bidirectional, and Table 7-2 uses `TT4`; the input subsection says `TT[0:3]`. This transcription preserves all five and flags the editorial inconsistency for errata/hardware-spec resolution.
- No RTL, BFM, assertion binding, bus simulation, or pin-level implementation is accepted by this source-contract task.

## Reproduction and validation

The transcription was made with local `pdfinfo`, `pdftotext -layout`, and Poppler-rendered PNGs. Rendered checks covered Figure 7-1, signal headings with overbars, and Chapter 8 Figures 8-6, 8-7, 8-9, 8-10, 8-12 through 8-23. PDF extraction was used for searchable prose only; it was not used to infer active polarity or waveform edges.

Run structural checks from the `ppc603e/` directory:

```sh
python3 -m json.tool sim/spec/bus_signals.json >/dev/null
python3 -m json.tool sim/spec/bus_scenarios.json >/dev/null
python3 -m json.tool sim/spec/bus_encodings.json >/dev/null
python3 sim/spec/check_bus.py
python3 -m unittest -v sim/tools/test_bus_scenarios.py
```

`check_bus.py` verifies the complete expected signal-ID set, visually checked polarity set, output-enable class references, widths, known signal locators, the exact Figure 8-1 through 8-23 inventory and PDF pages, diagram-to-scenario references, required topic coverage, detailed-cycle shape/source flags, key scenario figure/section locators, the exact bounded Figure 8-13, Figure 8-15, and Figure 8-17 through Figure 8-19 roles/cycles/limits, and the unresolved-boundary inventory. The focused tests add hand-anchored pacing, grant, retry, driver, beat-order, address-order, latency/throughput condition, and raw-conflict relationships plus negative source, mode, polarity, driver, transition, terminology, ordering, row-order, and unresolved-marker mutations.

The bounded [address decomposition contract](BUS_ADDRESSING.md) now covers Tables 8-4 through 8-7, including 32-bit DH lane marks and the two-beat aligned doubleword. The printed TSIZ conflict and three 32-bit lane-mark anomalies remain explicit. Endian byte significance/steering, cache transaction selection, transaction timing and exhaustive waveforms remain separate work.
