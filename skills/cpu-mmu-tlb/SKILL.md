---
name: cpu-mmu-tlb
description: Load when designing or reviewing address translation for an FPGA CPU — micro-TLBs, main TLB arrays, BAT registers, segment registers, protection/changed-bit checks, TLB miss handling (software reload on 603e), tlbie/tlbia/context-change invalidation, table-walk engines, or translation timing in the AGU/fetch path. Covers CAM emulation cost, µTLB + RAM TLB hierarchy, folding protection into the hit, epoch flash invalidate, and silent timing shortcuts to avoid.
---

# MMU and TLB design on Cyclone V

Evidence links point at the reference cores on GitHub, pinned to the reviewed commits: N64 = VR4300 (N64_MiSTer), PSX = R3000A (PSX_MiSTer), SH2 = SH-2 (Saturn_MiSTer), SS = SPARC V8 (Grabulosaure/ss), ARM7 = ARM7TDMI (Atari7800_MiSTer).

603e facts: 64-entry 2-way set-associative ITLB and
DTLB indexed by EA bits; 4 IBAT + 4 DBAT fully associative; 16 segment registers; **no hardware
table walk** — TLB misses raise exceptions (with IMISS/DMISS/HASH1/HASH2/ICMP/DCMP/RPA helpers) and
software reloads with `tlbli`/`tlbld`.

## 1. Hierarchy: small fast µTLB, big slow array

