# Dual dispatch and dual completion design

Design document, 2026-09-30. No RTL implements it yet. It maps the 603e's
two-per-cycle dispatch and completion (TASK_PLAN P11) onto the current core and
splits the work into slices with acceptance tests. Code is cited at
[`9f6a5ad`](https://github.com/kdedon/SloPPC603/tree/9f6a5adf622de8223dad5ffd4affe66dba40352d)
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
| Fetch | One untagged request, one 32-bit word ([`ppc_fetch.sv:4-7`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_fetch.sv#L4-L7), [`ppc_icache.sv:22-25`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_icache.sv#L22-L25)) | Two words per cycle from an aligned doubleword |
| Fetch-to-decode | One registered word, decoded at IQ push ([`ppc_core.sv:369-403`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_core.sv#L369-L403)) | Two registered words, two decoders |
| IQ | `ppc_fifo`, depth 6, one push, one pop, head pointer ([`ppc_core.sv:438-444`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_core.sv#L438-L444)) | Push 0–2, pop 0–2, fixed DQ0/DQ1 slots |
| Dispatch decision | One wide `iq_ready` term ([`ppc_core.sv:972-985`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_core.sv#L972-L985)) | DQ0 and DQ1 terms; DQ1 from predecoded pair bits |
| GPR file | 3 read, 1 write, one MLAB copy per read port ([`ppc_regfile_gpr.sv:4-20`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_regfile_gpr.sv#L4-L20)); an update load writes its base one edge later ([`ppc_core.sv:671-704`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_core.sv#L671-L704)) | 6 read (rA, rB, rS per slot), 2 write |
| Rename | 5 slots, 2 lookups, 1 allocation, 1 release, 1 wake ([`ppc_rename.sv:6-28`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_rename.sv#L6-L28)) | 4–6 lookups, 2 allocations, 2 releases, 2 wakes |
| Reservation | One IU entry ([`ppc_dispatch.sv:1-27`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_dispatch.sv#L1-L27)); the special lane reads committed GPRs after a drain ([`ppc_core.sv:474-475`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_core.sv#L474-L475)) | One entry per unit: IU, LSU (P3), SRU add/compare |
| Result buses | IU and special lane share one CQ finish port; overlapped work waits a cycle on collision ([`ppc_core.sv:900-908`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_core.sv#L900-L908)) | One finish/wake port per unit |
| CQ | Depth 5, one allocation, one finish, one retire ([`ppc_completion.sv:186-198`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_completion.sv#L186-L198)) | 2 allocations, 2–3 finish ports, 2 retires |
| CR/XER | One exact-tag flag owner ([`ppc_flags.sv:1-25`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_flags.sv#L1-L25)) | Unchanged: it is the manual's single CR rename. Pair check only |
| Branch unit | Resolves at the IQ head from committed CR/LR/CTR (the P2 rule), allocates a CQ entry and passes the IU as an add of zero ([`ppc_core.sv:560-669`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_core.sv#L560-L669)) | Must stop taking the IU slot; see [Branches](#branches) |
| FPU | Arithmetic issues on lane 0; lane 1 and `commit1` exist in `ppc_fpu` but are tied off ([`ppc_fpu.sv:9-24`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/fpu/ppc_fpu.sv#L9-L24), [`ppc_special.sv:2152-2162`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_special.sv#L2152-L2162)) | Connect both lanes; see [FPU](#fpu) |
| Retire port | `retire_valid_o/retire_ready_i/retire_o`, one packet ([`ppc_core.sv:165-167`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_core.sv#L165-L167)) | Add a younger packet `retire1_*` |

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
  [`ppc_dispatch`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_dispatch.sv#L1-L27):
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
head ([`ppc_completion.sv:137-141`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_completion.sv#L137-L141)),
and a store is performed only from the head
([`ppc_core.sv:939-944`](https://github.com/kdedon/SloPPC603/blob/9f6a5adf622de8223dad5ffd4affe66dba40352d/rtl/ppc_core.sv#L939-L944)).
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

- `DISPATCH_WIDTH` (1 or 2) on `ppc_core` and its wrappers, default 1. At 1 the
  DQ1 and `retire1` logic is not generated and traces match today's core
  exactly. Elaboration rejects 2 until slice 6 lands (TASK_PLAN P11: enable 2
  only when implemented).
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
