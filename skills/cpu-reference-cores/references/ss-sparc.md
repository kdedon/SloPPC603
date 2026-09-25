# TEMLIB SparcStation CPU — microarchitecture mining report

Source: [Grabulosaure/ss](https://github.com/Grabulosaure/ss/tree/70203e26e981069710e934600fd55b9d866a9e5b) `src/cpu/`. Links are pinned to the reviewed commit.

**Target note:** this is a **SPARC V8** CPU, not MIPS: MicroSPARC-II / SuperSPARC personality with register windows, delay slots and annul bits, plus a SPARC Reference MMU. The code is VHDL by "DO" (TEMLIB/TACUS), written between 2009 and 2018. Comments are in French.

**What gets built (SS5 revision, [`src/board/mister/SS_MiSTer/files.qip`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/board/mister/SS_MiSTer/files.qip)):**
- [`iu.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu.vhd) entity with the `iu_pipe5` architecture.
- [`fpu.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu.vhd) with the `fpu_simple` architecture, using `fpu_calc`, `fpu_mul`, `fpu_div` and `fpu_regs_2r1w`.
- [`mcu.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu.vhd) with the `mcu_simple` architecture plus `mcu_tw`.

**SS20 (SMP) build:** uses `mcu_mp` with `mcu_multi` and `mcu_multi_ext`, plus `smpmux` and a single shared `fpu_mp` (`fpu_multi`) for up to 4 CPUs.

**Clock and timing:** the core clock is `SYSFREQ` = 65 MHz for SS5 (50 MHz for SS20), set at [`ss.sv:367`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/board/mister/SS_MiSTer/ss.sv#L367). A Quartus build of the SS5 revision (timing report not in the repository) shows a slow-corner Fmax of **54.15 MHz** and setup slack of −10.6 ns on the core PLL clock. In other words, the design ships **without timing closure** and relies on typical-silicon margin. Use it as a source of structure, not of timing discipline.

**Resource figures:** the same build fits the whole SS5 system in 20.4k ALMs, 158 M10K and 43 DSP.

`src/docs` only covers SCSI and Ethernet, and `.claude/` only holds permissions. Neither is relevant to the CPU.

---

## 1. Pipeline organization (iu_pipe5.vhd)

### Stages
The pipeline is FETCH, DECODE, EXECUTE, MEMORY, WRITE. The header ([`iu_pipe5.vhd:13-58`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L13-L58)) diagrams how multi-cycle loads and stores re-occupy DECODE and EXECUTE for 2 or 3 cycles.

### Pipeline registers
Every stage uses the same record, `type_pipe` ([`iu_pipe5.vhd:85-110`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L85-L110)). Its fields are `v`, `anu` (annulled), `cat` (the decoded control word, see section 2), `cycle` (the micro-step of a multi-cycle instruction), `trap`, `pc/npc`, `num_rs1/rs2/rd` (physical register numbers after window mapping), `by_sel1/2` and `by_rs1/2` (precomputed bypass selects, see below), `rd`, `rd_maj`, `ry`, `psr`, `data_w` (the full memory request) and `adrs10`.

Naming convention:
- Registered records: `pipe_dec`, `pipe_exe`, `pipe_mem`, `pipe_wri`.
- Combinational next-state: `pipe_X_c`.
- Each stage is one `Comb_X` process plus one `Sync_X` process.

Note the naming offset: `pipe_dec` is the register *leaving* DECODE, so it is the instruction currently in EXECUTE.

### Stall / backpressure: "AS" = *au suivant* ("next stage can accept")
The ready chain runs backwards:

`as_wri_c` → `as_mem_c` → `as_exe_c` → `as_dec_c` / `na_c` (advance PC)

Each stage either holds its register (`pipe_exe_c<=pipe_exe`), bubbles (`v<='0'`), or passes the instruction on.

```vhdl
-- iu_pipe5.vhd:994-997  (EXE)
ELSIF as_mem_c='0' THEN
  pipe_exe_c<=pipe_exe;   -- hold
  as_exe_c<='0';
-- iu_pipe5.vhd:1122-1127 (MEM)
ELSIF as_wri_c='0' THEN
  pipe_mem_c<=pipe_mem; as_mem_c<='0'; data_w_c.req<='0';
```

**Pitfall:** the chain is fully combinational from the memory response to the PC and fetch registers:
- `as_wri_c` depends on `data_r.dreq` ([`iu_pipe5.vhd:1297`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1297)).
- `as_mem_c` depends on `data_r.ack` ([`iu_pipe5.vhd:1156`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1156)).
- These propagate through EXE and DEC to `na_c`, which updates `pc/npc` ([`390`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L390)).

This long path is a likely contributor to the 54 MHz Fmax. For the 603e, register the stall or use skid buffers, as the FPU does with `SSTALL` (section 5).

### Operand freeze on stall (clever, needed with BRAM register files)
When EXE stalls, DECODE holds its instruction. It also overwrites the bypass fields with the operand value EXE just resolved, and forces the select to "use the captured value":

```vhdl
-- iu_pipe5.vhd:632-642
ELSIF as_exe_c='0' THEN
  na_c<='0'; pipe_dec_c<=pipe_dec; ...
  pipe_dec_c.by_rs1<=dir_rs1_c;   -- value computed in EXE this cycle
  pipe_dec_c.by_rs2<=dir_rdi_c;
  pipe_dec_c.by_sel1<="11";       -- "Force maintien"
  pipe_dec_c.by_sel2<="11";
```

**Why:** the register file output is a registered BRAM read whose address follows the *new* decode, and the bypass source may drain out of the pipeline during the stall. Latching the resolved operand makes the stall safe without re-reading the register file.

### Hazard detection
- **RAW on loads (load-use).** `deps()` ([`iu_pipe5.vhd:120-134`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L120-L134)) stalls if a non-FP load sits in EXE *or* MEM and targets a source register. Load data only arrives in the WRITE stage, because the bus is two-phase (address in MEM, data in WRITE). The load-use penalty is therefore **2 cycles**.
- **Other decode stalls** ([`iu_pipe5.vhd:668-686`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L668-L686)):
  - A JMPL or RETT in EXE (its target is computed in EXE), unless the decoding instruction is also a JMPL.
  - An FPop while the FPU is not ready.
  - FBfcc while `fpu_rdy=0` (an FP trap may still arrive) or while `fccv=0`.
  - Anything following WRPSR when `BSD_MODE` is set, a NetBSD compatibility workaround (flagged as a **pitfall**: a global OS-behaviour constant in RTL).
- **Structural hazards.** Multi-cycle stores, LDD/STD, SWAP and CASA step the `cycle` field in DECODE (`ncycles_v`, [`699-720`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L699-L720)). A plain store takes 2 decode cycles because the store data needs a third read port. With `fst` (fast store, [`573-581`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L573-L581)), a store whose address is `rs1+imm` or `rs1+r0` completes in one cycle, since read port 2 is free to read `rd`.

### Forwarding network: select precomputed in DECODE
There are two variants, chosen by a constant ([`iu_pipe5.vhd:113-116`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L113-L116)):

```vhdl
CONSTANT BYPASS_DEC : boolean := true;  -- true=DECODE (fast), false=EXECUTE (small)
CONSTANT BYPASS_WRI : boolean := true;  -- bypass WRITE stage instead of RF write-through
```

**`BYPASS_DEC=true`:** `bypass_sel` ([`137-163`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L137-L163)) runs in DECODE and compares the source register numbers against `pipe_dec`, `pipe_exe` and `pipe_mem` (the instructions in EXE, MEM and WRITE). It then registers either a 2-bit select, or, for a producer that is already in MEM, **the value itself** (`rs<=pipe_exe.rd`).

In EXE, `bypass_mux` ([`165-184`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L165-L184)) is a plain 4:1 mux with a registered select:

| sel | source | meaning |
|---|---|---|
| "00" | `reg` | register file |
| "01" | `pipe_exe.rd` | producer was in EXE last cycle, one ahead now |
| "10" | `pipe_wri.rd` | producer was in WRITE; the RF read returned stale data |
| "11" | `by_rs` | value captured in DEC, or the frozen operand, or r0 = 0 |

**Why:** all the 8-bit register-number comparators and the priority chain move out of EXE. The EXE critical path becomes mux-select → ALU. **Cost:** 2 × 32-bit capture registers plus 2 × 2-bit selects in the pipeline record. The comment calls it "fast" versus "small".

**`BYPASS_WRI`:** the WRITE-stage result is forwarded from `pipe_wri.rd`, the register after the write mux, which includes aligned load data. This replaces a write-through register file, which is why `iregs` gets `THRU => NOT BYPASS_WRI` ([`330`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L330)).

### Branch handling (delay slots and annul)
Bicc, FBfcc and CALL are **resolved in DECODE** by `op_dec` ([`iu_pack.vhd:2469-2509`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L2469-L2509)). It computes `pc+disp` and evaluates the condition against `psr_c.icc`:

```vhdl
-- iu_pipe5.vhd:537-539
decode(inst_d_v,IFLUSH,CASA,cat_v,n_rd_v,n_rs1_v,n_rs2_v);
op_dec(op=>inst_d_v,pc=>pc,npc_o=>npc_v,npc_maj=>npc_mav,
       psr=>psr_c,fcc=>fpu_fcc,fexc=>fpu_fexc,annul_o=>annul_v);
```

`psr_c` is produced **combinationally from the ALU of the instruction currently in EXE** ([`iu_pipe5.vhd:1016-1017`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1016-L1017)). A `SUBcc; Bcc` pair therefore resolves with no bubble. The cost is a timing path: bypass mux → adder → ICC → `icc_test` → nPC mux → fetch-address register ([`iu_pipe5.vhd:736-738`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L736-L738), [`iu_pipe5.vhd:410`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L410)).

The `KEEP` attributes on `syn_npc_dec_c` and `npc_p4` ([`322-324`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L322-L324), "Optim. Synth.") keep the target adder and pc+4 as separate nodes, so the condition acts as a late select. This is a partial mitigation only.

**For the 603e:** do not copy this CR→fetch combinational path. Resolve in EXE with CR forwarding and static prediction or a BTIC.

**Delay-slot / annul model:**
- nPC is architectural: `pc<=npc; npc<=npc_c` ([`390-392`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L390-L392)).
- The annul bit is a registered flag (`annul`). The next decoded instruction becomes a bubble marked `anu=1`, with `rd_maj<='0'` and `mode<=CALC` ([`653-666`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L653-L666)). Annulled instructions still flow down the pipeline so the PC and trace stay consistent.
- JMPL/RETT targets come from EXE (`npc_exe_c`, [`731-735`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L731-L735)). Fetch is simply not advanced while a JMPL sits in EXE.
- There is **no prediction**: the whole design is built around the delay slot.

### Fetch
Fetch keeps up to **2 requests outstanding** (`inst_lev` 0..2) and a **2-entry return buffer** (`inst_r_mem`, `inst_r_mem2`, `inst_r_lev`, [`454-474`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L454-L474)).

**Why:** the memory side's data phase cannot be back-pressured (`dack` is always '1', see [`mcu_simple.vhd:33`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L33)). The fetch unit must therefore absorb up to two in-flight words when DECODE stalls. An assertion checks for overflow:

```vhdl
-- iu_pipe5.vhd:482-483
ASSERT inst_r.dreq='0' OR inst_r_lev/=2 OR as_dec_c='1'
  REPORT "ECRASEMENT" SEVERITY error;
```

The request's `cont` bit (`npc_cont_c`, meaning "sequential with the previous fetch") is passed to the MCU so it can stream I-fill data straight to the IU (section 6).

---

## 2. Decode

### One decoded control word, `type_cat`
`type_cat` ([`iu_pack.vhd:223-244`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L223-L244)) holds:
- `op`, the raw opcode, kept for the late stages.
- `mode`, a 7-bit one-hot-ish record `L S D J B F M`: load, store, double, jump, branch, FPU, mul/div.
- `priv`, `sub` (the ALU inverts rs2), and `size` (sign plus size).
- Write enables: `m_reg`, `m_ry`, `m_psr`, `m_psr_icc`, `m_psr_cwp`, `m_psr_s`, `m_wim`, `m_tbr`.
- Read dependencies: `r_reg(1..3)` for rs1/rs2/rd, `r_ry`, `r_psr_icc`, `r_fcc`.

Mode constants are defined as a table ([`iu_pack.vhd:199-217`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L199-L217)):

```vhdl
--                                      L   S   D   J   B   F   M
CONSTANT LOAD_DOUBLE    : type_mode :=('1','0','1','0','0','0','0');
CONSTANT FPSTORE_DOUBLE : type_mode :=('0','1','1','0','0','1','0');
```

Per-class templates (`CAT_LOAD`, `CAT_JMPL`, `CAT_RETT`, `CAT_MULDIV`, ..., [`iu_pack.vhd:767-833`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L767-L833)) are copied and then patched. The big `decode` procedure ("Grand Décodage Universel", [`iu_pack.vhd:834-1458`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L834-L1458)) is a nested `CASE` on `op`/`op2`/`op3`.

**Best practice:** later stages use only the flag bits (`cat.mode.l`, `cat.m_psr_icc`, ...) and never re-decode opcodes. The exceptions are a few `op(…)` peeks, for example ALU `op3` in `op_alu` and CASA detection.

### Keeping decode off the critical path
Decode is only partly kept off the critical path:
- **Helps:** the register-file read addresses (`dec_n_rs1_c`) are computed from decode *combinationally* and drive the synchronous BRAM read in the same cycle ([`iu_pipe5.vhd:342`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L342), [`590-602`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L590-L602)). The window mapping `regad()` (section 3) sits on this path, before the BRAM address register.
- **Hurts:** decode is not pre-decoded in fetch or the I-cache. Decode, window mapping, the dependency compare *and* branch resolution all run in one cycle from the raw instruction word, which may come directly from `inst_r.d` when the buffer is empty ([`524-532`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L524-L532)). A 603e should either register the instruction before decode (a 2-entry IQ) or pre-decode at I-cache fill.

### Next-CWP anticipation in decode
`cwpcalc` ([`iu_pack.vhd:1483-1512`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L1483-L1512)) computes the post-SAVE/RESTORE window in DECODE ([`iu_pipe5.vhd:553-555`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L553-L555)). The instruction's own `rd` is then mapped with the *new* window (`num_rd_v:=regad(n_rd_v,next_cwp_v,…)`, [`599`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L599)) while its sources use the old one. This is the SPARC equivalent of rename-at-decode for a single "rename" (the window pointer).

---

## 3. Register file (iu_regs_2r1w.vhd, fpu_regs_2r1w.vhd)

### Integer: 2R1W built from two 1R1W RAM copies
Both copies are written identically ([`iu_regs_2r1w.vhd:50-70`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_regs_2r1w.vhd#L50-L70)). The size is `NWINDOWS*16+8` = 136 × 32 for 8 windows ([`iu_pipe5.vhd:331`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L331)), so each copy fits in one M10K (256×32).

```vhdl
regfile1: PROCESS (clk) BEGIN IF rising_edge(clk) THEN
  IF rd_maj='1' THEN mem1(n_rd):=rd; END IF;
  rs1_i<=mem1(n_rs1);
END IF; END PROCESS;
```

An optional write-through register (`THRU`) compares the addresses in the *previous* cycle and muxes in a delayed copy of `rd` ([`72-90`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_regs_2r1w.vhd#L72-L90)). In the pipeline it is disabled, and forwarding comes from `pipe_wri` instead.

**Pitfall (read-during-write semantics):** the `shared variable` is written *before* it is read inside the process. VHDL simulation therefore returns **new** data, even though the generic's comment says "THRU=false: old value". Quartus has to emulate new-data with extra logic, because M10K mixed-port RDW is old or don't-care.

The FP register file adds `ramstyle "M9K, no_rw_check"` ([`fpu_regs_2r1w.vhd:45-48`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_regs_2r1w.vhd#L45-L48)). Synthesis then gives don't-care while simulation gives new data: a **sim/synth mismatch**, masked only because `THRU=>true` adds the explicit bypass.

**Lesson:** always pair `no_rw_check` with an explicit registered bypass, and write read-then-write ordering (or old-data) deliberately.

The `M9K` string is a stale Cyclone III/IV name on Cyclone V. It is harmless, but should be avoided.

### Register windows mapped to linear RAM
Implemented in `regad` ([`iu_pack.vhd:456-473`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L456-L473)):

```vhdl
v:=r;
IF v<8 THEN o:=v;                                     -- globals 0..7
ELSE o:=16*to_integer(cwpfix(cwp,NWINDOWS)) + v; END IF;
IF o<NWINDOWS*16+8 THEN RETURN o;
ELSE RETURN o - NWINDOWS*16; END IF;                  -- wrap: ins of last window
```

Each window owns 16 new registers (locals and outs). The previous window's outs overlap the current ins through the `16*cwp + r` arithmetic, and the top window's ins wrap to the bottom. The result is the physical index used for dependency checks (`regnum`, 0..135). Because hazards are checked on physical numbers, window aliasing is handled automatically.

**Transferable idea:** do the architectural→physical mapping *before* hazard compare and the RF read, so the rest of the pipeline only sees physical indices. This is exactly where 603e rename-register lookup belongs.

### FP register file
The FP register file ([`fpu_regs_2r1w.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_regs_2r1w.vhd)) is 16 × 64 bits: each even/odd register pair is stored as one 64-bit entry, in 4 RAMs (hi and lo halves × 2 read ports) with **independent hi/lo write enables** `fd_maj(0 TO 1)`:
- A single-precision write updates one half.
- A double write updates both halves in one cycle.
- LDDF writes hi, then lo, over two bus beats (`ld_hilo`, [`fpu_simple.vhd:318-327`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L318-L327)).

