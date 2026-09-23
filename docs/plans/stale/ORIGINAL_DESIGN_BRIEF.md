# PowerPC 603e FPGA Core — Implementation Plan (rev 2)

> Initial scaffold added 2026-09-12: see [ppc603e/README.md](../../../README.md) for implemented behavior and [the task breakdown](TASK_PLAN.md) for dependencies and acceptance gates. This document remains the original target design; its phases and technical assumptions are not completion claims.

> Source audit update (2026-09-12): [SOURCES.md](../../references/SOURCES.md) supersedes this brief’s unsupported technical/source assumptions. The local 603e manual is complete; referenced 601 appendices are absent. PID7v clock-mode fidelity, branch shadow-LR resources, endian transport and variant timing need the recorded source-specific treatment. The target is preserved; these are explicit corrections and open dispositions, not silent reductions in scope.

## Context

Goal: a synthesizable PowerPC processor that executes 602 and 603/603e code, with the **same micro-architecture as the MPC603e** (superscalar dual dispatch, branch folding, rename registers, in-order completion through a completion queue) and a **cycle-faithful 60x bus** so it can be dropped into a system design later. Target device: Cyclone V SoC `5CSEBA6U23I7` (DE10-nano).

Decisions agreed with the user:

| Decision | Choice |
|---|---|
| Deliverable | **CPU core only.** SystemVerilog RTL + Verilator harness + Quartus fit/timing check. No MiSTer `emu`, no board bring-up. |
| Feature scope | **Full 603e:** every implemented instruction, supervisor state, all exceptions incl. 603e TLB-miss and IABR, BAT + software-loaded TLB MMU, 64-bit hardware FPU, 16 KB 4-way I/D caches with MEI coherency, **little-endian mode (MSR[LE]/ILE)**, power-management modes, time base with TBEN. 602 is a configuration of this core. |
| Micro-architecture | **603e structure** per MPC603e UM ch. 1 and 6: fetch → decode/dispatch → execute → complete/writeback; six-entry instruction queue; two dispatch slots; BPU with folding and one level of static prediction; IU, SRU, LSU, FPU each with a reservation station; 5 GPR / 4 FPR / 1 CR / 1 LR / 1 CTR rename registers; five-entry completion queue retiring up to two per cycle. |
| Timing policy | **Documented timing is the target, gate-level timing is not.** Chapter 6 latency tables (6-1 … 6-6), the dispatch/completion resource rules (§6.6.1), serialization classes (§6.3.3.2) and the worked schedules (figures 6-3 … 6-5) are the specification; where the manual is silent, pick the simplest hardware that does not contradict it and document the choice. |
| Bus | **60x bus, as cycle-accurate as the manual allows** (ch. 7 signals, ch. 8 tenures/arbitration/termination, 64- and 32-bit data modes, address pipelining depth 2, ARTRY/DRTRY/TEA, snooping with MEI). Verified with a bus-functional model that checks the ch. 8 timing diagrams. |
| HDL | SystemVerilog per `hdl-coding-guidelines`. |

Judgment calls (say so if you disagree):

- **PID7v-603e is the reference model** (PVR `0x0007xxxx`), because the manual documents it most completely (misaligned LE support, 20-cycle divide, HID0 IFEM/ABE). `CPU_VARIANT` selects PID6-603e (37-cycle divide, no misaligned-LE hardware), 603 (8 KB 2-way caches), and 602 (4 KB caches, 32-entry TLBs, single-precision FPU with DP trapped, protection-only TLB mode, 602 SPR stubs). The 602's own UM is not in hand; its variant is best-effort.
- **Cycle-faithfulness ends at the bus pins and the ch. 6 tables.** Internal structure mirrors the manual's block diagram, but sub-block details the manual does not specify (e.g. exact reservation-station depth per unit, store-queue depth) are chosen for FPGA fit and written down in `docs/ARCHITECTURE.md`.
- **Bring-up parameter `DISPATCH_WIDTH`** (1 or 2) exists only to debug the machine one instruction at a time; the structure (IQ, rename, completion queue) is present from the first RTL. The delivered configuration is 2.
- **Note on sources:** `G5220297-00_Odyssey_MCM_Feb97.pdf` is the IBM *603e multi-chip-module* (603e + 660 bridge) reference-design guide, not the 603e User's Manual. It remains useful for the bus (it is a real 603e system: TT decoding, arbitration, endian handling by the bridge) but the 1997 MPC603e UM is now the primary source.

