---
name: cpu-fmax-critical-paths
description: Load when a CPU core misses timing, when reviewing RTL for fmax before a Quartus run, or when deciding where to cut a CPU pipeline on Cyclone V. Lists the recurring CPU critical loops (ALU→forward, load→bypass, branch→fetch, stall→PC, TLB/tag→hit→stall, multiplier), the proven fixes from shipping MiSTer CPUs, CPU-specific SDC rules (multicycle traps, CE/2), fan-out replication, and forbidden "timing shortcuts" that change architecture.
---

# CPU fmax: critical loops and fixes

Evidence links point at the reference cores on GitHub, pinned to the reviewed commits: N64 = VR4300 (N64_MiSTer), PSX = R3000A (PSX_MiSTer), SH2 = SH-2 (Saturn_MiSTer), SS = SPARC V8 (Grabulosaure/ss), ARM7 = ARM7TDMI (Atari7800_MiSTer).

**Reality check from the reference cores:** SS reaches 54 MHz slow-corner against a 65 MHz target
in a Quartus build of its SS5 revision; ARM7 fails by 0.8 ns standalone and 2.5 ns in-system at 71.6 MHz; PSX and SH2
close only because they run at 34 and 28.6 MHz. N64 closes at 93.75 MHz by aggressively registering
selects and by some shortcuts it should not have taken. Plan the 603e for timing from the start.

## 1. The loops to protect

| Loop | Minimal form | Keep out |
|---|---|---|
| Dependent ALU | op regs → ALU → result bus → operand mux → op regs | register compares, decode, handshakes, flag logic |
| Load-use | cache data → align → **register** → result bus | raw BRAM/bus output into forwarding (ARM7 −2.5 ns) |
| Branch | predicted fetch; resolve → **registered** redirect | CR produced by EX → condition → fetch address same cycle (SS, PSX) |
| Stall/ready | registered stall/ready from each unit | ack ripple → PC (SS) |
| Fetch/translate | EA reg → µTLB ∥ tag RAM → hit → **register** | hit → next-PC → tag address same cycle (PSX) |
| Multiplier | DSP in/out regs → result register | product on the forwarding loop (ARM7 −3.84 ns) |

## 2. Proven fixes

- **Register mux selects one stage early** (forwarding, operand source, result bus). N64 [`cpu.vhd:1269-1272`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L1269-L1272); SS `BYPASS_DEC`.
- **Remove late handshakes from data and address cones**; they gate enables only. ARM7 [`core:970-977`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L970-L977), [`2479-2546`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L2479-L2546).
- **Predecode into flops at capture** (regfile indexes, unit, serialize). ARM7 [`core:641-666`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L641-L666).
- **Operand-source codes + flat mux outside decode's priority chain.** ARM7 [`core:1694-1739`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L1694-L1739).
- **Precompute condition vectors and exception vectors into registers.** ARM7 [`core:1741-1764`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L1741-L1764); N64 [`cpu_cop0.vhd:489-519`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_cop0.vhd#L489-L519).
- **Store the last issued fetch address; increment at use.** ARM7 [`core:447-454`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L447-L454).
- **Evaluate both next-PC candidates in parallel** with duplicated tag RAMs; select late. N64 [`cpu.vhd:2143-2166`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2143-L2166).
- **Launch RAM reads from the previous stage's address** (BRAM input register = pipeline register). N64 D-cache from EX.
- **Skid/output register on every unit's ready**. SS FPU `SSTALL`.
- **One-hot AND-OR muxes** for way/TLB select instead of priority chains. SS [`mcu_simple.vhd:549-563`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L549-L563).
- **Registered near-full with headroom** instead of combinational full. PSX/N64 FIFOs.
- **Next-item pickers computed one step ahead** (lowest-set-bit isolate + OR-tree encode). ARM7 [`core:1354-1360`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L1354-L1360).
- **Keep the CPU's registered option inputs local**: re-register OSD/config bits before use. N64 [`cpu.vhd:2981-2982`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2981-L2982).
- **`KEEP` a target adder** so the condition acts as a late select (SS `syn_npc_dec_c`) — a partial mitigation, not a fix.

## 3. Fan-out

- High-fanout control (global stall, flush, retire/done, mispredict) → **compute one edge early and replicate
  per consumer group** with `/* synthesis dont_merge maxfan = N */`. ARM7 [`core:243-253`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L243-L253).
- A single global `stall = 0` enable over the whole core forces reliance on physical-synthesis duplication
  (N64 QSF). Prefer per-unit valid/ready.
- Don't reset datapath registers or arrays; reset fan-out is real and blocks RAM inference (ARM7 [`core:2550-2654`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L2550-L2654)).

## 4. SDC rules specific to CPUs

- **Default: every core path single-cycle.** Multi-cycle-looking FSM states usually have a degenerate
  one-cycle case (one-register LDM, m=1 multiply) — a multicycle there is a silent hardware bug.
  ARM7 [`arm7tdmi.sdc:31-71`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi.sdc#L31-L71).
- **If a path is truly multicycle, enforce it in RTL with an enable** and constrain with matching
  setup/hold; N64 samples a multiplier 4–7 cycles later with no constraint.
- **CE/2 cores**: either meet every path at the fast clock (SH2 does, no constraints) or add explicit
  multicycles tied to the CE — never leave it ambiguous.
- **False paths only for quasi-static configuration**, scoped `-to` the CPU clock, matched by instance
  (retiming renames registers), with `post_message -type critical_warning` when a collection is empty.
  ARM7 [`arm7tdmi.sdc:106-217`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi.sdc#L106-L217). Leave CDC mailboxes timed.

## 5. Forbidden shortcuts

Timing fixes must not change architecture. From N64: 29-bit PC adder ([`cpu.vhd:2133-2137`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2133-L2137)), region check on
base register only ([`2257-2259`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2257-L2259)), address-error check skipping the computed EA ([`2217`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2217)). If it doesn't fit,
add a stage or check a cycle later and raise a precise exception. **Accuracy-vs-timing trades go behind a
named, documented parameter** (ARM7 `MUL_RETIRE_STAGE`, [`core:18-41`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L18-L41)), never silently.

## 6. Procedure when a CPU path fails

1. Read the top 20 failing paths; classify each by the loop table in §1.
2. For each: which term is late? Handshake in a data cone → move to enable. Compare in mux select →
   register a stage early. Raw RAM/bus data → register. Priority chain → one-hot/flat case.
3. Check fan-out on the worst path's control nets; replicate if > ~32 loads across regions.
4. Re-run; record slack per clock and the change. Never add SDC exceptions to "fix" a real path.
5. Write the measured cause in the commit message, not in code comments.

## 7. Pre-synthesis review checklist

- [ ] Each loop in §1 is in its minimal form.
- [ ] No handshake/ack in any data, address or forward-valid cone.
- [ ] No RAM output or bus input feeds a mux select or forwarding path in the same cycle.
- [ ] Every high-fanout control net is registered and replicated.
- [ ] No multicycle/false-path constraint on core-internal paths without an RTL enable and justification.
- [ ] No architectural shortcut taken for timing.
