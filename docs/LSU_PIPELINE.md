# Pipelined load/store unit

Parameter `ENABLE_LSU_PIPE` runs plain integer and FP loads and stores in
`ppc_lsu_pipe` instead of the serialized special lane. Plain means no
reservation, string, multiple, cache operation or external access,
outside trace mode; for FP it also excludes the 602 SP/LT moves and a
replayed instruction ([FP accesses](#fp-accesses)). `ppc_core`, `ppc_core_bat`, `ppc_core_bat_cached_bus60x`,
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
  store data. Base registers come from rename, including a value written
  that cycle; an access waits at dispatch only until they are ready, except
  a D-form load, which waits for its base in P1
  ([Base snooping](#base-snooping)). Store data not yet produced follows
  from the result buses
  ([Update forms and rename operands](#update-forms-and-rename-operands)).
- P1 (two entries) offers the oldest access. A load offers at once. A store
  whose translation the router confirms enters the store queue without an
  offer ([Store queue](#store-queue)); any other store offers only at the
  completion-queue head with retirement authorized, the rule of UM 1.1.4.3
  the lane already follows. An offer stands until accepted. From its offer
  until it retires such a store cannot be cancelled by an external
  redirect, as in the lane.
- P2 (two entries) holds accepted accesses and takes their responses in order.
  A good response is aligned, sign-extended or byte-reversed into R.
- R finishes the completion entry. It has priority on the CQ result port; an
  IU result that finishes in the same cycle waits.

The IU reservation station takes R's value in the cycle it finishes, as it
does for IU results, so a dependent instruction issues two cycles after its
load issues (UM Table 6-6, load latency 2). Integer work dispatches behind
loads as before; readers of a load's destination wait in the reservation
station.

## FP accesses

A plain FP access (`lfs`, `lfd`, `stfs`, `stfd`, `stfiwx` and their
indexed forms) dispatches as FP work does: it issues into the FPU, takes
its place in the FP tag queue and retires when the FPU's result for it is
at the head. It also enters the unit, with the EA from the dispatch adder.
Its base registers must be committed, and a load waits for older FP work
that can still raise an exception, as an integer access does.

- The FPU launches the access as it issues (`MEM_AT_ISSUE`); the unit only
  records the launch. A load offers once launched; a store offers at the
  completion-queue head once the FPU presents the store's data. The unit
  names its P1 store's tag and the FPU answers with the data of that store
  at any position in its queue, once the store has launched, so FP stores
  queue one per cycle.
- The unit's R stage returns the response to the FPU instead of the
  completion queue: a word for `lfs`, both words for `lfd`. The FPU
  formats it, and the instruction retires the cycle after, as FP
  arithmetic does (Figure 6-3). A store's response finishes it the same
  way; the FPU's commit at retirement then writes nothing.
- A doubleword moves in one access on a 64-bit port when doubleword
  aligned, otherwise as two word beats, high word first; the second beat's
  EA advances as it reaches the head. The beats do not make each other
  speculative.
- Little-endian mode munges a word access to EA XOR 4 and leaves a
  doubleword's address alone ([LITTLE_ENDIAN.md](LITTLE_ENDIAN.md)).
- Only word-aligned accesses are performed, and in little-endian mode only
  doubleword-aligned doublewords. Any other access, and any response with
  a fault, answers the FPU with a fault and removes everything behind it.
  The FPU's exception replays the instruction alone in the serialized
  lane, which raises the alignment exception, DSI or machine check, or
  performs the 602's unaligned load. A faulting access is therefore
  repeated once by the lane; a misaligned one the FPU rejects itself is
  never offered and is removed by the replay.

Decode marks the D-form FP accesses with their displacement and a zero
rA, so the dispatch adder forms their EA as for integer accesses.

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
the data port needs no arbiter. Any other lane dispatch and interrupt
admission wait for the unit to empty. The lane's memory quiescence waits
only for traffic: an offer, a response owed, or a retired store not yet
written. Younger entries waiting for the lane, and stores not yet retired,
do not hold it; an alignment exception found once a load's base arrives
reaches the lane with younger accesses behind it.

## Speculation

A load may offer while an older one still awaits its response. Such a request
carries `dmem_attr_t.spec`. Per UM 3.5.5.2 it may be performed only where an
access that is later abandoned is harmless: a cacheable (I=0) location with
the data cache enabled. A receiver must hold a speculative request it cannot
perform that way until `spec` drops. The router accepts one only on a
micro-TLB hit with I=0 while `data_spec_ok_i` is set, which `ppc_core_bat`
drives from `ENABLE_DATA_SPECULATION` (set by the cached top) and HID0[DCE]
without HID0[DLOCK]; the uncached tops never accept one. A speculative request may be withdrawn
before acceptance when the older access faults or recovery removes it,
judged by whether it was speculative when last offered, since the faulting
access has left P2 by the time the entry is marked removed; every
other request stands until accepted, as the lane's do, and a removed entry's
response is drained. The micro-TLB never holds a direct-store (T=1) segment,
so a speculative access to one waits until it is not speculative, then
takes the direct-store path like a lane access.

A load may be requested once every older access has its response, before
an older store retires: the store has been performed and cannot fault.

## Store queue

UM 1.1.4.3 and 6.4.4: the LSU translates a store in its first stage, holds
it in the store queue until completion, and executes stores at one per
cycle with two-cycle latency (Table 6-6, 2:1). Loads may be performed ahead
of stores (UM 3.2, weakly ordered) except to caching-inhibited pages; the
603e combines no stores (UM 3.5.1). Here translation happens at the router,
so the router answers a check beside the request port instead:

- In P1, a store with its data asks the router whether a store to its page
  would translate without a fault: a second lookup of the data micro-TLB,
  which holds only translations a store was allowed through. On a hit the
  store leaves P1 without an offer, enters the queue and passes Q to R,
  which finishes it in the cycle a load would finish. On a miss it waits
  and offers at the completion-queue head as before, after every older
  queued store is written; the router's translation then raises any DSI.
- The queue (four entries) holds stores in program order. A store becomes
  committed when it retires; committed stores are written in order through
  the request port, one access per cycle as on the 603e's single-ported
  cache (UM 1.1.5.2). A load ready for its first offer goes first while the
  queue has room; otherwise a committed store goes ahead of any later offer
  (a standing non-speculative offer finishes first, and a standing store
  write keeps the port). Recovery or a faulting older access removes a
  store not yet retired.
- A load waits while a queued store shares its doubleword, compared on the
  page offset only (aliases of a physical page also match); stores do not
  forward. Otherwise it may pass queued stores, offered as speculative, so
  a receiver performs it only on a cacheable micro-TLB hit with the data
  cache enabled (UM 3.5.2, 3.5.5.2); elsewhere it waits until the queue is
  empty. A store does not queue behind a load that passed queued stores and
  still awaits its response, so a load that faults after passing is always
  younger than every queued store: its response is consumed, everything
  behind it removed, and once the queue drains the lane performs the load
  again and takes its exception.
- Every serialized-lane operation (sync, eieio, lwarx, stwcx., cache
  operations, dcbz, mtmsr, mtsr, tlbie, tlbld, rfi, exceptions), interrupt
  admission and the lane's memory quiescence wait for the unit to empty, so
  the queue drains first (UM 4.1: the completed store queue is emptied
  before an asynchronous exception) and no translation change reaches a
  queued store. Snoops see the cache as stores are written, as on the 603e.
- An error on a committed store's write is an asynchronous machine check
  (UM 4.5.2, Table 4-10): TEA is raised through the pin-event path, SRR0 is
  the next instruction to complete, SRR1[13] is set, and the rest of the
  queue is cancelled. Without machine check the core halts. The queue is
  used only where that path exists (`ENABLE_MACHINE_CHECK` off, or pin
  interrupts, data cache and external interrupts on); elsewhere stores offer
  at the head as before. A store whose fault the lane classifies (old path)
  stays precise.
- Little-endian munging and byte reversal are applied before the queue,
  which keeps the formatted address, data and strobes. An FP store queues
  once the FPU presents its data and finishes the FPU entry through R; a
  doubleword moved in two beats does not queue.
- Without a translating router (`ppc_core` alone, the untranslated bus
  tops) a top drives `dmem_store_check_ok_i` low and stores never queue;
  the FP core bench drives it from its protected-word map.

## Update forms and rename operands

UM 6.6: an update form takes two GPR rename registers; UM 6.3.3.1: an LSU
instruction takes its operands from the rename registers or the result buses
in its reservation station. Here:

- Integer and FP update forms (valid forms only; the others are illegal at
  decode) run in the unit. At dispatch the base register gets its own rename
  slot, written ready with the EA from the dispatch adder, so younger
  readers have it at once. The completion entry records the slot
  (`update_owned`, `update_tag`); retirement writes the base to the GPR file
  and releases the slot, and recovery rebuilds it for survivors. A fault
  clears the architectural update as before; the younger readers of the
  slot are removed with the exception. An update form dispatches alone, as
  its second slot uses the second rename port.
- The dispatch adder reads the base registers through rename (a third read
  port serves store data), so an access dispatches as soon as its base is
  ready, including in the cycle its producer's result is written, instead of
  waiting for the producer to retire. An access in DQ1 does the same
  through the second slot's ports (rA, rB and a sixth rename read port for
  rS: three per slot, UM 6.3.3.1); store data that DQ0 writes follows from
  DQ0's new rename slot. It still pairs only when aligned and never as an
  update form, and never beside a DQ0 access in the unit.
- A store dispatches without its data. P1 holds the producer's rename tag
  and takes the value from either result bus; the head uses a value
  written in its own cycle at once. Adoption by the lane waits for the data.
- At most two GPR writes retire per cycle: CQ[1] does not retire a GPR
  write beside an update form, and an update form retires only from CQ[0]. With two write ports the base is written
  beside the destination; with one it follows a cycle later and dispatch
  and retirement wait for it.

## Base snooping

Parameter `LSU_BASE_WAIT` (macro `PPC_LSU_BASE_WAIT`, default 1) makes P1 the
LSU's reservation station for a D-form load's base (UM 6.3.3, 6.3.3.1):

- A plain, non-update D-form integer load in DQ0 whose base is not yet
  produced dispatches; P1 keeps the base's rename tag and the displacement.
  A load whose base is ready keeps the dispatch adder and its alignment
  check.
- When a result bus writes the base, P1 registers base plus displacement as
  the EA and decides alignment from it (an exception goes to the lane at the
  head, its destination write suppressed at retirement). The access offers
  on the next cycle.

The path is result bus, adder, alignment check, register, like the dispatch
adder's; the request address still comes from a register. The load offers
in the same cycle it would have after waiting at dispatch, but younger work
dispatches behind it.

Recorded: `make -C sim test-core-lsu-timing test-core-lsu-timing-snoop test-core-lsu-update test-core-memory-edges test-core-fpu test-core-le test-lsu-update-edges test-core-dual test-dispatch-rules`, at width 1 and from `sim/` with `DISPATCH_WIDTH=2 BUILD_DIR=<dir> VERILATOR=$PWD/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/tools/verilate-lsu-pipe` (`DEMO_FW_DIR=<main checkout>/toolchain/build/demo` for the last), commit 103325b, 2026-10-04. All pass except `test-lsu-update-edges` with the unit, a bench fault ([Faulting update forms](#faulting-update-forms-2026-10-04)).

Parameter `LSU_BASE_SNOOP` (macro `PPC_LSU_BASE_SNOOP`, default 0) forms a
D-form load's EA in P1, as the 603e's LSU does from operands its station
snooped (UM 6.3.3.1):

- A plain, non-update D-form integer load in DQ0 dispatches without waiting
  for its base; P1 keeps the base's rename tag and the displacement.
- P1 compares both result buses against the tag and adds each bus to the
  displacement while comparing. The head offers in the cycle its base is
  written, with that sum as the address; an entry that does not offer then
  keeps the sum.
- Alignment is decided on that EA in the unit for every such load, ready
  base or not: a fault rewrites the entry to an alignment uop the lane
  adopts at the head, and its destination write is suppressed at
  retirement (the completion entry still names it).

A load or add producing the next load's base then costs Table 6-6's load
latency 2 instead of 3. The cost is one cycle holding the result bus, the
32-bit adder and the request address, which feeds the router's micro-TLB
and the cache index: hence off by default until a fit shows it meets the
clock target. Stores, indexed and update forms, DQ1 accesses and
little-endian mode keep the dispatch adder.

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
  in the next, so hits flow one per cycle. A copy-back store hit writes the
  data RAM and answers in that cycle too. It takes the next request only
  in its first lookup cycle, when the data RAM reads that request's double
  word, and only if that is not the double word being written; a store
  held in lookup by a snoop or a push of its line does not. An answer not taken is
  registered and held, as before. The fast path reads HID0[DCE] as it was
  in the request's accept cycle; HID0 changes only through the serialized
  lane, which runs while the unit is idle. Misses, other stores, cache
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
- Four `stw`: retired one per cycle (3 cycles first to last; 12 before the
  store queue), Table 6-6 2:1.
- `stw` then `lwz` of another doubleword: the load passes the queued store
  and retires the cycle after it. `lwz` of the stored doubleword waits for
  the write and retires 5 cycles after the store.
- Four `stw` then four `lwz` of other doublewords: the loads take the
  cache before the retired stores' writes and retire one per cycle, the
  last 4 cycles after the last store (7 with stores first).
- Four `stwu` through one base: dispatched and retired one per cycle (3
  cycles first to last), Table 6-6 2:1.
- Two `lbzu` through one base (four rename slots): dispatched one per
  cycle, retired one cycle apart with two GPR write ports, two with one.
- `lwz` then `stw` of its result: the store retires 2 cycles after the
  load.
- `lwz` or `addi` then `lwz` using the result as its base: 3 cycles apart,
  one more than Table 6-6; 2 with `LSU_BASE_SNOOP`
  ([Base snooping](#base-snooping)).

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
to 1.03 M cycles, CoreMark 2.97 M to 0.62 M). These figures predate FP
accesses in the unit.

FP accesses, dispatch-to-retirement (`test-core-fpu` with the unit on and
`test-core-lsu-timing`; FP rows retire one cycle after their last execute
cycle, integer rows two):

| Access | Lane | Unit | Unit, 32-bit port |
| --- | ---: | ---: | ---: |
| `lfs`, `lfd` | 6 | 3 | 3, `lfd` 5 |
| `stfs`, `stfiwx`, `stfd` | 7 | 3 | 3, `stfd` 5 |
| four `lfd` or `lfs`, first to last, memory taking one access per cycle | — | 3 | — |
| the same, memory taking one access every other cycle | 15 | 6 | `lfd` 12 |
| four `stfd` or `stfs`, first to last, dispatch and retirement | 18 | 3 | `stfd` 14 and 15 |
| `stfd` after the `fadd` producing its data, retirement spacing | 6 | 2 | 5 |

Loads and stores meet Table 6-6 (2:1). The unit looks up FP store data by
tag, so a younger store queues while older FP work is still pending; it is
written only after it retires, so an exception in older work still removes
it. A doubleword in two beats does not queue and stays at the
completion-queue head.

## Default

The unit stays off by default. It passes the benches listed under
[Verification](#verification) and gains 12-14% on the demo benchmarks, and
the chip with it meets 50 MHz, but it lowers the chip's Fmax from 68.3 to
61.0 MHz, below the 66 MHz target. A 50 MHz build (the demo SoC and the
MiSTer core) can set it now; making it the default waits for item 1 below.
FP accesses in the unit have no fit yet: the FPU's launch in its issue
cycle and its store data now reach the unit's P1 and request paths, so
the chip needs a fresh fit and timing report before the default changes.

## Remaining work

1. 66 MHz with the unit: let the cache accept the next request in
   `S_LOOKUP` without waiting for the tag compare, holding it when the
   current access misses (with per-request response formatting in
   `ppc_dcache_slot`), so the unit's P1 shift no longer follows the hit;
   and keep the one-cycle answer away from the serialized lane's
   `memory_result_q`.
2. A doubleword stored in two word beats (32-bit port) does not queue. The
   store queue needs a fit: the micro-TLB check feeds P1's pop and the
   queue's write shares the request mux, and the FPU's store-data lookup
   (P1 tag to pending entry to formatter) now feeds the queue's write.
3. A base written by a load or add in the access's dispatch cycle costs
   one cycle more than Table 6-6's load latency 2 unless `LSU_BASE_SNOOP`
   is set ([Base snooping](#base-snooping)). Making it the default needs a
   fit; if the result bus to micro-TLB path fails, compare the base's page
   bits directly and add only the page offset in that cycle, falling back a
   cycle when the sum carries out of the page. Stores, indexed and update
   forms and DQ1 accesses still form the EA at dispatch.
4. Loads behind older FP work that may still raise an exception wait for it
   to retire, as integer loads do; marking them speculative instead would
   let them proceed to cacheable memory.
5. With one GPR write port (width 1) an update load's base is written the
   cycle after its destination, holding dispatch and retirement for that
   cycle. The 603e completes two GPR writes per cycle (UM 6.6.1.3).

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

### Cached path, 2026-10-01

Recorded: `make -C sim lint check-spec test-dcache-fast`, commit 6c62b74,
2026-10-01. Pass: lint (the chip with the unit on and the FPU is now linted
too), `check-spec`, and the fast-hit cache bench for seeds 1-3 (546,716,
561,336 and 534,707 checks).

Recorded: `make -C sim -k -j2 test-core-lsu-timing test-core-fpu test-core-fpu-602 test-core-fpu-compact test-chip-fpu test-bat-memory-router test-page-memory-router test-micro-tlb-router test-bat-data-fault test-tlb-runtime-fill-router test-page-data-exception-router test-core-lsu-extensions test-core-alignment test-core-data-fault test-core-data-fault-disabled test-core-data-fault-cancel test-core-memory-edges test-core-bat-machine-check test-chip-603 test-chip-pins test-core-page-data-exception test-bat-runtime-router test-segment-runtime-router test-page-instruction-exception-router test-page-miss-result-router test-tlb-runtime-invalidate-router test-core-dcache test-core-dcache-lsu-pipe test-dcache test-core-dcache-negative test-chip-dcache-coherence test-core-bat-cached-bus60x test-core-tlb-miss test-core-cache-control`,
commit 310dc33, 2026-09-30. All pass with the unit off (the default; the
one `-lsu-pipe` target turns it on). Later commits change only
`ppc_lsu_pipe`, which a unit-off build does not instantiate. Unit-off
counts match the earlier records: `test-core-fpu` `lwz` 5 and `stw` 5,
`test-chip-603` 4,940 cycles, the cached machine-check fill variant 156
retirements and 7 bursts.

Recorded: `make -C sim -k -j2 BUILD_DIR=build/pipe VERILATOR="tools/verilate +define+PPC_LSU_PIPE=1" test-core test-core-recovery test-core-lsu-extensions test-core-lsu-update test-core-alignment test-core-alignment-disabled test-core-alignment-dependencies test-core-page-data-exception test-core-tlb-miss test-core-dcache test-core-dcache-negative test-core-machine-check-trace test-core-bus60x-update test-core-control-memory test-core-compare test-core-interrupt test-core-bat-cached-bus60x test-core-cache-control test-chip-dcache-coherence test-core-lsu-timing test-core-data-fault test-core-data-fault-disabled test-core-data-fault-cancel test-core-memory-edges test-core-bat-machine-check test-chip-fpu test-chip-603 test-chip-603-fpu test-chip-pins test-core-fpu test-core-fpu-602 test-core-fpu-compact`,
commit 49d95f3, 2026-10-01. Unit on in every core, so the cached tops run
the router pass-through and the fast cache hits. All pass except
`test-core-fpu`, whose two integer latency probes measure 4 where that
bench expects the lane's 5 (2 of 2,668 checks, as before);
`test-core-fpu-602` and `-compact` pass. `test-core-dcache` passes 221,981
checks and `test-core-dcache-negative` rejects all nine mutations;
`test-chip-dcache-coherence` passes three rounds; `test-chip-603` passes
(89 checks, 4,943 cycles) and `test-chip-603-fpu` (91 checks).

`test-core-fpu` now generates its program with `--lsu-pipe` when
`VERILATOR` selects the unit (`tools/verilate-lsu-pipe` or
`+define+PPC_LSU_PIPE=1`), so those two probes expect 4; it passes with the
unit on at both widths ([DUAL_DISPATCH_DESIGN.md](DUAL_DISPATCH_DESIGN.md#with-the-pipelined-loadstore-unit)).

Recorded: `make -C sim -k REFERENCE_DIR=../../../../../dingusppc test-reference test-reference-memory test-reference-lsu test-reference-stress test-reference-cached test-reference-managed test-reference-cache-disabled test-reference-bat test-reference-firmware test-reference-pid6 test-reference-603`
(DingusPPC at `/home/kevin/git/ppc/dingusppc`), commit 49d95f3 with
uncommitted edits to this document only, 2026-10-01. All pass with the
unit off. The same targets with `BUILD_DIR=build/pipe` and
`VERILATOR` and `VERILATOR_TOOL` set to a wrapper identical to
`tools/verilate-lsu-pipe` (committed afterwards in 6c62b74) all pass with
the unit on; the cached and BAT profiles differ from the unit-off run only
in request and stall counts (for example 10,065 instruction requests
against 10,067).

Recorded: `make -C sim -k demo-dhrystone demo-coremark demo-whetstone-hf` and
the same with `BUILD_DIR=build/pipe VERILATOR="tools/verilate +define+PPC_LSU_PIPE=1"`,
commit 49d95f3, 2026-10-01. All six runs pass their own checks; the
figures are in [Measured timing](#measured-timing). They establish the
cycle counts of these images on the simulated demo SoC, not hardware
frequency.

Recorded: `./quartus/chip/build.sh --docker` and
`./quartus/report-target-paths.sh chip --docker` under the Quartus lock,
commit 49d95f3 with `VERILOG_MACRO "PPC_LSU_PIPE=1"` added to
`ppc603e_chip.qsf` for that run (unit on), and commit 6c62b74 without it
(unit off; same RTL), 2026-10-01. Quartus 17.0.2, seed 1; both exited 0
and Analysis & Synthesis reported 0 errors.

| `chip` fit | ALMs | Registers | M10K | Fmax slow 100 C / -40 C | Setup (4 corners) | 66 MHz (15.152 ns) |
|---|---|---|---|---|---|---|
| Unit off | 11,563 | 13,191 | 36 | 68.26 / 68.80 MHz | +5.230 / +5.234 / +7.364 / +7.718 | met: 0 failing endpoints |
| Unit on | 12,556 | 14,269 | 36 | 60.98 / 60.62 MHz | +3.601 / +3.504 / +7.530 / +7.848 | fails: 2,644 endpoints, -1.344 ns |

The unit meets the 50 MHz gate with 3.5 ns to spare and costs 993 ALMs. It
misses 66 MHz, which the same RTL meets with the unit off, on three
groups of paths, worst first: the `ppc_lsu_pipe`
P1 entries from the IQ and the completion head (-1.344 ns), whose shift
now follows the cache's acceptance and so its tag compare through the
router; the IQ entries from themselves (-0.953 ns, 2,049 endpoints); and
the lane's `memory_result_q` from the cache tag RAM (-0.780 ns), the
one-cycle answer reaching the serialized lane's result formatting.

### FP accesses through the unit (2026-10-03)

Recorded: `make -C sim -k -j2 REFERENCE_DIR=<dingusppc> test <fpu> <extra>` in four
configurations, commit fc11594 (bench port fix in 3f8b059), 2026-10-03, where `<fpu>` is
`test-core-fpu test-core-fpu-split test-core-fpu-compact test-core-fpu-602
test-core-fpu-602-compact test-core-lsu-timing` and `<extra>` is the LSU, cache, fault,
alignment, coherence and chip benches (`test-core-lsu-extensions` through `test-chip-le`).

| Configuration | Extra make arguments | Result |
|---|---|---|
| Width 1, unit off | — | 537 PASS lines; `test-crstate-execution` failed lint (missing `ppc_special` FP ports in the bench), fixed in 3f8b059 and rerun with `tb_special_watchdog` and the 602 lint: pass |
| Width 2, unit off | `DISPATCH_WIDTH=2 BUILD_DIR=build-w2` | pass, 537 PASS lines |
| Width 1, unit on | `BUILD_DIR=build-lsu VERILATOR=$PWD/tools/verilate-lsu-pipe` | pass, 537 PASS lines |
| Width 2, unit on | `DISPATCH_WIDTH=2 BUILD_DIR=build-w2-lsu VERILATOR=$PWD/tools/verilate-lsu-pipe` | pass, 537 PASS lines, including `test-core-fpu-split` |

This establishes FP loads and stores through the unit with the FULL and COMPACT FPUs on
the 603e and 602 personalities, at both widths, with no regression in the core, cache,
fault and chip sets. It does not establish timing: no fit includes the FP launch path.

### Update forms and rename operands (2026-10-04)

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=build-foc-w<1|2> VERILATOR=$PWD/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/tools/verilate-lsu-pipe test-core-lsu-timing test-core-lsu-update test-core-dcache-lsu-pipe test-core-le test-core-fpu`, commit 60b0659, 2026-10-04.
All pass at both widths. `test-core-lsu-timing`: 2,711 checks, 27 latency
probes and 54 spacing checks, including the update, rename-base and
store-data rows under [Measured timing](#measured-timing); the program at
width 2 expects the update-load pair one cycle apart, at width 1 two.
`test-core-lsu-update` (unit on, width 1): 105,939 checks. `test-core-fpu`
exercises every FP load and store form, update forms included, through the
unit. `test-core-le` runs its 14 variants, unit on and off. These establish
the cycle counts and results against the bench memory and, for
`test-core-dcache-lsu-pipe`, the cached top; they do not cover the chip or
the 60x bus.

Recorded: `make -C sim lint check-spec` on commit 60b0659, `make -C sim test-execution test-recovery-state test-recovery-storage test-rename-pair` on the RTL of c72ab03, and `make -C sim test-dcache test-dcache-fast test-dcache-mutations` on the RTL of 30d1503, 2026-10-04.
All pass: strict lint, the rename unit benches with the new ports tied off,
and the data cache bench with the fast store hit (three seeds each, all seven
mutations detected).

Recorded: `make -C sim lint test-dcache test-dcache-fast`, `make -C sim test-chip-dcache-coherence test-chip-mp`, the same at `DISPATCH_WIDTH=2`, and `make -C sim DISPATCH_WIDTH=<1|2> VERILATOR=$PWD/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/tools/verilate-lsu-pipe test-chip-dcache-coherence test-core-dcache-lsu-pipe` plus `test-chip-mp` at width 2, commit 04be37c, 2026-10-04.
All pass. A copy-back store hit held in lookup behind a push of its line
took the next request when it answered, while the data RAM read the
store's double word, so a following load returned that double word
(`test-chip-dcache-coherence` at width 2 with the unit). The store now
takes the next request only in its first lookup cycle; `tb_dcache` with
fast hits has a directed case that fails without the fix. Coherence runs
six (three seeds, I-cache on and off) in each of the four configurations;
`test-chip-mp` five seeds at width 1, width 2, and width 2 with the unit.
Quartus `quartus_map --analysis_and_elaboration` of a copy of `quartus/chip`
with `PPC_DISPATCH_WIDTH=2` and `PPC_LSU_PIPE=1`: 0 errors, 49 warnings. No fit.

Dhrystone and CoreMark before and after are in
[PERFORMANCE_TARGET.md](PERFORMANCE_TARGET.md#today).

Recorded: `quartus_map ppc603e_chip -c ppc603e_chip --analysis_and_elaboration` on a copy of `quartus/chip` with `VERILOG_MACRO "PPC_LSU_PIPE=1"`, pinned container, commit 60b0659, 2026-10-04.
0 errors, 54 warnings: the sources elaborate in Quartus 17 with the unit on.
No fit or timing. The base operand now passes from the result bus through
rename into the dispatch adder, and a store hit's tag compare drives the data
RAM write enable, so the chip needs a fresh fit before any timing claim.

### FP stores at one per cycle (2026-10-04)

Recorded: `make -C sim lint test-crstate-execution variant-watchdog-602
variant-special-lint-602 test-fpu-shell test-fpu-602 test-fpu-stream-603
test-fpu-stream-602 test-fpu-dual-603 test-fpu-dual-602 test-fpu-compact-shell
test-fpu-compact-602 test-fpu-enabled-603 test-fpu-enabled-602
test-fpu-compact-enabled-603 test-fpu-compact-enabled-602 test-core-fpu
test-core-fpu-split test-core-fpu-compact test-core-fpu-602
test-core-fpu-602-compact test-core-lsu-timing`, and with the unit
(`BUILD_DIR=build-lsu VERILATOR=$PWD/tools/verilate-lsu-pipe`)
`test-core-fpu test-core-fpu-compact test-core-fpu-602
test-core-fpu-602-compact`, commit 78a6e0a, 2026-10-04: pass
(`test-core-fpu-split` with the unit ran before the punt fix was added).

- The unit asks the FPU for its P1 store's data by tag; the FPU answers
  for any launched store in its queue. `test-core-lsu-timing`: four `stfd`
  or four `stfs` dispatch and retire one per cycle (3 cycles first to last,
  9 before), and a `stfd` retires 2 cycles after the `fadd` producing its
  data (3 before); 2693 checks, 47 spacings. The FPU benches check that the
  looked-up data equals the store port's at every publication.
- `test-core-fpu-602` with the unit hung at commit 5d0d244: a 602 unaligned
  `lfs` that the unit punts answered the FPU in the cycle Q handed its queued
  store to R, and the store's answer was lost. A punt now waits for Q. The
  bench now passes (1115 checks).

This does not establish timing: the tag lookup adds the FPU's pending-entry
select and store formatter to the queue's write path, which needs a fit.

### DQ1 rename operands and base snooping (2026-10-04)

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> VERILATOR=$PWD/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/tools/verilate-lsu-pipe test-core-lsu-timing test-core-lsu-update test-core-dcache-lsu-pipe test-core-le test-core-fpu test-core-dual test-core-recovery test-core-machine-check-trace`, the same with a wrapper adding `+define+PPC_LSU_BASE_SNOOP=1` plus `test-core-lsu-timing-snoop`, `test-core-branch-fold` (both wrappers, default width), and unit off `test-core test-core-dual`, on commit 6546dc5, 2026-10-04.
All pass, except two expected differences with snooping on:
`test-core-lsu-timing` expects the two base rows 3 cycles apart and gets 2,
and `test-core-fpu` checks lane latencies when the wrapper's name lacks
`lsu-pipe` (renamed, it passes at both widths). `test-core-lsu-timing-snoop`:
2,717 checks, 27 probes and 54 spacing checks at each width, including the
load- and add-produced base rows at 2 cycles and an alignment exception on a
misaligned EA formed from a snooped base, with rD unchanged.
`test-core-dual` (unit on) pairs `or` with a `stw` of its result and a DQ1
`lwz` whose base is still in rename (1 such pair); unit off, neither pairs.
These establish results and cycle counts against the bench memories; they
do not cover the chip or the 60x bus.

Recorded: `make -C sim lint check-spec`, and the lint top with `+define+PPC_LSU_BASE_SNOOP=1` at widths 1 and 2, on commit 6546dc5, 2026-10-04.
All pass.

Recorded: `quartus_map ppc603e_chip -c ppc603e_chip --analysis_and_elaboration` on a copy of `quartus/chip` with `VERILOG_MACRO` `PPC_DISPATCH_WIDTH=2`, `PPC_LSU_PIPE=1` and `PPC_LSU_BASE_SNOOP=1`, pinned container, commit 6546dc5, 2026-10-04.
0 errors, 49 warnings. No fit or timing: the DQ1 base now passes from the
result bus through rename into the DQ1 adder and misalignment check that
gate `dispatch1`, and with snooping the result bus feeds the request address.


### Loads before retired stores (2026-10-04)

Recorded: `make -C sim lint check-spec`; `make -C sim -k test-core-lsu-timing test-core-lsu-update test-core-dcache-lsu-pipe test-core-dcache test-dcache test-dcache-fast test-core-le test-core-fpu test-chip-dcache-coherence test-chip-mp test-core-dual test-core-recovery` at width 1 (unit off except where the bench sets it) and with `DISPATCH_WIDTH=2 VERILATOR=$PWD/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/tools/verilate-lsu-pipe`; `make -C sim DISPATCH_WIDTH=2 VERILATOR=$PWD/tools/verilate-lsu-pipe DEMO_FW_DIR=<main checkout>/toolchain/build/demo test-dispatch-rules`; commit 97b28fc plus the bench probe (uncommitted then, committed with this record), 2026-10-04.
All pass. `test-core-lsu-timing` at both widths: 2,720 checks, 27 probes,
55 spacings, including the new four-stores-then-four-loads row at 4 cycles;
with the load-first rule disabled the same row measures 7 and fails. The
width 1 batch first failed only because the new probe overwrote a register
an older row still checked; the probe now loads into one register. These
establish ordering and data against the bench memories and the cached
tops; they do not establish timing.

Recorded: `quartus_map ppc603e_chip -c ppc603e_chip --analysis_and_elaboration` on a copy of `quartus/chip` with `VERILOG_MACRO` `PPC_DISPATCH_WIDTH=2` and `PPC_LSU_PIPE=1`, pinned container, commit 97b28fc, 2026-10-04.
0 errors, 51 warnings. No fit or timing: the store write's select now
waits for the P1 load's overlap compare, and the data micro-TLB has eight
entries.

### Faulting update forms (2026-10-04)

The `test-lsu-update-edges` hang with the unit was a bench fault. On a
faulting response the unit holds `dmem_rsp_ready_o` low until the lane
adopts the access (one cycle, [Adoption](#adoption-by-the-serialized-lane)).
The bench sampled ready before it settled, saw the value of the previous
cycle, dropped the response unaccepted and left the lane waiting for it.
The RTL needed no change. The bench now settles ready first, and the target
also builds the bench with the unit at widths 1 and 2.

Bus errors (TEA, UM 4.5.2) and DSI (UM 4.5.3) on update forms through the
unit take the exception at the access with rA unchanged, as PEM requires
of a faulting update form:

- `test-core-bat-machine-check`: `lwzu`, `stwu` and `stbu` take a machine
  check with SRR0 at the access in all three translated configurations;
  the base, the load target and memory are unchanged.
- `test-core-fpu-machine-check` (new, unit on): `lfdu`, `lfsu`, `stfdu`
  and `stfsu` take a machine check at the access; base and FP target
  unchanged. `test-core-fpu` adds DSI on `stfdu` and `stfsu`.
- `test-core-data-fault-cancel`: with the unit the redirect path may
  retire before a removed access's response drains; the bench allows it.

Recorded: `make -C sim test-lsu-update-edges test-core-lsu-update test-core-lsu-timing test-core-dcache-lsu-pipe test-core-bat-machine-check test-core-data-fault test-core-data-fault-cancel test-core-recovery test-core-fpu test-core-fpu-machine-check`, unit off at width 1 and from `sim/` with `DISPATCH_WIDTH=2 BUILD_DIR=<dir> VERILATOR=$PWD/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/tools/verilate-lsu-pipe`; `test-lsu-update-edges` and `test-core-data-fault-cancel` also with the unit at width 1; commit a882db3, 2026-10-04.
All pass. `test-lsu-update-edges`: 93 checks per build. `test-core-bat-machine-check`
at width 2 with the unit: 5,077 checks and 12 TEA tenures with line fills,
10,666 checks and 7 tenures without. `test-core-fpu-machine-check`: 2,641
checks, 4 machine checks, at both widths.

Recorded: `make -C sim lint check-spec`, commit a882db3, 2026-10-04. All pass.

Recorded: `quartus_map ppc603e_chip -c ppc603e_chip --analysis_and_elaboration` on a copy of `quartus/chip` with `VERILOG_MACRO` `PPC_DISPATCH_WIDTH=2` and `PPC_LSU_PIPE=1`, pinned container, commit a882db3 (no RTL change), 2026-10-04.
0 errors, 50 warnings.
