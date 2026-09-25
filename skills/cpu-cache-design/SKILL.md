---
name: cpu-cache-design
description: Load when designing or reviewing an L1 instruction or data cache for an FPGA CPU — tag/data array organization in MLAB/M10K, VIPT hit timing, way select, replacement (LRU/PLRU), line fill and critical-word-first, store/write buffers, write-back castouts, flash invalidate, cache maintenance instructions (icbi/dcbf/dcbst/dcbi/dcbz), snooping, and holding RAM outputs across stalls. Patterns come from N64, PSX, SH-2 and SPARC MiSTer cores.
---

# L1 cache design on Cyclone V

Evidence links point at the reference cores on GitHub, pinned to the reviewed commits: N64 = VR4300 (N64_MiSTer), PSX = R3000A (PSX_MiSTer), SH2 = SH-2 (Saturn_MiSTer), SS = SPARC V8 (Grabulosaure/ss), ARM7 = ARM7TDMI (Atari7800_MiSTer).

603e target: 16 KB 4-way I and D, 32 B lines,
128 sets, PLRU, D-cache write-back with MEI, 60x bursts critical-double-word-first.

## 1. Hit path

- **VIPT with index inside the page offset.** 16 KB/4-way → 4 KB per way → index bits 11:5, all in
  the 4 KB page offset: no aliasing, and the tag RAM read can start from the untranslated EA.
  SS config 4 KB/way × 4 ([`cpu_conf_pack.vhd:77-87`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/cpu_conf_pack.vhd#L77-L87)); N64 I-cache VIPT ([`cpu_instrcache.vhd:92-109`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_instrcache.vhd#L92-L109)).
- **Launch tag+data BRAM reads from the AGU address in EX; compare against the translated PA in MEM.**
  The BRAM's input register is the pipeline register and translation overlaps the RAM access.
  N64 [`cpu.vhd:2849`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2849), compare [`cpu_datacache.vhd:212`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_datacache.vhd#L212).
- **Two-phase access**: phase A = TLB compare + tag/data reads; phase B = per-way tag compare and way
  select by **AND-OR of one-hot hits** (no priority mux). SS [`mcu_simple.vhd:480-565`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L480-L565).
- **Tags in async MLAB** give a same-cycle compare (N64 I-tags, SH2 [`CACHE.sv:143-155`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/CACHE.sv#L143-L155), PSX I-tags);
  **tags in registered M10K** give a pipelined compare (N64 D-tags). Pick per cache by where the cycle is.
- **Data array as byte-lane M10Ks** (per-lane write enable instead of byte-enable ports): N64 8×8-bit
  ([`cpu_datacache.vhd:247-268`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_datacache.vhd#L247-L268)), SH2 4×8-bit with way bits as upper address ([`CACHE.sv:131-138`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/CACHE.sv#L131-L138)).
  Way-in-address means the hit way must be known before the data address registers; the alternative
  is one data RAM per way read in parallel and selected late.
- **Duplicated tag copies for parallel candidate addresses** (sequential vs branch target), selected
  late. N64 [`cpu.vhd:2143-2166`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L2143-L2166), [`cpu_instrcache.vhd:87-109`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_instrcache.vhd#L87-L109). MLAB tags make the copy cheap.
- **Tag write → read bypass** when a write lands on the index already being read (registered-read tags).
  N64 [`cpu_datacache.vhd:187`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_datacache.vhd#L187), [`325-340`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_datacache.vhd#L325-L340).

## 2. Holding RAM outputs across stalls (classic bring-up bug)

BRAM read outputs follow their address register, not your stall or `ce`. Choose per port:
- **(a) Clock-enable the read port with `!stall`** — output holds. N64 D-tags `clken_b => ce_fetch` ([`cpu_datacache.vhd:149`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_datacache.vhd#L149), [`178`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_datacache.vhd#L178)).
- **(b) Snapshot into a hold register on the first stalled cycle and mux it.** Use when the port address must
  keep moving (e.g. during a fill). N64 `opcode0` ([`cpu.vhd:1106-1110`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L1106-L1110)); PSX `cacheValueLast`, and again when
  `ce` drops (`ce_1`, [`cpu.vhd:792-825`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L792-L825)); SS `dcache_t_mem` ([`mcu_simple.vhd:1273`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L1273), [`1308`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L1308)).
After adding any global clock enable, audit every RAM output consumed over more than one cycle.

## 3. Replacement

- **PLRU/LRU in an MLAB per set** with separate CPU-read and fill-read copies, updated on every hit
  and fill through a registered write address. SH2 6-bit pairwise LRU ([`CACHE.sv:74-100`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/CACHE.sv#L74-L100), [`186-194`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/CACHE.sv#L186-L194)).
  603e 4-way PLRU is 3 bits/set.
- **Or pack LRU and state bits into the tag word** (no extra RAM): SS spreads 2 LRU bits per way plus
  V/M/Shared across the tags and rewrites all ways on order change ([`mcu_pack.vhd:998-1047`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_pack.vhd#L998-L1047), [`1188-1258`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_pack.vhd#L1188-L1258)).
  Cost: a hit that changes order needs a tag write; update only when the order actually changes.
- Victim: invalid way first, else LRU (SS `tag_selfill`).

## 4. Line fill

- **Fill straight from the memory controller's data beats into port A of a true-dual-port (mixed-width)
  BRAM in the memory clock domain; the CPU reads port B.** No fill buffer, no CDC FIFO, no width
  converter. N64 [`cpu_instrcache.vhd:136-184`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_instrcache.vhd#L136-L184) (64-bit DDR3 side, 32-bit CPU side); PSX I-cache written at clk3x by SDRAM.
- **Critical-word-first with early restart**: PSX rotates a one-hot word-bank write enable from the miss
  offset and raises ready early ([`sdram.sv:273-292`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/sdram.sv#L273-L292), [`451-456`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/sdram.sv#L451-L456)). N64 and SS do *not* (fill from line base);
  SH2 starts *after* the missed word. 603e 60x bursts are critical-double-word-first — bank data by double word.
- **Per-word (or per-double-word) valid bits in the tag** let the pipe restart on the first beat and allow
  partial fills without a separate FSM. PSX [`cpu.vhd:597-647`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L597-L647), [`memorymux.vhd:587-617`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/memorymux.vhd#L587-L617).
- **Stream sequential fetches from the fill beats** (SS `inst_cont`, [`mcu_simple.vhd:1500-1507`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L1500-L1507)).
- **Write back the dirty victim before the fill** to avoid a victim buffer (N64 [`cpu_datacache.vhd:379-385`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_datacache.vhd#L379-L385), [`489-523`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_datacache.vhd#L489-L523)),
  or keep a castout buffer if fill latency matters more.

## 5. Stores and ordering

- **Store hit: write data and set dirty in the same cycle** (N64 [`cpu_datacache.vhd:282`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_datacache.vhd#L282)).
- **Write buffer = oversized MLAB fall-through FIFO with registered near-full.** PSX 8-deep, near-full at 4
  ([`memorymux.vhd:446-475`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/memorymux.vhd#L446-L475), [`SyncFifoFallThroughMLAB.vhd`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/SyncFifoFallThroughMLAB.vhd)).
- **Ordering for free**: a single in-order outbound queue (N64: stores, uncached loads, castouts, fills,
  [`cpu.vhd:688-806`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L688-L806)) or FIFO-head priority over reads (PSX [`memorymux.vhd:479-487`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/memorymux.vhd#L479-L487)) means loads never pass
  older stores and no address-compare is needed. Add store-to-load forwarding or address match only when
  you want hit-under-miss. `sync`/`eieio` = drain the queue.
- **Posted writes**: release the requester at write start; stall only on a second colliding access
  (SH2 [`CACHE.sv:317-340`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/CACHE.sv#L317-L340); [`BSC.sv:664`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/BSC.sv#L664)).

## 6. Invalidate, maintenance, snoop

- **Flash invalidate with a flop bitmap over RAM valid bits**: one clock clears all; any later write to a
  set clears its mask bit. SH2 [`CACHE.sv:157-184`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/CACHE.sv#L157-L184). 603e HID0[ICFI/DCFI]: 128 sets × 4 ways = 512 flops per cache.
- **Or epoch-tag invalidate + background scrub** for direct-mapped arrays: a generation counter folded into the tag; see the TLB epoch pattern in SS below.
- **Reset/init walks the tag index with a counter** (N64/PSX `CLEARCACHE`). Keep it; the bitmap does not
  cover power-up garbage unless the bitmap itself resets to "all invalid".
- **Cache maintenance ops as pseudo-accesses through the normal LSU path** to the cache FSM, rather than
  side ports. SH2 purge/address-array spaces ([`CACHE.sv:48-55`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/CACHE.sv#L48-L55), [`341-346`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/CACHE.sv#L341-L346)); SS routes D-side requests to the
  I-side via a cross handshake ([`mcu_simple.vhd:991-1007`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_simple.vhd#L991-L1007)) for `icbi`-like ops.
- **Implement maintenance semantics exactly.** Anti-patterns: N64 index-invalidate ignores the tag ("HACK",
  [`cpu_instrcache.vhd:216-219`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_instrcache.vhd#L216-L219)); PSX cache-isolation store invalidates instead of writing
  ([`cpu.vhd:2175-2179`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L2175-L2179)); SS flush always invalidates the full line. `dcbz`, `dcbi`, `dcbf`, `dcbst`, `icbi`
  each have distinct architected effects.
- **Snoop port**: make tag (and data) RAMs true dual-port; port 1 = core lookup, port 2 = fill/castout/snoop
  engine, which also picks the requester's own victim. SS [`mcu_multi.vhd:336-452`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_multi.vhd#L336-L452),
  [`mcu_multi_ext.vhd:369-420`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/mcu_multi_ext.vhd#L369-L420). 603e: GBL/ARTRY/SHD snooping and castouts on port 2.
- **External-write snoop for coherence** with DMA (PSX [`dma.vhd:985-987`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/dma.vhd#L985-L987)).

## 7. Runtime knobs

Bring out cache enable, force-write-through, and an added-latency knob as debug ports/OSD bits so a bug can
be bisected on hardware. N64 `slow_in`, `force_wb_in`, `DATACACHEON` ([`cpu_datacache.vhd:396-399`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_datacache.vhd#L396-L399)).

## 8. Checklist

- [ ] Index bits ⊆ page offset (or aliasing handled).
- [ ] Every RAM output consumed across a stall is clock-enabled or snapshotted.
- [ ] Tag write→read same-index bypass exists where reads are registered.
- [ ] Fill restarts the pipe on the critical beat; per-beat valid tracked.
- [ ] Loads cannot pass older stores to the same address (single queue, head priority, or compare).
- [ ] Each maintenance op has its architected effect and a directed test; none is approximated.
- [ ] Flash invalidate and reset init both covered; snoop path cannot starve the core port.
