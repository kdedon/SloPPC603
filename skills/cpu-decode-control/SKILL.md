---
name: cpu-decode-control
description: Load when writing or reviewing instruction decode, predecode, decoded micro-op/uop structs, dispatch payloads, multi-cycle instruction sequencing (lmw/stmw, string ops, rfi, misaligned splits), exception/interrupt entry as pseudo-instructions, or when decode appears on a critical path. Covers carrying one packed decode record through every stage, operand-source codes with a flat mux, predecode at capture, microcode as decode(IR,STATE), and decode-table style.
---

# CPU decode and control words

Evidence links point at the reference cores on GitHub, pinned to the reviewed commits: N64 = VR4300 (N64_MiSTer), PSX = R3000A (PSX_MiSTer), SH2 = SH-2 (Saturn_MiSTer), SS = SPARC V8 (Grabulosaure/ss), ARM7 = ARM7TDMI (Atari7800_MiSTer).

## 1. Decode once, carry the record

- **Decode into one `typedef struct packed` of sub-structs and enums; every stage carries it.**
  Hazard, forwarding, port and completion logic test its fields and never re-decode opcode bits.
  Reset or a bubble is loading the default record. SH2 [`SH_pkg.sv:72-175`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_pkg.sv#L72-L175) (`DecInstr_t`),
  pipeline struct [`SH_pkg.sv:1332-1387`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_pkg.sv#L1332-L1387); SS `type_cat` ([`iu_pack.vhd:223-244`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L223-L244)).
- **Anti-lesson:** ARM7 declares ~140 loose `dec_*`/`exec_*` signals and copies them field by
  field in a 65-line task ([`core:277-407`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L277-L407), [`1519-1585`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L1519-L1585)). Missed fields become silent bugs.
- 603e record, at minimum:
  ```systemverilog
  typedef struct packed {
    unit_e     unit;          // IU, SRU, LSU, BPU, FPU
    src_t      a, b, c;       // {idx, rd}: rA/rB/rS or frA/frB/frC
    dst_t      d0, d1;        // {idx, wr}: rD, plus rA for update forms
    cr_use_t   cr;            // fields read / written
    logic      xer_ca_r, xer_ca_w, xer_ov_w, rc;
    opsel_e    opa_sel, opb_sel;  // GPR / imm kind / SPR / zero
    imm_e      imm_kind;      // SIMM, UIMM, shifted, D-form, BD, LI
    mem_t      mem;           // size, sign, update, reverse, is_store
    logic      serialize, refetch, privileged;
    exc_chk_e  exc_chk;       // which trap/overflow/alignment check applies
    logic [2:0] lst;          // last micro-step (0 = single step)
  } dec_t;
  ```
  Carry it in IQ, RS and CQ entries so rename, issue and completion never look at the raw word.

## 2. Keep decode off the critical path

- **Decode emits small control codes; one flat mux acts on them.** Operand-source names
  (`SRC_RN`, `SRC_IMM`, `SRC_SP` …) come out of decode; a separate flat `case` selects the 32-bit
  data. Otherwise the synthesizer builds the data mux in the shape of decode's priority chain.
  ARM7 [`core:108-125`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L108-L125), [`1694-1739`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L1694-L1739).
- **Predecode register indexes when the word is captured** (fetch buffer / IQ entry / I-cache fill)
  so regfile reads launch from flops. ARM7 `port_indexes()` ([`core:641-666`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L641-L666)). 603e: store rA/rB/rS/rD,
  unit class, serialize and "reads X" bits in the IQ entry or as I-cache predecode bits.
- **Precompute "really reads rs/rt" bits** so interlocks avoid false dependencies without full decode
  on the interlock path. PSX `decReqSource1/2` ([`cpu.vhd:857-953`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L857-L953)); SH2 load-use from decoded
  `RA.R/RB.R` ([`SH_core.sv:131-134`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_core.sv#L131-L134)).
- **Pre-classify checks in decode; evaluate in execute.** Decode selects *which* overflow/trap/
  alignment test applies (enum); execute evaluates only that one. N64 `decodeExcType` ([`cpu.vhd:2223-2248`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2223-L2248)).
- **Defer wide immediate construction**: decode emits a 3-bit immediate kind; EX builds it from the
  carried IR. SH2 [`SH_core.sv:402-421`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_core.sv#L402-L421).
- **Precompute all condition outcomes as a vector and index it**, so forwarded flags reach the result
  through one select. ARM7 [`core:1741-1764`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L1741-L1764). 603e `bc`: 32-bit "CR bit true" vector selected by BI,
  CTR==1 test in parallel.
- **Serializing ops flush, so decode may read committed mode state** (MSR[PR/IR/DR/FP], T bit) instead
  of forwarded state. ARM7 [`core:456-464`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L456-L464). Requires `mtmsr`, `rfi`, `isync`, `sc`, context-changing
  `mtspr` to be execution-serializing with refetch.
- **Normalize encodings to one datapath form** in decode (e.g. shift-immediate special cases →
  register form). ARM7 [`core:1675-1692`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L1675-L1692). 603e: `srawi` → `sraw` form, `subfic` → add with inverted operand.

## 3. Decode table style

- PowerPC: `case (opcd)` with nested `case (xo)` — flat, parallel. Avoid a long masked `if/else if`
  chain (ARM7 [`core:1870-2467`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L1870-L2467)); its outputs form a deep priority mux.
- Default-then-override: `d = DEC_DEFAULT;` then per-opcode overrides. SH2 [`SH_pkg.sv:190`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_pkg.sv#L190).
- **Use named struct literals** (`'{idx:5'd3, rd:1'b1}`), not positional (`'{SP,1,1}`); reordering
  a field silently breaks every positional row (SH2 lesson).
- Illegal/unimplemented opcodes decode to an exception class. Never `report … severity failure` in
  synthesizable decode (PSX [`cpu.vhd:1463`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L1463)) — hardware silently does nothing.
- ISA-variant gating as a function argument (SH2 `VER`, [`SH_pkg.sv:361`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_pkg.sv#L361)). 603e: `FPU_EN`, `MMU_EN`
  parameters make disabled classes decode to FP-unavailable/program exceptions.

## 4. Multi-cycle instructions as microcode in decode

- **`decode(IR, STATE)` with an `lst` field**: a small state counter in decode steps the instruction;
  each step emits a full normal decode record down the ordinary pipeline, reusing ALU/AGU/LSU.
  Fetch holds, and the next fetched word parks in a save register. SH2 [`SH_core.sv:235-249`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_core.sv#L235-L249), [`306`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_core.sv#L306), [`345-346`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_core.sv#L345-L346).
  603e uses: `lmw/stmw`, `lswi/stswi/lswx/stswx`, misaligned splits, `rfi`, `sc`, `dcbz`.
- **Decode-directed bypass for micro-op temporaries**: a flag forces "use previous micro-op's
  result" regardless of register number, so sequences need no architectural scratch register.
  SH2 `BPLDA/BPWBA/BPMAB` ([`SH_pkg.sv:78-80`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_pkg.sv#L78-L80), [`SH_core.sv:436`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_core.sv#L436), [`454`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_core.sv#L454)). Alternative: 1–2 hidden rename slots.
- **Exceptions and interrupts as injected pseudo-instructions** decoded into a micro-program that
  performs the saves and vector jump through the normal pipeline. SH2 [`SH_core.sv:298-300`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_core.sv#L298-L300),
  [`SH_pkg.sv:194-334`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_pkg.sv#L194-L334). 603e: inject at completion (when the faulting entry is oldest), not at decode,
  to stay precise.
- **Alternative for a few complex ops: transfer descriptor + side FSM.** Snapshot everything the op
  needs (addresses, list mask, resume PC) into dedicated registers; converge on one shared
  "retire from registers" state. ARM7 [`core:205-275`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L205-L275), [`1491-1504`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L1491-L1504). Good for LSU misses and `dcbz`.
- **Priority-list walk** (lmw/stmw, free-list pick): registered rest-mask, lowest-set-bit isolate
  `x & (~x + 1)`, OR-tree encoder, computed one step ahead. ARM7 [`core:222-226`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L222-L226), [`1354-1360`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L1354-L1360), [`3074-3079`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L3074-L3079).

## 5. Review checklist

- [ ] One packed decode struct, carried whole; stage transfers are single assignments.
- [ ] No opcode bits inspected after decode (grep for `ir[`/`instr[` in later stages).
- [ ] Data muxes are flat `case` on small registered select codes.
- [ ] Regfile read indexes come from flops (predecoded), not from a field mux on the fetched word.
- [ ] Every illegal/unimplemented encoding raises an architectural exception.
- [ ] Named struct literals in decode tables.
- [ ] Micro-sequenced ops: interrupts blocked mid-sequence; a flush mid-sequence resets `STATE`.
