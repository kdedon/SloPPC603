---
name: cpu-precise-exceptions
description: Load when implementing or reviewing exceptions, interrupts, flush/recovery, completion/commit, or speculative-vs-committed architectural state in a CPU — SRR0/SRR1/DAR/DSISR formation, exception priority, interrupt sampling (MSR[EE]), redirect after flush, draining outstanding bus transactions, commit-gated writeback for FPU/SRU, and serializing instructions. Patterns from SPARC, R3000, SH-2 and ARM7 FPGA cores.
---

# Precise exceptions, commit and recovery

Evidence links point at the reference cores on GitHub, pinned to the reviewed commits: N64 = VR4300 (N64_MiSTer), PSX = R3000A (PSX_MiSTer), SH2 = SH-2 (Saturn_MiSTer), SS = SPARC V8 (Grabulosaure/ss), ARM7 = ARM7TDMI (Atari7800_MiSTer).

603e model: in-order completion from a 5-entry CQ;
architectural state (GPR/FPR, CR, XER, LR, CTR, MSR, SPRs) changes only at completion.

## 1. Detect early, act at commit

- **Exception status is data carried with the instruction** (fetch fault with the word, data fault with
  the load/store result, decode/execute traps in the entry). Act only when the entry is oldest.
  SS carries `pipe.trap` and acts at WRITE ([`iu_pipe5.vhd:48-58`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L48-L58), [`1212-1217`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1212-L1217)); ARM7 prefetch abort is
  taken only when the word reaches execute, and a discarded word discards its abort ([`core:172-178`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L172-L178), [`2682-2698`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L2682-L2698)).
- **Priority by age first, then by architected order within an instruction.** SS: override order in EXE
  with any older carried trap winning ([`iu_pipe5.vhd:878-916`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L878-L916)). N64/PSX: fixed if/elsif chain.
- Micro-steps of a sequenced instruction must not trap mid-sequence unless the architecture defines
  restart (SS `cycle/=0` cannot trap). 603e `lmw`/string ops: DSI/alignment mid-sequence must leave
  a restartable state (SRR0 = the instruction, partial loads allowed per architecture).

## 2. Committed shadows of speculative state

- **Anything updated before commit needs a committed copy restored on flush.** SS updates PSR and Y in
  EXE but captures `psr_fin`/`ry_fin` at WRITE and restores them on a trap ([`iu_pipe5.vhd:973-990`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L973-L990), [`1327-1330`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1327-L1330)).
- 603e: CR, XER, LR, CTR (unless renamed) and MSR need committed copies; the rename map needs a committed
  map. Flush = restore committed copies + clear all younger entries.

## 3. Commit-gated writeback for in-order units (no ROB)

- **A unit that completes in order keeps a small FIFO of issued ops; the completion stage sends one commit
  pulse per retired op; a result writes architectural state only when "finished" meets a pending commit.**
  On flush, drain committed ops (counter to zero), then clear the FIFO. SS FPU [`fpu_simple.vhd:228-242`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L228-L242), [`560-569`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L560-L569)
  (`wri_cpt` counter), IU side [`iu_pipe5.vhd:1304-1307`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1304-L1307).
- 603e: FPU and SRU (mtspr, mtmsr, mtcrf) results commit on CQ pulses. Rename→architectural copy happens
  only on those pulses.
- **Side effects issued from the non-squashable point.** Stores, coprocessor writes/commands, SPR writes,
  cache ops leave only when the instruction can no longer be flushed. PSX GTE writes from stage 4 under
  the exception gate ([`cpu.vhd:2449-2459`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2449-L2459)). 603e: stores leave the store queue only after completion.

## 4. Redirect safely

- **Drain outstanding bus transactions before redirecting, or tag responses with an epoch and drop stale
  ones.** SS holds `trap_stop` until instruction and data outstanding counts are zero
  ([`iu_pipe5.vhd:1253-1256`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1253-L1256), counters [`446-452`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L446-L452), [`1187-1192`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1187-L1192)). ARM7 "request → drain → enter"
  ([`core:1462-1486`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L1462-L1486), [`2658-2680`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L2658-L2680)). The 60x bus has split address/data tenures, so a stale data beat after a
  flush is a real risk.
