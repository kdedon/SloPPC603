# Pipelined load/store unit

`ppc_core` parameter `ENABLE_LSU_PIPE` (default 0, or `+define+PPC_LSU_PIPE`)
runs plain integer loads and stores in `ppc_lsu_pipe` instead of the
serialized special lane. Plain means no update, reservation, string, multiple,
cache operation or external access, outside trace mode. With 0 the core is
unchanged. No top enables it yet: the router and data cache below still take
one access at a time and the router does not yet honor the speculation bit
(see [Remaining work](#remaining-work)).

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
  accepted.
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
  are drained.

The lane offers only while busy and the unit only while the lane is idle, so
the data port needs no arbiter. Any other lane dispatch, interrupt admission
and the lane's memory quiescence wait for the unit to empty.

## Speculation

A load may offer while an older one still awaits its response. Such a request
carries `dmem_attr_t.spec`. Per UM 3.5.5.2 it may be performed only where an
access that is later abandoned is harmless: a cacheable (I=0) location with
the data cache enabled. A receiver must hold a speculative request it cannot
perform that way until `spec` drops. A speculative request may be withdrawn
before acceptance when the older access faults or recovery removes it; every
other request stands until accepted, as the lane's do, and a removed entry's
response is drained.

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

## Remaining work

1. Router: honor `spec` (accept only a micro-TLB hit with I=0 while the
   data cache is enabled and unlocked; tie off the uncached tops), and accept
   a request while the previous one awaits its response, passing a micro-TLB
   hit to the cache in the same cycle.
2. Data cache: accept a load hit in `S_LOOKUP` and answer it from the lookup
   cycle, so hits flow one per cycle; then enable the unit on the cached and
   pin tops and check 66 MHz on the hit path.
3. Stores at one per cycle: finish a store when translated and checked, and
   write it from a committed store queue after retirement, with load
   forwarding or an address check against the queue.
4. FP loads and stores through the unit, with the FPU's memory port taking
   one access per cycle.
5. Loads whose base register has an uncommitted producer (operands from
   rename instead of the committed registers).

## Verification

See the records below.