The single operand is selected by `n_fs(0)` in a mux after the RAM ([`fpu_simple.vhd:595-598`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L595-L598)).

The address is 1 bit wider than needed. The upper half of the space holds the **deferred FP trap queue (DFQ)** entries `{pc, op}` (`n_fd_c<='1' & dfq_lev_i & '0'`, [`fpu_simple.vhd:259-262`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L259-L262)), so the DFQ costs no extra storage. **Clever reuse** of spare BRAM depth.

---

## 4. Multiply / divide (iu_muldiv.vhd)

### Interface
- `req` is asserted while the MUL/DIV instruction is in EXE: `muldiv_req_c<=pipe_dec.cat.mode.m AND as_exe AND pipe_dec.v` ([`iu_pipe5.vhd:922`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L922)).
- EXE holds (`as_exe_c<='0'`) until `ack`, and `muldiv_ack_mem` remembers an `ack` that arrived while MEM was stalled ([`1046-1050`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1046-L1050), [`1075-1079`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1075-L1079)).
- Results rejoin through the normal ALU result mux inside `op_alu`, where `rd_ot:=muldiv_rd` ([`iu_pack.vhd:1684-1703`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L1684-L1703)). So there is no extra write port or bypass source.
- The operands are required to stay stable: they come from the frozen EXE operands.

