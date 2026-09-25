---
name: cpu-verification-debug
description: Load when building or reviewing CPU verification and debug infrastructure — retirement/commit traces for lock-step diff against a reference emulator, per-unit traces (cache, FPU, MMU), architectural state injection (savestate-as-reset-value, halted state port), instruction-injection debug monitors, on-hardware error flags and watchdogs, stall/performance counters, and separating cycle-accuracy stalls from functional behavior. Patterns from N64, PSX, SPARC and ARM7 MiSTer cores.
---

# CPU verification and debug infrastructure

Evidence links point at the reference cores on GitHub, pinned to the reviewed commits: N64 = VR4300 (N64_MiSTer), PSX = R3000A (PSX_MiSTer), SH2 = SH-2 (Saturn_MiSTer), SS = SPARC V8 (Grabulosaure/ss), ARM7 = ARM7TDMI (Atari7800_MiSTer).

## 1. Retirement trace — the primary tool

- **Emit one line per retired instruction at the architectural commit point**, from sim-only logic.
  With out-of-order finish, trace at **completion**, not writeback, and trace both completion slots in order.
- **Delta format**: `PC xxxxxxxx OP xxxxxxxx` plus only the registers that changed. N64 [`export.vhd:209-257`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/export.vhd#L209-L257);
  PSX [`export.vhd:170-225`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/export.vhd#L170-L225). The reference emulator is patched to emit the identical format; diff line by line.
- **Exclude nondeterministic state** (N64 skips Random and Count, [`export.vhd:224`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/export.vhd#L224)). 603e: DEC, TBL/TBU.
- **Carry PC/opcode down a sim-only shadow pipeline** (`translate_off` / `ifndef SYNTHESIS`) so hardware pays
  nothing. N64 [`cpu.vhd:157-173`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L157-L173); PSX [`cpu.vhd:165-178`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L165-L178). Keep a sim-only shadow of the architectural regfile
  instead of adding read ports (N64 [`cpu.vhd:3257-3260`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L3257-L3260)).
- Optional instruction index / cycle stamp fields; roll files every N lines.
- 603e fields: PC, OP, changed GPR/FPR, CR, XER, LR, CTR, MSR, SRR0/1, DAR, DSISR, FPSCR, exception taken.

## 2. Per-unit traces

Localize divergence to a unit before full-system diffs: D-cache fill/read/store/writeback lines with tag and
index (N64 [`cpu_datacache.vhd:545-722`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_datacache.vhd#L545-L722)); FPU op/operands/result/FPSCR before-after vs softfloat
([`cpu_FPU.vhd:1770-1853`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_FPU.vhd#L1770-L1853)); bus transaction log (SS [`plomb_log.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/plomb/plomb_log.vhd)). Add MMU: TLB miss, BAT hit, reload.

## 3. State injection

- **Savestate registers double as reset values.** Every architectural register resets to `ss_in[n]`; register
  files and TLB load through their normal write ports with priority. Cold reset = load defaults into `ss_in`.
  One mechanism serves reset and restore, so the reset path is exercised constantly.
  N64 [`cpu.vhd:1086-1095`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L1086-L1095), [`3505-3528`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L3505-L3528), [`cpu_cop0.vhd:528-600`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_cop0.vhd#L528-L600); PSX [`cpu.vhd:771-775`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L771-L775).
- **Quiesce predicate**: save only when no multi-cycle op, pending interrupt or outstanding memory op exists,
  so in-flight state never needs capturing. PSX `SS_idle` ([`cpu.vhd:2775-2780`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2775-L2780)).
- **Start simulation from a captured state** to reproduce a hardware failure without re-simulating boot.
  PSX [`tb_savestates.vhd`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/sim/system/src/tb/tb_savestates.vhd) (`LOADSTATE`/`FILENAME`).
- **Halted architectural state port**: read/write every GPR/SPR/PC while halted, validate on commit, resume.
  ARM7 [`core:69-75`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L69-L75), [`3212-3281`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L3212-L3281). Enables SingleStepTests-style per-instruction vectors: load state → run one
  instruction → compare state and cycle count.

## 4. Debug access on hardware

- **Instruction injection**: when stopped, stuff an opcode into decode and let the pipeline execute it;
  capture the written value. Register/memory access needs no separate datapath. SS [`iu_pipe5.vhd:476-480`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L476-L480), [`1378-1380`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1378-L1380).
  603e: inject `mfspr/mtspr/lwz/stw` into the IQ while completion is held.
- **Borrow the real regfile read port while paused**: `raddr = EN ? decode_idx : dbg_idx`. SH2 [`SH_core.sv:100-104`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_core.sv#L100-L104).
- Global pause = one enable gating every CE, never a gated clock (SH2 `EN`, N64 `ce_93`).
- On-chip bus trace buffer with triggers readable over the debug link (SS [`dl_plomb_trace.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/plomb/dl_plomb_trace.vhd)).

## 5. On-hardware assertions and counters

- **Sticky error register visible in the OSD/debug port**: unknown opcode, stall watchdog (no retirement for
  N cycles), FIFO overflow, BIU timeout, illegal MMU op during a walk. N64 [`cpu.vhd:3574-3585`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L3574-L3585); PSX 512-cycle
  deadlock detector ([`cpu.vhd:2831-2845`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2831-L2845)).
- **Sim-only per-cause stall counters** and µTLB/cache hit counters (N64 [`cpu.vhd:3590-3605`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L3590-L3605); PSX [`2853-2862`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2853-L2862))
  guide IPC work.
- **Runtime disable knobs for every performance structure** (cache on/off, µTLB off, force write-through,
  added latency) so a bug can be bisected on hardware (N64 `DATACACHEON`, `DISABLE_DTLBMINI`, `slow_in`).
- **Poison init**: fill memory with a recognizable illegal word and assert on executing it (SS `0xBADACCE5`,
  [`iu_pipe5.vhd:759-767`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L759-L767)); init sim register files with a known pattern (SH2 [`SH_regfile.sv:71`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_regfile.sv#L71)).
- Per-stage disassembly strings for waveforms under `ifndef SYNTHESIS` (SS `dias_*`, `disas_pack`).

## 6. Accuracy vs function

- **Cycle-accuracy stalls are additive on top of a minimal-latency pipeline and switchable**
  (PSX `TURBO` gates each fidelity stall, [`cpu.vhd:1062-1067`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L1062-L1067), [`2318-2330`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2318-L2330); N64 `FASTBUS`; SH2 `FAST`).
  Test functional correctness with them on and off.
- **UNPREDICTABLE/undefined behavior pinned to a reference** and each deliberate divergence documented
  (ARM7 "oracle-verified" sites). Undocumented flag side effects need a reference model plus a differential
  test (ARM7 400k-vector Booth-carry check, [`core:882-885`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L882-L885)).

## 7. Reproducibility

- **Keep vectors, harness and reference-model patches in the repo** (or a pinned, scripted fetch). ARM7's
  SingleStepTests harness lives in an untracked directory and cannot be reproduced from the repo.
- Record seeds for random tests and print the first divergence with full context.
- A green lint run is not evidence of fit or conformance; record which evidence each claim rests on.

## 8. Checklist for a new CPU feature

- [ ] Retirement trace covers every architectural state the feature changes.
- [ ] Reference emulator emits the same fields; a diff test exists.
- [ ] State injection can place the core directly into the feature's interesting states.
- [ ] Directed tests for architectural corners + randomized differential with a recorded seed.
- [ ] Error flags/watchdog cover the feature's new deadlock or overflow modes.
- [ ] Performance structure added by the feature has a runtime disable.
