---
name: cpu-memory-interface
description: Load when designing or reviewing a CPU's bus interface unit and memory path — internal request/response protocol, outbound request/store queues, memory ordering, cache fill and castout transport, 60x-style split address/data tenures, multi-master arbitration, DMA sharing and ownership switches, SDRAM/DDR3 latency hiding, read-data muxing across slaves, and wait-state/cycle-accuracy modeling. Patterns from N64, PSX, SH-2, SPARC and ARM7 MiSTer cores.
---

# CPU memory interface and bus unit

Evidence links point at the reference cores on GitHub, pinned to the reviewed commits: N64 = VR4300 (N64_MiSTer), PSX = R3000A (PSX_MiSTer), SH2 = SH-2 (Saturn_MiSTer), SS = SPARC V8 (Grabulosaure/ss), ARM7 = ARM7TDMI (Atari7800_MiSTer).

## 1. Core-side protocol

- **Keep the core on a simple internal request/response bus; put external protocol pipelining in an adapter.**
  ARM7 core uses req/ready; the pin wrapper is a pure adapter ([`arm7tdmi_pin_wrapper.sv`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_pin_wrapper.sv)). SH2 core knows
  nothing of cache or bus protocol; SoC inserts cache/BSC ([`SH_core.sv:12-37`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/core/SH_core.sv#L12-L37)). 60x address/data tenure
  pipelining, ARTRY and snoop responses belong in the BIU, not in the LSU.
- **Responses carry a status code** (OK / error / fault) with the data; the core converts it to an
  exception at completion. SS PLOMB `code` field ([`plomb_pack.vhd:57-83`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/plomb/plomb_pack.vhd#L57-L83)).
- **Register the response before it enters the bypass network.** ARM7's failing path is
  external decode → load lane → forward mux → operand mux in one cycle ([`core:749`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L749), [`995-998`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L995-L998),
  [`arm_mapper_memory.sv:623-627`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm_mapper_memory.sv#L623-L627)). D-cache data → align/sign-extend → register → result bus.
- **Allow back-to-back requests**: shadow the controller's busy state locally so a new request issues on the
  same edge as the previous done (PSX `memoryMuxBusy`, [`cpu.vhd:469-526`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/cpu.vhd#L469-L526)).
- **Latch and replay a request that collides** with a higher-priority one or a busy controller
  (PSX/N64 `mem1_request_latched`). Never drop it.
- **Fetch must absorb in-flight responses** when the data phase cannot be back-pressured: SS keeps 2
  outstanding fetches and a 2-entry return buffer with an overflow assertion ([`iu_pipe5.vhd:454-483`](https://github.com/Grabulosaure/ss/blob/70203e26e981069710e934600fd55b9d866a9e5b/src/cpu/iu_pipe5.vhd#L454-L483));
  ARM7 parks a same-edge completion in `ahead_*` (`retain_completed_fetch`, [`core:1506-1517`](https://github.com/MiSTer-devel/Atari7800_MiSTer/blob/0dc8ad2e3ff724af57ba84c913e035a4c97733e8/rtl/arm7tdmi/arm7tdmi_core.sv#L1506-L1517)).

## 2. Queues and ordering

- **One in-order outbound queue for all traffic** (stores, uncached loads, castouts, I/D fills) gives memory
  ordering with no address comparators. N64 8-deep, 108-bit entries ([`cpu.vhd:688-806`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu.vhd#L688-L806)). Split into
  load-miss and store/castout queues with address match later, when hit-under-miss is wanted.
- **Early full with headroom = max requests already committed** (N64 `>= 4 of 8`, PSX near-full at 4 of 8).
  A hardware assertion on true full (N64 `error_fifo`).
- **Fall-through MLAB FIFO** (unregistered read address) so the head is valid whenever non-empty, thresholds
  computed from the next count. N64/PSX [`SyncFifoFallThroughMLAB.vhd`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/SyncFifoFallThroughMLAB.vhd).
- **Posted writes** release the requester at acceptance; `sync`/`eieio` drain.

## 3. Multi-master sharing

- **Tag each outstanding request with its master** so the response routes correctly across an ownership
  switch. PSX `ram_next_cpu` ([`psx_top.vhd:1338-1350`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/psx_top.vhd#L1338-L1350)).
- **Pause new requests before switching ownership** ("pauseNext"), and switch only when the controller is idle.
  PSX `canDMA <= memMuxIdle`, `pauseNext` ([`psx_top.vhd:747`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/psx_top.vhd#L747), [`1723`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/psx_top.vhd#L1723)).
- **Never grant during a locked sequence** (burst, atomic, reservation). SH2 `*_LOCK`, grant only in `T0 && BUS_END`
  ([`BSC.sv:922-963`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/BSC.sv#L922-L963)). 603e: `lwarx/stwcx.` reservation and burst tenures.
- **Multi-master release without tristates**: each released master becomes a mux stage fed by the next
  (`{A,DO} = !BUS_RLS ? {IA,IDO} : {EA,EDO}`, SH2 [`SH7604.sv:563-566`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/SH7604.sv#L563-L566); chain [`Saturn.sv:369-381`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/Saturn.sv#L369-L381)).
- **Early miss hint** lets the arbiter defer a lower-priority master (SH2 `IBUS_PREREQ`/`DBUS_SKIP`, [`CACHE.sv:437`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/CACHE.sv#L437)).
- Snoop external writes into caches for DMA coherence (PSX [`dma.vhd:985-987`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/dma.vhd#L985-L987)).

## 4. Latency hiding

- **Write fill data straight into the cache BRAM in the memory clock domain** (true dual-port, mixed width);
  only the `done` pulse crosses. N64 [`cpu_instrcache.vhd:136-184`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/cpu_instrcache.vhd#L136-L184); PSX I-cache at clk3x.
- **Critical-word-first with early ready** (PSX [`sdram.sv:273-292`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/sdram.sv#L273-L292), [`451-456`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/sdram.sv#L451-L456)). 60x bursts deliver the critical
  double word first — exploit it.
- **Pick clock ratios from one PLL VCO and time crossings as synchronous** (N64 93.75/62.5/125 MHz), keeping
  crossing paths short; pulses crossing to a slower related clock are stretched (N64 [`DDR3Mux.vhd:255-264`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/DDR3Mux.vhd#L255-L264)).
  Not applicable to asynchronous HPS/DDR clocks. Qualify 1×→2× pulses with a phase index (PSX `clk2xIndex`, [`gte.vhd:466`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/gte.vhd#L466)).

## 5. Read muxing and address decode

- **OR-reduced read bus** (every slave drives zero when unselected) is cheap but one non-compliant slave
  corrupts all reads (N64 [`memorymux.vhd:272-275`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/memorymux.vhd#L272-L275), PSX [`memorymux.vhd:426-427`](https://github.com/MiSTer-devel/PSX_MiSTer/blob/cd17b5a0ad261005c321d9d5ba41b8dbe313a7d3/rtl/memorymux.vhd#L426-L427)). Prefer a registered
  select or assert zero-when-idle per slave.
- **Per-slave `ACT/DO/BUSY` bundle, priority mux in the wrapper, each slave decodes its own range** (SH2 [`SH7604.sv:327-342`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/SH7604.sv#L327-L342)).
- **Register slave read data locally** (SH2 two-phase `REG_DO` pattern) so there is no combinational slave→core path.
- Clamp or flag out-of-range addresses and add a response-timeout watchdog (N64 [`DDR3Mux.vhd:327-341`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/DDR3Mux.vhd#L327-L341), [`382-385`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/DDR3Mux.vhd#L382-L385)).

## 6. Wait states and accuracy

- **Model per-region latency with counters behind a "fast" switch** (N64 `bus_slow` + `FASTBUS/FASTRAM`,
  [`memorymux.vhd:320-490`](https://github.com/MiSTer-devel/N64_MiSTer/blob/eb5554af01bb97bdf3d295aed02a989ac10ccee4/rtl/memorymux.vhd#L320-L490); PSX `TURBO`; SH2 `FAST`). Functional behavior must not change with the switch.
- Programmable wait states via small lookup functions indexed by region (SH2 `GetAreaW…`, [`BSC.sv:87-133`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/BSC.sv#L87-L133)).
- Bus sizing for narrow devices splits accesses with a remaining-byte-lane mask (SH2 [`BSC.sv:473-560`](https://github.com/MiSTer-devel/Saturn_MiSTer/blob/a23bbb22c8c9a43926ee2196875e257d225291b7/rtl/SH/SH7604/BSC.sv#L473-L560));
  prune with parameters when unused.

## 7. Checklist

- [ ] Core↔BIU interface is internal req/resp with status; external protocol isolated in the BIU.
- [ ] No raw bus data enters forwarding in the arrival cycle.
- [ ] Every request is either accepted, latched for replay, or back-pressured — never dropped.
- [ ] Ordering rule written down (single queue / head priority / address match) and tested with store→load same address.
- [ ] Outstanding requests tagged by master and by flush epoch; stale responses discarded.
- [ ] No grant during locked or reserved sequences.
- [ ] Watchdog/timeout and overflow flags wired to a visible error register.
