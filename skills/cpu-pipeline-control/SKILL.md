---
name: cpu-pipeline-control
description: Load when designing or reviewing CPU pipeline control — stall/advance logic, flush/kill, hazard detection, forwarding/bypass networks, operand capture in issue/reservation stations, load-use handling, or dispatch/completion backpressure. Gives FPGA-proven patterns (registered bypass selects, operand snoop/freeze, per-source stall bits, stage-sliced kill, extra forwarding stage for RAM regfiles) and the anti-patterns that cost fmax in shipping MiSTer CPUs.
---

# CPU pipeline control — stall, flush, hazards, forwarding

Evidence links point at the reference cores on GitHub, pinned to the reviewed commits: N64 = VR4300 (N64_MiSTer), PSX = R3000A (PSX_MiSTer), SH2 = SH-2 (Saturn_MiSTer), SS = SPARC V8 (Grabulosaure/ss), ARM7 = ARM7TDMI (Atari7800_MiSTer).

## 1. Forwarding: select early, mux late

- **Compute bypass selects one stage before use and register them.** The execute stage sees only
  a mux driven by flops; no register-number comparator sits in the ALU→ALU loop.
  N64 [`cpu.vhd:1269-1272`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L1269-L1272) (EX→EX select in decode), [`3029-3038`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L3029-L3038) (MEM→EX), EX mux [`2078-2084`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2078-L2084).
  SS [`iu_pipe5.vhd:113-184`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L113-L184) (`BYPASS_DEC`: 2-bit select + captured value; EX is a 4:1 mux).
- **Compare tags against predecoded source fields in parallel with the regfile read**; carry the
  hit with the operand so the final override is one small mux. ARM7 [`core:511-542`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L511-L542).
- **Forward-valid carries no handshake/stall terms.** A forward computed on a cycle that does not
  capture is simply discarded; gating it on `mem_ready`/`ack` puts a late bus input at the head of
  the forwarding cone. ARM7 [`core:970-977`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L970-L977).
- **Priority youngest-first**, one input per real producer stage, `r0`/no-write excluded by a
  registered flag, never by comparing to zero in the loop. PSX [`cpu.vhd:1084-1097`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L1084-L1097).