### Variants per technology
Selected by `TECHS(TECH).mul/div` ([`cpu_conf_pack.vhd:184-213`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/cpu_conf_pack.vhd#L184-L213)):

| Mode | Implementation | Latency |
|---|---|---|
| `mul=0` | 1 bit/cycle shift-add | 32 cycles |
| `mul=2` | **four 17×17 signed partial products** | 4 cycles ([`iu_muldiv.vhd:144-207`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_muldiv.vhd#L144-L207)) |
| `mul=7` / `div=7` | simulation-only `*` and `/` | 1 cycle |
| `div=0` | non-restoring divider | ~34 cycles |

The 4-cycle multiplier uses one small DSP and accumulates in a 34-bit accumulator. The sign is handled by feeding `(x(31) AND signe)` as a 17th bit. Even the Cyclone V setting uses `mul=2` (`ITECH_CYCLONE5 := (2,0,1,0)`), because it is cheap and short-path.

The non-restoring divider includes V8 overflow saturation and a final correction step ([`209-341`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_muldiv.vhd#L209-L341)). It has an **early out for divide-by-zero** at cycle 1 ([`331-336`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_muldiv.vhd#L331-L336)), which sets `dz` and forces `ack`.

**Note:** there is no early out for small operands. The ICC N/Z flags are computed from `rd_ot` inside the unit ([`433-434`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_muldiv.vhd#L433-L434)), so the flag logic is not on the ALU path.

---

## 5. FPU (fpu_simple.vhd, fpu_calc.vhd, fpu_mul.vhd, fpu_div.vhd, fpu_pack.vhd)

### IU↔FPU protocol: commit-gated retirement
This is **highly relevant to a completion queue**.

- The FPop is **issued at IU DECODE**: `fpu_req_c<='1'` when `cycle_dec=0` ([`iu_pipe5.vhd:710-712`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L710-L712)), with `fpu_i.cat<=pipe_dec_c.cat`.
- The FPU pushes the op into a 4-entry in-order FIFO (`type_fifo`, [`fpu_simple.vhd:120-133`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L120-L133)) and starts `fpu_calc` immediately.
- When the op reaches IU WRITE with no trap, the IU pulses `fpu_i.wri` ([`iu_pipe5.vhd:1306-1307`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1306-L1307)).
- The FPU counts committed ops in `wri_cpt` and **writes a result to the register file only when `calc_fin` coincides with a pending commit** ([`fpu_simple.vhd:228-242`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L228-L242)):

```vhdl
IF calc_fin='1' THEN
  IF i.wri='1' OR wri_cpt>0 THEN
    pop_v:='1'; ... write FR / FSR / push DFQ ...
  ELSE
    -- no commit yet: stall the FP pipe, hold result
    calc_stall_c<='1';
```

- On an IU trap, `tstop` sets `flush_pend`. Once all *committed* ops have drained (`wri_cpt=0`), the FPU flushes its pipe and FIFO ([`fpu_simple.vhd:560-569`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L560-L569)). Speculative FPops younger than the trap never update architectural state.

This is exactly the 603e rule that FPR writeback happens at or after completion. Here it is done with **one counter instead of a reorder buffer**, which works because the FPU completes in order.

### Scoreboard
- `o.rdy` goes low if an FPop's `fs1` or `fs2` matches `n_fd` of any of the 4 FIFO entries (`deps()` handles single/double overlap, [`fpu_simple.vhd:176-183`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L176-L183), [`441-452`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L441-L452)).
- It also goes low on FP load/store↔FPop phase mixing (`opls`), or when `calc` is not ready.
- FBfcc waits for `fccv = NOT fifo_lv` (FIFO empty, [`590`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L590)). This is very conservative, but simple.

### Deferred traps (SPARC `fp_exception`)
When an op completes with an enabled IEEE exception:
- The FPU sets `exception`, writes `ftt/cexc`, and pushes `{pc, op}` into the DFQ.
- Younger completed ops are also pushed to the DFQ ([`fpu_simple.vhd:268-273`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L268-L273)).
- The IU sees `fexc` and traps the *next* FP instruction in EXE ([`iu_pipe5.vhd:893-901`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L893-L901)).

The PowerPC FPU uses precise-or-imprecise modes, so only the FIFO and commit-counter part transfers.

### Calculation pipeline ([`fpu_calc.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_calc.vhd))
There are 4 stages, C1..C4: unpack and align, then add/sub *or* mul/div, then round, then pack. Each stage has its own valid bit and a backward-ready chain `asN_c` ([`fpu_calc.vhd:185-193`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_calc.vhd#L185-L193)):

```vhdl
as2_c<=NOT c2.v OR (as3_c AND c2_rdy_c);
as3_c<=NOT c3.v OR (as4_c AND c3_rdy_c);
as5_c<=NOT stall WHEN NOT SSTALL ELSE NOT mem_stall;
```

**`SSTALL` output skid register** ([`83`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_calc.vhd#L83), [`776-803`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_calc.vhd#L776-L803)): "Synchronous STALL, no comb. path with input". When `stall` arrives in the same cycle as `fin`, the result is captured in `mem_fd/mem_fcc/mem_exc` and presented from there. The ready chain sees the registered `mem_stall` instead of the external `stall`. **Best practice:** this is the fix the IU's own AS chain lacks.

Latencies (header [`fpu_calc.vhd:12-24`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_calc.vhd#L12-L24)):
- MOV/NEG/ABS: 2 cycles.
- ADD/SUB/CMP/conversions: 4 cycles.
- FMULs: 4 cycles; FMULd: 5 cycles on Spartan-6, and the same as single on Cyclone V.
- DIV/SQRT: 25 or 54 iterations.

There is **one shared add/convert datapath and one shared mul/div/sqrt datapath** for single and double. Singles are mapped into the double layout with `conv_in` and `conv_out` ([`fpu_pack.vhd:476-503`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_pack.vhd#L476-L503)).

### Multiplier ([`fpu_mul.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_mul.vhd))
- `fmul=1` (Cyclone V) does the 53×53 multiply in one registered cycle, with the sticky bit computed as `v_or(mul(50 downto 0))` ([`208-231`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_mul.vhd#L208-L231)). This is likely a DSP-cascade critical path.
- `fmul=0` (Spartan-6) splits the operands into 17-bit slices, with 2 passes for double using `mul_bsy` ([`83-196`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_mul.vhd#L83-L196)).

### Divider ([`fpu_div.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_div.vhd))
- A **combined non-restoring DIV/SQRT** shares one loop; SQRT only differs in the `dnr_m` bit injection ([`233-305`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_div.vhd#L233-L305)).
- SRT radix-2 and radix-4 carry-save variants exist (with a 1024-entry digit-selection table, [`94-229`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_div.vhd#L94-L229)). The header warns `<AVOIR> : Bugs diviseurs SRT`, and Cyclone V uses `fdiv=0`. **Pitfall:** do not trust the SRT code.

### IEEE corner cases
- 5-bit class vector computed once at unpack (`class()`, [`fpu_pack.vhd:516-560`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_pack.vhd#L516-L560)), with predicates `is_nan/is_snan/is_inf/…`.
- Tree leading-zero counter `clz64` ([`364-377`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_pack.vhd#L364-L377)), with a log-depth `enc`/`clzi` combine.
- Denormals are handled in hardware and iteratively (`DENORM_HARD`, `DENORM_ITER` flags, [`fpu_simple.vhd:102-109`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L102-L109)); unfinished-FPop traps are an option.
- **Pitfall for PowerPC:** "NaN contents are not preserved; NaN sign not preserved for subtraction" ([`fpu_pack.vhd:13-14`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_pack.vhd#L13-L14)). PowerPC requires propagating the first QNaN operand (a quieted SNaN), and has FPSCR fields (FPRF, FR/FI, VXSNAN/VXISI/…) that SPARC lacks. The datapath structure is reusable; the NaN/flag layer is not.

### Shared FPU for SMP ([`fpu_multi.vhd:92-280`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_multi.vhd#L92-L280))
One FPU serves N CPUs:
- The register-file address is extended by `NB` CPU-index bits, so each CPU gets a private register bank in the same RAM.
- FSR and exception state are arrays indexed by `cpusel`.
- The FPU switches owner only when idle (`fifo_lv='0' AND wri_cpt=0 AND exception="0000"`).

This is an interesting area trick, but not needed for a 603e.

---

## 6. Memory subsystem (mcu_simple.vhd, mcu_tw.vhd, mcu_pack.vhd, mcu_multi*.vhd)

### Bus protocol: PLOMB ([`plomb_pack.vhd:57-83`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/plomb/plomb_pack.vhd#L57-L83))
PLOMB is a split-transaction, pipelined bus:
- Address phase `req`/`ack`; data phase `dreq`/`dack`.
- A **per-beat error code** `code ∈ {PB_OK, PB_ERROR, PB_FAULT, PB_SPEC}` travels with the data.
- Other fields: `burst` (1/2/4/8), `cont` (sequential), `cache`, `lock`, `asi`.

Records are flattened with `pb_flat` ([`190-215`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/plomb/plomb_pack.vhd#L190-L215)) to pass through BRAM FIFOs.

**Best practice:** MMU faults and bus errors come back *as data*, in the response code. The IU turns them into traps only when the instruction reaches the commit point:
- Fetch faults ride with the instruction word and are ignored if it is annulled ([`iu_pipe5.vhd:541-551`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L541-L551)).
- Data faults are converted in WRITE ([`1212-1217`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1212-L1217), `plomb_trap_data` at [`iu_pack.vhd:751-763`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L751-L763)).

### Two-phase access pipeline in the MCU
Every access takes two phases (header [`mcu_simple.vhd:24-26`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L24-L26)):

**Phase A (the cycle `data_w` is valid):**
- Fully-associative L1 TLB compare, `tlb_test` over `N_DTLB=4` flip-flop entries ([`mcu_simple.vhd:480-490`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L480-L490)). Only the one-hot hit vector is registered.
- Speculative read of cache tag and data BRAMs at `data_w.a` (VA index) ([`1121-1127`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L1121-L1127)).
- Speculative precompute of the MMU register readback value (`dreg`, [`1253-1298`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L1253-L1298)).

**Phase B (`data2_w`):**
- Build the selected TLB entry by **AND-OR of the one-hot hit vector** (`tlb_or`, [`507-513`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L507-L513)), with no priority mux.
- Translate (`tlb_trans`), compare tags per way (`ptag_test` / `vtag_test`), and select data by OR-reduction:

```vhdl
-- mcu_simple.vhd:549-563
FOR i IN 0 TO WAY_DCACHE-1 LOOP
  IF DPTAG THEN ptag_test(vcache_hit_v(i),…,dcache_t_dr(i),pa_v,…);
  ELSE          vtag_test(vcache_hit_v(i),…,dcache_t_dr(i),data2_w.a,mmu_ctxr,…);
  END IF;
  IF vcache_hit_v(i)='1' THEN
    cache_tag_v:=cache_tag_v OR dcache_t_dr(i);
    cache_d_v  :=cache_d_v   OR dcache_d_dr(i);
  END IF;
END LOOP;
```

This is effectively **VIPT/VIVT with a 1-cycle hit**: index by VA, compare against a PA tag (`DPTAG`) or a VA+context tag. The configuration uses 4 KB/way × 4 ways with 32-byte lines ([`cpu_conf_pack.vhd:77-87`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/cpu_conf_pack.vhd#L77-L87)), so index bits ≤ page bits and physical tags have no aliasing.

**Just-after-tablewalk bypass:** after a walk, `data_jat` makes phase B use the freshly written TLB entry (`dtlb_mem`) directly instead of re-comparing ([`502-506`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L502-L506)).

**BRAM address mux idiom** ([`mcu_simple.vhd:1062-1127`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L1062-L1127)), with priority order:
1. Fill address.
2. Phase-B address, for writes, inval and LRU writes, and when stalled (`na_v='0'`).
3. The next phase-A address.

A hold register `dcache_t_mem` plus `dcache_tmux` ([`mcu_simple.vhd:1237`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L1237), [`1308`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L1308)) keeps the tag outputs valid while blocked.

### Tags pack V/M/Shared/LRU in the same word
The tag functions are at [`mcu_pack.vhd:998-1047`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_pack.vhd#L998-L1047):
- `ptag_encode` squeezes a 36-bit PA into 32 bits by reusing the index bit positions freed below the way size: `tag(31 DOWNTO NB_CACHE-4):=pa(35 DOWNTO NB_CACHE)`.
- Bit 0 is V, bit 1 is M (or S for virtual tags), bit 4 is SHared (MESI via `ptag_decode`), and bits 3:2 hold **2 bits of LRU history per way**.

**LRU state lives in the tag RAM:** a 4-way LRU permutation (8 bits) is spread as 2 bits across each of the 4 ways' tags (`hist_v(i*2+1 DOWNTO i*2):=dcache_tmux(i)(3 DOWNTO 2)`, [`mcu_simple.vhd:569-571`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L569-L571)). `tag_maj` rewrites *all ways'* tags whenever the order changes ([`mcu_pack.vhd:1210-1258`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_pack.vhd#L1210-L1258)). There is no separate LRU RAM and no extra port.

The cost: a read hit that changes the LRU order needs a tag write, so the ack is delayed one cycle (`na_v:=… NOT rmaj_v; readlru_v:=NOT na_v`, [`mcu_simple.vhd:760-762`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L760-L762)). Policy "A" only updates when the way was not already the most recent ([`mcu_pack.vhd:30-40`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_pack.vhd#L30-L40)), which limits that cost to non-repeating hits.

**Victim selection:** `tag_selfill` picks an invalid way first, otherwise the LRU-oldest ([`mcu_pack.vhd:1188-1204`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_pack.vhd#L1188-L1204)).

### Write policy
The simple MCU is **write-through, no allocate** (header [`mcu_simple.vhd:16`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L16)). Stores are **posted**: the store is acknowledged to the IU as soon as the external interface accepts it (`IF data_ext_rdy='1' THEN -- Ecriture postée`, [`mcu_simple.vhd:813-817`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L813-L817), [`mcu_simple.vhd:792-796`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L792-L796)).

The external interface holds **one registered slot per requester with zero-delay bypass** (`data_ext_mem` plus `data_ext_reqm`, [`mcu_multi_ext.vhd:215-250`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_multi_ext.vhd#L215-L250)). In practice this is a 1-entry store buffer per port.

Store-miss on a virtually tagged cache: the line is invalidated for alias protection ([`mcu_simple.vhd:787-790`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L787-L790)).

Write-back and allocate exist only in `mcu_multi` (FILLMOD = RWITM, FLUSH = writeback, EXCLUSIVE), limited to physical RAM below `WBSIZE` ([`mcu_tw.vhd:654`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L654): `wbzone`).

### Line fill
- The burst starts at the **line-aligned address** (`ext_w_i.a(NB_LINE+1 DOWNTO 2)<=(OTHERS=>'0')`, [`mcu_simple.vhd:2394-2398`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L2394-L2398)). It is *not* critical-word-first.
- It does **early restart**: the requested word is forwarded to the IU as it passes (`ext_dreq_data … AND ext_fifo.va(…)=ext_fifo.al`, [`2319-2329`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L2319-L2329)).
- **I-stream from fill:** while an I-line fills, sequential fetches (`cont=1`) are served directly from the fill beats (`inst_cont`, [`1500-1507`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L1500-L1507), [`1916-1923`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L1916-L1923)).

For the 603e (60x bus with critical-word-first bursts), keep early restart plus fill streaming and add wrap ordering.

### MMU / TLB hierarchy ([`mcu_tw.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd))
- **L1 TLBs:** 4 instruction and 4 data entries in flip-flops, fully associative, LRU ([`mcu_pack.vhd:24-28`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_pack.vhd#L24-L28)). Replacement fills an invalid entry first, then the LRU-oldest ([`mcu_simple.vhd:1147-1190`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L1147-L1190)). **Probing all entries at once is the CAM emulation.**
- **L2 TLB:** direct-mapped in one BRAM (`i_l2tlb`, `2^NB_L2TLB` = 128 entries). **Tag and PTE are interleaved** at even and odd addresses (`l2tlb_a(0)` selects tag or data), so one 32-bit-wide RAM holds both. A hit costs two sequential reads (`sTABLEWALK` → `sTABLEWALK_L2TLB`, [`mcu_tw.vhd:369-375`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L369-L375)).
- **Page-walk caches:** one L0 PTD and `N_PTD_L2` level-2 PTDs each for I and D, in flip-flops with LRU ([`120-150`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L120-L150), [`376-396`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L376-L396), [`484-502`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L484-L502)). A walk starts at level 3 or level 1 instead of the context table.
- **Hardware R/M update:** after a walk, the walker writes back the PTE with R or M set, as a locked read-modify-write ([`mcu_tw.vhd:512-535`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L512-L535)). An L2TLB hit that needs R/M set falls back to a real walk ([`mcu_tw.vhd:566-571`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L566-L571)). A store to a clean page triggers a "TABLE_MOD" walk before the write ([`mcu_simple.vhd:707-718`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L707-L718)). This matches PowerPC's hardware R/C update on the 603e: there the walk is software, but R/C updates happen on TLB reload.

### Flash-invalidate by epoch (very clever)
The L2 TLB tag compare replaces the (redundant) index bits of the VA with a **generation counter** `l2tlb_cpt2`:

```vhdl
-- mcu_tw.vhd:265-273
vtag_test(l2tlb_hit_v,ig_v,l2tlb_dr,
          tww.va(31 DOWNTO NB_L2TLB+13) & l2tlb_cpt2 & tww.va(11 DOWNTO 0), …);
l2tlb_tag_v:=vtag_encode(tww.va(31 DOWNTO NB_L2TLB+13) &
                         l2tlb_cpt2 & tww.va(11 DOWNTO 0), …);
```

- Any TLB flush or context-table change increments the epoch ([`mcu_tw.vhd:613-619`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L613-L619)), so every existing entry misses instantly.
- To stop stale entries matching again after the epoch wraps, each flush also schedules **one background scrub write**: `l2tlb_ipend/dpend` count pending scrubs, `l2tlb_icpt/dcpt` walk the index, and scrubs run only when the walker is idle ([`331-339`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L331-L339), [`621-633`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L621-L633)). With an (N+1)-bit epoch and N index bits, every entry is scrubbed before any epoch value repeats.

**Directly applicable** to 603e `tlbia`, segment-register writes and `tlbie` of a whole class, as well as BAT/SR changes invalidating the BTIC or I-cache.

### Snooping and coherency (`mcu_multi`, `mcu_multi_ext`, `smpmux`)
- All tag RAMs (and data RAMs) are **true dual-port** (`iram_dp`, [`mcu_multi.vhd:336`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_multi.vhd#L336), [`366`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_multi.vhd#L366), [`426-452`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_multi.vhd#L426-L452)). Port 1 is the CPU lookup; port 2 belongs to the external engine for fills, writebacks and snoops.
- `smpmux` broadcasts the granted transaction on `smp_r`. Every CPU looks it up through port 2 ([`mcu_multi_ext.vhd:369-420`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_multi_ext.vhd#L369-L420)) and answers with `hit` (sets `hitx` so the requester fills Shared instead of Exclusive) or `cwb` (modified hit, coherent writeback).
- The **requester's own victim selection and writeback go through the same port-2 path** at grant time (`sel` distinguishes self from other). A single snoop pipeline serves both.
- The MESI state is encoded in the tag bits.

The 603e is not SMP, but it snoops the 60x bus (ARTRY/SHD). The **dual-port tag RAM with a snoop/fill port** is the right structure there too.

### Alignment and ASI handling
- `align()`, `ld()`, `st()` and `ldst_be()` ([`iu_pack.vhd:572-666`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L572-L666)) are pure functions: stores replicate data across byte lanes and generate byte enables; loads extract and sign-extend in WRITE (`rd_c<=ld(size,adrs10,data_r.d)`, [`iu_pipe5.vhd:1235-1236`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1235-L1236)).
- The ASI travels on the bus, and the MCU dispatches on it with a `CASE` ([`mcu_simple.vhd:653-958`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L653-L958)): MMU registers, flush/probe, cache tag diagnostic access, physical pass-through `0x20-0x2F`, and cross-domain accesses.
- **Cross path:** a data-side request that targets the I-side (I-TLB flush, I-cache flush, instruction-space ASI) goes through the `sCROSS`/`sCROSS_DATA` handshake into the I-side state machine ([`991-1007`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L991-L1007)), rather than duplicating I-cache ports.
- For the 603e, the equivalents are `icbi`, `tlbie` and `dcbz`, and the SPR/SR accesses that touch the I-MMU.

---

## 7. Exceptions, traps and interrupts

### Detection points
The header summarizes them ([`iu_pipe5.vhd:48-58`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L48-L58)):
- **DECODE:** instruction bus errors or MMU faults (from `inst_r.code`) and instruction watchpoints.
- **EXECUTE:** ALU and LSU traps (illegal, privileged, alignment, window overflow via WIM, tag overflow, divide-by-zero), FP disabled, FP exception, and **interrupts**.
- **WRITE:** data bus errors and MMU faults.

The trap rides in `pipe.trap` (`type_trap = (t, tt)`) and is only acted on at WRITE.

### Priority encoding
Priority comes from the **order of overrides in EXE** ([`iu_pipe5.vhd:878-916`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L878-L916)):
1. Start from the LSU or ALU trap.
2. Override with FP-disabled / FP-exception.
3. Override with privileged instruction ("higher priority").
4. Override with any trap already carried from DECODE, which is older and therefore wins.
5. Only if none of these, an interrupt: `psr.pil<irl OR irl="1111"`, with `et=1`, and **not while a WRPSR is in MEM** (`pipe_exe.cat.m_psr='0'`).

Micro-steps with `cycle/=0` cannot trap. Later stages only add the WRITE-stage bus trap if none is already present ([`1212-1217`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1212-L1217)).

### Kill and redirect (precise)
1. At WRITE, a trap sets `trap_stop_c`, registered as `trap_stop`.
2. While `trap_stop=1`:
   - DECODE outputs `v<='0'`; EXE outputs `v<='0'`; MEM squelches `data_w.req`.
   - EXE **restores PSR and Y from the committed copies** (`psr_fin`, `ry_fin`, captured at WRITE when `regs_maj_c=1`, [`1327-1330`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1327-L1330)). It then forces `ET=0`, `S=1`, `PS=S`, `CWP-1` ([`973-990`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L973-L990)).
3. **Drain before redirect:** `trap_stop` stays high until all outstanding fetch and data transactions have returned (`inst_aec=0`, `inst_lev=0`, `inst_r_lev=0`, `data_aec=0`, `data_wu_req='0'`, [`1253-1256`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1253-L1256)). Only then does `trap_stop_delay` start fetching from `TBR.tba & tt & "0000"` ([`728-730`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L728-L730), [`395-404`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L395-L404)).
4. **Saving PC/nPC with no extra write port.** During `trap_stop`, MEM injects a synthetic `CAT_ALU` write of `R18 := trap_npc` ([`iu_pipe5.vhd:1109-1120`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1109-L1120)). WRITE then writes `R17 := trap_pc` into the new window's locals ([`1260-1262`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1260-L1262)). The single register-file write port is reused over two cycles.
5. **Error mode:** a trap with `ET=0` sets `halterror` and stops for the debugger ([`1287-1290`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1287-L1290)).

**Transferable:**
- Keep *committed* copies of any architectural state that EXE updates speculatively (PSR, Y; for the 603e: CR, XER, LR, CTR, MSR), and restore them on flush.
- Drain the outstanding bus transactions before redirecting, so no stale response reaches the new stream.
- Reuse the pipeline to perform the trap side-effect writes. SRR0/SRR1 are SPRs on the 603e, so this becomes an SPR write.

---

## 8. Timing / fmax techniques and non-techniques

**Good practices present:**
- Bypass select precomputed one stage early (`BYPASS_DEC`), described in section 1.
- Register-file addresses computed in DECODE, with BRAM reads registered at the EXE boundary.
- Muldiv flags computed inside the unit; the ALU just muxes.
- TLB compare in phase A, with only the one-hot hit vector registered. AND-OR (one-hot) muxes instead of priority muxes for TLB and cache way selection.
- MMU register readback value precomputed a cycle early (`dreg`).
- FPU output skid register (`SSTALL`) that breaks the combinational stall path.
- Single-precision data mapped onto the double datapath, which saves area.
- Multiplier split into 17×17 slices when the DSP budget or timing is tight.
- Shared 64-bit barrel rotate for SLL/SRL/SRA (`shift`, [`iu_pack.vhd:1517-1560`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L1517-L1560)): the operand is placed in a 64-bit vector whose upper half holds sign bits, rotated right by 5 staged steps, and the left shift is read from the other end. One shifter covers all three ops.
- `KEEP` on the branch-target adder output (`syn_npc_dec_c`).

**Timing weaknesses visible in the code** (these explain a 54 MHz Fmax against a 65 MHz target, and are to be avoided):
- A combinational backpressure chain from `data_r.ack/dreq` to the PC (section 1).
- ICC produced by the EXE ALU feeding branch resolution and the fetch address in the same cycle.
- Decode, window mapping, dependency compare and branch resolution all in one cycle on an unregistered instruction word from the bus.
- One-cycle 53×53 multiply plus sticky OR on Cyclone V.
- Load data aligned (`ld()`) in the WRITE stage and fed straight to the register-file write *and* to `pipe_wri.rd`, which is a bypass source.

There are **no SDC multicycle or false-path constraints** on the core ([`ss.sdc`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/board/mister/SS_MiSTer/ss.sdc) only has `derive_pll_clocks`).

---

## 9. Configurability

**Global CPU personality record.** `type_cpuconf` ([`cpu_conf_pack.vhd:21-53`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/cpu_conf_pack.vhd#L21-L53)) holds NWINDOWS, MULDIV, IFLUSH, CASA, version IDs, NB_CONTEXT, I/D cache size, ways, burst length, physical versus virtual tags, and L2TLB size. The personalities are records in an array, `CPUCONF(CPUTYPE)`, selected by one natural generic `CPUTYPE`. The top level derives `CPUTYPE` from `SS20` ([`ts_core.vhd:205-214`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/ts/ts_core.vhd#L205-L214)). **Best practice:** a single integer generic fans out to a whole coherent configuration, and every consumer reads `CPUCONF(CPUTYPE).FIELD` into local constants ([`iu_pipe5.vhd:75-81`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L75-L81), [`mcu_simple.vhd:81-92`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L81-L92)).

**Technology record.** `type_tech` ([`cpu_conf_pack.vhd:184-204`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/cpu_conf_pack.vhd#L184-L204)) holds `{mul, div, fmul, fdiv}` implementation choices per FPGA family, indexed by the `TECH` generic. Units use `Gen_MUL_2: IF TECHS(TECH).mul=2 GENERATE` and run-time-constant `CASE TECHS(TECH).mul IS WHEN 7 => (sim model)`.

**Architecture selection by file.** One entity file has several architectures in separate files (`iu` → `pipe5`; `fpu` → `simple`; `mcu` → `simple`; `mcu_mp` → `multi` / `multi_avant_x`). The build picks the architecture by which files are in [`files.qip`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/board/mister/SS_MiSTer/files.qip).

This is a **pitfall**:
- Quartus binds the last-analysed architecture.
- A dead variant ([`mcu_multi_avant_x.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_multi_avant_x.vhd)) sits in the tree.
- [`iram_bi.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/peri/iram_bi.vhd) has only the `srec` architecture, which instantiates **two** separate RAMs. The `TagRAMBi` generate in [`mcu_simple.vhd:403-417`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L403-L417), which intended to pack I and D tags into one dual-port BRAM, therefore saves nothing.

In SystemVerilog, prefer an explicit `generate if (VARIANT==…)`.

**Local tuning constants inside architectures.** Examples are `BYPASS_DEC`, `BYPASS_WRI`, `SSTALL`, `DENORM_*`, `FIFO_MAX`, `N_DTLB`, `DTLB_MODE (LRU|CPT)` and `LF_DCACHE (A|B|N)`. They are documented next to the declaration with the trade-off ("fast" / "small").

**OS workaround flag.** `BSD_MODE` ([`cpu_conf_pack.vhd:181`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/cpu_conf_pack.vhd#L181), used in [`iu_pipe5.vhd:685`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L685) and [`mcu_simple.vhd:661`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L661)) changes both pipeline and MMU behaviour. It is a warning sign that some corners were fitted to OS behaviour rather than to the specification.

---

## 10. Debug and verification

**Debug by instruction injection.** When stopped (`dstop`), the debugger writes an opcode, and `vazy` stuffs it into the decode buffer (`inst_r_mem.d <= debug_t.op`, [`iu_pipe5.vhd:476-480`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L476-L480)). The pipeline then executes it normally:
- Register and memory reads and writes need no separate debug datapath.
- `ppc` selects whether the injected instruction advances the PC.
- The value written back is captured in `debug_rd` ([`1378-1380`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1378-L1380)).
- Instruction and data breakpoints raise `TT_WATCHPOINT_DETECTED`, which becomes a debugger stop at WRITE instead of a trap ([`543-545`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L543-L545), [`883-887`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L883-L887), [`1273-1278`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1273-L1278)).

The control/status register map ([`iu_debug.vhd:8-50`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_debug.vhd#L8-L50)) is reached over a UART byte protocol ([`idu.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/idu.vhd)). A host tool lives in `soft/debugarm` (C with its own [`disas.c`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/soft/debugarm/disas.c)). **Very cheap and powerful**; directly reusable for a 603e JTAG-less debug monitor.

**In-pipeline disassembly.** Each stage has a `string(1 TO 50)` signal (`dias_dec`, `dias_exe`, `dias_mem`, `dias_wri`) set by `disassemble(op, pc)` from `disas_pack`, or to `"<ANNUL>"`, `"<TRAP : …>"` or `"..."`. The waveform then shows the instruction occupying each stage. These are ordinary signals, not `synthesis_off`, and Quartus prunes them because they have no loads. In SystemVerilog, wrap them in `ifndef SYNTHESIS`.

**Execution trace file.** With `DUMP` on, `Sync_DECODE` writes `CID pc : disasm {time}` for each issued instruction, plus trap lines, to `Trace_pipe5.log` ([`776-790`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L776-L790), [`1359-1368`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1359-L1368)). `plomb_log` logs every I and D bus transaction ([`plomb_log.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/plomb/plomb_log.vhd), instantiated sim-only in [`ts_core.vhd:607-613`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/ts/ts_core.vhd#L607-L613)). These traces allow diffing against a reference emulator (for example QEMU or TSIM traces).

**Assertions:**
- Fetch buffer overwrite ("ECRASEMENT", [`482`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/ts/ts_core.vhd#L482)).
- Execution of the poison word `0xBADACCE5` ([`iu_pipe5.vhd:759-767`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L759-L767)); memory initialised with it detects wild jumps.
- `REPORT` on recursive trap (error mode) and on every trap ([`1346-1358`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1346-L1358)).

**On-chip trace.** [`dl_plomb_trace.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/plomb/dl_plomb_trace.vhd) is a 512-entry bus trace buffer with triggers, readable over the debug link.

---

## 11. Other reusable HDL idioms

- **Uniform record-based stage interfaces with helper constructors:** `plomb_rd(a, asi, size)` and `plomb_wr(...)` return a fully-initialised bus record ([`iu_pack.vhd:670-715`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L670-L715)).
- **Default-then-override comb processes.** Each `Comb_X` assigns every output a default at the top, then a priority `IF trap_stop / ELSIF stall / ELSIF bubble / ELSE execute` ladder (for example [`iu_pipe5.vhd:620-724`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L620-L724), [`973-1061`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L973-L1061)). The ladder order *is* the stage's priority policy, and it is readable.
- **Big pure procedures in a package** (`op_alu`, `op_lsu`, `op_dec`, `decode`, `tlb_trans`, `tag_maj`). The stage processes stay short, and the same procedures serve simulation models.
- **Byte-lane BRAM inference:** four 8-bit `shared variable` arrays, one per byte enable ([`iram_srec.vhd:48-94`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/peri/iram_srec.vhd#L48-L94)). This is portable across vendors.
- **Every BRAM behind the same record port** (`type_pvc_w/r`), so cache, TLB and register RAMs are interchangeable wrappers.
- **Status-bit packing into tags:** V/M/SH/LRU in the tag word, and epoch counters folded into the redundant index bits of a direct-mapped tag.
- **Poison constant memory initialisation** (`0xBADACCE5`) combined with an assertion.

---

## Top transferable lessons for a 603e core (ranked)

1. **Commit-gated writeback with an in-order FIFO plus a commit counter.**
   - *Technique:* units that complete in order (FPU, and possibly LSU or MCIU) keep a small FIFO of issued ops. The completion stage pulses `wri` per retired op. A result updates architectural state only when `fin` and a pending `wri` coincide; otherwise the unit stalls. On flush, the unit drains the committed ops, then clears its FIFO.
   - *Why:* precise state without a reorder buffer for in-order-completing units.
   - *Evidence:* [`fpu_simple.vhd:207-242`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L207-L242), [`560-569`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L560-L569); [`iu_pipe5.vhd:1304-1307`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1304-L1307).
   - *603e:* the completion queue sends per-entry commit pulses to the FPU and SRU. Rename-register → GPR/FPR copy happens only on those pulses; flush clears after the committed count reaches zero.

2. **Keep committed shadows of speculatively-updated architectural registers and restore them on flush.**
   - *Technique:* PSR and Y are updated in EXE, but `psr_fin`/`ry_fin` are captured at WRITE and restored on trap.
   - *Evidence:* [`iu_pipe5.vhd:973-990`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L973-L990), [`1327-1330`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1327-L1330).
   - *603e:* CR, XER, LR and CTR (unless renamed) and MSR need committed copies, updated at completion and restored on exception or mispredict flush.

3. **Precompute bypass selects in the stage before use, and register them.**
   - *Technique:* compare destination and source register numbers in decode or dispatch. Register a 2-bit select, or the value itself for already-known producers. EXE is then just a 4:1 mux.
   - *Evidence:* [`iu_pipe5.vhd:113-116`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L113-L116), [`137-184`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L137-L184), [`606-609`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L606-L609), [`837-845`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L837-L845).
   - *603e:* at dispatch, look up the rename tag or ready value for each operand and register the result-bus select. Execute units see only a mux.

4. **Freeze resolved operands into the pipeline register on stall.**
   - *Technique:* when downstream stalls, copy the resolved operand values into the held register and force select = "captured", instead of relying on BRAM outputs and bypass sources that may change.
   - *Evidence:* [`iu_pipe5.vhd:632-642`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L632-L642).
   - *603e:* reservation stations or issue latches must capture operands when the result bus fires. Never depend on a register-file read port holding its value.

5. **Carry faults as data, and trap only at commit.**
   - *Technique:* the bus response has a `code` field; fetch faults travel with the instruction and are discarded if it is annulled or flushed. Data faults become traps at WRITE.
   - *Evidence:* [`plomb_pack.vhd:52`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/plomb/plomb_pack.vhd#L52), [`78-83`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/plomb/plomb_pack.vhd#L78-L83); [`iu_pipe5.vhd:541-551`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L541-L551), [`1212-1217`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1212-L1217); [`iu_pack.vhd:737-763`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L737-L763).
   - *603e:* I-MMU and D-MMU miss or protection results return as a code with the fetch or load. The completion queue raises ISI/DSI/alignment or TLB-miss exceptions only when the entry reaches the head.

6. **Drain outstanding bus transactions before redirecting the fetch stream on an exception.**
   - *Evidence:* [`iu_pipe5.vhd:1253-1256`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1253-L1256) (with the `inst_aec`/`data_aec` counters at [`446-452`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L446-L452), [`1187-1192`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1187-L1192)).
   - *603e:* count outstanding I/D requests (the 60x bus has address and data tenures), block the exception vector fetch until the counts are zero, or tag responses with an epoch and drop stale ones.

7. **Epoch-tagged flash invalidate with lazy background scrubbing.**
   - *Technique:* fold an (N+1)-bit generation counter into the redundant index bits of a direct-mapped BRAM tag. A flush increments the epoch, which invalidates everything instantly. Each flush also schedules one idle-time scrub write, so entries are cleared before the epoch repeats.
   - *Evidence:* [`mcu_tw.vhd:265-273`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L265-L273), [`331-339`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L331-L339), [`613-633`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L613-L633).
   - *603e:* `tlbia`, `tlbie` (congruence-class flush), SR/BAT writes invalidating a BTIC or L2 TLB, and `isync`-driven BTIC flush, all with no multi-cycle stall.

8. **Two-level TLB: small flip-flop fully-associative L1 (CAM emulation) plus BRAM L2 with tag and PTE interleaved in one RAM, plus page-walk caches.**
   - *Evidence:* [`mcu_pack.vhd:24-28`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_pack.vhd#L24-L28), [`73-86`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_pack.vhd#L73-L86); [`mcu_simple.vhd:480-513`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L480-L513), [`1147-1190`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L1147-L1190); [`mcu_tw.vhd:120-150`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L120-L150), [`205-230`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L205-L230), [`369-396`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L369-L396).
   - *603e:* the 603e has 64-entry 2-way I and D TLBs with software reload. Use a small flip-flop micro-TLB for the 1-cycle critical path, backed by BRAM 2-way TLB arrays (tag and PTE interleaved or split). BATs are FF comparators searched in parallel with the micro-TLB.

9. **Two-phase VIPT access: compare TLB and read tag/data BRAMs in phase A, select by AND-OR of one-hot hits in phase B.**
   - *Evidence:* [`mcu_simple.vhd:480-565`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L480-L565), [`1062-1127`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L1062-L1127), [`1308`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L1308).
   - *603e:* the 603e L1 is 8 KB or 16 KB, 2-way or 4-way, with a 4 KB page, so index bits ≤ page offset. Physical tags are alias-free if way size ≤ 4 KB, which holds for 8 KB 2-way and 16 KB 4-way. Use OR-reduction muxes for way select. Hold tag outputs in a register when stalled.

10. **Put the LRU/PLRU bits and the V/M/Shared state in the tag word.**
    - *Technique:* tags carry V/M/SH/LRU; `tag_maj` rewrites all ways together; LRU writes happen only on order change (policy A).
    - *Evidence:* [`mcu_pack.vhd:998-1047`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_pack.vhd#L998-L1047), [`1188-1255`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_pack.vhd#L1188-L1255); [`mcu_simple.vhd:569-575`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L569-L575), [`758-762`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L758-L762).
    - *603e:* MEI (603e D-cache) plus PLRU in the tag RAM avoids an extra LRU RAM. For 2-way, a single bit per set can live in way-0's tag. Budget the extra tag-write cycle, or use a separate MLAB for PLRU if hits must never stall.

11. **Dual-port tag RAM: port 1 for core lookups, port 2 owned by the fill/snoop/writeback engine, with a single snoop pipeline that also picks the requester's own victim.**
    - *Evidence:* [`mcu_multi.vhd:336-452`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_multi.vhd#L336-L452); [`mcu_multi_ext.vhd:180-420`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_multi_ext.vhd#L180-L420).
    - *603e:* 60x snooping (GBL, ARTRY, SHD) and castouts run on port 2, while the core keeps hitting on port 1. `dcbf`, `dcbst` and `dcbi` can use the same engine.

12. **Early restart and fill streaming for sequential fetch.**
    - *Technique:* forward the requested word as the burst passes, and serve following sequential fetches (a `cont` flag on the request) directly from the fill beats.
    - *Evidence:* [`mcu_simple.vhd:1500-1507`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L1500-L1507), [`1916-1923`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L1916-L1923), [`2319-2356`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L2319-L2356); [`iu_pipe5.vhd:410-414`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L410-L414).
    - *603e:* combine with 60x critical-word-first (wrap) ordering. The fetch unit's "sequential" hint lets the I-cache stream 2 instructions per beat into the instruction queue.

13. **Break combinational stall chains with an output skid register** (the FPU does this; the IU does not, and pays for it).
    - *Evidence:* good: [`fpu_calc.vhd:83`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_calc.vhd#L83), [`185-193`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_calc.vhd#L185-L193), [`776-803`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_calc.vhd#L776-L803); bad: [`iu_pipe5.vhd:1156`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1156), [`1297`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1297) feeding `na_c`.
    - *603e:* every unit→completion and completion→dispatch ready/stall signal should come from a register (valid/ready with skid buffers). Never ripple `data_r.ack` to the PC.

14. **Do not resolve branches from EXE-produced flags in the same cycle as fetch redirect.**
    - *Evidence:* [`iu_pipe5.vhd:537-539`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L537-L539), [`736-743`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L736-L743) with `psr_c` from [`1016-1017`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1016-L1017); the result is 54 MHz Fmax in the SS5 build.
    - *603e:* use static prediction or a BTIC at fetch, resolve in the BPU with registered CR/CTR (CR forwarding into a registered compare), and redirect a cycle later.

15. **Map architectural register names to physical indices before hazard compare and the register-file read.**
    - *Technique:* the window mapping `regad` and the next-CWP anticipation in decode mean all hazard logic works on physical indices.
    - *Evidence:* [`iu_pack.vhd:456-473`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L456-L473), [`1483-1512`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L1483-L1512); [`iu_pipe5.vhd:553-605`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L553-L605).
    - *603e:* at dispatch, map rA/rB/rS to rename-buffer or GPR indices, and allocate a rename buffer for rD. Everything downstream compares only physical tags.

16. **Reuse spare BRAM depth and the existing write port instead of adding structures.**
    - *Technique:* the DFQ is stored in unused FP register-file rows ([`fpu_simple.vhd:259-262`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L259-L262), [`516-523`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L516-L523)). Trap PC/nPC saves are injected as normal ALU writes over two cycles ([`iu_pipe5.vhd:1109-1120`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1109-L1120), [`1260-1262`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1260-L1262)). The 64-bit FP register file has split hi/lo write enables ([`fpu_regs_2r1w.vhd:62-101`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_regs_2r1w.vhd#L62-L101)).
    - *603e:* FPR rename buffers can share the FPR BRAM's spare rows. SRR0/SRR1/DAR/DSISR writes on an exception can be sequenced through the normal SPR write path.

17. **Debug by instruction injection into decode, plus per-stage disassembly strings and a DUMP trace.**
    - *Evidence:* [`iu_pipe5.vhd:476-480`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L476-L480), [`543-545`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L543-L545), [`694`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L694), [`776-790`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L776-L790); [`iu_debug.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_debug.vhd); [`plomb_log.vhd`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/plomb/plomb_log.vhd).
    - *603e:* a UART or JTAG monitor that stops completion and injects `mfspr`/`mtspr`/`lwz`/`stw` into the instruction queue gives full state access with no debug datapath. Per-stage `string` or `ifndef SYNTHESIS` disassembly and a commit-order trace can be diffed against a reference model such as PearPC, Dolphin or QEMU.

18. **One personality record plus one technology record, indexed by integer generics.**
    - *Evidence:* [`cpu_conf_pack.vhd:21-53`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/cpu_conf_pack.vhd#L21-L53), [`172-213`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/cpu_conf_pack.vhd#L172-L213); used at [`iu_pipe5.vhd:75-81`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L75-L81) and [`iu_muldiv.vhd:104`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_muldiv.vhd#L104), [`144`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_muldiv.vhd#L144), [`210`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_muldiv.vhd#L210).
    - *603e:* a SystemVerilog `package` holding a `typedef struct packed` config (cache sizes and ways, TLB sets, rename count, FPU present, multiplier style) and a `localparam cfg_t CFG[]` array. Select variants with `generate if`, not by which file is compiled (avoid the `iram_bi` and dead-architecture traps).

19. **Warnings to carry forward:**
    - Register-file read-during-write semantics differ between the VHDL variable ordering and `no_rw_check`; always add an explicit bypass ([`iu_regs_2r1w.vhd:50-90`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_regs_2r1w.vhd#L50-L90), [`fpu_regs_2r1w.vhd:45-48`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_regs_2r1w.vhd#L45-L48)).
    - The SRT dividers are marked buggy ([`fpu_div.vhd:10`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_div.vhd#L10)).
    - NaN payload and sign are not preserved ([`fpu_pack.vhd:13-14`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_pack.vhd#L13-L14)), which is not acceptable for PowerPC.
    - The SS5 build closes with negative setup slack.
    - `inval:='1' <PROVISOIRE>` makes every flush a full-line invalidate regardless of flush type ([`mcu_pack.vhd:1102`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_pack.vhd#L1102), [`1148`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_pack.vhd#L1148)). This is correct but coarse.
