# Dual dispatch and dual completion design

Design document, 2026-09-30. Slices 0 and 1 are implemented, slice 2 in part
([status](#slice-status)). It maps the 603e's
two-per-cycle dispatch and completion (TASK_PLAN P11) onto the current core and
splits the work into slices with acceptance tests. Code is cited at
[`23bbf9d`](https://github.com/kdedon/SloPPC603/tree/23bbf9d33d59269450f094a78d9c974bf3f18dcc)
(batch 7). Manual pages are physical PDF pages of the 603e UM; rule IDs refer to
`sim/spec/timing.json` ([TIMING_SPEC.md](references/TIMING_SPEC.md)).

## Manual rules

| Rule | Requirement | Source |
|---|---|---|
| Fetch | Up to two instructions per cycle from the I-cache into a six-entry IQ; one when only one entry is free. Dispatch from IQ0/IQ1 in order; IQ1 never bypasses a stalled IQ0. | §6.3.1, PDF 252–253 (`TIM-FETCH-IQ`, `TIM-DISP-WIDTH`) |
| Branches | Identified at fetch and sent to the BPU, bypassing dispatch; folded out of the stream; one unresolved prediction. A branch needing no LR/CTR write back is retired by the BPU. | §6.3.1, §6.4.1.1–2, PDF 253, 260–262 (`TIM-BPU-*`) |
| DQ[0] | Unit available; GPR/FPR renames available; CQ not full; a dispatch-serialized instruction needs an empty CQ; no dispatch-serialized instruction executing. | §6.6.1.2, PDF 267 (`TIM-DISP-DQ0`, `TIM-U05`) |
| DQ[1] | DQ[0] dispatches and is not dispatch-serialized; unit, renames and CQ available after DQ[0]; DQ[1] not dispatch-serialized. | §6.6.1.2, PDF 268 (`TIM-DISP-DQ1`) |
| Same unit | "If the second instruction in the dispatch unit requires the same execution unit, dispatch of that instruction will stall until the first instruction completes execution." | §6.3.3, PDF 257–258 |
| Reservation | A dependent instruction dispatches to its unit's reservation station and starts when the operand is forwarded. | §6.3.3, PDF 257 (`TIM-DISP-RESERVATION`) |
| Units | IU, SRU, LSU, FPU, BPU. The PID7v SRU executes `addi addis add addo cmpi cmp cmpli cmpl` unserialized, beside the IU. | §6.3, §6.4.5, PDF 252, 264 (`TIM-SRU-ADDCOMPARE`) |
| CQ | Five entries, one per dispatched instruction; dispatch stalls when full. | §6.3.3, PDF 258 (`TIM-CQ-ALLOC`) |
| CQ[0] | Finished, not behind an unresolved prediction, no exception. | §6.6.1.3, PDF 268 (`TIM-CQ-CQ0`) |
| CQ[1] | CQ[0] completes this cycle; CQ[1] finished, no exception, not behind a prediction, integer or load; pair updates at most one CR, two GPRs, one FPR. | §6.6.1.3, PDF 268 (`TIM-CQ-CQ1`) |
| Oldest only | Stores, FPU instructions and SRU instructions other than add/compare retire only from CQ[0]. | §6.3.3, PDF 258 (`TIM-CQ-ORDER`) |
| Writeback | Two GPR writebacks per cycle; one each to CR, FPR, LR, CTR. | §6.3.3, PDF 258 (`TIM-WB-LIMITS`) |
| Renames | Five GPR, four FPR, one each CR, LR, CTR (plus the branch LR shadow). Load with update takes two GPR renames. | §6.3.3.1, §6.6, PDF 258, 267 (`TIM-RENAME-*`) |
| Serialization | Completion-, dispatch- and refetch-serialized classes as listed; serializing instructions dispatch and complete one per cycle. | §6.3.3.2, PDF 259 (`TIM-SER-*`) |
| Exceptions | Signaled only from the oldest CQ position. | §6.3.3, PDF 258 (`TIM-EXC-PRECISE`) |

Legal pairs follow from "one instruction per unit per cycle": {IU, SRU, LSU, FPU}
choose two distinct units. Two IU operations do not pair, except that on PID7v
an add or compare goes to the SRU and pairs with an IU operation.

## Current core

One instruction dispatches and one retires per cycle. The table lists each
structure, what it is today and what dual dispatch needs.

| Structure | Today | Needed |
|---|---|---|
| Fetch | One untagged request, one 32-bit word ([`ppc_fetch.sv:4-7`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_fetch.sv#L4-L7), [`ppc_icache.sv:22-25`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_icache.sv#L22-L25)) | Two words per cycle from an aligned doubleword |
| Fetch-to-decode | One registered word, decoded at IQ push ([`ppc_core.sv:369-403`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_core.sv#L369-L403)) | Two registered words, two decoders |
| IQ | `ppc_fifo`, depth 6, one push, one pop, head pointer ([`ppc_core.sv:438-444`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_core.sv#L438-L444)) | Push 0–2, pop 0–2, fixed DQ0/DQ1 slots |
| Dispatch decision | One wide `iq_ready` term ([`ppc_core.sv:972-985`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_core.sv#L972-L985)) | DQ0 and DQ1 terms; DQ1 from predecoded pair bits |
| GPR file | 3 read, 1 write, one MLAB copy per read port ([`ppc_regfile_gpr.sv:4-20`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_regfile_gpr.sv#L4-L20)); an update load writes its base one edge later ([`ppc_core.sv:671-704`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_core.sv#L671-L704)) | 6 read (rA, rB, rS per slot), 2 write |
| Rename | 5 slots, 2 lookups, 1 allocation, 1 release, 1 wake ([`ppc_rename.sv:6-28`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_rename.sv#L6-L28)) | 4–6 lookups, 2 allocations, 2 releases, 2 wakes |
| Reservation | One IU entry ([`ppc_dispatch.sv:1-27`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_dispatch.sv#L1-L27)); the special lane reads committed GPRs after a drain ([`ppc_core.sv:474-475`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_core.sv#L474-L475)) | One entry per unit: IU, LSU (P3), SRU add/compare |
| Result buses | IU and special lane share one CQ finish port; overlapped work waits a cycle on collision ([`ppc_core.sv:900-908`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_core.sv#L900-L908)) | One finish/wake port per unit |
| CQ | Depth 5, one allocation, one finish, one retire ([`ppc_completion.sv:186-198`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_completion.sv#L186-L198)) | 2 allocations, 2–3 finish ports, 2 retires |
| CR/XER | One exact-tag flag owner ([`ppc_flags.sv:1-25`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_flags.sv#L1-L25)) | Unchanged: it is the manual's single CR rename. Pair check only |
| Branch unit | Resolves at the IQ head from committed CR/LR/CTR (the P2 rule), allocates a CQ entry and passes the IU as an add of zero ([`ppc_core.sv:560-669`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_core.sv#L560-L669)) | Must stop taking the IU slot; see [Branches](#branches) |
| FPU | Arithmetic issues on lane 0; lane 1 and `commit1` exist in `ppc_fpu` but are tied off ([`ppc_fpu.sv:9-24`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/fpu/ppc_fpu.sv#L9-L24), [`ppc_special.sv:2152-2162`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_special.sv#L2152-L2162)) | Connect both lanes; see [FPU](#fpu) |
| Retire port | `retire_valid_o/retire_ready_i/retire_o`, one packet ([`ppc_core.sv:165-167`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_core.sv#L165-L167)) | Add a younger packet `retire1_*` |

Unit mapping: the core has no SRU. The IU runs integer ALU, compare, multiply,
divide and branch pass-through; the serialized special lane runs SPR, CR logic,
MSR, cache/TLB, string/multiple and all loads/stores; plain loads/stores already
overlap younger IU work ([PERFORMANCE.md](PERFORMANCE.md#pipelined-loadstore-path)).
Dual dispatch therefore needs P3 to turn the plain-access path into an LSU with
its own reservation entry and finish port, and a small SRU add/compare lane on
PID7v.

## Target structure

```
 I-cache 64b ─► FD0/FD1 ─► decode ×2 ─► IQ[5..2] ─► DQ1 ─┐ pair bits, dep bit
                                          (shift)   DQ0 ─┤ registered counts
                                                         ▼
          GPR 6R/2W (LVT) + rename 2 alloc ───► IU RS │ SRU RS │ LSU RS (P3) │ FPU lane 0/1
                                                         │ finish/wake ports ×3, FPU alloc-finished
                                                         ▼
                              CQ ×5: alloc ×2, retire CQ[0] + CQ[1] ─► GPR ×2, CR, LR, CTR, FPR
```

## Changes by structure

### Fetch and IQ

- The I-cache returns the aligned doubleword; fetch pushes two words when the PC
  is doubleword-aligned and two IQ entries are free, else one (§6.3.1). A miss,
  uncached or translated fetch stays one word per response.
- Replace the head-pointer FIFO by a shifting queue whose bottom two entries are
  the fixed DQ0/DQ1 registers, as the manual draws it. This removes the
  head-pointer loop, which failed 66 MHz by 0.666 ns at single width
  ([PERFORMANCE.md](PERFORMANCE.md#branch-unit-and-folding)). Each entry selects
  from itself, the entry one or two above, or a push lane.
- Predecode at push, per entry: unit class, dispatch/completion serialization,
  "reads/writes CR, XER, LR, CTR", GPR destinations count (update load: 2),
  "may retire from CQ[1]", and `dep_prev`: a source equals the preceding
  instruction's destination. `dep_prev` compares against the other pushed word
  or the last pushed entry; a clear or fold resets it. DQ1 then needs no
  register-number compare at dispatch.

### Dispatch decision

DQ0 keeps today's term. DQ1 dispatches when:

```
dispatch1 = dispatch0 && pair_ok && res2_ok
pair_ok   = distinct units && neither serialized
            && DQ1 has no fetch fault, illegal or alignment class   (predecoded)
res2_ok   = cq_free_ge2 && gpr_rename_free >= need0+need1 && ...  (registered counts)
```

`cq_free_ge2` and the rename free counts are registered with next-state
lookahead from allocation and release counts, so DQ1 adds one AND to the DQ0
cone. Faulting or illegal instructions, special-lane operations and trace mode
dispatch alone from DQ0. The special lane drains before dispatch, which is
stricter than the manual's completion serialization, except for LR and CTR
moves ([slice 9](#slice-9)). Only CR writers share the flag token; XER-only
writers pair. A second CR writer bound for a station dispatches and waits
there for the token ([Station waits](#station-waits)).

### Operands, GPR file and rename

- GPR file: six read ports and two write ports. Two write ports on MLAB need a
  live-value table: two banks of six copies each and a 32-entry bank-select
  flop array. Twelve 32×32 copies cost about 24 MLABs. The alternative, one
  write port behind a writeback buffer, delays rename release and changes
  rename-full timing; it is rejected.
- The deferred update-base write goes away: an update load's two writes use both
  ports in one cycle. CQ[1] then cannot write a GPR (limit two).
- Rename: two allocations from a registered free mask (lowest and second-lowest
  free slot, computed one cycle ahead); the map update gives DQ1 priority on a
  same-register WAW. DQ1 sources with `dep_prev` take DQ0's new tag, not ready,
  through a select driven by the predecoded bit.
- Two releases per cycle at retirement; two wakes (IU and LSU) per cycle.

### Reservation stations, results and forwarding

- IU, SRU and LSU each keep one reservation entry, following
  [`ppc_dispatch`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_dispatch.sv#L1-L27):
  captured operands keep snooping every wake bus, and a back-to-back bypass uses a
  select marked at capture. Each station adds one snoop per extra result bus.
- Each unit gets its own CQ finish port and rename wake; the shared result mux
  and its one-cycle collision stall go away.
- The SRU lane executes the eight add/compare forms on PID7v; other variants
  route them to the IU. `cpu_cfg_t` gets `has_sru_add_compare`. They reach
  it from DQ1 beside an IU operation, or from DQ0 while the IU station is
  taken.

### Completion queue

- Two allocations per cycle (tail, tail+1), generations as today.
- A per-entry `cq1_ok` bit set at allocation: integer or load, and not a store,
  FP arithmetic or special-lane operation. Per-entry GPR/CR/FPR write counts are
  also set at allocation. Pair retirement is then:

```
retire1 = retire0 && done[head+1] && cq1_ok[head+1] && !fault[head+1]
          && gpr_n[head] + gpr_n[head+1] <= 2 && cr_n + cr_n <= 1 && fpr_n + fpr_n <= 1
```

  `head+1` is a register, not an adder.
- A faulting CQ[1] entry simply waits to become CQ[0]; exceptions keep acting
  only at the head.
- Retirement writes two GPRs, releases two renames and updates the flags from at
  most one packet (the CR limit makes this exact). `committed_next_pc_q` takes the
  younger retired packet.

### Branches

The P2 rule resolves a branch at the IQ head, allocates a CQ entry and sends it
through the IU as an add of zero. At width 2 this costs the IU slot, so an
integer operation cannot pair with a branch. Steps, in order:

1. A branch allocates its CQ entry finished, carrying its next PC, like FP
   entries today (`alloc_finished_i`), and never issues to the IU. It pairs with
   any unit. It may retire from CQ[1] (it is neither store, FPU nor SRU).
2. A branch in DQ1 resolves only when DQ0 writes nothing it reads (predecoded:
   CR, LR, CTR); otherwise it waits to reach DQ0.
3. A conditional branch in DQ0 that may redirect holds DQ1: the redirect
   decision (`bu_redirect`) is a CR compare and must not gate `dispatch1`. `b`
   and correctly folded branches never redirect at dispatch, so DQ1 still
   pairs behind them when the prediction is known right from registered state.
4. Built behind `ENABLE_BRANCH_REMOVAL`: a branch without LR/CTR updates,
   resolved at dispatch, takes no CQ entry (UM 6.3.1). An interrupt then
   resumes at the branch, which is idempotent; the resume override survives
   it. When DQ0 is removed, DQ1 allocates at the CQ tail
   (`alloc1_at_tail_i`). See
   [CONTROL_MEMORY.md](CONTROL_MEMORY.md#branch-unit) for the removed set
   and [branch removal](#branch-removal) for the record.

The irrevocable-head rules stay: a pivot cut may not kill an offered finished
head ([`ppc_completion.sv:137-141`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_completion.sv#L137-L141)),
and a store is performed only from the head
([`ppc_core.sv:939-944`](https://github.com/kdedon/SloPPC603/blob/23bbf9d33d59269450f094a78d9c974bf3f18dcc/rtl/ppc_core.sv#L939-L944)).
With `retire1` offered, CQ[1] becomes irrevocable too, so the pivot rule must
cover both offered entries. Stores stay CQ[0]-only, so the store rule is
unchanged.

### Exceptions, interrupts and recovery

- Interrupts are sampled only at a completion boundary and block both slots, as
  `iq_ready` blocks one today. With pair retirement the boundary follows the
  younger entry.
- Recovery kills by producer identity; the kill loop gains the SRU and LSU
  stations and the second FPU lane. Rename reconstruction from the survivor walk
  is unchanged by width.
- FP replay removes the whole queue, as today; FP entries never retire from
  CQ[1] except FP loads (below).

### Retire interface and traces

`retire1_valid_o/retire1_o` carry the younger packet; `retire_ready_i` covers
both and a new `retire1_ready_i` lets a consumer take one. With
`DISPATCH_WIDTH=1` the new port stays invalid and every existing bench runs
unchanged. The reference runner and firmware checkers consume `retire_o` then
`retire1_o` in order.

## Interaction with P3 and the FPU

### P3 (two-stage LSU)

Dual dispatch treats the LSU as a unit. P3 should deliver, or leave room for:

- a dispatch interface with a reservation entry holding tagged operands (rA,
  rB, rS), so a plain access no longer needs committed sources;
- its own CQ finish port and rename wake, independent of the IU;
- a registered `lsu_ready` (no cache hit or bus handshake in the dispatch cone);
- update forms as two GPR destinations (two rename allocations) rather than a
  serialized deferred base write;
- stores still performed only from the CQ head.

If P3 lands first with a single shared finish port, slice 3 below splits it.

P3 is the pipelined load/store unit (`ENABLE_LSU_PIPE`,
[LSU_PIPELINE.md](LSU_PIPELINE.md)). At width 2 with the unit, a plain
access in DQ0 enters the unit and pairs with an IU or FP operation in DQ1,
as a lane access does. A plain access in DQ1 does not pair: the unit takes
only DQ0. The main station's second bypass port then carries the unit's
results instead of the SRU's; SRU results still wake on the second bus. See
[With the pipelined load/store unit](#with-the-pipelined-loadstore-unit).

### FPU

The FPU already has lane 1 (`issue1_*`, one FP arithmetic plus one FP memory
operation per pair) and `result1`/`commit1` (an immediately younger FP load
retiring with the head) ([FPU_INTERFACE.md](FPU_INTERFACE.md)). Mapping:

- An integer operation pairs with FP arithmetic without lane 1: the integer
  goes to the IU, the FP to lane 0.
- FP arithmetic plus FP load/store in the same cycle uses lanes 0 and 1 in FP
  program order.
- CQ[1] may hold an FP load (a load, per §6.6.1.3). The core maps CQ positions
  to FPU lanes by FP-queue order: if CQ[0] is integer and CQ[1] an FP load, the
  load is the FPU's primary head and retires on `commit`, not `commit1`.
- FP arithmetic retires only from CQ[0]. Two FP loads never retire together
  (one FPR update per cycle).
- The COMPACT FPU never accepts lane 1, so its pairs fall back to one per cycle
  with correct results.

## Critical paths at 66 MHz

Baselines: translated top 71.39 MHz, worst +1.144 ns at 15.152 ns, 11,610 ALMs
([TRANSLATED_SYNTHESIS_BASELINE.md](TRANSLATED_SYNTHESIS_BASELINE.md));
integrated top 73.21 MHz ([INTEGRATED_SYNTHESIS_BASELINE.md](INTEGRATED_SYNTHESIS_BASELINE.md)).
The FPU top is FPU-limited near 51 MHz and is not the reference here. Three
single-width near misses at 66 MHz sit on the paths dual dispatch widens: the IQ
head-pointer loop (-0.666 ns), the rename-map lookup on the dispatch path
(-0.840 ns) and I-cache data through decode into the IQ (-0.670 ns). Each was
fixed by a register, not a trade.

| New path | Risk | Register boundary |
|---|---|---|
| DQ0 → `dispatch0` → `dispatch1` → IQ shift select | DQ1 serial behind DQ0 | Fixed DQ0/DQ1 flops, predecoded pair bits, registered free counts; `dispatch1` is one AND on `dispatch0` |
| Two rename allocations + map writes | Second free-slot pick | Pick both slots from the registered free mask one cycle ahead |
| DQ1 source lookup | Map mux plus `dep_prev` override | Lookup from DQ flops; override select is a predecoded bit |
| GPR read with LVT | One LUT level after the MLAB | Keep it off the EA adder: EA adds from captured operands in the LSU stage |
| Pair retirement → GPR ×2, rename ×2, flags | Worst path in older fits began at the CQ head | `head+1`, `cq1_ok` and write counts are flops; the retire decision is AND/compare of flops |
| Station snoop of 3 wake buses | Compare in the operand path | Mark bypass at capture, as today |
| Two decoders at IQ push | Decode already once failed here | FD registers for both words; decoders in parallel |
| Branch redirect vs `dispatch1` | CR compare gating DQ1 | Hold DQ1 behind a possibly-redirecting branch (step 3 above) |

Expected impact (estimate, unmeasured): widening without these boundaries puts
roughly 1.5–2.5 ns on the dispatch and retire cones, about 58–62 MHz. With them
the target is 66 MHz with at least 0.3 ns slack on the translated top, and
roughly 3–4k more ALMs. Every slice with RTL is fitted on the translated and
integrated tops before any timing claim.

## Parameters

- `DISPATCH_WIDTH` (1 or 2) on `ppc_core` and its wrappers, default 1, or
  the `PPC_DISPATCH_WIDTH` macro. At 1 the DQ1 and `retire1` logic is not
  generated and traces match the single-issue core exactly.
- `RETIRE_PAIRS` on `ppc_core_bat` and its bus wrappers, default
  `DISPATCH_WIDTH == 2`: CQ[1] retires beside the head but only the head
  appears on `retire_o`. Benches that check every retirement there set 0.
- `FETCH_WIDTH` (1 or 2) on `ppc_core`, `ppc_fetch` and `ppc_icache`, default 1.
  At 2 a response may carry the next word: `imem_rsp_insn_i` and
  `fetch_rsp_insn_o` widen to `{pair, word at addr + 4, word at addr}`. The
  I-cache sets `pair` on a RAM hit at an even word; refill-forwarded words stay
  single. `ppc_core_bat`, the router, `ppc_icache_managed` and
  `ppc_core_bat_cached_bus60x` pass `FETCH_WIDTH` through (default 1); `ppc603e`
  sets 2, so the chip, SoC and MiSTer tops fetch pairs. An uncached or
  faulting response carries no pair.
- `cpu_cfg_t.max_dispatch_width` per variant. The 603 and 603e allow 2. The
  602 FPU retires one per edge ([FPU_INTERFACE.md](FPU_INTERFACE.md)); its core
  width is unsourced, so it stays 1 until a 602 source says otherwise.
- `cpu_cfg_t.has_sru_add_compare`: PID7v per §6.4.5; the other variants need a
  source check (UM App. C).
- Trace mode, and `ENABLE_TEST_REDIRECT` pivot tests, force width 1 behavior at
  run time.

## Implementation slices

Each slice lands with its tests; slices 0–3 keep `DISPATCH_WIDTH=1` behavior
identical and can run beside P3. Every slice runs `lint`, `check-spec`, its
focused benches, `test-reference*` and the Dhrystone/CoreMark CPI demos; the
coordinator runs `ci`, `xrand-sweep` and the fits.

| # | Slice | Acceptance |
|---|---|---|
| 0 | Dispatch/complete event monitor: per-cycle dispatch and retire counts from the core, a checker comparing directed programs to expected schedules (P12 start) | Monitor passes on today's core for the existing `test-stage` rows; mutation (one-cycle shift) fails |
| 1 | Shifting IQ with fixed DQ0/DQ1 and predecoded pair bits; 2-wide fetch from the I-cache doubleword | Width 1: all core and reference benches identical; IQ push-2 directed bench (aligned/unaligned PC, one free entry, fold, clear); fit ≥ 66 MHz translated |
| 2 | GPR 6R/2W LVT, rename 2 alloc/2 release, CQ 2 alloc/2 retire ports, `retire1_*`; logic present, second lanes idle | Width 1 identical traces; unit benches for the LVT (same-index write/read, both ports), rename (two allocations, same-register WAW, recovery rebuild) and CQ (pair rules, each limit, irrevocable CQ[1]); `test-completion*` extended |
| 3 | Unit split: branch allocates finished and leaves the IU; SRU add/compare lane; per-unit finish ports (with P3's LSU) | Width 1 CPI no worse; `test-core-branch-recovery`, `test-core-compare`, control-memory benches pass; directed SRU vs IU result equality |
| 4 | Dual dispatch behind `DISPATCH_WIDTH=2` (still rejected by default): pair rules, `dep_prev`, resource-after-DQ0 | Cycle benches: two independent adds dispatch together (manual sanity gate); `add`+`addi` on PID7v pairs IU+SRU; `add`+`mullw` stall DQ1 one cycle (same unit); dependent `lwz`→`add` pair with RS wait; `sync`/`isync`/`mtmsr` alone with empty CQ; CQ-full and rename-full stall the right slot; first-slot fault/redirect keeps DQ1 undispatched |
| 5 | Dual completion | `add`+`add` retire together; store at CQ[1] waits; `lwzu`+`add` retire singly (GPR limit); two CR writers never pair; `lfd`+`lfd` retire singly (FPR limit); integer + FP load uses `commit`, FP arith + FP load uses `commit1`; interrupt between and after pairs saves the right SRR0 |
| 6 | Enable width 2 as default for 603/603e; FPU lane 1 connected | Width 1 vs width 2 architectural traces identical over the full reference corpus and `rtl-all`; `xrand-sweep`; Figures 6-3/6-4/6-5 integer rows replay (`TIM-FIG63..65`) with deviations listed; CPI recorded; fits on translated, integrated and chip tops |
| 7 | Measured options: branch in DQ1 behind a known-correct fold; no CQ entry for branches without LR/CTR update | CPI gain against the added path; interrupt-at-branch resume tests |

## Slice status

| # | State | Where |
|---|---|---|
| 0 | Done | `ppc_core` `+DISPATCH_TRACE=<path>` monitor (simulation only); `sim/tools/check_dispatch_trace.py`; expected schedule `sim/spec/schedules/stage.txt`; mutation tests `sim/tools/test_dispatch_trace.py` |
| 1 | Done; chip top meets 66 MHz, translated fit left to the coordinator | `rtl/ppc_iq.sv`; `FETCH_WIDTH` in `ppc_fetch`, `ppc_core`, `ppc_icache`; `iq_pair_t`/`pair_predecode` in `ppc_pkg`; bench `tb/tb_core_fetch2.sv` |
| 2 | Ports and unit benches done; width-1 traces identical, but 95 core benches fail at 0a9fe26 (see below) | `ppc_regfile_gpr` (`DUAL_WRITE`), `ppc_rename`, `ppc_completion` (`ENABLE_PAIR_RETIRE`), `retire1_*` on `ppc_core`; benches `tb/tb_regfile_gpr_ports.sv`, `tb/tb_rename_pair.sv`, `tb/tb_completion_pair.sv` |
| 3 | Implemented at width 2: finished-at-allocation branches, PID7v SRU add/compare lane on the CQ's second finish port and wake bus | `ppc_core` (`HAS_SRU`, `g_sru`), `ppc_completion` (`result1_*`, `wake1_*`) |
| 4 | Implemented behind `DISPATCH_WIDTH=2`; pair rules checked on compiled programs by `test-dispatch-rules` ([below](#dispatch-and-completion-rule-check)); directed pair-rule cycle benches beyond `tb_core_dual` not written | `ppc_core` (`dispatch1`, `pair_units`); bench `tb/tb_core_dual.sv` |
| 5 | Implemented; only `tb_core_reference` and the SoC/MiSTer benches observe CQ[1] | `ppc_core` (`commit1`); `RETIRE_PAIRS` on the BAT wrappers |
| 6 | Partial: width 2 selectable (`make -C sim DISPATCH_WIDTH=2`, `--dual` builds), default still 1; the chip top misses 66 MHz, and 50 MHz hold by 6 ps (see below); two-word fetch through the wrappers wired ([slice 8](#slice-8)) | `FETCH_WIDTH` on the BAT wrappers, `ppc603e` |
| 7 | Branch in DQ1 and `bclr`/`bcctr` folding done; branches still take a CQ entry | `ppc_core` (`d1_branch`, `lr_iq_q`/`ctr_iq_q`, `folds`); benches `test-core-branch-fold`, `tb_core_machine_check_trace` scenarios 16-18, `tb_core_dual` |
| 8 | Speculative `bc`, shadow LR, unresolved `bc` + DQ1 pair, DQ1 access into the LSU unit; branches still take a CQ entry | `ppc_core` (`bs_*`, `lr_front_q`/`lr_disp_q`, `d1_lsu`), `ppc_lsu_pipe` (`bspec`); scenarios 19-20, `tb_core_dual` group H |

Slice 0. The monitor writes one line per cycle with a dispatch or an accepted
retirement: `<cycle> D<n> R<n> <dispatch pcs> | <retire pcs>`, cycle 0 being
the first edge out of reset. The checker compares a trace with an expected
schedule exactly, and with `--stage` also against the stage bench's own edge
trace. Any `make -C sim` target accepts `SIM_ARGS=+DISPATCH_TRACE=<path>`.

Recorded: `make -C sim test-stage check-spec`, commit 5f96aba, 2026-09-30.
`test-stage` passes its schedule (14 dispatches, 14 retirements, last event
cycle 76) and the cross-check against the stage edge trace. In `check-spec`,
`test_dispatch_trace` shifts each event by one cycle, drops or adds a PC and
breaks a count; every mutation fails. This establishes the monitor and checker
on the single-issue core; the schedule is recorded from the core, not derived
from Table 6-x timing.

Slice 1. The IQ is a six-entry shifting queue (`ppc_iq`): DQ0 and DQ1 are
entries 0 and 1, and each entry loads itself, the entry one or two above, or a
push lane. With `FETCH_WIDTH=2` two FD registers and two decoders push both
words of an aligned pair when the IQ will hold them behind the FD words, else
the second word is dropped and fetched again. A folding first word drops the
second; a folding second word is pushed with the first. Each entry carries
`iq_pair_t` (unit class, SRU form, serial, CR/XER/LR/CTR reads and writes, GPR
destinations, `cq1_ok`, per-source `dep_prev` against the preceding pushed
word, reset by a clear or fold). At `DISPATCH_WIDTH=1` DQ1 and the pair bits
have no reader and synthesis removes them; simulation assertions check DQ1
follows DQ0 and that its pair bits match its uop and DQ0.

Recorded: dispatch-trace equivalence, commits 5f96aba (base) and 2b22f0b, 2026-09-30.
Every `test-*` target whose recipe runs a core testbench binary with
`$(SIM_ARGS)` (146 targets: core, stage, recovery, control-memory, bus60x,
cached/managed, BAT/MMU, TLB, interrupts, timers, FPU core benches, chip pins,
power, ratios, coherence, 602, full decode, PID6 divider) ran on both
commits with `make -C sim -k -j2 <targets> 'SIM_ARGS=+DISPATCH_TRACE=<dir>/$@.txt'`.
All 146 trace pairs are byte-identical: 149,637 dispatches and 147,841
retirements on the same cycles with the same PCs. The 2b22f0b traces were taken
on its tree before `generate`/`endgenerate` keywords were added around three
generate blocks, which does not change elaboration. This establishes cycle
equivalence at width 1 for those benches; compiled-firmware `rtl-all` was not
traced.

Recorded: `make -C sim lint check-spec test-stage test-core-fetch2 test-icache test-icache-bus60x test-icache-managed test-fetch-recovery test-decode-sweep test-reference test-reference-memory test-reference-bat test-reference-cached test-reference-managed test-reference-cache-disabled test-reference-lsu test-reference-stress test-reference-pid6`, commit 2b22f0b, 2026-09-30.
All pass. `test-core-fetch2` runs one program at both widths: 43 retirements,
identical retire streams; width 1 takes 156 cycles, width 2 146. At width 2 it
requires and sees pair pushes (8), a pair split by one free entry (2),
unaligned single-word responses (18), a lane-0 fold dropping lane 1 (7), a
lane-1 fold (1), a mispredict clearing an IQ holding more than one entry (1),
DQ1 occupancy (68 cycles) and `dep_prev` on both the lane-to-lane (5) and
last-pushed (14) paths. `test-icache` adds a `FETCH_WIDTH=2` build: 4,506 pair
responses, each second word checked against the line image. Reference
comparisons: DingusPPC 5b292af4d7b3, 8,500 snapshots (`test-reference`), 9,881
retirements on the memory/BAT/cached/managed/disabled runs.

Recorded: Quartus 17 `quartus_map --analysis_and_elaboration`, commit 2b22f0b, 2026-09-30.
The chip top (`ppc603e_measure`, width 1) and `ppc_core` with `FETCH_WIDTH=2`
both elaborate with 0 errors. No new warnings beyond unused-object notes for
the width-2 signals at width 1.

Recorded: `./quartus/chip/build.sh --docker` and `./quartus/report-target-paths.sh chip --docker`, commit 2b22f0b plus uncommitted documentation edits, 2026-10-01.
Width 1. Meets 50 MHz at every corner (setup +3.988 / +4.173 / +6.439 / +7.039
ns, hold +0.152 / +0.164 / +0.116 / +0.091 ns) and 66 MHz: no endpoint fails at
15.152 ns. 10,830 ALMs, 12,032 registers, 36 M10K. The 50 MHz worst setup path
was not identified, so no Fmax is derived. The translated and integrated fits
that the slice 1 acceptance names were not run here.

Slice 2. The GPR file has six read ports and, with `DUAL_WRITE`, two write
ports over a live-value table: one bank of six MLAB copies per write port and
32 select flops; port 1 wins a same-register write and reads in the write
cycle return the old value. Rename has DQ1 lookups, two allocations (lowest
and second-lowest free slot, both from the `valid` flops; lane 1 allocates
only beside lane 0 and wins a same-register map write) and two releases. The
CQ allocates at `tail` and `tail+1` and, with `ENABLE_PAIR_RETIRE`, offers
CQ[1] on `retire1_*` when it is finished, `cq1_ok`, free of faults, and the
pair writes at most two GPRs, one flag packet, one FPR and one LR/CTR;
`head+1` and `tail+1` are flops, and an offered CQ[1] is irrevocable.
`retire_packet_t` gains `cq1_ok` and `fpr_write`, set at allocation. The core
wires CQ[1] to GPR port 1 and the second rename release; flags, LR/CTR,
`committed_next_pc_q` and the FPU commit for CQ[1] are slice 5.

Deviations at width 1. The live-value-table select is one LUT level between
the GPR read and the dispatch EA adder; with it the chip top missed 66 MHz by
1.069 ns (614 endpoints, all from the IQ). `DUAL_WRITE` is therefore
`DISPATCH_WIDTH == 2`, and width 1 keeps one write port and the deferred
update-base write. Width 2 needs the EA added from captured operands (P3)
before the table goes back on that path. The one-cycle dispatch hold after an
update load stays at both widths, so removing it is a separate, measured CPI
change.

Recorded: `make -C sim lint check-spec test-regfile-gpr-ports test-regfile-tgpr test-rename-pair test-completion`, commits a95efb1 and af5d282, 2026-10-01.
All pass. `test-regfile-gpr-ports` checks all six read ports against a model,
with and without TGPR: 242,880 read checks; each register written from each
port and read through every port; 64 write-write pairs across edges in both
port orders; about 10,000 cycles each of port 0 alone, port 1 alone and both;
33,263 / 25,399 same-cycle reads of a register being written on port 0 / 1.
A mutation (port 1 not setting the table) fails it. `test-rename-pair`:
2,181,383 checks over 50,000 random cycles, 12,043 dual allocations (4,172
same-register), 10,864 dual releases, 1,351 recovery rebuilds, plus directed
WAW and release-order cases. `test-completion` adds `tb_completion_pair`: 575
checks from every head slot, 40 pair and 55 single retirements, each CQ[1]
rule and limit, lane-1 readiness at one free slot, and pivot recovery with
CQ[1] offered (refused when it would kill CQ[1]; survivors exclude both
retiring entries). This establishes the port logic; no core bench drives a
second lane yet.

Recorded: Quartus 17 `quartus_map --analysis_and_elaboration`, `./quartus/chip/build.sh --docker` and `./quartus/report-target-paths.sh chip --docker`, commit af5d282, 2026-10-01.
The chip top (`ppc603e_measure`, width 1, batch 8 merged with P3 off)
elaborates with no errors and fits: 50 MHz met at every corner (setup +4.955 /
+4.895 / +7.675 / +7.973 ns, hold +0.196 / +0.197 / +0.133 / +0.117 ns); at
15.152 ns no endpoint fails. 11,540 ALMs, 13,249 registers, 36 M10K, 50 MLAB
LABs (24,576 MLAB bits), 2 DSP. The failed 66 MHz fit above was commit b26aa1f
(table at width 1): 12,822 ALMs. No translated or integrated fit was run.

Recorded: dispatch-trace equivalence, commits cdb8b82 (base) and 0a9fe26 plus uncommitted bench edits in the exported tree, 2026-09-30.
Both commits were exported with `git archive`. The 151 `test-*` targets whose
recipe runs, with `$(SIM_ARGS)`, a testbench instantiating `ppc_core*`,
`ppc603e`, `ppc602` or including `chip_harness.svh` (same list on both; none
absent from the base) ran with
`make -C sim -k -j2 <targets> 'SIM_ARGS=+DISPATCH_TRACE=<dir>/$@.txt'`.
SoC, MiSTer and cache-geometry targets are not in the list.

At 0a9fe26 unchanged, 95 of the 151 produce no trace:

- 93 do not elaborate. 44 benches (and the reference benches) read
  `regfile.gpr[]` hierarchically; the GPR array is now
  `g_bank[*].g_copy[*].copy`.
- `test-stage`: `tb_stage_timing` fails lint, `retired[1:0]` unused, because
  `retire_packet_t` gained `cq1_ok` and `fpr_write`.
- `test-core-recovery` fails "retirement packet/value matches surviving
  stream" at cycle 38: its model builds packets field by field and leaves
  `cq1_ok` 0, which the core now sets for `addi`.

To measure, the exported 0a9fe26 tree got three simulation-only edits: a
`gpr[32]` view of bank 0 copy 0 in `ppc_regfile_gpr` (bank 0 takes every write
at width 1), a lint waiver on `retired` in `tb_stage_timing`, and
`cq1_ok`/`fpr_write` copied from `dut.allocation` in the `tb_core_recovery`
model. With them all 151 trace pairs are byte-identical: 139,388 dispatches and
137,838 retirements, and `test-core-recovery` passes with the base's counts
(1,120 checks, 45 retired). `test-stage` exits nonzero on both trees only
because the override replaces its own `+DISPATCH_TRACE`, so its schedule check
finds no events file; its trace is in the comparison.

Recorded: `make -C sim test-reference test-reference-memory test-reference-bat test-reference-cached test-reference-managed test-reference-lsu test-reference-stress test-reference-pid6 test-reference-603 REFERENCE_DIR=<dingusppc>`, commit 0a9fe26, 2026-09-30.
Fails as committed: all nine benches read `regfile.gpr`. On the exported tree
with the edits above, all pass against DingusPPC 5b292af4d7b3: 8,500 snapshots
for each of `test-reference`, `-pid6` and `-603`; 9,881 retirements each on
memory, BAT, cached and managed; LSU 530 snapshots; stress 3 seeds, 3,419
snapshots.

This establishes width-1 cycle equivalence of the slice 2 RTL for those
benches. It does not make 0a9fe26 pass: the benches need a GPR read view
(or updated hierarchy) and the two bench fixes before slice 2 is accepted.

Bench fixes. `ppc_regfile_gpr` has a simulation-only `gpr[32]` view (inside
`synthesis translate_off`): at `DUAL_WRITE=0` bank 0, otherwise each
register from the bank its live-value-table entry selects; TGPR is not in
it. Benches read `regfile.gpr[]` as before. `tb_stage_timing` asserts
`cq1_ok` and not `fpr_write` on each retired `addi`. The `tb_core_recovery`
model sets `cq1_ok` for `addi` from the allocation rule (integer, not
serial, not a store), not from DUT state; `fpr_write` stays 0.

Recorded: `make -C sim lint check-spec test-regfile-gpr-ports test-stage test-core-recovery`, commit a69b0e9, 2026-09-30.
All pass. `test-regfile-gpr-ports` now runs four builds (TGPR on/off ×
`DUAL_WRITE` 1/0) and compares the view with the model for all 32
registers and with every non-TGPR read on each check: about 1.29 million
view checks per build beside 242,880 / 242,688 read checks. Without
`DUAL_WRITE` port 1 stays idle. A mutation (view always from bank 0) fails
at `DUAL_WRITE=1`. `test-stage`: 14 retirements, schedule check passes.
`test-core-recovery`: 1,120 checks, 45 retired, as at the base.

Recorded: `make -C sim -k -j2 <153 targets>`, commit a69b0e9, 2026-09-30.
The list is every `test-*` target whose own recipe runs a testbench with
`$(SIM_ARGS)` that instantiates `ppc_core*`, `ppc603e` or `ppc602` or
includes `chip_harness.svh`, selected from `make -n` output. This
selection gives 153 targets, two more than the 151 of the trace check,
whose exact list was not kept. Make exits 0: every target passes.

Recorded: `make -C sim test-reference test-reference-memory test-reference-bat test-reference-cached test-reference-managed test-reference-lsu test-reference-stress test-reference-pid6 test-reference-603 REFERENCE_DIR=<dingusppc>`, commit a69b0e9, 2026-09-30.
All nine pass against DingusPPC 5b292af4d7b3 with the counts of the
exported-tree run above: 8,500 snapshots each for `test-reference`, `-pid6`
and `-603`; 9,881 retirements each on memory, BAT, cached and managed; LSU
530 snapshots; stress 3 seeds, 3,419 snapshots.

Recorded: Quartus 17 `quartus_map --analysis_and_elaboration ppc603e_chip`, commit a69b0e9, 2026-09-30.
The chip top elaborates with 0 errors and 48 warnings; none is new in
`ppc_regfile_gpr`, since synthesis does not see the view. No fit was run;
the view adds no synthesized logic.

Slices 3–6. At width 2 DQ1 dispatches beside DQ0 to a different unit (IU,
the PID7v SRU add/compare lane, the load/store lane or the FPU); a folded
unconditional branch allocates finished and pairs. CQ[1] retires beside a
clean head under the pair limits above, never beside a head writing its
destination register. `make -C sim DISPATCH_WIDTH=2 <targets>` builds every
bench whose width is not set at 2, into `sim/build-w2`;
`quartus/chip/build.sh --dual` and `mister/build.sh --dual` build width 2.

Bench fixes at width 2. Benches that model the instruction stream (ADD,
ADDE, unary ADD, rotate, record-logical, recovery) also follow DQ1 dispatch,
SRU issue and the CQ's second finish port. `tb_core_reference` samples the
CQ[1] packet before the retire edge; before this it logged the next
entry's PC for the younger line. `ppc_core_bat` exported only the head while
CQ[1] retired, so benches that check every retirement on `retire_o`
(live context, page translation, cached 60x, cache operations, BAT
reference) missed the younger one; they now set `RETIRE_PAIRS` to 0.
`tb_stage_timing` instantiates the core at width 1, the pipeline its
recorded schedule describes. None of these failures was an RTL defect.

Recorded: `make -C sim -k -j2 DISPATCH_WIDTH=2 test REFERENCE_DIR=<dingusppc>`, commit 6d68f78 (merge of `batch8`) plus uncommitted bench edits, 2026-10-01; failures rerun at commit 9a96699.
254 targets. On the first run 245 passed and 9 failed: `test-reference`
(the CQ[1] logging above), `test-crstate-execution` (`dispatch_adopt_i`
unconnected, at any width), and `test-core-bat-live-context`,
`test-core-page-translation`, `test-tlb-geometry-16`,
`test-core-bat-cached-bus60x`, `-ratios`, `-cacheops` and
`test-reference-bat` (hidden CQ[1] retirements). The stream-model benches
were edited while the run was in progress and passed in it. At 9a96699 these
16 targets pass: `test-reference` 8,500 snapshots against DingusPPC
5b292af4d7b3 with 461 pair retirements; BAT reference 9,881 retirements;
the stream-model benches with the width-1 counts, seeing 2 to 10 pair
dispatches each. Strict `lint` passes at both widths.

Recorded: `make -C sim -k -j2 DISPATCH_WIDTH=2 test-selftest-fpu demo-whetstone-hf demo-dhrystone demo-coremark` and, at width 1, `make -C sim -k -j2 demo-whetstone-hf demo-dhrystone demo-coremark`, commit 9a96699, 2026-10-01.
All pass; the FPU self-test passes 1,218 of 1,218 cases at width 2. CPI is
the benchmark's measured region (`perf cpi`).

| Benchmark | Width 1 | Width 2 |
|---|---:|---:|
| Dhrystone CPI, DMIPS/MHz | 4.104, 0.235 | 3.880, 0.248 |
| CoreMark CPI, CoreMark/MHz | 3.174, 1.042 | 3.028, 1.092 |
| Whetstone (FPU) CPI, MWIPS at 50 MHz | 3.911, 20.321 | 3.803, 20.898 |

Recorded: dispatch-trace equivalence at width 1, commits 290a73b (`batch8`, base) and 9a96699, 2026-10-01.
Both exported with `git archive` under `sim/build/`; the 153 `test-*`
targets selected as for slice 2 (the head adds only `test-core-dual`,
which the base lacks) ran with
`make -C sim -k -j2 <targets> 'SIM_ARGS=+DISPATCH_TRACE=<dir>/$@.txt'`.
All 153 trace pairs are byte-identical: 157,338 dispatches and 155,334
retirements. `test-stage` exits nonzero on both trees only because the
override replaces its own trace path. This establishes width-1 cycle
equivalence with `batch8` for those benches, not for `rtl-all`.

Recorded: `./quartus/chip/build.sh --docker --dual` and `./quartus/report-target-paths.sh chip --docker`, commit 9a96699, 2026-10-01.
Width 2, chip top `ppc603e_measure`. 15,887 ALMs, 15,996 registers, 42
M10K, 50 MLAB LABs, 4 DSP (width 1 at af5d282: 11,540 ALMs). At 50 MHz setup
is met at every corner (+3.397 / +3.197 / +7.521 / +7.835 ns) but hold fails
at the slow 100 °C corner by 6 ps on one endpoint (−0.006 ns; −40 °C
+0.018, fast +0.069 / +0.047 ns), so 50 MHz is not met; the endpoint was not
identified. At 15.152 ns 4,700 endpoints fail, worst −1.651 ns; every
failing group starts at the IQ entries (`special` capture registers, the IQ
itself, GPR bank 1, rename map, CQ packets, station), the DQ1 pair decision
fanning into dispatch.

### With the pipelined load/store unit

Width 2 and `ENABLE_LSU_PIPE` together (`make -C sim DISPATCH_WIDTH=2
VERILATOR=$PWD/sim/tools/verilate-lsu-pipe BUILD_DIR=build-w2-pipe`;
`mister/build.sh --dual --lsu-pipe`). Fixes made for the combination:

- A plain access in DQ0 entering the unit pairs with DQ1 (it did not after
  the merge; `tb_core_dual` expected the lwz + dependent add pair).
- Under test redirects (`ENABLE_TEST_REDIRECT`, benches only), the
  completion queue refused a committed exception's redirect when the head
  behind the faulting instruction was finished, although the core was
  holding that head and had not offered it. `ppc_completion` takes the hold
  (`retire_hold_i`). `tb_core_alignment_dependencies` variant 6 failed the
  "committed exception redirect was not accepted" assertion.
- Benches: the compiled-firmware BAT benches set `RETIRE_PAIRS` to 0, as the
  other benches that log every retirement do; `test-reference-firmware`
  builds with the selected Verilator wrapper; `tb_core_fpu` records DQ1
  dispatches and, at width 2, takes its single-dispatch spacings as upper
  bounds; `test-core-fpu` expects the unit's lwz/stw latency when the
  wrapper selects it; `tb_core_dual` expects no add + lwz pair with the
  unit; the full-decode firmware bench counts a retried eciwx/ecowx tenure
  once (60x ARTRY repeats the tenure).

Recorded: `make -C sim -k -j2 REFERENCE_DIR=<dingusppc> lint check-spec test-core-dual test-core-lsu-timing test-core-dcache test-core-dcache-lsu-pipe test-dcache-fast test-core-data-fault test-core-data-fault-disabled test-core-data-fault-cancel test-core-memory-edges test-core-alignment test-core-alignment-disabled test-core-alignment-dependencies test-core-recovery test-core-fpu test-chip-fpu test-chip-603 test-chip-pins test-reference test-reference-memory test-reference-lsu test-reference-stress test-reference-cached test-reference-managed test-reference-cache-disabled test-reference-bat test-reference-firmware test-reference-pid6 test-reference-603 test-selftest test-selftest-fpu mister-smoke mister-smoke-fpu demo-dhrystone demo-coremark demo-whetstone-hf` in four configurations (no options; `DISPATCH_WIDTH=2`; `BUILD_DIR=build/pipe VERILATOR=$PWD/tools/verilate-lsu-pipe`; both), commit 6d64392, 2026-10-01. DingusPPC 5b292af4d7b3.
All 37 goals pass in each configuration. `test-core-lsu-timing` sets the
unit itself, so it runs with the unit in all four.

| Check | W1 off | W2 off | W1 on | W2 on |
|---|---|---|---|---|
| `test-core-dual` width-2 run: cycles, dispatch pairs, retire pairs | 109, 8, 7 | 109, 8, 7 | 107, 7, 7 | 107, 7, 7 |
| `test-core-fpu` (STALL=0): checks, probes, spacings | 2,668, 27, 41 | 2,668, 27, 41 | 2,668, 27, 41 | 2,668, 27, 41 |
| `test-core-alignment-dependencies` checks | 753 | 753 | 764 | 764 |
| `test-reference`, `-pid6`, `-603` | 8,500 snapshots each | same | same | same |
| cached, managed, disabled, BAT references | 9,881 retirements each | same | same | same |
| `test-reference-firmware` | 6 images | 6 images | 6 images | 6 images |
| `test-selftest`, `test-selftest-fpu` | 1,047/1,047, 1,218/1,218 | same | same | same |

`test-core-dual` is the same bench in every column; its width-2 run sees the
unit only in the "on" columns. The table establishes that the combination
passes these benches and references; it does not cover `rtl-all`, `ci` or
`xrand-sweep`.

Recorded: `make -C sim -k -j2 DISPATCH_WIDTH=2 BUILD_DIR=build-w2-pipe VERILATOR=$PWD/tools/verilate-lsu-pipe REFERENCE_DIR=<dingusppc> test`, commit 747d5f2, 2026-10-01.
All 256 targets pass with width 2 and the unit on (make exit 0). The
full-decode bench fix came after it and touches no bench in `test`.

Recorded: Quartus 17 `quartus_map --analysis_and_elaboration ppc603e_chip`
with `VERILOG_MACRO "PPC_DISPATCH_WIDTH=2"` and `"PPC_LSU_PIPE=1"` added to a
copy of `quartus/chip/ppc603e_chip.qsf`, under the Quartus lock, commit
747d5f2, 2026-10-01. 0 errors, 46 warnings (unused-object and
one-processor notes); `ppc_lsu_pipe` elaborates under `ppc_core`. No fit was
run.

Demo SoC (`ppc603e_demo_soc`, on-chip RAM over the 60x bus) from the same
runs as the first record. Figures are the benchmarks' own reports; MWIPS
assumes 50 MHz.

| Benchmark | W1 off | W2 off | W1 on | W2 on |
|---|---:|---:|---:|---:|
| Dhrystone 2.1, DMIPS/MHz | 0.235 | 0.248 | 0.267 | 0.285 |
| CoreMark/MHz | 1.042 | 1.092 | 1.214 | 1.252 |
| Whetstone hard-float, MWIPS at 50 MHz | 20.321 | 20.898 | 22.815 | 23.485 |
| Dhrystone run, cycles (CPI) | 6,488,985 (4.034) | 6,194,149 (3.850) | 5,805,902 (3.609) | 5,513,449 (3.427) |
| CoreMark run, cycles (CPI) | 11,341,339 (3.243) | 10,875,541 (3.110) | 9,913,119 (2.835) | 9,646,835 (2.759) |
| Whetstone run, cycles (CPI) | 5,285,692 (3.616) | 5,183,921 (3.547) | 5,082,211 (3.477) | 4,986,510 (3.411) |

Run CPI is the whole image, start-up and screen output included. Against
width 1 without the unit, width 2 gains 2.8-5.5%, the unit 12-17% and both
16-21%; the unit gains about as much at either width.

### Slice 7

Folding (603e UM §6.4.1.1, PDF 260-261). A `bclr` or `bcctr` predicted taken
(branch-always BO, or the y bit set) now folds at IQ push like `b` and `bc`,
to the committed LR or CTR, when no older instruction writes that register.
The manual stops the fold for the same producers: `mtspr` LR/CTR, a counting
`bc`, a linking branch. Writers are counted while queued (`lr_iq_q`,
`ctr_iq_q`: push adds, dispatch subtracts, an IQ clear zeroes) and tracked
from dispatch to retirement by `lr_pending_q`/`ctr_pending_q`, which now
include `mtlr`/`mtctr`. A lane-1 branch also checks the lane-0 word. The
legality test for the XL form uses the word's bits, so the push enable does
not wait for the decoder. Simulation assertions check that a folded branch
never sees its target register pending and that the next queued word is at
the resolved target.

Branch in DQ1. A branch-always `b`, `bc`, `bclr` or `bcctr` that folded
(`d1_branch`) dispatches from DQ1 beside an IU, lane, FPU or FP-access
instruction in DQ0. It cannot redirect, reads no CR, and its LR/CTR target
was final at fetch, so DQ0 cannot change what it resolved. It allocates a
finished CQ[1] entry with its next PC, and LK sets `lr_pending_q` with the
DQ1 tag. A conditional or unfolded branch still waits for DQ0.

No CQ entry: not built. Dispatching a branch without allocating would free a
CQ entry and a retire slot but keep the dispatch slot; the real gain needs
the branch removed from the IQ at fetch. Either way every retirement-trace
consumer (reference runner, program interpreters, firmware checkers, the
width-1/width-2 packet comparisons) would lose branch retirements, so it
belongs with the fetch-side BPU (P09).

Recorded: `make -C sim lint check-spec test-core-branch-fold
test-core-machine-check-trace test-core-dual test-core-dcache-lsu-pipe`,
commit 9df93a3, 2026-10-03.
All pass. `test-core-branch-fold` runs a 521-word, 566-retirement program
(`control_memory_program.py --branch-fold`) at four code offsets: returns
after long and empty bodies, `mtlr`/`mtctr` right before the branch and four
words earlier, a `bdnz` before `bcctr`, `bclrl`/`bcctrl`, conditional
`bclr`/`bcctr` mispredicted both ways, a decrementing `bclr`, a return to a
folded `b` and a nested epilogue. The model checks every retirement's path,
GPRs, CR, XER, LR, CTR and memory digest, at width 1 with one-word fetch
(43,856 checks, 2,282 cycles; 2,366 on `batch10`) and at width 2 with
two-word fetch (43,735 checks, 1,954 cycles; 2,078 on `batch10`). Folding
regardless of a pending writer fails it (path mismatch at retirement 17).
`test-core-machine-check-trace` (four seeds, 1,815 checks) adds IABR on a
folded return's target and on a `bctr` that folds when refetched, a DSI on
the `bctr` target, single step over `bl`/`blr`/`bctr` (one trace each, no
fold) and an external interrupt after a folded return (SRR0 = return
target); three folds are counted. `tb_core_dual` shows `cmpw` + folded `b`
pairing from DQ1. Not established: cycle timing against Table 6-1, and a
fold count in compiled code.

Recorded: `make -C sim -j2 -k test`, `make -C sim -j2 -k DISPATCH_WIDTH=2
test` and, from `sim/`, `make -j2 -k DISPATCH_WIDTH=2
VERILATOR=$PWD/tools/verilate-lsu-pipe BUILD_DIR=build-w2-lsu test`, commit
9645f3a, 2026-10-03.
Width 1 and width 2 exit 0 (544 PASS lines each). With the LSU unit only
`test-core-event-reset` failed: the unit's request offer was not held low in
reset, so it depended on X initialization; 9df93a3 gates it with reset and
the bench then passes (`batch10` passes it too).

Recorded: `make demo-soc-model` and `Vtb_demo_soc` on the `toolchain/build/demo`
images (`DISPATCH_WIDTH=2` for width 2), commit 9df93a3 against `batch10`
(2f049c5), 2026-10-03. Firmware was not rebuilt.

| Run cycles (CPI) | `batch10` | slice 7 |
|---|---:|---:|
| Dhrystone, width 1 | 6,488,985 (4.034) | 6,426,502 (3.996) |
| Dhrystone, width 2 | 6,194,149 (3.850) | 6,143,555 (3.819) |
| CoreMark, width 1 | 11,341,339 (3.243) | 11,295,321 (3.230) |
| CoreMark, width 2 | 10,875,541 (3.110) | 10,823,644 (3.095) |

Dhrystone gains 1.0% at width 1 and 0.8% at width 2, CoreMark 0.4% and
0.5%. The added path is a 30-bit LR/CTR mux into the fold target register
and the DQ1 next-PC adder; no fit was run. Quartus 17
`quartus_map --analysis_and_elaboration ppc603e_chip`, under the Quartus
lock on a copy of `quartus/chip`, commit 9645f3a: 0 errors at width 1 (51
warnings) and with `PPC_DISPATCH_WIDTH=2`, `PPC_LSU_PIPE=1` (47 warnings).

### Slice 8

Fetch and branch work toward the 603e's timing
([PERFORMANCE_TARGET.md](PERFORMANCE_TARGET.md#fetch-and-branch-round)):

- Two-word fetch through the wrappers: `ppc603e` builds the core with
  `FETCH_WIDTH=2`; the IQ stays six entries (UM 6.3.2.2).
- Speculative `bc` (UM 6.4.1.2): a branch whose CR owner has not finished
  dispatches on its prediction; nothing completes past it until it resolves,
  and a miss retires the branch with its real next PC and recovers the
  machine on the next edge. One level. Details in
  [CONTROL_MEMORY.md](CONTROL_MEMORY.md#branch-unit).
- Shadow LR: a `bclr` behind an uncommitted linking branch folds and
  resolves from that branch's PC + 4.
- Pairing: an unresolved `bc` in DQ0 pairs with DQ1 (it cannot redirect at
  dispatch), and a plain load or store in DQ1 with committed sources enters
  the LSU unit beside an IU operation or such a branch.

New logic on the fetch side is the shadow-LR mux into the fold target
(`lr_free ? LR : lr_front_q`, 30 bits) and one OR term in the fold enable;
the rest sits on dispatch (`bu_spec`, the DQ1 EA adder and LSU input mux)
and retirement (`bs_hold`). No fit was run.

Recorded: `make -C sim lint test-chip-pins test-chip-ratios test-chip-603 test-chip-le test-chip-mp test-chip-power test-chip-dcache-coherence test-icache-managed test-chip602-pins`, commit 800c8f4, 2026-10-04.
All pass with the chip top fetching pairs (pins at five PLL ratios, three MP
seeds, coherence, LE firmware, the 603 and 602 tops). Not established:
timing.

Recorded: `make -C sim test-core-control-memory test-core-branch-fold test-core-branch-recovery test-core-dual test-core-machine-check-trace test-core-compare check-spec`, and from `sim/` the same benches with `DISPATCH_WIDTH=2 BUILD_DIR=build-w2-lsu VERILATOR=$PWD/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/tools/verilate-lsu-pipe`, commit 9dae6d9, 2026-10-04.
All pass. `test-core-branch-fold` now runs 922 retirements: at four code
offsets, a `bc` whose compare waits on `divw` (taken and not, predicted right
and wrong, y set, LK, an add between compare and branch so it can retire
from CQ[1]), with a store, load, second compare and CR branch, `mtctr` behind
it; a `bne` loop on a loaded counter; and a CTR-and-condition `bc`. Width 1:
71,592 checks, 4,222 cycles; two-word fetch at width 2: 71,350 checks, 3,878
cycles; with the unit 4,074 and 3,708. `test-core-machine-check-trace`
scenarios 19-20 (four seeds, 1,911 checks): a mispredicted `bne` whose wrong
path holds an IABR match and a DSI takes neither, and an external interrupt
at its boundary saves the real target; predicted right, both are taken. Two
speculative dispatches and one miss are counted. `tb_core_dual` group H pairs
the unresolved `bc` with the add behind it; `add` + `lwz` now pairs with the
unit. Not established: misprediction cost against F6-5, which the core
exceeds (the 603e redirects at R+1; the core waits for the branch to
retire).

Quartus 17 `quartus_map --analysis_and_elaboration ppc603e_chip` under the
Quartus lock on a copy of `quartus/chip` with `PPC_DISPATCH_WIDTH=2` and
`PPC_LSU_PIPE=1`, commit 98e94dd: 0 errors, 48 warnings.

Second round ([PERFORMANCE_TARGET.md](PERFORMANCE_TARGET.md#fetch-and-branch-round-2)):

- Fetch every cycle: with two-word fetch the router offers a micro-TLB hit
  to the physical port in the cycle it accepts it, and the cached wrapper
  accepts a cache fetch on the edge that completes the previous one, so
  hits stream one request, two words, per cycle (UM 6.3.2.2). Misses, ICE
  off, ILOCK, faults and uncached fetches keep the registered path.
- Misprediction recovery at resolution: the edge after a speculative `bc`
  resolves wrong, its younger work is removed and fetch redirects; the
  branch retires later ([CONTROL_MEMORY.md](CONTROL_MEMORY.md#branch-unit)).
- A DQ0 branch pairs whenever it does not redirect at dispatch, not only
  when folded.

New logic on the fetch-redirect path: the micro-TLB hit, its RPN and the
cache's tag compare now follow the fetch request in one cycle, so the
redirect term in the fetch offer (`frontend_clear`) reaches the I-cache's
accept and response registers through the router's `i_pipe_try` and the
wrapper's `managed_fetch_valid`; before, it ended at the router's lane
registers. The misprediction recovery is selected from registered state
(`bs_miss_q`, `bs_tag_q`, `bs_alt_q`). `bu_redirect` now feeds
`dispatch1`. No fit was run.

Recorded: `make -C sim test-icache-managed test-chip-pins test-chip-603 test-core-dual`, at width 1 and at width 2 with the LSU unit, commits 311a5be and b28e2ad, 2026-10-04.
All pass. `test-chip-pins` checks that a cache hit is fetched on consecutive
cycles (117 such fetches at width 1, 105 at width 2; 1,618 checks).
`tb_core_dual` adds group I (a `bc` beside the compare that sets its CR does
not pair) and group J (a `bc` resolved at dispatch pairs with the `addi`
behind it): 47 retirements, 13 dispatch pairs, 10 retire pairs, 135 cycles at
width 2. `test-chip-le`, `test-chip-mp` and `test-chip-dcache-coherence` passed
at width 1 on a tree between 311a5be and a20c314; at width 2 with the unit `test-chip-le` does not
build (Verilator UNOPTFLAT through `fp_mem_pipe_ready`, also in
`lint-mister-load` at 56e7a26) and the other two were killed for memory.
On the batch-12 integration (29d1376) the loop no longer exists: `lint-mister-load`
passes and `test-chip-le` builds and passes at width 2 with the unit.

Quartus 17 `quartus_map --analysis_and_elaboration ppc603e_chip` under the
Quartus lock on a copy of `quartus/chip` with `PPC_DISPATCH_WIDTH=2` and
`PPC_LSU_PIPE=1`, commit b28e2ad: 0 errors, 48 warnings.

### Slice 9

Dispatch rules the 603e manual allows and the core had made stricter
([PERFORMANCE_TARGET.md](PERFORMANCE_TARGET.md#serialization-flag-token-and-dq1-branches)):

- LR and CTR moves are completion-serialized (UM 6.3.3.2): they wait in a
  one-entry holding slot, outside the lane, until they reach the CQ head;
  younger work dispatches behind them; readers of their result wait at
  dispatch until the lane finishes. While a move waits the lane takes no
  younger access, and the LSU unit hands over only accesses older than it.
- The flag token is the single CR rename (UM 6.3.3.1). An instruction
  writing only CA, OV or SO takes none; CA and SO readers wait until the
  youngest older writer retires. Two flag writers still never retire
  together.
- A `bc` on a CR bit alone pairs in DQ1: resolved when its CR is final and
  matches the fetch path, predicted when DQ0 writes its CR.

Recorded: `make -C sim test-core-dual test-core-control-memory test-core-machine-check-trace test-crstate-execution test-core-crstate test-core-branch-recovery test-core-branch-fold test-core-serialization test-core-sprg test-core-lsu-timing test-flags test-completion-flags test-core-add-flags test-core-adde test-core-rotate test-core-compare test-reference test-reference-lsu test-reference-stress`, and from `sim/` the same with `DISPATCH_WIDTH=2 BUILD_DIR=build-w2-lsu VERILATOR=$PWD/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/tools/verilate-lsu-pipe`, commit c1f9cce, 2026-10-04.
All pass. `tb_core_dual` (65 retirements, widths 1 and 2 retire identical
packets) adds three groups: J, an `mtctr` and the `addi` behind it
dispatch before an older `mullw` retires and the `add` reading `mfctr`'s
result dispatches after it retires; K, a `cmpw` behind `subfc` dispatches
before `subfc` retires and `adde` after; L, `cmpw` + `bc` in DQ1 pairs
predicted right and wrong (the wrong path's `addi` never retires), and
`addi` + `bc` pairs resolved. The width-2 checks of L ran on the commit
after c1f9cce, which adds the mispredicted case. With the unit,
`test-core-control-memory` takes 3,414 cycles at width 2 (3,708 before),
`test-reference` 8,500 snapshots.

Recorded: `make -C sim -k test-core-add-recovery test-core-adde-recovery test-addme-recovery test-addze-recovery test-slw-recovery test-srw-recovery test-sraw-recovery test-srawi-recovery test-insert-recovery test-subf-recovery test-neg-recovery test-subfc-recovery test-subfe-recovery test-subfe-zero-recovery test-subfme-recovery test-subfze-recovery test-subfic-recovery test-subfic-negative-recovery test-addic-recovery test-addic-record-recovery test-andi-recovery test-andis-recovery test-cntlzw-recovery test-extsb-recovery test-extsh-recovery test-multiply-recovery test-multiply-overflow-recovery test-mulhw-recovery test-mulhwu-recovery test-divwu-recovery test-divwu-zero-recovery test-divw-recovery test-divw-zero-recovery test-divw-overflow-recovery test-core-logical test-core-record-logical test-core-add-unary test-core-shifts test-core-arithmetic-shifts test-core-subtract test-core-subcarry test-core-subextend test-core-subunary test-core-subimmediate test-core-addimmediate test-core-unarylogical test-core-crtransfer test-core-crlogical test-core-xer`, commit 2df5715, 2026-10-04.
All pass at width 1. Five benches modelled one flag owner for every flag
instruction and now model the CR token: `tb_core_add_flags`, `tb_core_adde`,
`tb_core_add_unary`, `tb_core_rotate`, `tb_core_add_recovery`. In the last,
`subfic` and non-record `addic` no longer wait behind the seed's token, so
they finish before the barrier stalls and only the finished-kill and
commit-redirect modes (2 of 5) reach them; `addic.` still runs all five.

Quartus 17 `quartus_map --analysis_and_elaboration ppc603e_chip` under the
Quartus lock on a copy of `quartus/chip` with `PPC_DISPATCH_WIDTH=2` and
`PPC_LSU_PIPE=1`, commit c1f9cce: 0 errors, 49 warnings. No fit was run.
New logic on the dispatch path: the holding-slot destination compare
(5 bits, three sources per slot), two pending XER tags compared at
retirement, and the DQ1 `bc` condition from the merged CR.

### Station waits

Rules the manual states as station waits rather than dispatch conditions
([PERFORMANCE_TARGET.md](PERFORMANCE_TARGET.md#station-waits-for-cr-base-and-the-sru)):

- The flag token stays the single CR rename (UM 6.3.3.1), but UM 6.6.1.2
  does not make it a dispatch condition. One younger CR writer that writes
  at most one CR field and goes to the IU or SRU station dispatches while
  the token is held, from DQ0 or DQ1 (two `cmpw` pair). `ppc_flags` keeps
  it as the waiter and hands it the token on the edge the owner retires,
  at once if it dispatched in that cycle. Its station holds it until then;
  a `bc` behind it is predicted against it. A third writer waits at
  dispatch; other CR writers still need the token free.
- A DQ0 add or compare goes to the SRU station when the IU station is
  taken and the SRU's is free (UM 6.3, 6.4.5). DQ1 then takes no integer
  operation.

Recorded: `make -C sim lint check-spec`; `make -C sim -k -j2 <bench>` and, from `sim/`, the same with `DISPATCH_WIDTH=2 BUILD_DIR=<dir> VERILATOR=$PWD/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/tools/verilate-lsu-pipe`, for `test-core test-core-dual test-core-recovery test-core-machine-check-trace test-core-branch-fold test-core-control-memory test-flags test-completion-flags test-completion test-core-add-flags test-core-crstate test-crstate-execution test-core-compare test-core-lsu-timing test-core-lsu-timing-snoop test-core-lsu-update test-core-fpu test-core-le test-stage test-core-divider-timing test-core-divider-timing-pid6 test-lsu-update-edges test-core-logical test-core-record-logical test-core-record-edges test-core-memory-edges test-crstate-edges test-crlogical-edges test-crtransfer-edges test-core-crlogical test-core-crtransfer test-completion-cr-bits test-completion-cr-fields test-core-add-recovery test-core-rotate test-core-shifts test-core-interrupt test-core-adde test-core-add-unary`; `make -C sim test-dispatch-rules DEMO_FW_DIR=<main checkout>/toolchain/build/demo` in both configurations; commit 103325b (these station waits merged with completion in the writeback cycle), 2026-10-04.
All pass except `test-lsu-update-edges` at width 2 with the unit, a bench fault ([LSU_PIPELINE.md](LSU_PIPELINE.md#faulting-update-forms-2026-10-04)).
Quartus 17 `quartus_map --analysis_and_elaboration ppc603e_chip`, under the Quartus lock on a copy of `quartus/chip` with `PPC_DISPATCH_WIDTH=2` and `PPC_LSU_PIPE=1`, commit 8f66fa3 (same RTL): 0 errors, 50 warnings.

### Branch removal

`ENABLE_BRANCH_REMOVAL` (default 0; `BRANCH_REMOVAL=1` sets it for a sim
build) retires a branch that needs no SPR write back in the BPU (UM 6.3.1).
A plain `b` never enters the IQ; `bc`, `bclr`, `bcctr` and branch-always
forms without LK or a CTR decrement, resolved at dispatch, take no CQ entry,
IU slot or station. The removed set and its exclusions are in
[CONTROL_MEMORY.md](CONTROL_MEMORY.md#branch-unit). Each packet's
`removed_branches` counts the branches removed just before it; the machine
trace prints it as `rb=<head>,<CQ[1]>`, the firmware traces as a last field,
and `+DISPATCH_TRACE` marks a dispatch-removed branch with `*`.

Recorded: `make -C sim BRANCH_REMOVAL=1 test-core test-core-dual test-core-branch-fold test-core-control-memory test-core-branch-recovery test-core-machine-check-trace test-core-recovery test-core-fetch2 test-stage test-chip-pins`, at width 1 and at width 2 with the LSU unit (`DISPATCH_WIDTH=2 VERILATOR=$PWD/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/tools/verilate-lsu-pipe` from `sim/`), commit 3bb0024, 2026-10-04.
All pass. `test-core-branch-fold` (922 retirements) removes 86 branches at
width 1 (4,110 cycles) and 80 with two-word fetch at width 2 (3,554 cycles;
3,598 at a20c314 without removal); the control/memory bench checks that each removed
branch is a `b`, `bc`, `bclr` or `bcctr` without LK or CTR decrement and
skips its expected row. `tb_core_dual` and `tb_core_fetch2` leave every such
branch out of the width-comparison log, since which ones are removed depends
on timing; at width 2 the plain `b` at 0x6c is never dispatched.
`test-core-machine-check-trace` scenario 18 now expects the interrupt
requested at a removed `blr` to save the `blr`'s own address (four seeds,
1,903 checks each). Two faults were found and fixed on the way: the
dependency bits of the entry after a removed `b` compared against nothing
(the fold cleared them), and two assertions assumed DQ1 or a folded target
follows DQ0 directly.

Recorded: `make -C sim BRANCH_REMOVAL=1 test-dispatch-rules test-reference-machine REFERENCE_DIR=../../dingusppc DEMO_FW_DIR=<main checkout>/toolchain/build/demo`, at width 1 and at width 2 with the LSU unit, commits 9e13b56 (rules at both widths, reference machine at width 1) and 2fbb2a4 (reference machine at width 2), 2026-10-04.
All pass. Dhrystone, CoreMark and Whetstone pass every dispatch rule,
including `TIM-BPU-FOLD`; at width 2 Dhrystone dispatches 1,646,861 and
removes 49,503 branches at dispatch (52,728 at width 1). The whole-machine
comparison passes all five programs and the negative controls at both widths;
the reference steps 62,418 removed branches in Dhrystone at width 1, which
includes plain `b` removed before the IQ. At width 2 with the unit the
comparison first failed: a store's write from the store queue reached the
trace after younger records (and after the last one), which removal makes
common. The runner now carries an owed store across records and the trace
ends with a record of the stores drained after the last retirement
([REFERENCE_MACHINE.md](REFERENCE_MACHINE.md#tolerances)); Dhrystone has
148,364 such late writes at width 2.

Quartus 17 `quartus_map --analysis_and_elaboration ppc603e_chip` under the
Quartus lock on a copy of `quartus/chip` with `PPC_DISPATCH_WIDTH=2`,
`PPC_LSU_PIPE=1` and `PPC_BRANCH_REMOVAL=1'b1`, commit 9e53e78: 0 errors,
49 warnings. No fit was run.

## Dispatch and completion rule check

Recorded: `make -C sim test-dispatch-rules` at width 1, width 1 with the LSU unit, `DISPATCH_WIDTH=2` and width 2 with the unit (`VERILATOR=tools/verilate-lsu-pipe`), commits 333c376 and bf69248, 2026-10-04.
Dhrystone, CoreMark and Whetstone pass every rule in all four configurations. The
first width-2 run failed TIM-WB-LIMITS on Whetstone; the cause was the checker reading
bit 31 of D-form words as Rc (an `ori` with an odd immediate counted as a CR writer).
bf69248 reads Rc only for opcodes 20, 21, 23, 31, 59 and 63 and counts `fcmpu`,
`fcmpo` and `mcrfs` as CR writers; the RTL never paired two flag writers.

`check_dispatch_trace.py --rules` checks a `+DISPATCH_TRACE` stream of any
length against the manual rules above, taking each PC's instruction word from
the program image. `make -C sim test-dispatch-rules` streams Dhrystone,
CoreMark and Whetstone (soft float) on the demo SoC through it, at the build's
width and LSU setting. Each rule is marked in `sim/spec/timing.json`
(`trace_checked`, or `partially_trace_checked` when the trace shows only some
of its requirements).

| Rule | Checked |
|---|---|
| `TIM-DISP-WIDTH` | At most `width` dispatches and retirements per cycle |
| `TIM-DISP-DQ1` | A pair has no dispatch-serialized instruction and needs two distinct units, where add/compare may take the SRU (`--sru`, width 2) and a branch the BPU |
| `TIM-DISP-DQ0` | A dispatch-serialized instruction dispatches only when every older instruction has retired, at the latest in that cycle |
| `TIM-SER-DISPATCH` | Nothing dispatches while a dispatch-serialized instruction is in flight |
| `TIM-SER-REFETCH` | Nothing dispatches in the cycle `isync` retires |
| `TIM-SER-COMPLETE` | A completion-serialized instruction never completes from CQ[1] |
| `TIM-CQ-ORDER`, `TIM-CQ-CQ1` | Retirement in dispatch order, never in the dispatch cycle; only the work a misprediction recovery removed behind a conditional branch (`!<n>` in the trace, UM 6.4.1.2) is skipped; CQ[1] holds only integer, load or branch (branches keep a CQ entry unless removed) |
| `TIM-WB-LIMITS` | A retired pair writes at most two GPRs and one each of CR, FPR, LR, CTR |
| `TIM-BPU-FOLD` | A branch removed at dispatch (`*`) is a branch without LR or CTR write, and never retires |
| `TIM-CQ-ALLOC`, `TIM-RENAME-LIMITS` | After a cycle's retirements, at most five instructions in the CQ (UM 6.3.3, 6.6.1.2), five GPR destinations, two for a load with update, and four FPR destinations (UM 6.6) |
| `TIM-BPU-FETCH-STOP` | The UM 6.4.1.1 cases (`mtlr`/`bclr`, `mtctr`/`bcctr` or `bc(CTR)`, `bc(CTR)`/`bc(CTR)` or `bcctr`, branch(LK)/branch(LK) except `bl`): until the older instruction completes, the waiting branch is not removed at dispatch and nothing younger dispatches. A move to LR or CTR is completion-serialized and its result is not forwarded before it retires (UM 6.3.3.2) |
| `TIM-BPU-ONE-PREDICTION` | On a mispredicted path, a branch on CR alone is not removed and nothing behind it dispatches (UM 6.4.1.2 one level of prediction, 6.6.1.1, last case of 6.4.1.1) |
| `TIM-BPU-MISPREDICT` | After a recovery, the first dispatch is at least four cycles after the dispatch of the mispredicted branch's CR producer (compare or record form on the tested field): execute the cycle after dispatch, resolve the cycle after that, fetch, then dispatch (UM 6.4.1.2.1, Figure 6-5) |

Unit tests in `test_dispatch_trace.py` (`check-spec`) make each rule fail on a
crafted trace. Not checked, because the trace does not show them: renames held
past completion, the single CR, LR and CTR renames (a station waiter holds
none), IQ occupancy, unit busy times, operand readiness, exception-free CQ[1]
retirement, the path of a correctly predicted branch, and when a move to LR or
CTR executes. Not checked either: the per-row latencies and the chapter 6
worked schedules.

Recorded: `make -C sim check-spec`; `make -C sim test-dispatch-rules DEMO_FW_DIR=<main checkout>/toolchain/build/demo`, the same with `BRANCH_REMOVAL=1`, each at width 1 and with `DISPATCH_WIDTH=2 BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/sim/tools/verilate-lsu-pipe`; commit bee8f17, 2026-10-06.
Dhrystone, CoreMark and Whetstone pass every rule, in both configurations
and with branch removal. The CQ and GPR destination counts reach five and
never exceed it. No fetch stop is held: every waiting branch waits at
dispatch until the older instruction completes. No branch on CR dispatched
on a mispredicted path.

## CQ[1] retirement audit

Recorded: `make -C sim DISPATCH_WIDTH=<1|2> BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe demo-soc-model`, then `Vtb_demo_soc +IMAGE=<main checkout>/toolchain/build/demo/<dhrystone|coremark>.hex +PROFILE`, commits c77ae69 (before) and 9906d74 (after), 2026-10-04.
`+PROFILE` names why a finished CQ[1] does not retire beside a retiring
head: `retire1 held: <gate term>` and `retire1 not offered: <pair rule>`.
Each cause against UM 6.6.1.3 (counts and verdicts in
[PERFORMANCE_TARGET.md](PERFORMANCE_TARGET.md#batch-13-start-and-cq1-retirement)):

- Speculative `bc` in CQ[1] resolving as predicted: 79 of the 90.5 held
  cycles per Dhrystone run. It follows no unresolved prediction, so it now
  retires that cycle, from CQ[0] or CQ[1] (`bs_hit`). Neutral on cycles: the
  CQ-full stall comes from entries freed by retirement reaching dispatch a
  cycle later.
- Kept, as the manual requires: a mispredicted `bc` or anything behind one,
  stores, pairs over two GPR writes.
- Kept, stricter than the manual, each at most 1.5 held cycles per
  Dhrystone run and 0.3% of CoreMark cycles: an SPR move
  finishing in the special lane at the head, an update load in CQ[1], one
  GPR written by both, two branches.

Recorded: `make -C sim lint check-spec test-core test-core-dual test-core-recovery test-core-machine-check-trace test-core-branch-fold test-core-lsu-timing test-core-lsu-update test-core-fpu test-completion-flags test-completion` at width 1, the benches again from `sim/` with `DISPATCH_WIDTH=2 BUILD_DIR=<dir> VERILATOR=$PWD/tools/verilate-lsu-pipe VERILATOR_TOOL=$PWD/tools/verilate-lsu-pipe`, and `test-dispatch-rules DEMO_FW_DIR=<main checkout>/toolchain/build/demo` in both configurations, commit 9906d74, 2026-10-04.
All pass. Dispatch rules at width 2 with the unit, every rule including
`TIM-CQ-CQ1` and `TIM-WB-LIMITS`: Dhrystone 407,503 pairs retired of 1,605,731
retirements, CoreMark 815,628 of 3,496,987, Whetstone 878,210 of 4,577,906.
Quartus 17 `quartus_map --analysis_and_elaboration ppc603e_chip` with
`PPC_DISPATCH_WIDTH=2` and `PPC_LSU_PIPE=1`: 0 errors.

## Completion in the writeback cycle

Recorded: `make -C sim lint check-spec`; `make -C sim DISPATCH_WIDTH=2 BUILD_DIR=<dir> VERILATOR=$PWD/sim/tools/verilate-lsu-pipe <bench>` and the same at width 1 without the unit, for `test-core test-core-dual test-core-recovery test-core-machine-check-trace test-core-branch-fold test-core-control-memory test-core-lsu-timing test-core-lsu-update test-core-fpu test-completion test-completion-flags test-stage test-core-interrupt`; `make -C sim test-dispatch-rules DEMO_FW_DIR=<main checkout>/toolchain/build/demo` at width 1 and at width 2 with the unit, commit b73b3d6, 2026-10-04.
All pass. `test-reference-machine` at width 2 with the unit fails at `hello`
record 67 (a queued store's write lands on the next retirement line), on
f5305d4 as well; the trace does not place post-retirement store-queue writes.

A fault-free result on either finish port retires with the head (or CQ[1])
in its arrival cycle, its value and flag deltas merged into the retire
packet (UM 6.3.3; F6-3, F6-5). The queue frees the entry the next cycle.
Special-lane results are excluded: the lane's commit-time redirect and
exception outputs take their commit from registered state
(`retire_settled_o`), as do FP heads, which allocate finished.

New combinational path: unit result valid and producer → finish acceptance
(generation compare, recovery kill) → head match → `retire_valid_o` →
`commit` fan-out (GPR write enable, rename release, flags, store queue,
LR/CTR), plus result value → retire packet → GPR write data and CR delta.
Kept registered: the retire tag (`retire_tag_o` keys holds such as `bs_hold`
on head occupancy), the CQ[1] pairing checks (`head_o`, `head1_o`) and the
irrevocable-head test of recovery acceptance. Quartus analysis and
elaboration of the chip top at width 2 with the unit passes; no fit yet.

Bench changes: latency probes and spacings drop by one cycle (add 3→2;
unit `lwz`/`stw` 4→3; a load behind a store to its doubleword 5→4); the
stage contract's `finish_to_retire_min` is 0. Where faster draining left
fetch behind a group's sync, the group waits longer (`tb_core_dual` group I
on a divide, the `stwu` group behind two syncs). The recovery and interrupt
benches read stored head state where retirement eligibility or ready would
otherwise form a loop through the finish path.

## Risks

- **Throughput depends on P3 first.** Today's CPI is about 4 on Dhrystone and
  CoreMark; dual dispatch removes only the dispatch cycle itself, estimated at
  0.2–0.3 CPI after the LSU work ([PERFORMANCE.md](PERFORMANCE.md#optimizations-ranked)).
  Enable width 2 after P3.
- **The special lane is stricter than the manual.** It drains before dispatch;
  SPR, CR-logic and string timing will still differ from Table 6-4 after dual
  dispatch. Record it as a deviation, do not widen it.
- **Branch model.** Branches resolve at dispatch and allocate a CQ entry; the
  603e BPU folds at fetch and takes no dispatch slot. Slice 7 removes the slot
  cost only for a folded branch in DQ1; cycle-exact branch rows need the
  branch removed at fetch (P09). Until then branch timing is a listed
  deviation.
- **Speculative recovery is late.** A mispredicted speculative `bc` recovers
  when it retires, not at resolution; never faster than the 603e, but
  slower when older work is long.
- **LVT correctness.** Two write ports to one register in one cycle cannot occur
  (retire pairs have distinct destinations or are ordered); an assertion checks
  it and a directed bench covers the same-index read-after-write.
- **Retire interface change** touches every trace consumer; width 1 keeps them
  unchanged, width 2 needs the reference runner and firmware checkers updated in
  slice 5.
- **Recovery breadth.** More stations and a second FPU lane widen the kill loop;
  `test-core-recovery` and the pivot scoreboard must cover a killed DQ1 and a
  killed CQ[1].
- **Area.** Roughly 3–4k ALMs on the translated top; the MiSTer build has room
  but the FPU build is already large.

## Open questions

- `TIM-U05`: the DQ[0] "serialized and CQ empty" bullet stays read as a
  condition.
- Whether a load in CQ[1] retires with a store in CQ[0] on the same cycle when
  both touch the D-cache; the manual permits it and the D-cache must not reorder.
- SRU add/compare presence on PID6 and the 603 (App. C).
