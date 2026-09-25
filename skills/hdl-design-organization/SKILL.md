---
name: hdl-design-organization
description: Load when structuring SystemVerilog source for a large core — packages and typedef'd structs/enums, pipeline-register records, configuration records and variant selection, RAM/FIFO primitive wrappers, SPR/peripheral register definitions with write/read masks, feature-disable parameters, function/task use, sim-only constructs, and file/build hygiene (files.f/qip). Extracted from recurring good and bad practice across five MiSTer CPU cores; complements hdl-coding-guidelines.
---

# HDL design organization for large cores

Evidence links point at the reference cores on GitHub, pinned to the reviewed commits: N64 = VR4300 (N64_MiSTer), PSX = R3000A (PSX_MiSTer), SH2 = SH-2 (Saturn_MiSTer), SS = SPARC V8 (Grabulosaure/ss), ARM7 = ARM7TDMI (Atari7800_MiSTer).

## 1. Types first

- **Pipeline payloads are `typedef struct packed`**; a stage transfer is one assignment. SH2 `PipelineState_t`
  of per-stage structs ([`SH_pkg.sv:1332-1387`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_pkg.sv#L1332-L1387)); SS `type_pipe` records ([`iu_pipe5.vhd:85-110`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L85-L110)).
  Anti-lesson: ARM7's ~140 loose signals and field-copy task.
- **Enums for every small code** (unit, result mux, load type, wait reason, FSM state) with explicit storage
  type. N64 `t_decodeResultMux`; PSX `CPU_EXESTALLTYPE`. Avoid `localparam` code lists (ARM7 ALU opcodes).
- **Named struct literals** in tables and defaults; positional literals break silently on field reorder (SH2).
- A default constant per struct (`DEC_DEFAULT`, `UOP_NOP`) used for reset, bubbles and decode defaults.

## 2. Configuration

- **One config struct per personality, one per technology, selected by a single parameter.**
  SS `CPUCONF(CPUTYPE)` / `TECHS(TECH)` records ([`cpu_conf_pack.vhd:21-53`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/cpu_conf_pack.vhd#L21-L53), [`184-213`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/cpu_conf_pack.vhd#L184-L213)), consumers copy fields
  into local constants. SV: `typedef struct packed {…} cfg_t; localparam cfg_t CFG[N] = …;`.
- **Select variants with `generate if`, never by which file is compiled.** SS binds architectures by file
  list: a dead variant sits in the tree and an intended I/D tag-RAM packing silently never happens
  ([`iram_bi.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/peri/iram_bi.vhd), [`mcu_simple.vhd:403-417`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L403-L417)).
- **Feature-disable parameters gate the update logic so synthesis prunes it** (SH2 `UBC_DISABLE`,
  [`SCI.sv:81`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/SCI.sv#L81); `SIZE_BYTE_DISABLE`). Disabled ISA features decode to an architectural exception.
- **Trade-off constants documented at declaration** with what each setting costs ("fast" vs "small").
  SS `BYPASS_DEC`, `SSTALL`; ARM7 `MUL_RETIRE_STAGE` ([`core:18-41`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L18-L41)).
- Elaboration-time checks reject unsupported parameter values.

## 3. Primitive wrappers

- **One wrapper per RAM flavor, pinning block type and RDW behavior**: MLAB async-read regfile, M10K
  registered true-dual-port (mixed width, per-port clock and clken), byte-lane RAM. N64/PSX [`RamMLAB.vhd`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/RamMLAB.vhd),
  [`dpram.vhd`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/dpram.vhd); SS gives every RAM the same record port so cache/TLB/regfile RAMs are interchangeable.
- **Exactly one definition of each module in the build.** SH2 has two differing [`SH_mem.sv`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_mem.sv) copies; which one
  you get depends on the qip.
- Behavioral sim models of vendor primitives with *the same* RDW semantics (PSX `sim/system/src/mem/`).
- **Fall-through FIFO on MLAB** with next-count near-full/near-empty thresholds (N64/PSX `SyncFifoFallThroughMLAB`).

## 4. Register definitions (SPRs, peripherals)

- **Struct per register + `_WMASK`, `_RMASK`, `_INIT` constants in a package.** Writes `r <= d & WMASK`,
  reads `r & RMASK`, reset `INIT`. SH2 [`SH7604_pkg.sv:4-104`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/SH7604_pkg.sv#L4-L104); PSX COP0 write masks at the write site
  (`cop0_SR <= value and x"F27FFF3F"`). 603e: MSR, HID0/1/2, BATs, SDR1, SRR1, DSISR, FPSCR, XER.
- **Peripheral bundle** `{ACT, DO, BUSY}`, each block decodes its own range, priority mux in the wrapper
  (SH2 [`SH7604.sv:327-342`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/SH7604.sv#L327-L342)).
- Shared prescaler producing enable pulses; no per-block dividers (SH2 [`SH7604.sv:369-421`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/SH7604.sv#L369-L421)).

## 5. Functions, tasks, block shape

- **Pure functions in the package for datapath pieces** (adder, shifter, align/extract, rf_index, one-hot
  encode) — short stage processes, reusable in testbenches. SH2 `Adder/Log/Shifter`; SS `op_alu`, `tlb_trans`;
  ARM7 `load_lane`, `oh_encode`.
- **Per stage: one combinational "next" block with defaults + a priority ladder
  (`kill / stall / bubble / advance`), and one sequential commit block.** The ladder order is the stage's policy.
  SS `Comb_X`/`Sync_X`; PSX two-process stages.
- Avoid one giant `always_ff` owning all state (ARM7 ~800 lines, bus outputs written from ~20 places → wide
  priority muxes). One owner block per concern.
- Macros: avoid; if unavoidable, `undef` at file end (ARM7 leaks macros).
- No blocking assignments to state in clocked blocks (SH2 [`INTC.sv:279-309`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/INTC.sv#L279-L309)).

## 6. Sim-only code

- Wrap traces, shadow pipelines, disassembly strings and counters in `` `ifndef SYNTHESIS`` (or
  `translate_off`), never in a way that changes synthesized behavior.
- Known-pattern init for sim-only arrays; poison memory init + assertion.

## 7. Build hygiene

- Explicit compile order in the file list; every RTL file appears exactly once per build profile.
- Remove dead code and stale variants when restructuring (ARM7 left unused functions, empty branches,
  stale comments after its timing rewrite).
- Comments state *why*, briefly; measured timing history goes in commit messages or design docs.

## 8. Review checklist

- [ ] Stage payloads are packed structs; no field-by-field copies.
- [ ] Every small code is an enum; literals are named.
- [ ] Variants chosen by parameters + `generate`, not file lists; unsupported values fail elaboration.
- [ ] RAMs only through wrappers; one definition per module.
- [ ] SPR/peripheral registers defined with masks and init in one package.
- [ ] Sim-only constructs guarded; no macro leakage; no dead code left behind.