- **Add one forwarding stage after writeback when the regfile RAM has no read-during-write
  guarantee** (MLAB `CONSTRAINED_DONT_CARE`). PSX stage 5 `writeDone`; SH2 `WB2` ([`SH_core.sv:372-377`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_core.sv#L372-L377)).
- **Express architectural visibility windows as forward enables, not stalls** (e.g. "old value
  visible for one instruction"). PSX `blockLoadforward`, `execute_lastreadCOP` ([`cpu.vhd:1084-1097`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L1084-L1097), [`1948-1951`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L1948-L1951)).
  603e use: SPR-move ordering, CR-field/XER visibility rules.

603e: at dispatch, resolve each operand to "GPR / rename slot k / result bus j" and register a
one-hot select. Intra-pair dependencies in dual dispatch are resolved at decode, not at issue.

## 2. Operands that wait must keep watching

- **A latched operand keeps snooping the write/result buses every cycle until it issues**, including
  the cycle it is written. Otherwise a stalled operand goes stale. N64 [`cpu.vhd:2056-2064`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2056-L2064).
- **On a downstream stall, freeze the resolved operand into the held pipeline register** and force
  its select to "captured"; do not rely on a RAM read port or a bypass source still holding the value.
  SS [`iu_pipe5.vhd:632-642`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L632-L642).
- These two rules are the reservation-station contract. Make them a checklist item for every issue queue.

## 3. Stall structure

- **One registered stall bit per cause, ORed only at the point of use**, with per-cause counters in
  simulation. N64 [`cpu.vhd:682`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L682), PSX [`cpu.vhd:485`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L485), [`2853-2862`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2853-L2862). 603e causes: no rename slot, CQ full,
  RS busy, serialization, I-miss, D-miss, BIU full.
- **Derive per-stage stalls from a few named causes** (SH2 `BUS_STALL`, `INST_SPLIT`, `MAWB_STALL`,
  [`SH_core.sv:114-256`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_core.sv#L114-L256)). Funnel every slave's wait into one `lsu_wait` / `ifu_wait`; never scatter raw
  slave signals through the core.
- **Never ripple a memory ack combinationally back to the PC.** SS's `data_r.ack → as_mem → as_exe →
  as_dec → na_c → pc` chain ([`iu_pipe5.vhd:1156`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1156), [`1297`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1297), [`390`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L390)) is a named cause of its 54 MHz fmax.
  Its own FPU shows the fix: an output skid register so the ready chain sees a registered stall
  ([`fpu_calc.vhd:83`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_calc.vhd#L83), [`185-193`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_calc.vhd#L185-L193), [`776-803`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_calc.vhd#L776-L803)).
- **A global "stall everything" enable is simple but fans out to the whole core**; N64 relies on
  physical-synthesis duplication. For a 603e, prefer per-unit valid/ready with skid buffers and
  register and replicate any remaining global enable per consumer group.
- **Registered near-full with headroom beats combinational full on a stall path**: size the queue for
  real entries plus flag lag. PSX write FIFO near-full at 4 of 8 ([`memorymux.vhd:446-475`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/memorymux.vhd#L446-L475)); N64
  request FIFO `>= 4 of 8` ([`cpu.vhd:807`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L807)).

## 4. Load-use and long-latency ops

- **Stall only true dependents.** PSX non-blocking load: pipeline releases once the request is
  accepted; a scoreboard (`lateReadTarget`) is checked against precomputed "reads rs/rt" bits
  ([`cpu.vhd:2137-2140`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2137-L2140), [`1058-1069`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L1058-L1069)). N64's "every load bubbles" ([`cpu.vhd:2780`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2780)) is the anti-pattern.
- **Drop a stale late write**: if a younger instruction writes the same destination before the load
  returns, the load's write is suppressed (PSX [`cpu.vhd:2335-2337`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2335-L2337), [`2485-2492`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2485-L2492)). In a renamed core this
  is automatic (write goes to the rename slot), but any unrenamed state (XER, CR fields if not renamed)
  needs the same check.
- **Typed wait reason + self-completion**: a stalled instruction records *why* it waits (enum) and
  fills its own result when the resource is ready; one site handles all execute-stage waits.
  PSX `CPU_EXESTALLTYPE`, [`cpu.vhd:282-289`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L282-L289), [`1232-1250`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L1232-L1250), [`1825-1833`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L1825-L1833).
- **Interlock only when a consumer touches the result early**: MAC/mul latency counter stalls only
  dependents (SH2 [`MULT.sv:81-125`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/MULT.sv#L81-L125), [`168`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/MULT.sv#L168)). Don't freeze the pipe for mul/div/FPU/TLB miss (N64 does).
- **Keep a single regfile write port by stalling one cycle on late return** instead of adding a port,
  when throughput allows. PSX [`cpu.vhd:2158-2161`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2158-L2161).

## 5. Flush and kill

- **Kill by age slice**: a registered exception/redirect vector indexed by the raising stage clears
  valid bits of every younger stage next cycle. PSX `exceptionNew` ([`cpu.vhd:487`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L487), [`1008`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L1008), [`1864`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L1864), [`2168`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2168)).
  603e equivalent: CQ age mask; every structure holding an instruction clears entries younger than the flush point.
- **Squash wrong-path slots by marking them invalid/NOP**, not by resetting pipeline registers.
  SH2 substitutes NOP at decode input ([`SH_core.sv:298-304`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_core.sv#L298-L304)); SS keeps annulled instructions flowing
  with `anu=1` so PC and trace stay consistent ([`iu_pipe5.vhd:653-666`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L653-L666)).
- **Every externally visible side effect is emitted at exactly one gated site** (`ce ∧ ¬stall ∧
  ¬kill`): store request, SPR write, coprocessor command, divider start. PSX [`cpu.vhd:2023`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2023), [`2449-2459`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2449-L2459).
  This makes squash correctness auditable.
- **A unit start pulse must be gated by the same condition that commits the instruction** so a
  squashed instruction never starts a divider/FPU op (PSX `DIVstart`, [`cpu.vhd:2023`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2023)).

## 6. Branch redirect

- **Register the redirect.** Same-cycle "resolve → fetch address → tag lookup" works only at 34 MHz
  (PSX [`cpu.vhd:639-647`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L639-L647)) and helped cap SS at 54 MHz ([`iu_pipe5.vhd:537-539`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L537-L539), [`736-743`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L736-L743)).
  603e: predict at fetch (static/BTIC), resolve in BPU from registered/forwarded CR/CTR, redirect next cycle.
- **Look up both candidate next PCs in parallel and select late** (N64 duplicated I-tag RAMs,
  [`cpu.vhd:2143-2166`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2143-L2166)).
- **Store the last issued fetch address; increment at use**, so a redirect drives only a mux.
  ARM7 [`core:447-454`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L447-L454).

## 7. Anti-patterns (grep your diff for these)

| Symptom | Seen in | Fix |
|---|---|---|
| 5-bit register compare feeding the EX operand mux | — | register select in prior stage (§1) |
| `ack`/`ready` inside forward-valid or regfile write address/data | ARM7 pre-fix | late signal gates enable only |
| Operand register not updated during stall | — | snoop result buses (§2) |
| Memory ack → stall → PC in one cycle | SS | skid register, registered stall |
| All loads bubble / long ops freeze everything | N64 | scoreboard or rename-ready bits |
| Magic cycle counter for interrupt hold-off | PSX [`cpu.vhd:688`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L688), [`728`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L728) | derive from architectural state |
| Branch condition from EX-produced flags → fetch address same cycle | SS, PSX | predict + registered resolve |

## 8. Review checklist

- [ ] Every EX-stage mux select is a flop (or one gate from a flop).
- [ ] Every waiting operand snoops all result buses, including same-cycle writes.
- [ ] Every stall cause is its own registered bit and has a sim counter.
- [ ] No handshake input appears in a forward-valid, write-address or write-data cone.
- [ ] Each side effect has one emission site gated by commit conditions.
- [ ] Flush clears every younger entry in every queue (IQ, RS, CQ, LSU, fetch buffer, BIU requests).
- [ ] RAM regfile RDW is covered by an explicit forwarding stage, and a test exercises it.