- **Precompute the vector address into a register every cycle** (from MSR[IP], cause) so the flush path
  is flop → fetch mux. N64 `exceptionPC` ([`cpu_cop0.vhd:489-519`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_cop0.vhd#L489-L519)).
- **Spread SRR0/SRR1/DAR/DSISR formation over registered steps with one commit point.** PSX latches
  EPC candidate/BD/code at N, forms SR/CAUSE/EPC at N+2, commits when the squashed pseudo-op passes
  ([`cpu.vhd:2656-2711`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2656-L2711), [`1939-1944`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L1939-L1944)).
- **Reuse the normal write paths for exception side-effect writes** instead of adding ports. SS injects
  synthetic ALU writes to save PC/nPC over two cycles ([`iu_pipe5.vhd:1109-1120`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1109-L1120), [`1260-1262`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1260-L1262)); SH2 runs a
  micro-program through the pipeline ([`SH_pkg.sv:194-334`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_pkg.sv#L194-L334)). 603e: SRR0/SRR1 are SPR writes; the MSR update
  and vector fetch follow.

## 5. Interrupts

- **Sample interrupts at a completion boundary using the post-instruction mask**, so `mtmsr` setting EE
  takes effect for the next boundary. ARM7 [`core:1610-1612`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L1610-L1612); SH2 accepts only when not blocked by the
  previous instruction, not in a delay slot, not mid-sequence ([`SH_core.sv:833`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_core.sv#L833)).
- **Snapshot the accepted source/vector at acceptance** so a later higher-priority arrival cannot change
  the in-flight vector. SH2 `INT_ACCEPTED` ([`INTC.sv:236-241`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/INTC.sv#L236-L241)).
- **Never use a magic hold-off counter** (PSX blocks IRQs for 10 cycles, [`cpu.vhd:688`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L688), [`728`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L728)). Derive
  acceptance from architectural state: MSR[EE], context-synchronizing ops, completion state.
- Decrementer/external/SMI enter through the same pseudo-exception path as synchronous exceptions.
- Glitch-filter asynchronous interrupt pins after synchronization (SH2 IRL 4-sample filter, [`INTC.sv:108-132`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/INTC.sv#L108-L132)).

## 6. Serialization

- **Make context-changing ops execution-serializing with refetch**: `mtmsr`, `rfi`, `isync`, `sc`,
  `mtspr` to BATs/SDR1/HID0, `mtsr`. Then decode/translation may read committed MSR state without
  forwarding (ARM7 invariant, [`core:456-464`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L456-L464)), and µTLB/BTIC flushes happen at a known point.
- Don't model an OS quirk as a global RTL constant (SS `BSD_MODE`, [`iu_pipe5.vhd:685`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L685)).

## 7. Gaps seen in reference cores — do not copy

- SH-2 has no address-error exception at all; misaligned accesses silently rotate.
- PSX leaves unknown fetch regions as `-- todo` (no bus-error exception, [`cpu.vhd:718`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L718)).
- ARM7 suppresses base writeback on data abort (base-restored) where the real part updates the base.
Every architected fault needs a directed test proving the exception, the saved state and the restart.

## 8. Checklist

- [ ] Every fault source produces a code carried with its instruction; none acts before completion.
- [ ] Every speculatively updated register has a committed copy and a restore on flush.
- [ ] Stores/SPR writes/cache ops leave only after completion.
- [ ] Redirect waits for (or epoch-filters) outstanding bus responses.
- [ ] Vector address is a flop; SRR/DAR/DSISR formation is pipelined with a single commit.
- [ ] Interrupt acceptance depends only on architectural state; tested with EE toggling around `mtmsr`/`rfi`.
- [ ] Flush clears IQ, RS, CQ, LSU/store queue (uncommitted part), fetch buffer, BIU requests, µTLB if needed.