Everything new lives under `/home/kevin/git/ppc/ppc603e/`, leaving the downloaded artifacts untouched.

---

## 1. Source artifacts and how each is used

| Artifact | Role |
|---|---|
| `1997_MPC603EUM_MPC603e_EC603e_Users_Manual.pdf` (455 pp) | **Primary source.** Ch. 1 (block diagram, execution units, IQ/dispatch/completion overview §1.1.3–1.1.4), Ch. 2 (register set incl. HID0/HID1/IABR/DMISS/IMISS/DCMP/ICMP/HASH1/HASH2/RPA §2.1.2; LE mode and alignment §2.3.x), Ch. 3 (16 KB 4-way caches, MEI §3.6, cache-control instruction bus effects §3.8, state transitions §3.10), Ch. 4 (exception classes, priorities, every vector §4.5.1–4.5.15), Ch. 5 (MMU: BAT §5.3, page history §5.4.1, TLB §5.4.3, software table search §5.5.2 with example handlers §5.5.2.2.1), **Ch. 6 (instruction timing: pipeline stages, IQ, rename, serialization, dispatch/completion rules §6.6.1, latency tables 6-1…6-6)**, Ch. 7 (every 60x signal), **Ch. 8 (bus protocol: tenures, arbitration, transfer attributes, burst order, alignment tables, termination, snooping, 32-bit mode, DBWO)**, Ch. 9 (power modes), App. A (instruction listing), App. B (not implemented: 64-bit ops, `fsqrt`, EC603e FP), App. C (603 vs 603e differences). Note: this copy is ~300 pages short of the full book; gaps are filled from the 601 UM and DingusPPC. |
| `MPC601UM.pdf` | Secondary ISA reference: Ch. 10 per-instruction pseudo-code and App. A encodings (the 603e copy's App. A is a listing only). Filter out 601/POWER-only items (App. C/H). Ch. 6 §6.9 hash function detail. |
| `MPC602EC.PDF` | 602 variant parameters (§1.1.1): 4 KB 2-way caches, 32-entry 2-way TLBs, SP-only FPU, protection-only TLB mode. |
| `MPC601.pdf` | 601 technical summary; historical only. |
| `G5220297-00_Odyssey_MCM_Feb97.pdf` | Real 603e system: ch. 3 (660 bridge response by TT type, table 3-1, address ranges), ch. 8 (interrupt/reset wiring), ch. 11 (bi-endian byte-lane steering as seen by the bridge). Used to build the bus-functional model's "memory controller" behaviour and LE tests. |
| `416591138-MIT.pdf` | Decode categorization (§3.2) and stage/packet abstraction (§2.3.1); divider (fig. 3-3). Reference only. |
| `dingusppc/cpu/ppc/` | **Golden model.** Instruction semantics (`ppcopcodes.cpp`, `ppcfpopcodes.cpp`), exceptions (`ppcexceptions.cpp`: SRR1 masks, DSISR construction), MMU translation (`ppcmmu.cpp`), opcode dispatch tables (`ppcexec.cpp` `OpcodeGrabber`), decode helpers (`ppcdechelpers.h`). Test vectors `test/ppcinttests.csv` (5620) and `test/ppcfloattests.csv` (2054); `test/genppctests.py` encodings; `test/ppctests.cpp` CSV grammar; built with `-DDPPC_BUILD_PPC_TESTS=ON`. Compile-time `SUPPORTS_PPC_LITTLE_ENDIAN_MODE` gives an LE reference. **Gaps:** no 603 software-TLB-miss SPR model (verified from UM §5.5.2 instead); no timing model (timing verified against ch. 6 tables). |
| `powerpc_fpga/` | Tiny iCE40 reference; not reused. |

Still missing, not blocking: the full MPC603e UM (this copy is abridged), *PowerPC 602 User's Manual*, *PowerPC 603e Hardware Specifications* (AC timing — needed only if anyone later wants pin-level setup/hold fidelity).

---

## 2. Repository layout

```
ppc603e/
  README.md
  docs/
    ARCHITECTURE.md      pre-RTL plan (§3): units, queues, rename/completion rules, stage×cycle schedules, bus FSMs
    TIMING_SPEC.md       Ch. 6 tables transcribed as the per-instruction latency/throughput/serialization contract
    BUS_SPEC.md          Ch. 7/8 transcribed: signal list, tenure FSMs, qualified-grant rules, termination, snoop responses
    ISA_MATRIX.md        opcode × variant × {implemented, traps, n/a} × unit × latency, generated
    VERIFICATION.md      test tiers, how to run
  rtl/
    ppc_pkg.sv           types: micro-op, unit_e, rename tags, exc_e, spr_e, MSR/HID0/FPSCR bit localparams
    ppc_core.sv          top: fetch+BPU, dispatch, units, completion, MMUs, caches, bus unit; 60x pins + INT/SMI/MCP/HRESET/SRESET/TBEN/etc.
    ppc_fetch.sv         fetch unit: 2 instr/cycle from I-cache, six-entry IQ (enter at 5, issue from 1/0), branch folding hook
    ppc_bpu.sv           BPU: decode/execute branches at fetch, static prediction (one outstanding), LR/CTR rename, CR-dependency reservation station, mispredict purge
    ppc_dispatch.sv      DQ[0]/DQ[1] rules per UM §6.6.1.2; rename allocation; completion-buffer allocation; serialization classes (§6.3.3.2)
    ppc_rename.sv        5 GPR + 4 FPR + CR/LR/CTR rename registers with tags, feed-forward buses, flush on mispredict/exception
    ppc_regfile_gpr.sv   32×32 GPR (+ TGPR shadow r0–r3), read ports sized for 2 dispatches/cycle
    ppc_regfile_fpr.sv   32×64 FPR
    ppc_iu.sv            integer unit + reservation station: single-cycle ALU/rotate/compare; mul (registered DSP, latencies per Table 6-4); iterative divider (20 or 37 cycles by variant)
    ppc_sru.sv           system register unit: mtspr/mfspr/mtmsr/rfi/sc/CR-logical/mfcr/mtcrf, add/compare path, completion-serialized ops
    ppc_lsu.sv           load/store unit: stage 1 EA+DMMU, stage 2 D-cache; store queue; lmw/stmw/lswi/stswx sequencing; alignment/LE munging; lwarx/stwcx reservation (RSRV pin)
    ppc_fpu.sv           3-stage pipelined FPU (multiply, add, round/convert) per UM §6.4.3 and Table 6-5; fdiv/fres/frsqrte iterative; FPSCR; SP/DP by variant
    ppc_completion.sv    five-entry completion queue: finish tracking, retire ≤2/cycle per §6.6.1.3, exception detection at head, rename→architected commit, flush
    ppc_spr.sv           SPR storage: XER, SRR0/1, SPRG0-3, DAR, DSISR, DEC, TB, SDR1, SRs, PVR, HID0/1, IABR, BATs, TLB-miss SPRs, 602 stubs
    ppc_exc.sv           exception priority/vector logic (UM §4.1–4.2), MSR update, LE/ILE handling, power-mode entry (ch. 9)
    ppc_mmu.sv           I/D MMU: BAT (4+4) → TLB (64-entry 2-way, or 32 for 602) → miss/protection; software search SPR generation (§5.5.2.1)
    ppc_bat.sv, ppc_tlb.sv
    ppc_icache.sv        16 KB 4-way, 32-byte lines, PLRU, locking/invalidate/disable (HID0), M10K
    ppc_dcache.sv        16 KB 4-way, write-back, MEI states, castout/push queues, WIMG, snoop port, dcbz/dcbf/dcbst/dcbi/icbi bus effects (§3.8)
    ppc_bus60x.sv        60x bus unit: address tenure FSM (BR/BG/ABB/TS, TT/TSIZ/TBST/CI/WT/GBL/CSE, AACK/ARTRY), data tenure FSM (DBG/DBB/DBWO, TA/DRTRY/TEA), 2-deep address pipeline, 64/32-bit mode, burst ordering (§8.3.2.3), snoop response, parity generation/check
    ppc_cdc_sync.sv      only if a separate bus clock is ever used; v1 runs core and bus at 1:1
  tb/
    tb_core.sv           Verilator top: core + 60x BFM + flat memory + tohost mailbox
    bfm/bus60x_bfm.sv    bus-functional model: arbiter, memory slave with programmable wait states, ARTRY/DRTRY/TEA injection, snooper; SVA checkers for every ch. 8 rule
    tb_alu_vectors.sv, tb_fpu_vectors.sv, tb_mmu.sv, tb_cache.sv, tb_bus.sv
    timing/              per-instruction latency checks and figure 6-3/6-4/6-5 schedule replays
  sim/  Makefile, cosim/, tests/asm, tests/c, tools/
  quartus/  fit project, SDC, build.sh (docker theypsilon/quartus-lite-c5:17.0.2)
  toolchain/  Dockerfile (gcc-powerpc-linux-gnu), crt0.S, linker.ld, LE variant flags
```

---

## 3. Pre-RTL plan summary (full version in docs/ARCHITECTURE.md)

**Clocks/reset.** Single core clock; bus clock ratio 1:1 in v1 (the 603e supports 1:1, 2:1, 3:1, 4:1 via PLL_CFG; ratio > 1 is a later item and would add a CDC boundary at the bus unit). `HRESET`/`SRESET` semantics per §7.2.9.6; internal `rst_n` sync-released. Target 50 MHz.

**Pipeline (UM §6.2–6.3).**

| Stage | Contents |
|---|---|
| Fetch | I-cache/IMMU request, 2 instr/cycle into IQ; BPU pulls branches out of the stream and folds them; taken branch redirects fetch same cycle it resolves. |
| Decode/dispatch | DQ[0]/DQ[1] = IQ[0]/IQ[1]; rules from §6.6.1.2 (unit free, rename free, completion buffer free, serialization); operands read from register file or rename tag; completion buffer allocated at dispatch. |
| Execute | IU (1-cycle ALU; mul/div multi-cycle), SRU (1–3 cycles, mostly completion-serialized), LSU (2 stages: EA/translate, cache access; store queue), FPU (3 stages: multiply, add, round-convert; ≤3 in flight). Each unit has a reservation station holding one instruction waiting on a rename tag. Results go to rename registers with feed-forward to waiting units. |
| Complete/writeback | Five-entry in-order completion queue; retire rules §6.6.1.3 (CQ[1] must be integer or load; ≤1 CR, ≤2 GPR, ≤1 FPR updates per cycle); exceptions recognized only when the instruction is at the head; branch mispredict flushes everything younger. |

**Serialization classes** exactly as §6.3.3.2: completion-serialized (SRU ops except add/compare, FPSCR/CR-modifying FP ops, cache/TLB management, lmw/stmw/string, sync-class), dispatch-serialized (lmw/lswi/lswx, mtspr(XER), mcrxr, sync/isync/mtmsr/rfi/sc), refetch-serialized (isync).

**Branch handling** per §6.4.1: folding; static prediction by BO hint; one unresolved predicted branch at a time; the listed mtspr(LR/CTR)→bclr/bcctr and back-to-back dependency cases stall fetch as documented.

**Exceptions** per ch. 4: precise; priority table §4.1; vectors 0x100–0xD00, 0x1000/0x1100/0x1200 TLB miss (TGPR remap), 0x1300 IABR, 0x1400 SMI; MSR[ILE]→MSR[LE] copy on entry; MSR[IP] vector base.

**Little-endian mode**: EA munging (xor 0b111/0b110/0b100 by size) in the LSU per UM §2.3.x, instruction fetch unaffected; misaligned LE access → alignment exception on PID6, hardware-handled on PID7v; lmw/stmw/string in LE → alignment exception; DMISS/IMISS always hold BE addresses (§2.1.2 note). Bus byte lanes per ch. 8 alignment tables and MCM ch. 11.

**60x bus (ch. 7/8)**: independent address and data tenures, each arbitration/transfer/termination; qualified BG = BG & ~ABB & ~ARTRY; qualified DBG = DBG & ~DBB & ~DRTRY & ~ARTRY; address-only transactions (dcbz, tlbie, sync, eieio, icbi per §3.8); single-beat 1–8 bytes, 4-beat 32-byte bursts (critical-word-first order §8.3.2.3); 32-bit data mode with 1/2/8 beats; up to two outstanding address tenures; ARTRY handling incl. snoop push priority; DRTRY late-cancel; TEA → machine check; parity on A/D with APE/DPE; RSRV, TLBISYNC, TBEN, QREQ/QACK, CKSTP_IN/OUT, MCP, SMI, INT.

**Caches (ch. 3)**: 16 KB, 4-way, 32-byte lines, PLRU; I-cache read-only with icbi/invalidate/lock; D-cache write-back with MEI, castout and push queues, snoop on GBL transactions, WIMG behaviour §3.5, HID0 ICE/DCE/ICFI/DCFI/ILOCK/DLOCK, dcbt/dcbtst touch.

**Resource strategy.** GPR/FPR in flops with enough read ports for dual dispatch; rename registers in flops; IQ/CQ in flops; caches/TLB in M10K with registered reads; integer multiplier and FPU mantissa multiplier on DSPs; dividers iterative. Estimate: 25–35 K ALMs, ~40 M10K, ~14 DSP; fits with margin.

---

## 4. Implementation phases

Every phase ends with `verilator --lint-only -Wall` clean and its gate passing. Phases 1–3 are sequential; 4–8 have the dependencies noted.

### Phase 0 — Scaffolding and specifications
- Repo layout, `sim/Makefile`, `quartus/build.sh` (from `~/git/C16_MiSTer/build.sh`), toolchain Dockerfile (BE and LE build flags), DingusPPC `testppc` built and passing on host.
- **Write `docs/TIMING_SPEC.md`** by transcribing UM Tables 6-1…6-6 and §6.6.1 rules, and **`docs/BUS_SPEC.md`** from ch. 7/8 (signal table, FSM states, every timing diagram reduced to a cycle table). These two documents are the contracts the checkers in phases 2 and 5 enforce.
- Generate `docs/ISA_MATRIX.md` from DingusPPC tables + UM App. A/B, annotated with unit and latency from TIMING_SPEC.

### Phase 1 — Machine skeleton with integer execution
- Fetch/IQ, BPU (unconditional and resolved branches only at first), dispatch with rename and completion queue, IU, SRU (CR-logical, mfcr/mtcrf, mfspr/mtspr XER/LR/CTR), LSU stages with a simple memory port (no cache yet, no MMU: real mode), completion/retire ≤2.
- Bring up with `DISPATCH_WIDTH=1`, then enable 2 and the prediction path.
- **Gate:** all 5620 integer CSV vectors; directed `.S` tests for loads/stores/multiple/string/branches; dual-dispatch sanity (two independent adds retire in one cycle; §6.6.1.3 limits observed).

### Phase 2 — Timing conformance harness
- `tb/timing/`: for every row of TIMING_SPEC, a micro-test measures dispatch-to-finish latency and throughput and compares to the table; replays of figures 6-3, 6-4, 6-5 as cycle-by-cycle expected schedules.
- **Gate:** all latency rows match (or are on a written exceptions list with reason); figure replays match cycle-for-cycle from the dispatch stage onward.

### Phase 3 — Supervisor state, exceptions, cosimulation
- MSR, rfi/sc/mtmsr, all SPRs, exception logic per ch. 4 with priorities, DEC/TB, IABR, trace, SMI, power modes (doze/nap/sleep with QREQ/QACK).
- Cosim harness linking DingusPPC's `cpu/ppc` as a library; retirement-trace lock-step compare; random instruction streams + compiled C tests.
- **Gate:** 10⁷ random instructions zero mismatch; directed exception tests for every vector.

### Phase 4 — MMU (depends on 3)
- BATs, segment registers, 64-entry 2-way TLBs, software table search SPRs and exceptions exactly per §5.5.2 (use the example handlers in §5.5.2.2.1 as the test handlers), tlbie/tlbsync with TLBISYNC pin, R/C bit scenarios §5.4.1.3, 602 protection-only mode.
- **Gate:** `tb_mmu.sv` directed tests; MMU-on Dhrystone with the UM example handlers; cosim with page tables (architectural-effect comparison, since DingusPPC has no software-miss model).

### Phase 5 — 60x bus unit and bus-functional model (can start after 1)
- `ppc_bus60x.sv` per BUS_SPEC; `bus60x_bfm.sv` with arbiter, wait-state memory, snoop agent, ARTRY/DRTRY/TEA injection, 64/32-bit mode, and SVA properties for every ch. 8 rule (qualified grants, AACK/ARTRY window, TA/DRTRY/TEA exclusivity, burst beat count/order, DBB negation, address pipelining depth).
- **Gate:** every ch. 8 timing diagram reproduced by a BFM scenario and passing the checkers; TEA → machine check; ARTRY retry; DBWO ordering.

### Phase 6 — Caches and coherency (depends on 4 and 5)
- I-cache, D-cache with MEI, castout/push, snoop response, cache-control instruction bus operations (§3.8 table), WIMG, HID0 cache bits, lwarx/stwcx with reservation and RSRV pin.
- **Gate:** phases 1–4 tests rerun with caches on and BFM wait states; MEI state-transition tests per §3.10; snoop-hit-on-modified push; dcbz/dcbf/dcbst/icbi bus effects observed on the BFM.

### Phase 7 — FPU (depends on 3; parallelizable with 5/6)
- 3-stage pipelined FPU with Table 6-5 latencies, iterative fdiv, fres/frsqrte estimates, FPSCR/CR effects, denormals, NI mode; 602 variant traps DP ops; EC603e variant traps everything (FP unavailable).
- **Gate:** 2054 float vectors × 4 rounding modes; FP cosim; timing rows for FP instructions.

### Phase 8 — Little-endian mode and remaining full-support items (depends on 3, 5, 6)
- MSR[LE]/ILE, EA munging, misaligned-LE behaviour by PID variant, alignment-exception rules, byte-lane steering on the bus (ch. 8 alignment tables + MCM ch. 11), LE instruction fetch behaviour.
- Parity, checkstop, reduced-pinout mode (§8.6.3), 32-bit data bus mode end-to-end, JTAG/COP left as stubs.
- **Gate:** LE C tests built with `-mlittle-endian`, cosim with DingusPPC LE build, BFM byte-lane checks.

### Phase 9 — Quartus fit and timing
- Fit project with BFM-less BRAM stand-ins on the 60x pins; SDC 50 MHz; read reports per guideline §10; iterate on named critical paths (expected: dispatch resource check, rename CAM compare, completion retire mux, D-cache tag compare + MEI, TLB compare).
- **Gate:** fits, 50 MHz met, resource table in README.

---

## 5. Verification summary

| Tier | Source | Gate |
|---|---|---|
| Lint | `verilator --lint-only -Wall` | zero warnings |
| Vector | DingusPPC int/float CSVs | 100% |
| Directed asm | exceptions, MMU (UM example handlers), string/multiple, reservations, LE | PASS via tohost |
| Timing | TIMING_SPEC rows + figure 6-3/6-4/6-5 replays | match or documented exception |
| Bus | BFM scenarios for every ch. 8 diagram + SVA checkers | zero violations |
| Cache | §3.10 MEI transitions, §3.8 bus operations, snoop tests | PASS |
| Cosim | DingusPPC lock-step (BE and LE builds) | zero mismatches, 10⁷ instr |
| Programs | Dhrystone, CoreMark-lite, MMU-on, FP, LE variants | self-check PASS |
| Synthesis | Quartus 17.0.2 docker | fits, 50 MHz |

Tools on this machine: Verilator 5.020, Icarus 12, Docker 29.8 with `theypsilon/quartus-lite-c5:17.0.2.docker0` pulled, Python 3. Missing: PowerPC cross compiler (Phase 0 Dockerfile).

---

## 6. Open items (do not block start)

1. Abridged UM: confirm which ~300 pages are missing (likely parts of ch. 2 instruction descriptions and ch. 7 signal detail); fill from the 601 UM and flag any rule taken from a non-603e source in the spec docs.
2. 602 details (FPR width, `lfd/stfd` legality, 602 SPRs) need the 602 UM; the 602 variant stays best-effort until then.
3. Bus/core clock ratios > 1:1 and the AC timing of the *603e Hardware Specifications* are out of scope for v1.
4. Core directory name (`ppc603e/` proposed).
