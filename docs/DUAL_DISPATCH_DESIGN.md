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
pair_ok   = distinct units && neither serialized && !(both need flags)
            && DQ1 has no fetch fault, illegal or alignment class   (predecoded)
res2_ok   = cq_free_ge2 && gpr_rename_free >= need0+need1 && ...  (registered counts)
```

`cq_free_ge2` and the rename free counts are registered with next-state
lookahead from allocation and release counts, so DQ1 adds one AND to the DQ0
cone. Faulting or illegal instructions, special-lane operations and trace mode
dispatch alone from DQ0. The current special lane drains before dispatch, which
is stricter than the manual's completion serialization; that deviation stays
and is recorded, not widened.

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
  route them to the IU. `cpu_cfg_t` gets `has_sru_add_compare`.

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
4. Later, and measured: branches without LR/CTR updates take no CQ entry, as
   the manual's folding does. An interrupt then resumes at the branch, which is
   idempotent. This needs care with `committed_next_pc_q` and the resume
   override.

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
  single. The wrappers still build width 1; wiring them (and the translation
  router) is slice 6 work.
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
| 4 | Implemented behind `DISPATCH_WIDTH=2`; pair-rule cycle benches beyond `tb_core_dual` not written | `ppc_core` (`dispatch1`, `pair_units`); bench `tb/tb_core_dual.sv` |
| 5 | Implemented; only `tb_core_reference` and the SoC/MiSTer benches observe CQ[1] | `ppc_core` (`commit1`); `RETIRE_PAIRS` on the BAT wrappers |
| 6 | Partial: width 2 selectable (`make -C sim DISPATCH_WIDTH=2`, `--dual` builds), default still 1; the chip top misses 66 MHz, and 50 MHz hold by 6 ps (see below); two-word fetch through the wrappers not wired | |
| 7 | Not started | |

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

## Risks

- **Throughput depends on P3 first.** Today's CPI is about 4 on Dhrystone and
  CoreMark; dual dispatch removes only the dispatch cycle itself, estimated at
  0.2–0.3 CPI after the LSU work ([PERFORMANCE.md](PERFORMANCE.md#optimizations-ranked)).
  Enable width 2 after P3.
- **The special lane is stricter than the manual.** It drains before dispatch;
  SPR, CR-logic and string timing will still differ from Table 6-4 after dual
  dispatch. Record it as a deviation, do not widen it.
- **Branch model.** The P2 rule resolves at dispatch and allocates a CQ entry;
  the 603e BPU folds at fetch and takes no dispatch slot. Cycle-exact branch rows
  need slice 7 or a fetch-side BPU (P09); until then branch timing is a listed
  deviation.
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
