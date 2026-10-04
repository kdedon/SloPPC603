# Pipelined load/store unit

Parameter `ENABLE_LSU_PIPE` runs plain integer and FP loads and stores in
`ppc_lsu_pipe` instead of the serialized special lane. Plain means no
update, reservation, string, multiple, cache operation or external access,
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

## FP accesses

A plain FP access (`lfs`, `lfd`, `stfs`, `stfd`, `stfiwx` and their
indexed forms) dispatches as FP work does: it issues into the FPU, takes
its place in the FP tag queue and retires when the FPU's result for it is
at the head. It also enters the unit, with the EA from the dispatch adder.
Its base registers must be committed, and a load waits for older FP work
that can still raise an exception, as an integer access does.

- The FPU launches the access as it issues (`MEM_AT_ISSUE`); the unit only
  records the launch. A load offers once launched; a store offers at the
  completion-queue head once the FPU presents the store's data, which it
  does for its oldest instruction.
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
before acceptance when the older access faults or recovery removes it,
judged by whether it was speculative when last offered, since the faulting
access has left P2 by the time the entry is marked removed; every
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
| four `stfd`, first to last retirement | 18 | 9 | 15 |
| `stfd` after the `fadd` producing its data | 6 | 3 | 5 |

Loads meet Table 6-6 (2:1). Stores offer only at the completion-queue
head, three cycles apart.

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
2. Stores at one per cycle: finish a store when translated and checked, and
   write it from a committed store queue after retirement, with load
   forwarding or an address check against the queue. The 603e checks the
   store in the LSU's MMU stage and writes the cache after completion;
   here translation happens with the access at the router, so the unit
   needs either the micro-TLB's check on the request path before the
   write or a probe request, which would halve the port's store bandwidth.
   Offering a store before it is the head, once every older instruction
   has finished without an exception, gives two cycles per store without
   a queue.
3. Loads whose base register has an uncommitted producer (operands from
   rename instead of the committed registers). The 603e reads them from the
   rename buffers or the result buses into the LSU's reservation station;
   here the EA adder sits at dispatch and reads the committed registers, so
   this needs the adder moved into the unit behind an operand-wait stage
   that snoops results. Store data (rS) needs a third rename read port.
4. Loads behind older FP work that may still raise an exception wait for it
   to retire, as integer loads do; marking them speculative instead would
   let them proceed to cacheable memory.
5. Update forms (integer and FP) still take the lane.

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
