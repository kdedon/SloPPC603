---
name: cpu-register-files
description: Load when implementing or reviewing a CPU register file, rename buffers/physical register storage, multi-ported register arrays on Cyclone V (MLAB/M10K/flops), read-during-write behavior, extra read/write ports, banked or shadow registers, FPR half-word writes, or savestate/debug access to register state. Gives port-replication, bypass, flop-shadow, write-funnel and rename-by-index patterns from shipping FPGA CPUs, plus RDW sim/synth mismatch pitfalls.
---

# CPU register files on FPGA

Evidence links point at the reference cores on GitHub, pinned to the reviewed commits: N64 = VR4300 (N64_MiSTer), PSX = R3000A (PSX_MiSTer), SH2 = SH-2 (Saturn_MiSTer), SS = SPARC V8 (Grabulosaure/ss), ARM7 = ARM7TDMI (Atari7800_MiSTer).

## 1. Storage choice

| Structure | Use | Why |
|---|---|---|
| **MLAB, async read, one copy per read port** | GPR, FPR, small tag arrays | read in the same cycle the index is known; replicate for ports |
| M10K, registered read | large arrays where a read cycle is budgeted | registered address = pipeline register |
| Flops | rename buffers (5 GPR + 4 FPR on 603e), odd extra ports, special regs | cheap at small depth; any number of ports |

- **Replicate per read port, share the write port(s).** N64 two 32×64 MLAB copies ([`cpu.vhd:953-1000`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L953-L1000),
  [`RamMLAB.vhd:30-51`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/RamMLAB.vhd#L30-L51)); PSX three copies incl. a savestate read port ([`cpu.vhd:531-594`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L531-L594)); SH2 two copies.
  603e dual dispatch needs ~4–6 GPR reads: 4–6 MLAB copies of 32×32 is still small.
- **Pin the primitive explicitly** in a wrapper (`altdpram`, `ram_block_type="MLAB"`,
  `rdaddress_reg="UNREGISTERED"`, `outdata_reg="UNREGISTERED"`,
  `read_during_write_mode_mixed_ports="CONSTRAINED_DONT_CARE"`). N64/PSX [`RamMLAB.vhd`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/RamMLAB.vhd). Keep exactly
  one definition per RAM module in the build (SH2 had stale duplicates that differed).
- **Never reset a regfile array.** Resetting forces flops and adds reset fan-out (ARM7 resets 960 bits,
  [`core:2551-2552`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L2551-L2552)). Reset valid bits and map tables only. If zeroed contents are required, walk the
  write port with a counter (PSX [`cpu.vhd:2767-2773`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2767-L2773)).

## 2. Read-during-write

- MLAB mixed-port RDW is don't-care; **cover it with explicit forwarding**, never with vendor bypass logic.
  Either a write-through compare in the read stage (N64 [`cpu.vhd:1259-1267`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L1259-L1267)) or one more forwarding
  stage after writeback (PSX `writeDone`, SH2 `WB2`).
- **Sim/synth mismatch trap:** a VHDL `shared variable` written before it is read simulates new-data,
  while `no_rw_check`/M10K synthesizes old or don't-care. SS [`iu_regs_2r1w.vhd:50-90`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_regs_2r1w.vhd#L50-L90),
  [`fpu_regs_2r1w.vhd:45-48`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_regs_2r1w.vhd#L45-L48). Write the behavioral model with the RDW the hardware will have, and test
  the write-then-read-same-index case explicitly.

## 3. Extra ports without extra RAM copies

- **Flop shadow for a hot register** gives a third read port: SH2 shadows R0 in flops
  ([`SH_regfile.sv:148-162`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_regfile.sv#L148-L162)). PowerPC analogue: none architecturally hot, but rename buffers in flops
  serve the same purpose.
- **Special registers live in flops beside the RAM**: SH2 PR at index 16 muxed outside the 16-deep RAM
  ([`SH_regfile.sv:126-146`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_regfile.sv#L126-L146)).
- **Time-multiplex a second write port onto the idle fast-clock cycle when the core runs at CE = clk/2.**
  SH2 [`SH_regfile.sv:105-126`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_regfile.sv#L105-L126). Hard requirement: CE ≤ clk/2; add an assertion.
- **Stall one cycle instead of adding a write port** when a late result collides with normal writeback
  and the collision is rare. PSX [`cpu.vhd:2158-2161`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2158-L2161).
- Two true write ports otherwise need a live-value table (LVT) or bank split; decide early.

## 4. Write-port funnel: "which" vs "whether"

- **Funnel every write site into N fixed ports.** Select address/data from stable, registered state
  (FSM state, decoded kind); let the late handshake (`mem_ready`, cache hit) drive **only the enable**.
  ARM7 [`core:2479-2546`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L2479-L2546), [`3285-3288`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L3285-L3288) — removed the bus from the regfile data mux.
- Port order resolves same-address conflicts deterministically (ARM7 port B wins: load over base update).
- 603e: one result bus per unit (IU, LSU, SRU, FPU) writing rename slots; completion copies rename →
  architectural file through its own funnelled port(s).
- **Savestate/debug load gets top priority on the existing write mux**; no extra port. N64 [`cpu.vhd:968-974`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L968-L974),
  PSX [`cpu.vhd:546-555`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L546-L555).

## 5. Rename-by-index, never copy data

- **Architectural name → physical index via a map computed from registered state; mode switch,
  exception entry or commit changes the map, never moves data.** ARM7 replaced a banked save/restore
  fabric (~⅓ of the core) with one flat `rf[0:29]` and `rf_index(idx, mode)` ([`core:142-153`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L142-L153), [`474-495`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L474-L495)).
  SS maps register windows to a linear RAM before hazard checks (`regad`, [`iu_pack.vhd:456-473`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L456-L473)).
- **Do the mapping before hazard compare and RAM read**, so everything downstream sees physical indices.
  SS computes the next window in decode so a SAVE's `rd` maps with the new window ([`iu_pack.vhd:1483-1512`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pack.vhd#L1483-L1512)).
- 603e: rename map lookup at dispatch; allocate a rename slot for each destination (including rA for
  update forms and CR/XER if renamed); completion commits by copying slot → GPR (or by remapping, if a
  physical-register-file design is chosen). Flush restores the map from the committed copy.

## 6. FPR specifics

- 64-bit FPRs as two 32-bit halves with independent write enables support partial writes and paired
  modes. N64 [`cpu.vhd:876-947`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L876-L947); SS [`fpu_regs_2r1w.vhd:62-101`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_regs_2r1w.vhd#L62-L101). PowerPC always writes 64 bits (singles
  are stored as doubles), so a plain 64-bit array usually suffices.
- **Spare depth is free storage**: SS stores its deferred-trap queue in unused FPR rows
  ([`fpu_simple.vhd:259-262`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/fpu_simple.vhd#L259-L262)). FPR rename buffers can share spare rows of the FPR RAM.

## 7. Checklist

- [ ] Read ports counted for worst-case dual dispatch (incl. rS for stores, rA for update forms, CR/XER/LR/CTR).
- [ ] One MLAB copy per read port, one wrapper module, RDW declared don't-care.
- [ ] Explicit forwarding covers write→read same index, with a directed test.
- [ ] No reset on array contents.
- [ ] All writes pass through a fixed set of funnelled ports; enables carry the late signals.
- [ ] Architectural→physical mapping happens once, before hazard logic.
- [ ] Savestate/debug access reuses existing ports with priority.
