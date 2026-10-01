# Pipelined load/store unit

Parameter `ENABLE_LSU_PIPE` runs plain integer loads and stores in
`ppc_lsu_pipe` instead of the serialized special lane. Plain means no
update, reservation, string, multiple, cache operation or external access,
outside trace mode. `ppc_core`, `ppc_core_bat`, `ppc_core_bat_cached_bus60x`,
`ppc603e`, `ppc603e_demo_soc` and `ppc603e_mister` carry it, each defaulting
to the `PPC_LSU_PIPE` macro (0 when undefined), so a build enables it with
the parameter or with `+define+PPC_LSU_PIPE=1` (Quartus:
`VERILOG_MACRO "PPC_LSU_PIPE=1"`). With 0 every top is unchanged. With a data
cache, the router and the cache also take one load hit per cycle
([Cached path](#cached-path)).

## Stages

```
dispatch -> P1 offer -> P2 await response -> R result -> CQ -> retire
  n          n+1         n+2 (response)       n+3          n+4
```

- Dispatch captures the uop, completion tag, PC, EA (the dispatch adder) and
  store data from the committed registers. As before, a plain access
  dispatches only when its source GPRs have no uncommitted producer; the
  check now moves to the IQ entry behind the head on a dispatch, so
  back-to-back accesses do not lose a cycle to it.
- P1 (two entries) offers the oldest access. A load offers at once; a store
  offers only at the completion-queue head with retirement authorized, the
  rule of UM 1.1.4.3 the lane already follows. An offer stands until
  accepted. From its offer until it retires a store cannot be cancelled by
  an external redirect, as in the lane.
- P2 (two entries) holds accepted accesses and takes their responses in order.
  A good response is aligned, sign-extended or byte-reversed into R.
- R finishes the completion entry. It has priority on the CQ result port; an
  IU result that finishes in the same cycle waits.

The IU reservation station takes R's value in the cycle it finishes, as it
does for IU results, so a dependent instruction issues two cycles after its
load issues (UM Table 6-6, load latency 2). Integer work dispatches behind
loads as before; readers of a load's destination wait in the reservation
station.

## Adoption by the serialized lane

The unit performs only naturally aligned accesses that respond without a
fault. The lane takes over ("adopts") everything else once it is the oldest
access, through its normal dispatch port:

- a misaligned access, or one whose alignment exception was detected at
  dispatch, before any offer; the lane splits, faults or rejects it exactly
  as before, and younger entries wait for the lane to go idle;
- an access whose response carries a fault (DSI, page miss, machine check,
  transport error). The response stays at the port and the lane, started in
  its wait state, consumes it, so the fault is classified by the existing
  logic and no access is repeated. Such a response always ends in an
  exception or halt, so the entries behind it are dropped; accepted ones
  are drained. The lane takes the response one cycle after it arrives.
  An entry that recovery removes on that edge is not adopted; its
  response is drained.

The lane offers only while busy and the unit only while the lane is idle, so
the data port needs no arbiter. Any other lane dispatch, interrupt admission
and the lane's memory quiescence wait for the unit to empty.

## Speculation

A load may offer while an older one still awaits its response. Such a request
carries `dmem_attr_t.spec`. Per UM 3.5.5.2 it may be performed only where an
access that is later abandoned is harmless: a cacheable (I=0) location with
the data cache enabled. A receiver must hold a speculative request it cannot
perform that way until `spec` drops. The router accepts one only on a
micro-TLB hit with I=0 while `data_spec_ok_i` is set, which `ppc_core_bat`
drives from `ENABLE_DATA_SPECULATION` (set by the cached top) and HID0[DCE]
without HID0[DLOCK]; the uncached tops never accept one. A speculative request may be withdrawn
before acceptance when the older access faults or recovery removes it; every
other request stands until accepted, as the lane's do, and a removed entry's
response is drained. The micro-TLB never holds a direct-store (T=1) segment,
so a speculative access to one waits until it is not speculative, then
takes the direct-store path like a lane access.

A load may be requested once every older access has its response, before
an older store retires: the store has been performed and cannot fault.

## Cached path

With the unit and a data cache, `ppc_core_bat` sets the router's
`ENABLE_DATA_PIPELINE` and the cache's `FAST_LOAD_HIT`.

- Router: a plain request (`DMEM_NORMAL`) that hits the data micro-TLB goes
  to the physical port in the cycle the router accepts it, with the
  micro-TLB's page and WIMG, and is accepted only when the port takes it.
  It may follow one access that still awaits its response unless that one
  is a direct-store access, whose reply `d_ds_q` decodes; at most two are
  outstanding, answered in order. A miss, or any other class, takes the
  translation sequence as before, accepted only with no response owed.
  `pdmem_req_now_o` marks a passed-through request, so `ppc_core_bat` sends
  its incoming attributes rather than the held ones. The speculation rule
  is unchanged: a speculative request needs a micro-TLB hit with I=0 and
  `data_spec_ok_i`.
- Data cache: a cacheable load hit answers from its first `S_LOOKUP` cycle,
  from the data RAM output selected by the tag compare. When the answer is
  taken, the cache accepts the next request in that cycle and looks it up
  in the next, so hits flow one per cycle. An answer not taken is
  registered and held, as before. The fast path reads HID0[DCE] as it was
  in the request's accept cycle; HID0 changes only through the serialized
  lane, which runs while the unit is idle. Misses, stores, cache
  operations and inhibited or write-through accesses take the cache's plan
  as before; the next request waits for their response.

`ppc_dcache_slot` formats each answer from the request it accepted last,
which is the one answered: a new request is accepted only in the cycle the
previous answer is taken.

## Measured timing

Against the bench memory that takes one access per cycle and responds the
next (`test-core-lsu-timing`), dispatch-to-retirement, isolated:

| Access | Serialized lane | Pipelined unit | `add` reference |
| --- | ---: | ---: | ---: |
| `lwz` | 5 | 4 | 3 |
| `stw` | 5 | 4 | 3 |

- Four independent `lwz`: dispatched and retired one per cycle (3 cycles
  first to last).
- `lwz` then a dependent `add`: the `add` retires the cycle after the load,
  as an independent one would (2-cycle load-use).
- Four `stw`: 12 cycles first to last retirement, 4 each: each offers only
  at the queue head.

Through the router and data cache of the cached top (`test-core-dcache`
and `test-core-dcache-lsu-pipe`; DR=1 and IR=1 over BATs, the line and the
loop cached), second pass of a loop of four independent `lwz`, a fifth
`lwz` and an `add` that uses it:

| | Unit off | Unit on |
| --- | ---: | ---: |
| `lwz` retirements after the first | +5 +10 +15 | +1 +4 +5 |
| dependent `add` after its `lwz` | 2 | 1 |
| load hits answered in consecutive cycles (whole program) | 0 | 7 |

With the unit on the load path matches ideal memory: offer, answer in the
cache's lookup cycle, result, so a dependent instruction retires the cycle
after its load. The spacing of the four loads is set by fetch, which in this
top supplies about one instruction every two cycles.

Demo SoC (`ppc603e_demo_soc`, 50 MHz model, on-chip RAM over the 60x bus),
the same images with the unit off and on:

| Benchmark | Unit off | Unit on | Change |
| --- | ---: | ---: | ---: |
| Dhrystone 2.1, cycles per run | 2421.8 | 2126.8 | -12.2% |
| Dhrystones/s at 50 MHz | 20645 | 23508 | +13.9% |
| CoreMark, cycles per iteration | 959225 | 823314 | -14.2% |
| Whetstone hard-float, MWIPS at 50 MHz | 20.321 | 22.815 | +12.3% |

The core's own counters attribute the gain to `lsu_busy` (Dhrystone 2.03 M
to 1.03 M cycles, CoreMark 2.97 M to 0.62 M); FP loads and stores still use
the lane.

## Remaining work

1. Stores at one per cycle: finish a store when translated and checked, and
   write it from a committed store queue after retirement, with load
   forwarding or an address check against the queue.
2. FP loads and stores through the unit, with the FPU's memory port taking
   one access per cycle.
3. Loads whose base register has an uncommitted producer (operands from
   rename instead of the committed registers).

## Verification

Recorded: `make -C sim test-core-lsu-timing`, commit 397aa7d, 2026-09-30.
Passes: 2,672 checks, 27 latency probes and 45 spacing checks with
retirement stalls off, and the same program with random retirement stalls.
The program is the FP core program (`test-core-fpu`) plus the integer rows
above, on `tb_core_fpu` with `PIPE_MEM=1`. It establishes the cycle counts
in the table against ideal memory; it does not cover the router, the data
cache or the 60x bus.

Recorded: `make -C sim lint check-spec test-core-fpu test-core-fpu-602 test-core-fpu-compact test-chip-fpu test-bat-memory-router test-page-memory-router test-micro-tlb-router test-bat-data-fault test-tlb-runtime-fill-router test-page-data-exception-router test-core-lsu-extensions test-core-alignment test-core-data-fault test-core-memory-edges test-core-bat-machine-check`, commit 397aa7d, 2026-09-30.
All pass with the unit off (the default): the existing cycle counts are
unchanged (`test-core-fpu` still measures `lwz` 5, `stw` 5).

Recorded: the targets below built with
`VERILATOR="$PWD/tools/verilate +define+PPC_LSU_PIPE=1"`, commit 397aa7d
(the earlier ones on ecdb69d with that commit's RTL changes uncommitted),
2026-09-30. Unit on in every core:

- Pass: `test-core`, `test-core-recovery` (pivot redirects),
  `test-core-lsu-extensions`, `test-core-lsu-update`, `test-core-alignment`,
  `test-core-alignment-disabled`, `test-core-alignment-dependencies`,
  `test-core-page-data-exception`, `test-core-tlb-miss`, `test-core-dcache`,
  `test-core-dcache-negative`, `test-core-machine-check-trace`,
  `test-core-bus60x-update`, `test-core-control-memory`, `test-core-compare`,
  `test-core-interrupt`, `test-core-bat-cached-bus60x`,
  `test-core-cache-control`, `test-chip-dcache-coherence`.
- `test-core-fpu`: every result check passes; the two integer latency
  probes fail as expected (4 measured, 5 expected by that bench).
- Failed on that commit, resolved below: `test-core-data-fault`,
  `test-core-data-fault-disabled`, `test-core-data-fault-cancel`,
  `test-core-memory-edges`. `test-core-bat-machine-check` was not run.

Recorded: `make -C sim lint check-spec` and `make -C sim test-core-lsu-timing test-core-fpu test-core-fpu-602 test-core-fpu-compact test-chip-fpu test-bat-memory-router test-page-memory-router test-micro-tlb-router test-bat-data-fault test-tlb-runtime-fill-router test-page-data-exception-router test-core-lsu-extensions test-core-alignment test-core-data-fault test-core-data-fault-disabled test-core-data-fault-cancel test-core-memory-edges test-core-bat-machine-check test-chip-603 test-chip-pins test-core-page-data-exception test-bat-runtime-router test-segment-runtime-router test-page-instruction-exception-router test-page-miss-result-router test-tlb-runtime-invalidate-router`, commit 14bcfd3 (after merging the 603 direct-store work), 2026-09-30.
All pass with the unit off. The unit-off cycle counts are unchanged:
`test-core-fpu` measures `lwz` 5 and `stw` 5. Quartus
`quartus_map ppc603e_chip --analysis_and_elaboration` (`quartus/chip`, pinned
container) passes with 0 errors, so the merged sources elaborate. This
says nothing about fit or timing.

Recorded: the targets below with
`VERILATOR="$PWD/tools/verilate +define+PPC_LSU_PIPE=1"` (unit on in every
core), commit 14bcfd3, 2026-09-30. All pass: `test-core`,
`test-core-recovery`, `test-core-lsu-extensions`, `test-core-lsu-update`,
`test-core-alignment`, `test-core-alignment-disabled`,
`test-core-alignment-dependencies`, `test-core-page-data-exception`,
`test-core-tlb-miss`, `test-core-dcache`, `test-core-dcache-negative`,
`test-core-machine-check-trace`, `test-core-bus60x-update`,
`test-core-control-memory`, `test-core-compare`, `test-core-interrupt`,
`test-core-bat-cached-bus60x`, `test-core-cache-control`,
`test-chip-dcache-coherence`, `test-core-lsu-timing`,
`test-core-data-fault` (4,368 checks), `test-core-data-fault-disabled`
(1,703), `test-core-data-fault-cancel` (421), `test-core-memory-edges`
(722) and `test-core-bat-machine-check` (all six variants; the cached
fill variant retires 155 instructions and sees 8 routine bursts against
156 and 7 with the unit off: the retired sequence is identical except
that the closing `b .` retires one fewer time before the bench stops).

What the four fault-path benches showed:

- Two RTL defects, fixed. A store stayed cancellable by an external
  redirect from its response until it retired; it is now irrevocable
  from its offer to its retirement, as in the lane. An access that
  recovery removed on the edge its fault response arrived could still be
  handed to the lane, which would then take the fault for a cancelled
  instruction; it is now drained instead.
- Four bench assumptions, corrected. A younger load may be requested
  after an older store's response and before that store retires: the
  store has been performed and cannot fault. A faulting response may wait
  a cycle for the lane. The memory-edges bench read the response ready
  in the same step it raised the response, before ready settled, and
  then withdrew the response without a handshake. It also took a store
  offer seen between clock edges, which follows retirement authorization
  combinationally, as committed.