- **Fully associative CAM in flops is expensive and slow beyond a handful of entries.** Keep the
  single-cycle path to a tiny flop µTLB and back it with a RAM array.
  N64: 1-entry µITLB, 4-entry round-robin µDTLB ([`cpu_TLB_instr.vhd:68`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_TLB_instr.vhd#L68), [`cpu_TLB_data.vhd:57`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_TLB_data.vhd#L57), [`181`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_TLB_data.vhd#L181))
  over a 32×101-bit MLAB JTLB. SS: 4 I + 4 D flop L1 TLBs over a BRAM L2 TLB ([`mcu_simple.vhd:480-513`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L480-L513)).
- **Probe all µTLB entries in parallel; register only the one-hot hit vector; build the entry by AND-OR
  next phase** (no priority mux). SS `tlb_test`/`tlb_or` ([`mcu_simple.vhd:480-513`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L480-L513)).
- **Main array searched sequentially when fully associative**: N64 walks the MLAB one entry per cycle
  starting from the last hit, so locality makes most misses 1–2 cycles ([`cpu_cop0.vhd:920-1030`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_cop0.vhd#L920-L1030)).
  603e's TLB is 2-way set-associative, so it is naturally a 2-read BRAM lookup — no sequential search needed.
- **Interleave tag and payload in one RAM** when width is tight (SS L2 TLB even/odd words, [`mcu_tw.vhd:369-375`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L369-L375)).
- 603e mapping: flop µTLB (+ BATs) in the AGU/fetch cycle; 2-way BRAM TLB behind it; miss →
  capture EA/compare word → precise TLB-miss exception at completion.

## 2. BATs and segments

- BATs are fully associative flops (4+4); compare them **in parallel with the µTLB** in the same cycle.
  BAT hit overrides page translation.
- Segment register lookup (EA[0:3]) is a 16-entry read; register its result early or fold VSID into
  the µTLB entry so the fast path needs no SR read.
- **Register MSR-derived mode bits (IR, DR, PR) and translation enables every cycle** so they are flops
  at the compare (N64 registered `bit64mode`, `privilegeMode`, [`cpu_cop0.vhd:788-798`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_cop0.vhd#L788-L798)).

## 3. Fold slow-path conditions into the hit

- **A µTLB "hit" means "fast path is legal"**: fold protection and must-update bits into it. N64 treats a
  store to a clean page as a µTLB miss, so the slow path raises TLB-Mod ([`cpu_TLB_data.vhd:88`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_TLB_data.vhd#L88)).
- 603e: treat store with C=0, PP/key protection failure, and (if desired) WIMG I=1/G=1 as µTLB-miss or
  slow-path, producing DSI/ISI or R/C handling precisely. The fast path stays one AND.
- **Just-after-reload bypass**: after a fill, use the freshly written entry directly instead of
  re-comparing (SS `data_jat`, [`mcu_simple.vhd:502-506`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L502-L506)).

## 4. Invalidation

- **Invalidate the whole µTLB on any translation-state change** instead of tracking back-references.
  N64 flushes on TLBWI/TLBWR and ASID change ([`cpu_cop0.vhd:711-720`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_cop0.vhd#L711-L720), [`910-912`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_cop0.vhd#L910-L912)).
  603e triggers: `tlbie`, `tlbia`, `tlbli/tlbld`, `mtsr/mtsrin`, BAT `mtspr`, SDR1 write, MSR[IR/DR/PR] change.
- **Epoch-tagged flash invalidate for RAM arrays**: fold an (N+1)-bit generation counter into redundant
  index bits of the tag; a flush increments it (instant miss for all entries) and schedules one idle-time
  scrub write so every entry is cleared before the epoch repeats. SS [`mcu_tw.vhd:265-273`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L265-L273), [`331-339`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L331-L339), [`613-633`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L613-L633).
  Fits `tlbia`, BTIC flush, and SR/BAT changes that invalidate shadow translation state.
- **Or a flop invalid bitmap** over RAM valid bits (SH2 cache technique, [`CACHE.sv:157-184`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/CACHE.sv#L157-L184)): 64 sets × 2
  ways = 128 flops per TLB.
- `tlbie` on the 603e invalidates the congruence class (both ways) for the EA index; test it against
  entries loaded in either way.

## 5. Faults and misses

- **Faults travel as data** with the fetch word or load response (a code field) and become exceptions only
  when the instruction reaches completion. A wrong-path fault vanishes with its instruction.
  SS bus `code` ([`plomb_pack.vhd:52`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/plomb/plomb_pack.vhd#L52), [`78-83`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/plomb/plomb_pack.vhd#L78-L83)), converted at WRITE ([`iu_pipe5.vhd:1212-1217`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L1212-L1217)); ARM7 prefetch abort
  rides with the word ([`core:172-178`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L172-L178), [`2682-2698`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L2682-L2698)).
- **Queue I- and D-side miss requests to one walker/reload engine** with latched requests
  (N64 `*_fetchReq_saved`, [`cpu_cop0.vhd:907-908`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_cop0.vhd#L907-L908)). On the 603e the "walker" is the exception path plus
  `tlbli/tlbld`, but the capture of EA, compare word and way (SRR1.WAY) is the same descriptor idea.
- **Hardware R/C update** if implemented belongs on reload, as a locked RMW (SS [`mcu_tw.vhd:512-535`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_tw.vhd#L512-L535)).

## 6. Timing shortcuts — forbidden

N64 took these for timing; each silently changes architecture:
- region/segment check from the base register only, not base+offset (N64 [`cpu.vhd:2257-2259`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2257-L2259));
- address-error check skipping the computed address (N64 [`cpu.vhd:2217`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2217));
- narrowed 29-bit PC adder (N64 [`cpu.vhd:2133-2137`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2133-L2137)).
If a check does not fit, add a pipeline stage or evaluate it one cycle later and raise a precise exception.

## 7. Checklist

- [ ] Fast path = flop µTLB ∥ BATs, one-hot hit registered; no priority mux on the entry payload.
- [ ] Protection, changed-bit and WIMG slow-path conditions folded into "hit".
- [ ] Every translation-state change flushes the µTLB (list in §4 covered by tests).
- [ ] Miss/fault codes carried with the instruction; exceptions raised only at completion.
- [ ] `tlbie` invalidates both ways of the class; `tlbia` is O(1) (epoch or bitmap).
- [ ] No partial-address shortcuts in translation or protection checks.
